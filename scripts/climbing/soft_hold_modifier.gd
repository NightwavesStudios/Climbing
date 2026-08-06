class_name SoftHoldModifier
extends HoldModifierBase
## Soft Hold Modifier
##
## A hold that can only be used a limited number of times before it crumbles
## and falls off the wall. Each limb placement (grab) counts toward the limit
## — releasing a limb does NOT restore a use.
##
## For example, with max_uses=4:
##   1) foot placed  (grab)  → uses_remaining 4→3
##   2) hand placed  (grab)  → uses_remaining 3→2
##   3) foot removed, then foot placed again (grab) → uses_remaining 2→1
##   4) hand placed  (grab)  → uses_remaining 1→0
##   5) next limb grab       → hold crumbles, all limbs force-released
##
## State machine:
##   IDLE    → normal, accepting grabs until uses run out
##   FALLING → crumbling, limbs force-released, hold drops off screen
##   FALLEN  → off-screen, inactive
##
## No visual indication (cracking textures) yet — that will come later.

# ── Tunable parameters ────────────────────────────────────────────────────
## Maximum number of limb placements before the hold crumbles.
@export var max_uses: int = 4
## Gravity applied to the hold while falling off-screen.
@export var fall_gravity: float = 1800.0

# ── Internal state ────────────────────────────────────────────────────────
enum _State { IDLE, FALLING, FALLEN }
var _state: _State = _State.IDLE
var _uses_remaining: int = 4
var _claimed_limbs: Array[Node2D] = []
var _fall_velocity: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _origin_set: bool = false
var _visual_root_cache: Node2D = null
var _fall_active: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	modifier_type = "soft_hold"
	_uses_remaining = max_uses
	super._ready()

func _compute_visual_root() -> Node2D:
	if hold == null:
		return null
	var parent = hold.get_parent()
	if parent is Node2D and parent.get_script() == null:
		return parent as Node2D
	return hold

func _get_visual_root() -> Node2D:
	if _visual_root_cache != null and is_instance_valid(_visual_root_cache):
		return _visual_root_cache
	return hold

func on_hold_ready() -> void:
	_visual_root_cache = _compute_visual_root()
	if hold != null and hold.is_inside_tree():
		_origin = _get_visual_root().global_position
		_origin_set = true

# ── Per-frame ─────────────────────────────────────────────────────────────

func on_process(delta: float) -> void:
	if not _origin_set and hold != null and is_instance_valid(hold):
		_origin = _get_visual_root().global_position
		_origin_set = true

	if _state == _State.FALLING:
		_fall_velocity += fall_gravity * delta
		_get_visual_root().global_position += Vector2(0.0, _fall_velocity * delta)
		# Once far off-screen, stop doing anything.
		if _get_visual_root().global_position.y > _origin.y + 3000.0:
			_state = _State.FALLEN

# ── Grab / release hooks ──────────────────────────────────────────────────

func allow_grab(_limb_node: Node2D, _is_foot: bool) -> bool:
	# Cannot grab a hold once it has fallen (or is currently falling).
	return _state == _State.IDLE

func on_grab(limb_node: Node2D) -> void:
	if _state != _State.IDLE:
		return

	if limb_node not in _claimed_limbs:
		_claimed_limbs.append(limb_node)

	# If uses are exhausted, the hold crumbles immediately.
	if _uses_remaining <= 0:
		_trigger_fall()
		return

	_uses_remaining -= 1

func on_release(limb_node: Node2D) -> void:
	_claimed_limbs.erase(limb_node)

# ── State transitions ─────────────────────────────────────────────────────

func _trigger_fall() -> void:
	if _state != _State.IDLE:
		return
	_state = _State.FALLING
	_fall_velocity = 0.0
	_force_release_all()
	_set_collision_enabled(false)

func on_climb_reset() -> void:
	_do_reset()

func on_caught_reset() -> void:
	# When the rope catches the player, restore the hold (if it's still
	# in the scene). Can't restore a soft hold that crumbled, but we
	# reset it anyway so the level state is consistent.
	if _state == _State.IDLE:
		return
	_do_reset()

func _do_reset() -> void:
	_state = _State.IDLE
	_uses_remaining = max_uses
	_fall_velocity = 0.0
	_claimed_limbs.clear()
	if _origin_set and _get_visual_root() != null:
		_get_visual_root().global_position = _origin
	_set_collision_enabled(true)

# ── Helpers ───────────────────────────────────────────────────────────────

func _force_release_all() -> void:
	var to_release := _claimed_limbs.duplicate()
	_claimed_limbs.clear()

	for limb in to_release:
		if not is_instance_valid(limb):
			continue
		# Release from the hold first.
		if hold and hold.has_method("release"):
			hold.release(limb)
		# Then properly clear the limb state on the character.
		var character := _find_character(limb)
		if character != null and "_limbs" in character:
			for s in character._limbs:
				if s.node == limb:
					character.release_limb(s)
					s.is_grabbing = false
					if character.has_method("_reset_limb_ghost"):
						character._reset_limb_ghost(limb)
					# Small downward impulse so the fall feels immediate.
					character.com_velocity.y = maxf(character.com_velocity.y, 150.0)
					break
		elif hold and hold.has_method("release"):
			hold.release(limb)

func _find_character(limb_node: Node2D) -> Node2D:
	if limb_node == null:
		return null
	var parent: Node = limb_node.get_parent()
	if parent is CharacterBody2D:
		return parent as Node2D
	return null

func _set_collision_enabled(enabled: bool) -> void:
	if hold == null:
		return
	for child in hold.get_children():
		if child is CollisionShape2D:
			child.disabled = not enabled

# ── Serialization ─────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"type": "soft_hold",
		"max_uses": max_uses,
		"fall_gravity": fall_gravity,
	}

func deserialize(data: Dictionary) -> void:
	max_uses = int(data.get("max_uses", max_uses))
	fall_gravity = float(data.get("fall_gravity", fall_gravity))
	_uses_remaining = max_uses