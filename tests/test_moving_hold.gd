## test_moving_hold.gd
## Verifies the MovingHoldModifier:
##   - the hold moves in a straight line between start_point and end_point
##   - it ping-pongs back and forth (returns to start after reaching end)
##   - movement speed is respected (distance / speed = travel time)
##   - serialize/deserialize round-trips the points and speed
##   - on_climb_reset returns the hold to the start point
##
## NOTE: the Ziva test runner calls test_*() methods during SceneTree._initialize
## before any frame is pumped, so nodes can't enter the tree (no _ready, no
## await). Strategy: build the modifier off-tree and drive on_process manually.
extends Node

var _checks: int   = 0
var _failures: int = 0
var _log: String   = ""

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		_log += "PASS: " + msg + "\n"
	else:
		_failures += 1
		_log += "FAIL: " + msg + "\n"

func _finish() -> void:
	_log += "RESULT: " + str(_checks - _failures) + "/" + str(_checks) + " checks passed, " + str(_failures) + " failed"
	print("==============================================")
	print(_log)
	assert(_failures == 0, "MOVING_HOLD_TESTLOG: " + _log.replace("\n", " | "))

func _build() -> Dictionary:
	var hold: Node2D = Node2D.new()
	var mod: MovingHoldModifier = MovingHoldModifier.new()
	hold.add_child(mod)  # stays off-tree, so _ready never fires
	mod.hold = hold
	mod._visual_root_cache = hold
	mod._editor_context = 0  # pretend standalone game → always simulate
	mod.start_point = Vector2(100, 100)
	mod.end_point = Vector2(300, 100)   # 200px horizontal path
	mod.speed = 100.0
	return {"mod": mod, "hold": hold}

func _x(mod: MovingHoldModifier) -> float:
	return mod._get_visual_root().global_position.x

# ── Basic straight-line motion ────────────────────────────────────────────
func test_moves_in_straight_line() -> void:
	var b: Dictionary = _build()
	var mod: MovingHoldModifier = b["mod"]
	var hold: Node2D = b["hold"]

	# Off-tree the modifier can't snap on_hold_ready; the first process tick
	# (delta 0) lands the hold exactly on the start point.
	mod.on_process(0.0)
	_check(hold.global_position == Vector2(100, 100), "hold starts at the start point")

	# Half of the travel time → halfway along the path.
	mod.on_process(1.0)  # 200px / 100px/s = 2s full travel; 1s = halfway
	_check(is_equal_approx(_x(mod), 200.0), "after half the travel time the hold is halfway (x=200)")
	_check(hold.global_position.y == 100.0, "hold stays on the straight line (y unchanged)")

	# Full travel time → at the end point.
	mod.on_process(1.0)
	_check(is_equal_approx(_x(mod), 300.0), "after full travel time the hold reaches the end point")

	# Ping-pong: now it heads back toward start.
	mod.on_process(1.0)
	_check(is_equal_approx(_x(mod), 200.0), "after travelling back halfway the hold returns to the middle")
	mod.on_process(1.0)
	_check(is_equal_approx(_x(mod), 100.0), "after full return travel the hold is back at the start")

	_finish()

# ── Speed is respected ────────────────────────────────────────────────────
func test_speed_controls_travel_time() -> void:
	var b: Dictionary = _build()
	var mod: MovingHoldModifier = b["mod"]
	var hold: Node2D = b["hold"]

	mod.speed = 200.0  # 200px path / 200px/s = 1s travel
	mod.on_hold_ready()
	mod.on_process(0.5)
	_check(is_equal_approx(_x(mod), 200.0), "at 200px/s the hold is halfway after 0.5s")
	mod.on_process(0.5)
	_check(is_equal_approx(_x(mod), 300.0), "at 200px/s the hold reaches the end after 1s")

	_finish()

# ── Degenerate path (start == end) is safe ────────────────────────────────
func test_degenerate_path_is_safe() -> void:
	var b: Dictionary = _build()
	var mod: MovingHoldModifier = b["mod"]
	mod.end_point = mod.start_point
	mod.on_hold_ready()
	mod.on_process(5.0)  # must not divide by zero / error
	_check(mod._get_visual_root().global_position == mod.start_point, "degenerate path keeps the hold on the start point")

	_finish()

# ── serialize / deserialize round-trip ────────────────────────────────────
func test_serialize_round_trip() -> void:
	var mod: MovingHoldModifier = MovingHoldModifier.new()
	mod.start_point = Vector2(50, 60)
	mod.end_point = Vector2(250, 180)
	mod.speed = 145.0
	mod.pause_at_ends = true
	mod.pause_time = 0.8

	var data := mod.serialize()
	_check(data.get("type", "") == "moving", "serialize keeps the moving type key")
	_check(float(data.get("start_x", 0)) == 50.0 and float(data.get("start_y", 0)) == 60.0, "serialize stores start point")
	_check(float(data.get("end_x", 0)) == 250.0 and float(data.get("end_y", 0)) == 180.0, "serialize stores end point")
	_check(float(data.get("speed", 0)) == 145.0, "serialize stores speed")
	_check(bool(data.get("pause", false)) == true, "serialize stores pause flag")
	_check(float(data.get("pause_time", 0)) == 0.8, "serialize stores pause time")

	var mod2: MovingHoldModifier = MovingHoldModifier.new()
	mod2.deserialize(data)
	_check(mod2.start_point == Vector2(50, 60), "deserialize restores start point")
	_check(mod2.end_point == Vector2(250, 180), "deserialize restores end point")
	_check(mod2.speed == 145.0, "deserialize restores speed")
	_check(mod2.pause_at_ends == true, "deserialize restores pause flag")
	_check(mod2.pause_time == 0.8, "deserialize restores pause time")

	_finish()

# ── climb reset returns to start ──────────────────────────────────────────
func test_reset_returns_to_start() -> void:
	var b: Dictionary = _build()
	var mod: MovingHoldModifier = b["mod"]
	var hold: Node2D = b["hold"]

	mod.on_hold_ready()
	mod.on_process(1.5)  # somewhere in the middle of the path
	_check(_x(mod) != 100.0, "hold has moved off the start point")

	mod.on_climb_reset()
	_check(hold.global_position == Vector2(100, 100), "climb reset returns the hold to the start point")

	_finish()

# ── pause_at_ends dwells at each end ──────────────────────────────────────
func test_pause_at_ends() -> void:
	var b: Dictionary = _build()
	var mod: MovingHoldModifier = b["mod"]
	var hold: Node2D = b["hold"]

	mod.speed = 100.0       # 200px path, 2s travel
	mod.pause_at_ends = true
	mod.pause_time = 1.0
	mod.on_hold_ready()

	# During the initial pause the hold should sit at the start point.
	mod.on_process(0.5)
	_check(hold.global_position == Vector2(100, 100), "hold dwells at start during the initial pause")

	# After the pause it travels. _time is now 0.5s; add 1.5s more so the
	# elapsed time is 2.0s = 1.0s pause + 1.0s travel → halfway along the path.
	mod.on_process(1.5)
	_check(is_equal_approx(_x(mod), 200.0), "hold travels toward the end after the pause (x=200)")

	_finish()