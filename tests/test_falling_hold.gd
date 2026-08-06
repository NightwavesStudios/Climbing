## test_falling_hold.gd
## Verifies the FallingHoldModifier state machine — the fall is committed the
## moment any limb grabs the hold: letting go before the fall timer elapses
## does NOT cancel the shake, and the hold always falls once the timer runs
## out (grabbed or not).
##
## NOTE: the Ziva test runner calls test_*() methods during SceneTree._initialize
## before any frame is pumped, so nodes can't enter the tree (no _ready, no
## await). Strategy: build the modifier off-tree and drive its methods manually.
extends Node

# Mirrors FallingHoldModifier._State
const IDLE: int    = 0
const SHAKING: int = 1
const FALLING: int = 2

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
	assert(_failures == 0, "FALLING_HOLD_TESTLOG: " + _log.replace("\n", " | "))

func _build() -> Dictionary:
	var hold: Node2D  = Node2D.new()
	var limb_a: Node2D = Node2D.new()
	var limb_b: Node2D = Node2D.new()
	var mod: FallingHoldModifier = FallingHoldModifier.new()
	hold.add_child(mod)  # stays off-tree, so _ready never fires
	mod.hold             = hold
	mod._visual_root_cache = hold
	mod._origin          = Vector2(100, 200)
	mod._origin_set      = true
	return {"mod": mod, "limb_a": limb_a, "limb_b": limb_b}

# ── A grab commits the fall: letting go before the timer still falls ─────────
func test_partial_grab_still_falls() -> void:
	var b: Dictionary  = _build()
	var mod: FallingHoldModifier = b["mod"]
	var limb_a: Node2D = b["limb_a"]

	_check(mod._state == IDLE, "hold starts idle")

	# Reach: a limb grabs the falling hold → shaking begins.
	mod.on_grab(limb_a)
	_check(mod._state == SHAKING, "a grab starts the shake")
	mod.on_process(0.5)
	_check(mod._get_visual_root().global_position != mod._origin, "hold is visibly rattling while held")

	# The climber lets go before the fall timer elapses — the fall is already
	# committed, so the hold keeps shaking instead of cancelling.
	mod.on_release(limb_a)
	_check(mod._state == SHAKING, "release before the fall does NOT cancel the shake")
	mod.on_process(0.5)
	_check(mod._state == SHAKING, "hold keeps shaking with nobody hanging on")

	# Keep simulating well past fall_delay — the abandoned hold must STILL fall.
	mod.on_process(2.0)
	_check(mod._state == FALLING, "abandoned hold still falls once the timer elapses")

	# And it keeps falling even while ungrabbed.
	var pos_after_fall: Vector2 = mod._get_visual_root().global_position
	mod.on_process(0.25)
	_check(
		mod._get_visual_root().global_position.y > pos_after_fall.y,
		"unheld hold continues to fall after entering FALLING"
	)

	_finish()

# ── Core mechanic preserved: a committed grab still makes it fall ───────────
func test_committed_grab_still_falls() -> void:
	var b: Dictionary  = _build()
	var mod: FallingHoldModifier = b["mod"]
	var limb_a: Node2D = b["limb_a"]

	mod.on_grab(limb_a)
	mod.on_process(2.5)  # held longer than fall_delay (2.2s)
	_check(mod._state == FALLING, "hanging on through the shake still makes it fall")
	_check(mod._claimed_limbs.is_empty(), "falling force-releases the limb")

	_finish()

# ── Multi-limb: releasing limbs never cancels a committed fall ──────────────
func test_releasing_limbs_never_cancels_fall() -> void:
	var b: Dictionary  = _build()
	var mod: FallingHoldModifier = b["mod"]
	var limb_a: Node2D = b["limb_a"]
	var limb_b: Node2D = b["limb_b"]

	mod.on_grab(limb_a)
	mod.on_grab(limb_b)
	mod.on_release(limb_a)
	_check(mod._state == SHAKING, "one limb still on the hold → keeps shaking")
	mod.on_release(limb_b)
	_check(mod._state == SHAKING, "last limb off does NOT cancel the committed shake")
	mod.on_process(2.5)  # past fall_delay
	_check(mod._state == FALLING, "hold still falls after every limb let go")

	_finish()