# hold_modifiers.gd
# res://scripts/holds/hold_modifiers.gd
# ═══════════════════════════════════════════════════════════════════════════════
# Contains:
#   1. HoldModifierBase      — base class, extend this for every modifier
#   2. FallingHoldModifier   — hold that shakes then falls when grabbed
# ═══════════════════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 1 — BASE CLASS
# ═══════════════════════════════════════════════════════════════════════════════

class_name HoldModifierBase
extends Node

var modifier_type: String = "base"
var hold: Node2D = null

func _ready() -> void:
	hold = get_parent() as Node2D
	if hold == null:
		push_error("HoldModifierBase (%s): parent must be a Node2D hold." % modifier_type)

func on_hold_ready() -> void:
	pass

func on_process(_delta: float) -> void:
	pass

func allow_grab(_limb_node: Node2D, _is_foot: bool) -> bool:
	return true

func on_grab(_limb_node: Node2D) -> void:
	pass

func on_release(_limb_node: Node2D) -> void:
	pass

func modify_pressure(raw: float, _delta: float) -> float:
	return raw

func modify_recovery(raw: float, _delta: float) -> float:
	return raw

func serialize() -> Dictionary:
	return {"type": modifier_type}

func deserialize(_data: Dictionary) -> void:
	pass

func get_display_name() -> String:
	return modifier_type.capitalize()


# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 2 — FALLING HOLD MODIFIER
#  Type key: "falling"
#
#  State machine:
#    IDLE      → waiting for any limb to grab
#    SHAKING   → rattling, ramps up over fall_delay seconds
#    FALLING   → limbs force-released, hold drops, collision disabled
#    FALLEN    → resting off-screen, waiting for reset_delay
#    RESETTING → snaps back to origin, collision re-enabled
# ═══════════════════════════════════════════════════════════════════════════════

class FallingHoldModifier extends HoldModifierBase:

	# ── Tunable parameters ────────────────────────────────────────────────────
	var fall_delay:       float = 2.2
	var reset_delay:      float = 4.0
	var fall_gravity:     float = 1800.0
	var auto_reset:       bool  = false
	var calm_if_released: bool  = true

	var shake_max_amp:    float = 1.8
	var shake_frequency:  float = 22.0
	var shake_ramp_speed: float = 1.8

	# ── Internal state ────────────────────────────────────────────────────────
	enum _State { IDLE, SHAKING, FALLING, FALLEN, RESETTING }
	var _state:         _State  = _State.IDLE
	var _shake_timer:   float   = 0.0
	var _fall_timer:    float   = 0.0
	var _reset_timer:   float   = 0.0
	var _shake_lerp:    float   = 0.0
	var _fall_velocity: float   = 0.0
	var _time:          float   = 0.0
	var _origin:        Vector2 = Vector2.ZERO
	var _origin_set:    bool    = false
	var _claimed_limbs: Array[Node2D] = []

	# ── Lifecycle ─────────────────────────────────────────────────────────────

	func _ready() -> void:
		modifier_type = "falling"
		super._ready()

	func _get_visual_root() -> Node2D:
		if hold == null:
			return null
		var parent = hold.get_parent()
		if parent is Node2D and parent.get_script() == null:
			return parent as Node2D
		return hold

	func on_hold_ready() -> void:
		if hold != null and hold.is_inside_tree():
			_origin     = _get_visual_root().global_position
			_origin_set = true
		else:
			_capture_origin_deferred()

	func _capture_origin_deferred() -> void:
		await hold.get_tree().process_frame
		if hold != null and is_instance_valid(hold):
			_origin     = _get_visual_root().global_position
			_origin_set = true

	# ── Per-frame ─────────────────────────────────────────────────────────────

	func on_process(delta: float) -> void:
		if not _origin_set and hold != null and is_instance_valid(hold):
			_origin     = _get_visual_root().global_position
			_origin_set = true

		_time += delta
		match _state:
			_State.IDLE:      _tick_idle()
			_State.SHAKING:   _tick_shaking(delta)
			_State.FALLING:   _tick_falling(delta)
			_State.FALLEN:    _tick_fallen(delta)
			_State.RESETTING: _tick_resetting(delta)

	# ── Grab / release hooks ──────────────────────────────────────────────────

	func allow_grab(_limb_node: Node2D, _is_foot: bool) -> bool:
		return _state != _State.FALLING and _state != _State.FALLEN

	func on_grab(limb_node: Node2D) -> void:
		if not _origin_set and hold != null and is_instance_valid(hold):
			_origin     = _get_visual_root().global_position
			_origin_set = true

		if limb_node not in _claimed_limbs:
			_claimed_limbs.append(limb_node)
		if _state == _State.IDLE:
			_enter_shaking()

	func on_release(limb_node: Node2D) -> void:
		_claimed_limbs.erase(limb_node)
		if calm_if_released \
				and _state == _State.SHAKING \
				and _claimed_limbs.is_empty() \
				and _shake_timer < fall_delay * 0.5:
			_enter_idle_calm()

	# ── State ticks ───────────────────────────────────────────────────────────

	func _tick_idle() -> void:
		pass

	func _tick_shaking(delta: float) -> void:
		_shake_timer += delta
		_shake_lerp   = lerp(_shake_lerp, 1.0, shake_ramp_speed * delta)

		var amp := _shake_lerp * shake_max_amp
		var ox  := sin(_time * shake_frequency * TAU)              * amp
		var oy  := sin(_time * shake_frequency * TAU * 1.3 + 1.1) * amp * 0.55
		_get_visual_root().global_position = _origin + Vector2(ox, oy)

		if _shake_timer >= fall_delay:
			_enter_falling()

	func _tick_falling(delta: float) -> void:
		_fall_velocity                     += fall_gravity * delta
		_get_visual_root().global_position += Vector2(0.0, _fall_velocity * delta)
		_fall_timer                        += delta
		if _fall_timer >= reset_delay and auto_reset:
			_enter_resetting()

	func _tick_fallen(_delta: float) -> void:
		pass

	func _tick_resetting(delta: float) -> void:
		_reset_timer += delta
		if _reset_timer >= 0.35:
			_do_reset()

	# ── Transitions ───────────────────────────────────────────────────────────

	func _enter_shaking() -> void:
		_state       = _State.SHAKING
		_shake_timer = 0.0
		_shake_lerp  = 0.0

	func _enter_falling() -> void:
		_state         = _State.FALLING
		_fall_timer    = 0.0
		_fall_velocity = 0.0
		_force_release_all()
		_set_collision_enabled(false)
		_get_visual_root().global_position = _origin

	func _enter_idle_calm() -> void:
		_state                             = _State.IDLE
		_shake_timer                       = 0.0
		_shake_lerp                        = 0.0
		_get_visual_root().global_position = _origin

	func _enter_resetting() -> void:
		_state       = _State.RESETTING
		_reset_timer = 0.0

	func on_climb_reset() -> void:
		_do_reset()

	func _do_reset() -> void:
		_state                             = _State.IDLE
		_shake_timer                       = 0.0
		_shake_lerp                        = 0.0
		_fall_timer                        = 0.0
		_fall_velocity                     = 0.0
		_reset_timer                       = 0.0
		_claimed_limbs.clear()
		_get_visual_root().global_position = _origin
		_set_collision_enabled(true)

	# ── Helpers ───────────────────────────────────────────────────────────────

	func _force_release_all() -> void:
		for limb in _claimed_limbs.duplicate():
			if is_instance_valid(limb) and hold.has_method("release"):
				hold.release(limb)
				# Walk up to the climber and reset this limb's ghost so the
				# reaching arm doesn't snap from the old falling-hold position.
				var climber = limb.get_parent()
				if climber and climber.has_method("_reset_limb_ghost"):
					climber._reset_limb_ghost(limb)
		_claimed_limbs.clear()

	func _set_collision_enabled(enabled: bool) -> void:
		for child in hold.get_children():
			if child is CollisionShape2D:
				child.disabled = not enabled

	# ── Serialization ─────────────────────────────────────────────────────────

	func serialize() -> Dictionary:
		return {
			"type":             "falling",
			"fall_delay":       fall_delay,
			"reset_delay":      reset_delay,
			"fall_gravity":     fall_gravity,
			"auto_reset":       auto_reset,
			"calm_if_released": calm_if_released,
			"shake_max_amp":    shake_max_amp,
			"shake_frequency":  shake_frequency,
			"shake_ramp_speed": shake_ramp_speed,
		}

	func deserialize(data: Dictionary) -> void:
		fall_delay       = float(data.get("fall_delay",       fall_delay))
		reset_delay      = float(data.get("reset_delay",      reset_delay))
		fall_gravity     = float(data.get("fall_gravity",     fall_gravity))
		auto_reset       = bool( data.get("auto_reset",       auto_reset))
		calm_if_released = bool( data.get("calm_if_released", calm_if_released))
		shake_max_amp    = float(data.get("shake_max_amp",    shake_max_amp))
		shake_frequency  = float(data.get("shake_frequency",  shake_frequency))
		shake_ramp_speed = float(data.get("shake_ramp_speed", shake_ramp_speed))

	func get_display_name() -> String:
		return "Falling (%.1fs)" % fall_delay
