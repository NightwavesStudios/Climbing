# hold_modifiers.gd
# res://scripts/holds/hold_modifiers.gd
# ═══════════════════════════════════════════════════════════════════════════════
# Contains:
#   1. HoldModifierBase      — base class, extend this for every modifier
#   2. FallingHoldModifier   — hold that shakes then falls when grabbed
#
# To add a new modifier, extend HoldModifierBase here (or in a new file),
# then register the type key in hold_modifier_registry.gd.
# ═══════════════════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 1 — BASE CLASS
#  All modifiers extend this. Override only the hooks you need.
# ═══════════════════════════════════════════════════════════════════════════════

class_name HoldModifierBase
extends Node

# Unique string key written to / read from JSON. Set in every subclass _ready().
var modifier_type: String = "base"

# The hold Area2D/Node2D this modifier is a child of.
# Assigned automatically in _ready() and by the registry before add_child().
var hold: Node2D = null

func _ready() -> void:
	hold = get_parent() as Node2D
	if hold == null:
		push_error("HoldModifierBase (%s): parent must be a Node2D hold." % modifier_type)

# ── Override these in subclasses ──────────────────────────────────────────────

## Called once after hold + modifier are both in the scene tree.
func on_hold_ready() -> void:
	pass

## Called every frame via the hold's _process().
func on_process(_delta: float) -> void:
	pass

## Return false to block a grab before it is registered.
func allow_grab(_limb_node: Node2D, _is_foot: bool) -> bool:
	return true

## Called after a limb successfully claims this hold.
func on_grab(_limb_node: Node2D) -> void:
	pass

## Called whenever a limb releases (player choice or force-release).
func on_release(_limb_node: Node2D) -> void:
	pass

## Return the (possibly modified) pressure value for this frame.
func modify_pressure(raw: float, _delta: float) -> float:
	return raw

## Return the (possibly modified) recovery value for this frame.
func modify_recovery(raw: float, _delta: float) -> float:
	return raw

## Return a Dictionary that fully describes this modifier's config (for JSON).
func serialize() -> Dictionary:
	return {"type": modifier_type}

## Restore config from a Dictionary produced by serialize().
func deserialize(_data: Dictionary) -> void:
	pass

## Human-readable label shown in the editor modifier dropdown.
func get_display_name() -> String:
	return modifier_type.capitalize()


# ═══════════════════════════════════════════════════════════════════════════════
#  SECTION 2 — FALLING HOLD MODIFIER
#  Type key: "falling"
#  Registered in hold_modifier_registry.gd under "falling".
#
#  State machine:
#    IDLE      → waiting for any limb to grab
#    SHAKING   → rattling with orange tint, ramps up over fall_delay seconds
#    FALLING   → limbs force-released, hold drops, collision disabled
#    FALLEN    → resting off-screen, waiting for reset_delay
#    RESETTING → snaps back to origin, collision re-enabled
#
#  Early-release behaviour:
#    If the climber releases ALL limbs before 50 % of fall_delay has elapsed,
#    the hold calms back to IDLE (configurable via calm_if_released).
# ═══════════════════════════════════════════════════════════════════════════════

class FallingHoldModifier extends HoldModifierBase:

	# ── Tunable parameters (all round-trip through JSON) ─────────────────────
	var fall_delay:       float = 2.2     # seconds from first grab to fall
	var reset_delay:      float = 4.0     # seconds fallen before auto-reset
	var fall_gravity:     float = 1800.0  # px/s² while falling
	var auto_reset:       bool  = true    # if false, stays fallen forever
	var calm_if_released: bool  = true    # calm when all limbs let go early

	var shake_max_amp:    float = 6.0     # peak shake radius in pixels
	var shake_frequency:  float = 22.0    # oscillations per second
	var shake_ramp_speed: float = 1.8     # lerp speed 0 → full amplitude

	var warning_color: Color = Color(1.0,  0.55, 0.20, 1.0)   # orange
	var fallen_color:  Color = Color(0.35, 0.35, 0.35, 0.50)  # grey

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
	var _claimed_limbs: Array[Node2D] = []

	# ── Lifecycle ─────────────────────────────────────────────────────────────

	func _ready() -> void:
		modifier_type = "falling"
		super._ready()

	func on_hold_ready() -> void:
		# Wait one frame so the hold has its final world-space position
		await hold.get_tree().process_frame
		_origin = hold.global_position

	# ── Per-frame ─────────────────────────────────────────────────────────────

	func on_process(delta: float) -> void:
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
		var progress  = clamp(_shake_timer / fall_delay, 0.0, 1.0)
		_shake_lerp    = lerp(_shake_lerp, 1.0, shake_ramp_speed * delta)

		var amp := _shake_lerp * shake_max_amp
		var ox  := sin(_time * shake_frequency * TAU)              * amp
		var oy  := sin(_time * shake_frequency * TAU * 1.3 + 1.1) * amp * 0.55
		hold.global_position = _origin + Vector2(ox, oy)
		hold.modulate        = Color.WHITE.lerp(warning_color, progress)

		if _shake_timer >= fall_delay:
			_enter_falling()

	func _tick_falling(delta: float) -> void:
		_fall_velocity       += fall_gravity * delta
		hold.global_position += Vector2(0.0, _fall_velocity * delta)
		_fall_timer          += delta
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
		hold.global_position = _origin
		hold.modulate        = fallen_color

	func _enter_idle_calm() -> void:
		_state               = _State.IDLE
		_shake_timer         = 0.0
		_shake_lerp          = 0.0
		hold.global_position = _origin
		hold.modulate        = Color.WHITE

	func _enter_resetting() -> void:
		_state       = _State.RESETTING
		_reset_timer = 0.0

	func _do_reset() -> void:
		_state               = _State.IDLE
		_shake_timer         = 0.0
		_shake_lerp          = 0.0
		_fall_timer          = 0.0
		_fall_velocity       = 0.0
		_reset_timer         = 0.0
		_claimed_limbs.clear()
		hold.global_position = _origin
		hold.modulate        = Color.WHITE
		_set_collision_enabled(true)

	# ── Helpers ───────────────────────────────────────────────────────────────

	func _force_release_all() -> void:
		for limb in _claimed_limbs.duplicate():
			if is_instance_valid(limb) and hold.has_method("release"):
				hold.release(limb)
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
			"warning_color":    [warning_color.r, warning_color.g,
								 warning_color.b, warning_color.a],
			"fallen_color":     [fallen_color.r,  fallen_color.g,
								 fallen_color.b,  fallen_color.a],
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
		if "warning_color" in data:
			var c: Array = data["warning_color"]
			warning_color = Color(c[0], c[1], c[2], c[3])
		if "fallen_color" in data:
			var c: Array = data["fallen_color"]
			fallen_color = Color(c[0], c[1], c[2], c[3])

	func get_display_name() -> String:
		return "Falling (%.1fs)" % fall_delay
