## test_soft_hold.gd
## Verifies the SoftHoldModifier usage-count mechanic:
## each limb placement (grab) consumes one use; releasing does NOT restore a
## use; when the count hits zero the NEXT grab crumbles the hold.
##
## NOTE: the Ziva test runner calls test_*() methods during SceneTree._initialize
## before any frame is pumped, so nodes can't enter the tree (no _ready, no
## await). Strategy: build the modifier off-tree and drive its methods manually.
extends Node

# Mirrors SoftHoldModifier._State
const IDLE: int    = 0
const FALLING: int = 1
const FALLEN: int  = 2

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
	assert(_failures == 0, "SOFT_HOLD_TESTLOG: " + _log.replace("\n", " | "))

func _build(max_uses: int = 4) -> Dictionary:
	var hold: Node2D  = Node2D.new()
	var limb_a: Node2D = Node2D.new()
	var limb_b: Node2D = Node2D.new()
	var mod: SoftHoldModifier = SoftHoldModifier.new()
	hold.add_child(mod)  # stays off-tree, so _ready never fires
	mod.hold              = hold
	mod._visual_root_cache = hold
	mod._origin           = Vector2(100, 200)
	mod._origin_set       = true
	mod.max_uses          = max_uses
	mod._uses_remaining   = max_uses
	return {"mod": mod, "limb_a": limb_a, "limb_b": limb_b}

# ── Core mechanic: the user's example scenario ─────────────────────────────
func test_use_counter_matches_user_example() -> void:
	var b: Dictionary  = _build(4)
	var mod: SoftHoldModifier = b["mod"]
	var limb_a: Node2D = b["limb_a"]
	var limb_b: Node2D = b["limb_b"]

	_check(mod._state == IDLE, "hold starts idle")
	_check(mod._uses_remaining == 4, "soft hold starts with max_uses remaining")

	# 1) foot placed
	mod.on_grab(limb_a)
	_check(mod._uses_remaining == 3, "(1) foot placed → 3 uses left")
	_check(mod._state == IDLE, "still standing after foot placement")

	# 2) hand placed
	mod.on_grab(limb_b)
	_check(mod._uses_remaining == 2, "(2) hand placed → 2 uses left")
	_check(mod._state == IDLE, "still standing after hand placement")

	# foot removed — release must NOT restore a use
	mod.on_release(limb_a)
	_check(mod._uses_remaining == 2, "foot removed → uses do NOT come back")
	_check(mod._state == IDLE, "release alone never breaks the hold")

	# 3) foot placed again
	mod.on_grab(limb_a)
	_check(mod._uses_remaining == 1, "(3) foot placed again → 1 use left")
	_check(mod._state == IDLE, "still standing after third placement")

	# 4) hand placed again
	mod.on_grab(limb_b)
	_check(mod._uses_remaining == 0, "(4) hand placed again → 0 uses left")
	_check(mod._state == IDLE, "still standing after fourth placement — hold holds")

	# 5) next limb grab → hold crumbles
	mod.on_grab(limb_a)
	_check(mod._state == FALLING, "(5) next limb grab crumbles the hold")
	_check(mod._claimed_limbs.is_empty(), "crumbling force-releases all limbs")
	_check(mod.allow_grab(limb_b, false) == false, "cannot grab a crumbled hold")

	_finish()

# ── release does not restore uses ──────────────────────────────────────────
func test_release_never_restores_uses() -> void:
	var b: Dictionary  = _build(1)
	var mod: SoftHoldModifier = b["mod"]
	var limb_a: Node2D = b["limb_a"]
	var limb_b: Node2D = b["limb_b"]

	mod.on_grab(limb_a)
	_check(mod._uses_remaining == 0, "one use consumed with max_uses=1")
	mod.on_release(limb_a)
	_check(mod._uses_remaining == 0, "releasing does not restore the use")
	_check(mod._state == IDLE, "release alone does not crumble the hold")

	# A fresh limb grabbing the exhausted hold triggers the fall.
	mod.on_grab(limb_b)
	_check(mod._state == FALLING, "exhausted hold crumbles on the next grab")

	_finish()

# ── max_uses=1: first grab fine, second grab crumbles ──────────────────────
func test_single_use_soft_hold() -> void:
	var b: Dictionary  = _build(1)
	var mod: SoftHoldModifier = b["mod"]
	var limb_a: Node2D = b["limb_a"]
	var limb_b: Node2D = b["limb_b"]

	_check(mod.allow_grab(limb_a, false), "fresh hold allows the first grab")
	mod.on_grab(limb_a)
	_check(mod._uses_remaining == 0, "single-use hold consumed")
	_check(mod._state == IDLE, "hold still up after first grab")

	mod.on_grab(limb_b)
	_check(mod._state == FALLING, "second limb grab crumbles a single-use hold")

	_finish()

# ── same limb re-grab counts as a new use ──────────────────────────────────
func test_same_limb_regrab_counts() -> void:
	var b: Dictionary  = _build(2)
	var mod: SoftHoldModifier = b["mod"]
	var limb_a: Node2D = b["limb_a"]

	mod.on_grab(limb_a)
	_check(mod._uses_remaining == 1, "first grab consumed a use")
	mod.on_release(limb_a)
	mod.on_grab(limb_a)
	_check(mod._uses_remaining == 0, "same limb re-grabbing consumes another use")
	mod.on_release(limb_a)
	mod.on_grab(limb_a)
	_check(mod._state == FALLING, "third grab of an exhausted hold crumbles it")

	_finish()

# ── serialize / deserialize round-trip ─────────────────────────────────────
func test_serialize_round_trip() -> void:
	var mod: SoftHoldModifier = SoftHoldModifier.new()
	mod.max_uses = 7
	var data := mod.serialize()
	_check(data.get("type", "") == "soft_hold", "serialize keeps the soft_hold type key")
	_check(data.get("max_uses", 0) == 7, "serialize stores max_uses")

	var mod2: SoftHoldModifier = SoftHoldModifier.new()
	mod2.deserialize(data)
	_check(mod2.max_uses == 7, "deserialize restores max_uses")
	_check(mod2._uses_remaining == 7, "deserialize refreshes uses remaining")

	_finish()

# ── climb reset restores the hold ──────────────────────────────────────────
func test_reset_restores_uses() -> void:
	var b: Dictionary  = _build(2)
	var mod: SoftHoldModifier = b["mod"]
	var limb_a: Node2D = b["limb_a"]

	mod.on_grab(limb_a)
	mod.on_grab(limb_a)
	_check(mod._uses_remaining == 0, "uses consumed before reset")

	mod.on_climb_reset()
	_check(mod._state == IDLE, "reset returns hold to idle")
	_check(mod._uses_remaining == 2, "reset restores uses to max")
	mod.on_grab(limb_a)
	_check(mod._state != FALLING, "hold is usable again after reset")

	_finish()
