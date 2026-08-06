## test_zoom_tutorial_guide.gd
## Verifies the ZoomTutorialGuide (level 5 planning tutorial) helper logic:
## the halfway-jug detection and the camera-zoom helpers.
##
## NOTE: the Ziva test runner calls test_*() methods during SceneTree._initialize
## before any frame is pumped, so nodes can't enter the tree (no _ready, no
## await). Strategy: build the tutorial off-tree and drive its methods directly.
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
	assert(_failures == 0, "ZOOM_TUTORIAL_TESTLOG: " + _log.replace("\n", " | "))

func _build() -> Dictionary:
	var tut: ZoomTutorialGuide = ZoomTutorialGuide.new()
	# Real DynamicWall node exposes get_bounds() reading wall_min/wall_max.
	var fake_wall: Node2D = DynamicWall.new()
	var fake_main: Node2D = load("res://tests/fake_main_for_tutorial.gd").new()
	fake_main.dynamic_wall = fake_wall
	fake_main.camera = Camera2D.new()
	fake_wall.wall_min = Vector2(-192.0, -1536.0)
	fake_wall.wall_max = Vector2(256.0, 256.0)
	fake_wall.wall_valid = true
	tut._main_scene = fake_main
	return {"tut": tut, "fake_main": fake_main}

func test_halfway_y_computed_from_wall_bounds() -> void:
	var b: Dictionary = _build()
	var tut: ZoomTutorialGuide = b["tut"]
	_check(is_equal_approx(tut._halfway_y(), -640.0), "halfway_y == midpoint of wall bounds (-640)")

func test_halfway_jug_detection() -> void:
	var b: Dictionary = _build()
	var tut: ZoomTutorialGuide = b["tut"]

	var jug_high: ClimbingHold = ClimbingHold.new()
	jug_high.hold_type = ClimbingHold.HoldType.JUG
	jug_high.global_position = Vector2(0.0, -1200.0)  # above halfway (-640)
	_check(tut._is_halfway_jug(jug_high), "high jug counts as halfway")

	var jug_low: ClimbingHold = ClimbingHold.new()
	jug_low.hold_type = ClimbingHold.HoldType.JUG
	jug_low.global_position = Vector2(0.0, -100.0)  # below halfway
	_check(not tut._is_halfway_jug(jug_low), "low jug does NOT count as halfway")

	var crimp: ClimbingHold = ClimbingHold.new()
	crimp.hold_type = ClimbingHold.HoldType.CRIMP
	crimp.global_position = Vector2(0.0, -1200.0)
	_check(not tut._is_halfway_jug(crimp), "high non-jug does NOT count as halfway")

func test_camera_zoom_helpers() -> void:
	var b: Dictionary = _build()
	var tut: ZoomTutorialGuide = b["tut"]
	var cam: Camera2D = b["fake_main"].camera

	cam.zoom = Vector2(0.3, 0.3)
	_check(tut._camera_zoomed_out(), "zoom 0.3 is zoomed out")
	_check(not tut._camera_zoomed_in(), "zoom 0.3 is not zoomed in")

	cam.zoom = Vector2.ONE
	_check(not tut._camera_zoomed_out(), "zoom 1.0 is not zoomed out")
	_check(tut._camera_zoomed_in(), "zoom 1.0 is zoomed in")