extends CharacterBody2D

# =============================================================================
#  LIMB STATE CLASSES
# =============================================================================

class LimbState:
	var node:  Node2D
	var joint: Node2D

	var hold:   Area2D  = null
	var pin:    Vector2 = Vector2.ZERO
	var anchor: Vector2 = Vector2.ZERO

	var pressure:    float = 0.0
	var grip:        int   = 0
	var static_time: float = 0.0
	var force:       float = 0.0

	var velocity:       Vector2 = Vector2.ZERO
	var joint_velocity: Vector2 = Vector2.ZERO
	var grab_target:    Vector2 = Vector2.ZERO
	var previous_pos:   Vector2 = Vector2.ZERO

	var is_grabbing: bool = false
	var selected:    bool = false
	var is_left:     bool = false

	var shake_offset:  Vector2 = Vector2.ZERO
	var visual_offset: Vector2 = Vector2.ZERO
	var shake_lerp:    float   = 0.0

	var ghost:      Vector2 = Vector2.ZERO
	var ghost_init: bool    = false

	func is_hand() -> bool: return false
	func is_foot() -> bool: return false

	func origin(_body: Vector2, _soff: float, _hoff: float, _hdown: float) -> Vector2:
		return Vector2.ZERO

	func reach(_au: float, _al: float, _lu: float, _ll: float) -> float:
		return 0.0

	func is_load_bearing() -> bool:
		return hold != null and not is_grabbing

	func reset_velocity() -> void:
		velocity = Vector2.ZERO
		joint_velocity = Vector2.ZERO

	func reset_all() -> void:
		hold = null
		pin = Vector2.ZERO
		anchor = Vector2.ZERO
		pressure = 0.0
		grip = 0
		static_time = 0.0
		force = 0.0
		reset_velocity()
		grab_target = Vector2.ZERO
		is_grabbing = false
		selected = false
		shake_offset = Vector2.ZERO
		visual_offset = Vector2.ZERO
		shake_lerp = 0.0
		ghost_init = false


class HandState extends LimbState:
	var fail_stage:     int   = 0
	var struggle_timer: float = 0.0
	var catch_boost:    float = 1.0
	var catch_timer:    float = 0.0

	func is_hand() -> bool: return true

	func origin(body: Vector2, soff: float, _hoff: float, _hdown: float) -> Vector2:
		return body + Vector2(-soff if is_left else soff, 0.0)

	func reach(au: float, al: float, _lu: float, _ll: float) -> float:
		return au + al

	func reset_all() -> void:
		super.reset_all()
		fail_stage = 0
		struggle_timer = 0.0
		catch_boost = 1.0
		catch_timer = 0.0


class FootState extends LimbState:
	var manual:        bool = false
	var user_override: bool = false

	func is_foot() -> bool: return true

	func origin(body: Vector2, _soff: float, hoff: float, hdown: float) -> Vector2:
		return body + Vector2(-hoff if is_left else hoff, hdown)

	func reach(_au: float, _al: float, lu: float, ll: float) -> float:
		return lu + ll

	func reset_all() -> void:
		super.reset_all()
		manual = false
		user_override = false


# =============================================================================
#  CLIMBER
# =============================================================================

@onready var main_scene: Node  = get_tree().current_scene
@onready var cam: Camera2D     = $"../Camera2D"

var camera_owned_by_main: bool = false

@onready var _lh_node:  Node2D = $LeftHand
@onready var _rh_node:  Node2D = $RightHand
@onready var _lf_node:  Node2D = $LeftFoot
@onready var _rf_node:  Node2D = $RightFoot
@onready var _lh_joint: Node2D = $LeftHandJoint
@onready var _rh_joint: Node2D = $RightHandJoint
@onready var _lf_joint: Node2D = $LeftFootJoint
@onready var _rf_joint: Node2D = $RightFootJoint
@onready var _lh_area:  Area2D = $LeftHand/Area2D
@onready var _rh_area:  Area2D = $RightHand/Area2D
@onready var _lf_area:  Area2D = $LeftFoot/Area2D
@onready var _rf_area:  Area2D = $RightFoot/Area2D

@export var debug:         bool  = false
@export var aesthetic:     bool  = true
@export var show_load_hud: bool  = true
@export var GRAB_RADIUS:   float = 35.0

# =============================================================================
#  OUTLINE EXPORTS
# =============================================================================
@export_group("Outline")
@export var figure_outline_enabled: bool = true
@export var figure_outline_width: float = 5.5
@export_range(0.0, 1.0, 0.01) var figure_outline_alpha: float = 1
@export_range(0.0, 1.0, 0.01) var figure_outline_darken: float = 0.25
@export_group("")

enum GripState    { RELAXED, ENGAGED, PUMPED, FAIL }
enum FailureStage { NONE, SLIP, STRUGGLE, FALLING }

const CAM_LERP = 0.05

# -- Anatomy ------------------------------------------------------------------
const ARM_UPPER_LENGTH  = 50.0
const ARM_LOWER_LENGTH  = 50.0
const LEG_UPPER_LENGTH  = 45.0
const LEG_LOWER_LENGTH  = 45.0
const SHOULDER_OFFSET   = 0.0
const HIP_OFFSET        = 0.0
const HIP_DOWN          = 20.0
const HEAD_OFFSET       = -20.0
const COM_OFFSET_Y      = 15.0

# -- Physics ------------------------------------------------------------------
const GRAVITY                   = 2200.0
const BODY_DRAG                 = 0.96
const LIMB_DRAG                 = 0.94
const BODY_PULL_STRENGTH        = 0.55
const JOINT_STIFFNESS           = 0.92
const LIMB_STIFFNESS            = 0.92
const MAX_JOINT_STRETCH         = 1.0
const MAX_LIMB_STRETCH          = 1.0
const MAX_LEG_TOTAL_STRETCH     = 1.0
const LEG_FORCE_RELEASE_THRESHOLD = 1.15
const HAND_LOAD_TOLERANCE       = 1.08
const FOOT_RELEASE_THRESHOLD    = 2.2
const FOOT_CUT_THRESHOLD        = 320.0

# -- Foot support -------------------------------------------------------------
const FOOT_SUPPORT_STRENGTH  = 0.40
const FOOT_SUPPORT_MIN_Y     = -30.0
const FOOT_SUPPORT_MAX_PUSH  = 80.0
const FOOT_LATERAL_ASSIST    = 0.08

# -- Natural pose -------------------------------------------------------------
const ARM_NATURAL_ANGLE_DEG      = 45.0
const FREE_ARM_RELAXATION_SPEED = 0.10
const FREE_LEG_RELAXATION_SPEED = 0.10

# -- Pressure -----------------------------------------------------------------
const PRESSURE_ENGAGED = 25.0
const PRESSURE_PUMPED  = 60.0
const PRESSURE_FAIL    = 100.0

const ONE_ARM_PRESSURE_MULTIPLIER    = 1.8
const TWO_ARM_PRESSURE_MULTIPLIER    = 1.5
const THREE_LIMB_PRESSURE_MULTIPLIER = 1.0
const FOUR_LIMB_PRESSURE_MULTIPLIER  = 0.6
const FOOT_PRESSURE_REDUCTION        = 0.3
const EASY_HOLD_BASE_PRESSURE        = 0.8
const POOR_POSITION_PRESSURE_MULT    = 1.6
const LOCK_OFF_PRESSURE_MULT         = 1.5
const LOCK_OFF_THRESHOLD             = 0.7
const SHAKE_OUT_RECOVERY_RATE        = 14.0
const SHARED_HOLD_PRESSURE_MULT      = 1.82

# -- Exertion / catch ---------------------------------------------------------
const UPWARD_VELOCITY_THRESHOLD    = -80.0
const UPWARD_DRAIN_MULT            = 1.5
const SOLE_SUPPORT_DRAIN_MULT      = 1.2
const CATCH_BURST_1_LIMB           = 0.20
const CATCH_BURST_2_LIMB           = 0.08
const CATCH_DRAIN_BOOST_1          = 1.5
const CATCH_DRAIN_BOOST_2          = 1.2
const CATCH_DRAIN_BOOST_DURATION_1 = 1.0
const CATCH_DRAIN_BOOST_DURATION_2 = 0.5

# -- Fatigue / P2 -------------------------------------------------------------
const P2_FORCE_ONSET    = 0.45
const P2_FORCE_MID      = 0.70
const P2_FORCE_HIGH     = 0.90
const P2_MAX_SAG_PX     = 10.0
const P2_REST_DRAIN_BOTH_FEET = 0.30
const P2_REST_DRAIN_ONE_FOOT  = 0.65
const P2_REST_RECOVERY_SCALE  = 1.5
const P2_SHAKE_ONSET    = 0.15
const P2_SHAKE_MAX_AMP  = 3.0
const P2_SHAKE_LERP_IN  = 0.2
const P2_SHAKE_LERP_OUT = 1.2
const P2_PULSE_ONSET    = 0.65
const P2_PULSE_AMP      = 1.8
const P2_PULSE_FREQ     = 3.0
const P2_DARK_ONSET     = 0.35
const P2_DARK_COLOR     = Color(0.18, 0.12, 0.12, 1.0)
const P2_DARK_MAX_BLEND = 0.55
const SHAKE_LERP_SPEED  = 2.0

# -- Failure / P3 -------------------------------------------------------------
const P3_LEG_BONUS_DRAIN_MULT = 0.88
const P3_LEG_BONUS_COM_TOL   = 50.0
const P3_LEG_BONUS_RAMP      = 0.5
const P3_SLIP_THRESHOLD      = 0.90
const P3_STRUGGLE_THRESHOLD  = 1.00
const P3_STRUGGLE_WINDOW     = 0.55

# -- Adaptive legs ------------------------------------------------------------
const ENABLE_ADAPTIVE_LEGS     = true
const LEG_ASSIST_THRESHOLD     = 0.8
const LEG_ASSIST_STRENGTH      = 0.4
const LEG_ASSIST_SPEED         = 0.3
const LEG_ASSIST_MAX_EXTENSION = 0.92

# -- Mouse / aim --------------------------------------------------------------
const MOUSE_CONTROL_ENABLED  = true
const MOUSE_DEADZONE         = 5.0
const BASE_HAND_MOVE_SPEED   = 0.75
const CRIMP_LEG_SPEED_FACTOR = 0.45

# -- Grab sharing -------------------------------------------------------------
const SHARED_HOLD_HAND_OFFSET      = 5.0
const SHARED_HOLD_HAND_FOOT_OFFSET = 5.0

# -- Hip shift ----------------------------------------------------------------
const HIP_SHIFT_STRENGTH   = 0.022
const HIP_SHIFT_MAX_RADIUS = 60.0
const HIP_SHIFT_DEADZONE   = 18.0
const HIP_SHIFT_MAX_SPEED  = 300.0

# -- Load distribution --------------------------------------------------------
const LOAD_LERP_SPEED = 4.0

# -- Fall detection -----------------------------------------------------------
const FALL_DETECTION_TIME     = 2.0
const FALL_VELOCITY_THRESHOLD = 400.0

# -- Visual -------------------------------------------------------------------
const VISUAL_ANIMATION_SPEED = 0.25

# -- Draw scale / hover jitter ------------------------------------------------
const LIMB_FREE_SCALE_TARGET = 1.15
const LIMB_SCALE_LERP_SPEED  = 8.0
const HOVER_JITTER_RADIUS    = 60.0
const HOVER_JITTER_AMP       = 1.6
const HOVER_JITTER_FREQ      = 22.0

# =============================================================================
#  RUNTIME STATE
# =============================================================================

var _lh_press_time: float = 0.0
var _rh_press_time: float = 0.0
var _lf_press_time: float = 0.0
var _rf_press_time: float = 0.0

const QUICK_TAP_THRESHOLD: float = 0.1

var lh: HandState
var rh: HandState
var lf: FootState
var rf: FootState

var _limbs: Array = []
var _hands: Array = []
var _feet:  Array = []

var com_position:    Vector2 = Vector2.ZERO
var com_velocity:    Vector2 = Vector2.ZERO
var body_velocity:   Vector2 = Vector2.ZERO
var last_held_limbs: int     = 0

var selected_limbs:     Array   = []
var mouse_aim_position: Vector2 = Vector2.ZERO
var use_mouse_aim:      bool    = false
var building_momentum:  bool    = false

var _hip_shift_offset: Vector2      = Vector2.ZERO
var _load:             Array[float] = [0.0, 0.0, 0.0, 0.0]

var rest_mode_active:  bool  = false
var _leg_bonus_smooth: float = 1.0

var spawn_position:    Vector2 = Vector2.ZERO
var climb_started:     bool    = false
var climb_completed:   bool    = false
var _grab_initialized: bool    = false

var fall_timer:        float = 0.0
var _ragdoll_active:   bool  = false
var _ragdoll_elapsed:  float = 0.0
var _ragdoll_max_time: float = 2.0

var current_discipline: int    = 0
var rope_system:        Node2D = null
var speed_timer:        Node   = null
var speed_climb_active: bool   = false
var _weather_modifier:  Node   = null
var _spotlight:         Node   = null

# -- Draw scale & hover jitter ------------------------------------------------
var _lh_draw_scale:   float   = 1.0
var _rh_draw_scale:   float   = 1.0
var _lf_draw_scale:   float   = 1.0
var _rf_draw_scale:   float   = 1.0

var _lh_hover_jitter: Vector2 = Vector2.ZERO
var _rh_hover_jitter: Vector2 = Vector2.ZERO
var _lf_hover_jitter: Vector2 = Vector2.ZERO
var _rf_hover_jitter: Vector2 = Vector2.ZERO

# -- Input gate (set by main.gd during route preview) -------------------------
var _input_enabled: bool = true
var _r_was_pressed: bool = false

# =============================================================================
#  INIT
# =============================================================================

func _ready() -> void:
	z_index = 10
	spawn_position = global_position
	_build_limbs()
	_set_default_local_positions()
	for area in [_lh_area, _rh_area, _lf_area, _rf_area]:
		area.collision_mask = 2
	com_position = global_position + Vector2(0, COM_OFFSET_Y)
	for s in _limbs:
		s.previous_pos = s.node.global_position
	_weather_modifier = get_tree().get_first_node_in_group("weather_modifier")
	_spotlight        = get_node_or_null("SpotLight2D")
	await get_tree().process_frame
	call_deferred("initial_grab")


func _build_limbs() -> void:
	lh = HandState.new(); lh.is_left = true;  lh.node = _lh_node; lh.joint = _lh_joint
	rh = HandState.new(); rh.is_left = false; rh.node = _rh_node; rh.joint = _rh_joint
	lf = FootState.new(); lf.is_left = true;  lf.node = _lf_node; lf.joint = _lf_joint
	rf = FootState.new(); rf.is_left = false; rf.node = _rf_node; rf.joint = _rf_joint
	_limbs = [lh, rh, lf, rf]
	_hands = [lh, rh]
	_feet  = [lf, rf]


func _set_default_local_positions() -> void:
	_lh_joint.position = Vector2(-SHOULDER_OFFSET, 10)
	_rh_joint.position = Vector2( SHOULDER_OFFSET, 10)
	_lh_node.position  = Vector2(-SHOULDER_OFFSET, 10 + ARM_LOWER_LENGTH)
	_rh_node.position  = Vector2( SHOULDER_OFFSET, 10 + ARM_LOWER_LENGTH)
	_lf_joint.position = Vector2(-HIP_OFFSET, HIP_DOWN + 20)
	_rf_joint.position = Vector2( HIP_OFFSET, HIP_DOWN + 20)
	_lf_node.position  = Vector2(-HIP_OFFSET, HIP_DOWN + LEG_UPPER_LENGTH + LEG_LOWER_LENGTH / 2)
	_rf_node.position  = Vector2( HIP_OFFSET, HIP_DOWN + LEG_UPPER_LENGTH + LEG_LOWER_LENGTH / 2)
	_ensure_shadow_node()

# =============================================================================
#  INPUT GATE (called by main.gd during route preview)
# =============================================================================

func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		# Clean up any in-flight selection so the character isn't left dangling
		selected_limbs.clear()
		use_mouse_aim = false

# =============================================================================
#  MAIN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if not _grab_initialized:
		queue_redraw()
		if _shadow_node and is_instance_valid(_shadow_node):
			_shadow_node.queue_redraw()
		return

	if _ragdoll_active:
		_ragdoll_elapsed += delta
		if _ragdoll_elapsed >= _ragdoll_max_time:
			_ragdoll_active = false
		update_camera()
		queue_redraw()
		if _shadow_node and is_instance_valid(_shadow_node):
			_shadow_node.queue_redraw()
		return

	handle_input()
	update_grip_states(delta)
	update_shake_effects(delta)
	simulate_physics(delta)
	_update_load_distribution(delta)
	check_fall_detection(delta)
	check_climb_completion()
	update_camera()
	_update_spotlight()
	_update_weather_modifier()
	_update_draw_scales(delta)
	queue_redraw()
	if _shadow_node and is_instance_valid(_shadow_node):
		_shadow_node.queue_redraw()

# =============================================================================
#  INPUT
# =============================================================================

func handle_input() -> void:
	# Bail out when main.gd has locked input (e.g. during route preview)
	if not _input_enabled:
		return

	var r_pressed := Input.is_key_pressed(KEY_R)
	if Input.is_action_just_pressed("ui_cancel") or (r_pressed and not _r_was_pressed):
		var main = get_tree().current_scene
		if main and main.has_method("on_player_reset"):
			main.on_player_reset()
		else:
			reset_climb()
		return
	_r_was_pressed = r_pressed

	building_momentum = false
	var shift_held = Input.is_key_pressed(KEY_SHIFT)

	rest_mode_active = (shift_held
		and selected_limbs.is_empty()
		and (lh.hold != null or rh.hold != null))

	_sel_press("select_left",       lh, shift_held, false)
	_sel_press("select_right",      rh, shift_held, false)
	_sel_press("select_left_foot",  lf, shift_held, true)
	_sel_press("select_right_foot", rf, shift_held, true)

	if MOUSE_CONTROL_ENABLED and not selected_limbs.is_empty():
		var mouse_global = get_global_mouse_position()
		var centroid     = _selected_centroid()
		if centroid.distance_to(mouse_global) > MOUSE_DEADZONE:
			use_mouse_aim      = true
			mouse_aim_position = mouse_global
			building_momentum  = true
		else:
			use_mouse_aim = false
	else:
		use_mouse_aim = false

	_sel_release("select_left",       lh, shift_held, false)
	_sel_release("select_right",      rh, shift_held, false)
	_sel_release("select_left_foot",  lf, shift_held, true)
	_sel_release("select_right_foot", rf, shift_held, true)

func _set_press_time(s: LimbState, t: float) -> void:
	if   s == lh: _lh_press_time = t
	elif s == rh: _rh_press_time = t
	elif s == lf: _lf_press_time = t
	elif s == rf: _rf_press_time = t

func _get_press_time(s: LimbState) -> float:
	if   s == lh: return _lh_press_time
	elif s == rh: return _rh_press_time
	elif s == lf: return _lf_press_time
	elif s == rf: return _rf_press_time
	return 0.0

func _sel_press(action: String, s: LimbState, shift_held: bool, is_foot: bool) -> void:
	if not Input.is_action_just_pressed(action):
		return
	_set_press_time(s, Time.get_ticks_msec() * 0.001)
	if is_foot:
		if shift_held:
			_toggle_sel(s)
		else:
			if not (lh in selected_limbs) and not (rh in selected_limbs):
				selected_limbs.clear()
			if s not in selected_limbs:
				selected_limbs.append(s)
		(s as FootState).user_override = true
	else:
		if shift_held:
			_toggle_sel(s)
		else:
			selected_limbs.clear()
			selected_limbs.append(s)
	s.ghost      = s.node.global_position
	s.ghost_init = true
	if s.hold != null and s in selected_limbs:
		release_limb(s)
		s.is_grabbing = false


func _sel_release(action: String, s: LimbState, shift_held: bool, is_foot: bool) -> void:
	if not Input.is_action_just_released(action):
		return
	if s in selected_limbs:
		var held_secs: float = Time.get_ticks_msec() * 0.001 - _get_press_time(s)
		if held_secs < QUICK_TAP_THRESHOLD:
			release_limb(s)
			s.is_grabbing = false
		else:
			if s.is_hand():
				_fire_dyno_impulse()
			attempt_grab(s)
			if is_foot:
				(s as FootState).manual = true
	if not shift_held:
		if is_foot:
			if not (lh in selected_limbs) and not (rh in selected_limbs):
				selected_limbs.clear()
		else:
			selected_limbs.clear()
	use_mouse_aim = false
	if is_foot:
		var fs = s as FootState
		fs.user_override = false
		if fs.hold == null:
			fs.manual = false


func _toggle_sel(s: LimbState) -> void:
	if s in selected_limbs: selected_limbs.erase(s)
	else: selected_limbs.append(s)


func _selected_centroid() -> Vector2:
	if selected_limbs.is_empty():
		return global_position
	var sum = Vector2.ZERO
	for s in selected_limbs:
		sum += s.node.global_position
	return sum / selected_limbs.size()

# =============================================================================
#  GRIP STATES
# =============================================================================

func update_grip_states(delta: float) -> void:
	_leg_bonus_smooth = lerp(_leg_bonus_smooth, _compute_leg_bonus_target(), P3_LEG_BONUS_RAMP * delta)
	for s in _limbs:
		_update_limb_grip(s, delta)

func _update_limb_grip(s: LimbState, delta: float) -> void:
	if s.hold != null and s not in selected_limbs:
		s.static_time += delta
	else:
		s.static_time = 0.0

	if s.hold != null:
		var body_offset  = _calculate_body_offset(s)
		var foot_support = _calculate_foot_support_ratio()
		var held_count   = _count_held_limbs()
		var loading_mult = _get_loading_multiplier(held_count)
		var hold_pressure = s.hold.get_state_pressure(delta, body_offset, s.static_time, foot_support, s.node)

		if s.is_hand():
			hold_pressure = _apply_hand_pressure_mods(s as HandState, hold_pressure, loading_mult, body_offset, foot_support, delta)
		else:
			hold_pressure = _apply_foot_pressure_mods(hold_pressure, loading_mult, body_offset, delta)

		var sharing = _limbs.any(func(o): return o != s and o.hold == s.hold)
		if sharing:
			hold_pressure *= SHARED_HOLD_PRESSURE_MULT

		hold_pressure *= _leg_bonus_smooth
		s.pressure     = clamp(s.pressure + hold_pressure, 0.0, PRESSURE_FAIL)

		var recovery = s.hold.get_recovery_rate(delta, _calculate_body_balance(), foot_support)
		if recovery > 0.0:
			if rest_mode_active and foot_support > 0.0 and s.is_hand():
				recovery *= P2_REST_RECOVERY_SCALE
			s.pressure -= recovery
	else:
		s.force = 0.0
		if s not in selected_limbs:
			s.pressure -= SHAKE_OUT_RECOVERY_RATE * delta

	s.pressure = clamp(s.pressure, 0.0, PRESSURE_FAIL)

	if s.is_hand():
		_update_hand_failure_stage(s as HandState, delta)
		if (s as HandState).fail_stage == FailureStage.FALLING:
			s.grip = GripState.FAIL
			release_limb(s)
			return
	elif s.pressure >= PRESSURE_FAIL:
		s.grip = GripState.FAIL
		release_limb(s)
		return

	if s.pressure >= PRESSURE_PUMPED:    s.grip = GripState.PUMPED
	elif s.pressure >= PRESSURE_ENGAGED: s.grip = GripState.ENGAGED
	else:                                s.grip = GripState.RELAXED

func _apply_hand_pressure_mods(s: HandState, p: float, loading_mult: float,
		body_offset: float, foot_support: float, delta: float) -> float:
	var pull_force = abs(com_velocity.y) + abs(com_velocity.x) * 0.3
	s.force = pull_force * (1.0 - foot_support)
	var arm_ext = _calculate_arm_extension(s)
	var lockoff = LOCK_OFF_PRESSURE_MULT if arm_ext < LOCK_OFF_THRESHOLD else 1.0
	p *= (1.0 + s.force * 0.01) * lockoff * loading_mult
	p *= _get_hand_exertion_mult(s)
	p *= _tick_catch_boost(s, delta)
	if rest_mode_active:
		if foot_support >= 1.0:   p *= P2_REST_DRAIN_BOTH_FEET
		elif foot_support > 0.0:  p *= P2_REST_DRAIN_ONE_FOOT
	var pressure_floor = EASY_HOLD_BASE_PRESSURE * loading_mult * 0.5 * delta
	if p < pressure_floor: p = pressure_floor
	if body_offset > 0.5:  p *= POOR_POSITION_PRESSURE_MULT
	return p


func _apply_foot_pressure_mods(p: float, loading_mult: float, body_offset: float, delta: float) -> float:
	p *= FOOT_PRESSURE_REDUCTION * loading_mult
	var floor_p = EASY_HOLD_BASE_PRESSURE * FOOT_PRESSURE_REDUCTION
	if p < floor_p: p = floor_p * delta
	if body_offset > 0.5: p *= 1.2
	return p


func _compute_leg_bonus_target() -> float:
	if not (lf.hold and rf.hold): return 1.0
	var mid_x = (lf.hold.get_limb_anchor(lf.node).x + rf.hold.get_limb_anchor(rf.node).x) * 0.5
	return P3_LEG_BONUS_DRAIN_MULT if abs(com_position.x - mid_x) <= P3_LEG_BONUS_COM_TOL else 1.0


func _update_hand_failure_stage(s: HandState, delta: float) -> void:
	if s.hold == null:
		s.fail_stage = FailureStage.NONE; s.struggle_timer = 0.0; return
	var t = s.pressure / PRESSURE_FAIL
	if t < P3_SLIP_THRESHOLD:
		s.fail_stage = FailureStage.NONE; s.struggle_timer = 0.0
	elif t < P3_STRUGGLE_THRESHOLD:
		s.fail_stage = FailureStage.SLIP; s.struggle_timer = 0.0
	elif s.fail_stage != FailureStage.STRUGGLE:
		s.fail_stage = FailureStage.STRUGGLE; s.struggle_timer = P3_STRUGGLE_WINDOW
	else:
		s.struggle_timer -= delta
		if s.struggle_timer <= 0.0: s.fail_stage = FailureStage.FALLING


func _get_hand_exertion_mult(s: HandState) -> float:
	if _count_held_limbs() == 1 and s.is_load_bearing(): return SOLE_SUPPORT_DRAIN_MULT
	if com_velocity.y < UPWARD_VELOCITY_THRESHOLD and s.is_load_bearing(): return UPWARD_DRAIN_MULT
	return 1.0


func _tick_catch_boost(s: HandState, delta: float) -> float:
	if s.catch_timer > 0.0:
		s.catch_timer -= delta
		if s.catch_timer <= 0.0: s.catch_timer = 0.0; s.catch_boost = 1.0
	return s.catch_boost


func _apply_catch_penalty(s: HandState) -> void:
	if com_velocity.y < FALL_VELOCITY_THRESHOLD: return
	if _count_held_limbs() == 1:
		s.pressure    = minf(s.pressure + PRESSURE_FAIL * CATCH_BURST_1_LIMB, PRESSURE_FAIL)
		s.catch_boost = CATCH_DRAIN_BOOST_1; s.catch_timer = CATCH_DRAIN_BOOST_DURATION_1
	else:
		s.pressure    = minf(s.pressure + PRESSURE_FAIL * CATCH_BURST_2_LIMB, PRESSURE_FAIL)
		s.catch_boost = CATCH_DRAIN_BOOST_2; s.catch_timer = CATCH_DRAIN_BOOST_DURATION_2


func _get_grip_force_scalar(pressure: float) -> float:
	var t = pressure / PRESSURE_FAIL
	if t < P2_FORCE_ONSET:  return 1.0
	elif t < P2_FORCE_MID:  return lerp(1.0,  0.75, (t - P2_FORCE_ONSET) / (P2_FORCE_MID  - P2_FORCE_ONSET))
	elif t < P2_FORCE_HIGH: return lerp(0.75, 0.50, (t - P2_FORCE_MID)   / (P2_FORCE_HIGH - P2_FORCE_MID))
	return lerp(0.50, 0.0, (t - P2_FORCE_HIGH) / (1.0 - P2_FORCE_HIGH))


func _get_body_fatigue_t() -> float:
	var total = 0.0; var count = 0
	for s in _hands:
		if s.hold: total += s.pressure / PRESSURE_FAIL; count += 1
	return total / max(count, 1)

# =============================================================================
#  SHAKE EFFECTS
# =============================================================================

func update_shake_effects(delta: float) -> void:
	var t_now = Time.get_ticks_msec() * 0.001

	for s in _hands:
		var hs   = s as HandState
		var base = _get_pressure_shake_frac(hs.pressure)
		var fadd = 0.0
		if   hs.fail_stage == FailureStage.SLIP:     fadd = 0.15
		elif hs.fail_stage == FailureStage.STRUGGLE: fadd = 0.35
		var tgt = minf(base + fadd, 1.0)
		var spd = P2_SHAKE_LERP_IN if tgt > hs.shake_lerp else P2_SHAKE_LERP_OUT
		hs.shake_lerp = lerp(hs.shake_lerp, tgt, spd * delta)
		if hs.shake_lerp > 0.01:
			var amp  = hs.shake_lerp * P2_SHAKE_MAX_AMP
			var freq = 28.0 + hs.shake_lerp * 8.0
			var ph   = 0.0 if hs.is_left else 0.5
			hs.shake_offset = (Vector2(sin(t_now * freq + ph) * amp,
				sin(t_now * freq * 1.3 + 1.7 + ph) * amp)
				+ _get_pulse_offset(hs.pressure, 0.0 if hs.is_left else PI))
		else:
			hs.shake_offset = Vector2.ZERO

	for s in _feet:
		var mods      = _get_foot_modifiers(s.grip)
		var tgt_shake = mods.shake
		s.shake_lerp  = lerp(s.shake_lerp, tgt_shake, SHAKE_LERP_SPEED * delta)
		if s.shake_lerp > 0.01:
			var freq = 25.0 + s.shake_lerp * 15.0
			var amp  = s.shake_lerp * 2.5
			var ph   = 1.0 if s.is_left else 1.5
			s.shake_offset = Vector2(sin(t_now * freq + ph) * amp,
				sin(t_now * freq * 1.2 + ph - 0.2) * amp)
		else:
			s.shake_offset = Vector2.ZERO


func _get_hand_modifiers(grip: int) -> Dictionary:
	match grip:
		GripState.RELAXED: return {"reach_mult": 1.0,  "speed_mult": 1.0,  "latency": 0.0,  "shake": 0.0}
		GripState.ENGAGED: return {"reach_mult": 0.95, "speed_mult": 0.98, "latency": 0.02, "shake": 0.05}
		GripState.PUMPED:  return {"reach_mult": 0.82, "speed_mult": 0.78, "latency": 0.10, "shake": 0.20}
		GripState.FAIL:    return {"reach_mult": 0.0,  "speed_mult": 0.0,  "latency": 1.0,  "shake": 1.0}
	return _get_hand_modifiers(GripState.RELAXED)


func _get_foot_modifiers(grip: int) -> Dictionary:
	match grip:
		GripState.RELAXED: return {"shake": 0.0}
		GripState.ENGAGED: return {"shake": 0.04}
		GripState.PUMPED:  return {"shake": 0.14}
		GripState.FAIL:    return {"shake": 0.6}
	return _get_foot_modifiers(GripState.RELAXED)


func _get_pressure_shake_frac(p: float) -> float:
	var t = p / PRESSURE_FAIL
	if t < P2_SHAKE_ONSET: return 0.0
	return (t - P2_SHAKE_ONSET) / (1.0 - P2_SHAKE_ONSET)


func _get_pulse_offset(pressure: float, phase: float) -> Vector2:
	var t = pressure / PRESSURE_FAIL
	if t < P2_PULSE_ONSET: return Vector2.ZERO
	var strength = (t - P2_PULSE_ONSET) / (1.0 - P2_PULSE_ONSET)
	var p = sin(Time.get_ticks_msec() * 0.001 * P2_PULSE_FREQ * TAU + phase) * P2_PULSE_AMP * strength
	return Vector2(p * 0.25, p)


func _get_limb_color(pressure: float) -> Color:
	var t = pressure / PRESSURE_FAIL
	if t < P2_DARK_ONSET: return Color.BLACK
	var blend = minf((t - P2_DARK_ONSET) / (1.0 - P2_DARK_ONSET), 1.0) * P2_DARK_MAX_BLEND
	return Color.BLACK.lerp(P2_DARK_COLOR, blend)

# =============================================================================
#  DRAW SCALE & HOVER JITTER
# =============================================================================

func _update_draw_scales(delta: float) -> void:
	var t_now    = Time.get_ticks_msec() * 0.001
	var mouse_gp = get_global_mouse_position()
	_update_one_draw_scale(lh, delta, t_now, mouse_gp, 0.0)
	_update_one_draw_scale(rh, delta, t_now, mouse_gp, 1.1)
	_update_one_draw_scale(lf, delta, t_now, mouse_gp, 2.2)
	_update_one_draw_scale(rf, delta, t_now, mouse_gp, 3.3)


func _update_one_draw_scale(s: LimbState, delta: float, t_now: float,
		mouse_gp: Vector2, phase: float) -> void:
	var is_free = (s.hold == null or s in selected_limbs)
	var tgt     = LIMB_FREE_SCALE_TARGET if is_free else 1.0

	match s:
		lh: _lh_draw_scale = lerp(_lh_draw_scale, tgt, LIMB_SCALE_LERP_SPEED * delta)
		rh: _rh_draw_scale = lerp(_rh_draw_scale, tgt, LIMB_SCALE_LERP_SPEED * delta)
		lf: _lf_draw_scale = lerp(_lf_draw_scale, tgt, LIMB_SCALE_LERP_SPEED * delta)
		rf: _rf_draw_scale = lerp(_rf_draw_scale, tgt, LIMB_SCALE_LERP_SPEED * delta)

	var jitter = Vector2.ZERO
	if s in selected_limbs:
		var dist_to_mouse = s.node.global_position.distance_to(mouse_gp)
		var inner_dead = MOUSE_DEADZONE * 1.8
		var jitter_dist = max(dist_to_mouse - inner_dead, 0.0)
		var proximity   = clamp(1.0 - jitter_dist / HOVER_JITTER_RADIUS, 0.0, 1.0)
		if proximity > 0.01:
			var amp = proximity * HOVER_JITTER_AMP
			jitter = Vector2(
				sin(t_now * HOVER_JITTER_FREQ + phase) * amp,
				sin(t_now * HOVER_JITTER_FREQ * 1.37 + phase + 0.8) * amp
			)

	match s:
		lh: _lh_hover_jitter = jitter
		rh: _rh_hover_jitter = jitter
		lf: _lf_hover_jitter = jitter
		rf: _rf_hover_jitter = jitter

# =============================================================================
#  PHYSICS
# =============================================================================

func simulate_physics(delta: float) -> void:
	var held_hand_count = _count_held_array(_hands)
	var held_foot_count = _count_held_array(_feet)
	var total_held      = held_hand_count + held_foot_count

	if total_held < last_held_limbs:
		com_velocity += Vector2(randf_range(-20, 20), 30) * 0.05
	last_held_limbs = total_held

	var wdata    = _query_water(com_position, com_velocity)
	var in_water = wdata["in_water"] as bool
	if in_water:
		var drag:     Vector2 = wdata["drag"]
		var buoyancy: float   = wdata["buoyancy"]
		com_velocity.x *= drag.x
		com_velocity.y *= drag.y
		com_velocity.y -= buoyancy * delta

	if held_hand_count > 0:
		com_velocity.y += GRAVITY * delta * (0.15 if held_foot_count > 0 else 0.18)
	else:
		com_velocity.y += GRAVITY * delta * (0.4 if in_water else 1.4)
		if not in_water:
			for s in _feet:
				if s.hold: release_limb(s)

	if rope_system != null and not is_instance_valid(rope_system):
		rope_system = null
		if current_discipline == 1 and rope_system != null:
			if rope_system.has_method("apply_rope_force_to_player"):
				com_velocity = rope_system.apply_rope_force_to_player(com_velocity)

	_apply_hip_shift(delta, held_hand_count, held_foot_count)
	_pin_held_limbs()
	_apply_limb_gravity(delta)

	if use_mouse_aim and not selected_limbs.is_empty():
		_apply_mouse_control(delta)

	if ENABLE_ADAPTIVE_LEGS:
		_apply_adaptive_leg_assistance(delta)

	for s in _limbs:
		s.previous_pos = s.node.global_position

	if held_foot_count > 0 and held_hand_count > 0:
		_apply_foot_support(delta)

	if held_foot_count > 0 and abs(com_velocity.x) > FOOT_CUT_THRESHOLD:
		for s in _feet:
			if s.hold: release_limb(s)

	_apply_limb_tension(delta, held_foot_count)

	com_position    += com_velocity * delta
	global_position  = com_position + Vector2(0, -COM_OFFSET_Y)

	_apply_limb_velocities(delta)
	_check_leg_overstretch()
	_check_limb_overload()

	for _i in range(5):
		_apply_joint_constraints()

	_apply_natural_limb_positions(delta)
	_update_grab_animations()
	_pin_held_limbs()

	com_velocity *= 0.88 if in_water else BODY_DRAG
	_apply_limb_drag()


func _apply_hip_shift(delta: float, held_hand_count: int, held_foot_count: int) -> void:
	if held_hand_count == 0:
		_hip_shift_offset = _hip_shift_offset.lerp(Vector2.ZERO, 3.0 * delta)
		_commit_hip_shift_bias(); return
	var mouse_global = get_global_mouse_position()
	var to_mouse     = mouse_global - global_position
	var dist         = to_mouse.length()
	if not selected_limbs.is_empty():
		_hip_shift_offset = _hip_shift_offset.lerp(Vector2.ZERO, 0.8 * delta)
		_commit_hip_shift_bias(); return
	if dist < HIP_SHIFT_DEADZONE:
		_hip_shift_offset = _hip_shift_offset.lerp(Vector2.ZERO, 2.5 * delta)
		_commit_hip_shift_bias(); return
	var desired = to_mouse.normalized() * minf(dist - HIP_SHIFT_DEADZONE, HIP_SHIFT_MAX_RADIUS)
	if held_foot_count == 0: desired *= 0.4
	_hip_shift_offset = _hip_shift_offset.lerp(desired, HIP_SHIFT_STRENGTH * delta * 60.0)
	_commit_hip_shift_bias()


func _commit_hip_shift_bias() -> void:
	if _hip_shift_offset.length() < 1.0: return
	var bias_force = _hip_shift_offset * 0.18
	if bias_force.length() > HIP_SHIFT_MAX_SPEED:
		bias_force = bias_force.normalized() * HIP_SHIFT_MAX_SPEED
	com_velocity += bias_force


func _apply_limb_gravity(delta: float) -> void:
	for s in _limbs:
		if s.hold != null or s not in selected_limbs or s.is_grabbing: continue
		var gs = 0.18 if s.is_hand() else 0.22
		var gj = 0.12 if s.is_hand() else 0.16
		s.velocity.y       += GRAVITY * delta * gs
		s.joint_velocity.y += GRAVITY * delta * gj


func _apply_limb_velocities(delta: float) -> void:
	for s in _limbs:
		if s.hold == null and s in selected_limbs and not s.is_grabbing:
			s.node.global_position  += s.velocity       * delta
			s.joint.global_position += s.joint_velocity * delta


func _apply_limb_drag() -> void:
	for s in _limbs:
		if s.hold == null and s in selected_limbs:
			s.velocity       *= LIMB_DRAG
			s.joint_velocity *= LIMB_DRAG


func _pin_held_limbs() -> void:
	for s in _limbs:
		if s.hold and not s.is_grabbing:
			s.node.global_position = s.pin if s.pin != Vector2.ZERO else s.hold.get_limb_anchor(s.node)
			s.reset_velocity()


func _apply_limb_tension(_delta: float, held_foot_count: int) -> void:
	var target_pos   = Vector2.ZERO
	var total_weight = 0.0
	for s in _hands:
		if s.hold: target_pos += s.hold.get_limb_anchor(s.node) * 2.0; total_weight += 2.0
	for s in _feet:
		if s.hold: target_pos += s.hold.get_limb_anchor(s.node) * 0.5; total_weight += 0.5
	if total_weight > 0:
		target_pos /= total_weight
		target_pos += Vector2(0, 60.0 if held_foot_count == 0 else 30.0)
		var fat = _get_body_fatigue_t()
		target_pos   += Vector2(0, fat * P2_MAX_SAG_PX)
		com_velocity += (target_pos - com_position) * BODY_PULL_STRENGTH * _get_grip_force_scalar(fat * PRESSURE_FAIL)


func _apply_foot_support(delta: float) -> void:
	var foot_center      = Vector2.ZERO
	var total_foot_count = 0
	for s in _feet:
		if s.hold: foot_center += s.hold.get_limb_anchor(s.node); total_foot_count += 1
	if total_foot_count > 0: foot_center /= total_foot_count

	var max_arm_reach  = ARM_UPPER_LENGTH + ARM_LOWER_LENGTH
	var hand_reach_sum = 0.0; var hand_count = 0
	for s in _hands:
		if s.hold:
			hand_reach_sum += clamp((com_position.y - s.hold.get_limb_anchor(s.node).y) / max_arm_reach, 0.0, 1.0)
			hand_count     += 1
	var reach_factor = smoothstep(0.0, 0.6, hand_reach_sum / max(hand_count, 1) + 0.25)

	if not has_meta("foot_push_smooth"): set_meta("foot_push_smooth", reach_factor)
	var prev_smooth: float = float(get_meta("foot_push_smooth"))
	var smoothed_reach = lerp(prev_smooth, reach_factor, (0.6 if reach_factor > prev_smooth else 0.35) * delta)
	set_meta("foot_push_smooth", smoothed_reach)

	var support_force      = Vector2.ZERO
	var effective_strength = FOOT_SUPPORT_STRENGTH * smoothed_reach
	for s in _feet:
		if s.hold:
			var foot_rel_y = s.hold.get_limb_anchor(s.node).y - com_position.y
			if foot_rel_y > FOOT_SUPPORT_MIN_Y:
				support_force.y -= effective_strength * clamp(foot_rel_y, 0.0, FOOT_SUPPORT_MAX_PUSH)

	if total_foot_count > 0:
		support_force.x += FOOT_LATERAL_ASSIST * (foot_center.x - com_position.x)
		if com_velocity.y > 0: com_velocity.y *= lerp(0.995, 0.96, smoothed_reach)

	support_force.y  = max(support_force.y, -max(0.0, com_velocity.y * 0.6))
	com_velocity    += support_force

func _apply_mouse_control(delta: float) -> void:
	for s in _limbs:
		if s not in selected_limbs or s.hold != null or s.is_grabbing: continue
		var org   = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
		var max_r = s.reach(ARM_UPPER_LENGTH, ARM_LOWER_LENGTH, LEG_UPPER_LENGTH, LEG_LOWER_LENGTH)
		var to_m  = mouse_aim_position - org
		var dist  = to_m.length()
		var clamped_tgt = org + to_m.normalized() * max_r if dist > max_r else mouse_aim_position
		var mods        = _get_hand_modifiers(s.grip) if s.is_hand() else {"speed_mult": 1.0}
		var prox_slow   = lerp(1.0, 0.45, smoothstep(0.6, 1.0, clamp(dist / max_r, 0.0, 1.0)))
		var move_speed  = clamp(60.0 * mods.speed_mult * prox_slow * (0.8 if s.is_foot() else 1.0) * delta, 0.0, 1.0)
		if not s.ghost_init: s.ghost = s.node.global_position; s.ghost_init = true
		s.ghost                = s.ghost.lerp(clamped_tgt, move_speed)
		s.node.global_position = s.ghost
		var upper = ARM_UPPER_LENGTH if s.is_hand() else LEG_UPPER_LENGTH
		s.joint.global_position = s.joint.global_position.lerp(org + (s.ghost - org).normalized() * upper, 0.35)
		s.reset_velocity()


func _apply_adaptive_leg_assistance(_delta: float) -> void:
	if not use_mouse_aim: return
	if not (lh in selected_limbs or rh in selected_limbs): return
	var reach_dir      = (mouse_aim_position - global_position).normalized()
	var reach_distance = global_position.distance_to(mouse_aim_position)
	var reach_ratio    = clamp(reach_distance / (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH), 0.0, 1.5)
	if reach_ratio < LEG_ASSIST_THRESHOLD: return
	var assist_amount = clamp((reach_ratio - LEG_ASSIST_THRESHOLD) / (1.5 - LEG_ASSIST_THRESHOLD), 0.0, 1.0) * LEG_ASSIST_STRENGTH
	for s in _feet:
		if s.hold:
			var hip = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
			if hip.distance_to(s.hold.get_limb_anchor(s.node)) / (LEG_UPPER_LENGTH + LEG_LOWER_LENGTH) < LEG_ASSIST_MAX_EXTENSION:
				com_velocity += reach_dir * assist_amount * LEG_ASSIST_SPEED * 100.0
	if lf.hold and rf.hold:
		com_velocity += reach_dir * assist_amount * LEG_ASSIST_SPEED * 50.0


func _apply_natural_limb_positions(_delta: float) -> void:
	for s in _hands:
		if s.hold != null or s in selected_limbs or s.is_grabbing: continue
		var shoulder  = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
		var sx        = -1.0 if s.is_left else 1.0
		# Natural hang: elbows slightly out, hands angled outward (not crossed).
		var tgt_elbow = shoulder + Vector2(sx * 12.0, ARM_UPPER_LENGTH * 0.60)
		var tgt_hand  = tgt_elbow + Vector2(sx * 4.0,  ARM_LOWER_LENGTH * 0.85)
		s.joint.global_position = s.joint.global_position.lerp(tgt_elbow, FREE_ARM_RELAXATION_SPEED)
		s.node.global_position  = s.node.global_position.lerp(tgt_hand,  FREE_ARM_RELAXATION_SPEED)
		s.reset_velocity()
	var leg_splay = 8.0
	for s in _feet:
		if s.hold != null or s in selected_limbs or s.is_grabbing: continue
		var hip      = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
		var sx       = -1.0 if s.is_left else 1.0
		var tgt_knee = hip + Vector2(sx * leg_splay, LEG_UPPER_LENGTH)
		s.joint.global_position = s.joint.global_position.lerp(tgt_knee, FREE_LEG_RELAXATION_SPEED)
		s.node.global_position  = s.node.global_position.lerp(tgt_knee + Vector2(sx * leg_splay * 0.5, LEG_LOWER_LENGTH), FREE_LEG_RELAXATION_SPEED)
		s.reset_velocity()

func _update_grab_animations() -> void:
	for s in _limbs:
		if s.is_grabbing:
			s.visual_offset        = s.node.global_position - s.grab_target
			s.node.global_position = s.grab_target
			s.is_grabbing          = false
		s.visual_offset = s.visual_offset.lerp(Vector2.ZERO, VISUAL_ANIMATION_SPEED)
		if s.visual_offset.length() < 0.5: s.visual_offset = Vector2.ZERO

# =============================================================================
#  JOINT CONSTRAINTS
# =============================================================================

func _apply_joint_constraints() -> void:
	_constrain_arm(lh, global_position + Vector2(-SHOULDER_OFFSET, 0))
	_constrain_arm(rh, global_position + Vector2( SHOULDER_OFFSET, 0))
	_constrain_leg(lf, global_position + Vector2(-HIP_OFFSET, HIP_DOWN))
	_constrain_leg(rf, global_position + Vector2( HIP_OFFSET, HIP_DOWN))


func _constrain_arm(s: HandState, shoulder: Vector2) -> void:
	var pinned = s.hold != null or s in selected_limbs or s.is_grabbing
	var to_h   = s.node.global_position - shoulder
	var dist   = to_h.length()
	if dist < 0.01: return
	var total = ARM_UPPER_LENGTH + ARM_LOWER_LENGTH
	var max_r = total * MAX_JOINT_STRETCH
	if dist > max_r:
		s.node.global_position = shoulder + to_h.normalized() * max_r
		to_h = s.node.global_position - shoulder; dist = max_r
	if pinned or dist >= total * 0.98:
		if dist >= total * 0.98:
			s.joint.global_position = shoulder + to_h * (ARM_UPPER_LENGTH / total)
		else:
			var dir = to_h.normalized()
			var c   = clamp(dist, abs(ARM_UPPER_LENGTH - ARM_LOWER_LENGTH) + 0.1, total - 0.1)
			var ca  = clamp((ARM_UPPER_LENGTH * ARM_UPPER_LENGTH + c * c - ARM_LOWER_LENGTH * ARM_LOWER_LENGTH) / (2.0 * ARM_UPPER_LENGTH * c), -1.0, 1.0)
			var ang = acos(ca); var bend = -1.0 if s.is_left else 1.0
			s.joint.global_position = shoulder + dir * (ARM_UPPER_LENGTH * cos(ang)) + Vector2(-dir.y, dir.x) * (ARM_UPPER_LENGTH * sin(ang)) * bend
	else:
		_relax_segment(s.joint, s.node, shoulder, ARM_UPPER_LENGTH, ARM_LOWER_LENGTH)


func _constrain_leg(s: FootState, hip: Vector2) -> void:
	var pinned = s.hold != null or s in selected_limbs or s.is_grabbing
	var to_f   = s.node.global_position - hip
	var dist   = to_f.length()
	if dist < 0.01: return
	var total = LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
	var max_r = total * MAX_LEG_TOTAL_STRETCH
	if dist > max_r:
		s.node.global_position = hip + to_f.normalized() * max_r
		to_f = s.node.global_position - hip; dist = max_r
	if pinned or dist >= total * 0.98:
		if dist >= total * 0.98:
			s.joint.global_position = hip + to_f * (LEG_UPPER_LENGTH / total)
		else:
			var dir = to_f.normalized()
			var c   = clamp(dist, abs(LEG_UPPER_LENGTH - LEG_LOWER_LENGTH) + 0.1, total - 0.1)
			var ca  = clamp((LEG_UPPER_LENGTH * LEG_UPPER_LENGTH + c * c - LEG_LOWER_LENGTH * LEG_LOWER_LENGTH) / (2.0 * LEG_UPPER_LENGTH * c), -1.0, 1.0)
			var ang = acos(ca)
			s.joint.global_position = hip + dir * (LEG_UPPER_LENGTH * cos(ang)) + Vector2(-dir.y, dir.x) * (LEG_UPPER_LENGTH * sin(ang))
	else:
		_relax_segment(s.joint, s.node, hip, LEG_UPPER_LENGTH, LEG_LOWER_LENGTH)


func _relax_segment(jn: Node2D, en: Node2D, origin: Vector2, upper: float, lower: float) -> void:
	var tj = jn.global_position - origin; var jd = tj.length()
	if jd > 0.01:
		var mu = upper * MAX_JOINT_STRETCH
		jn.global_position = (origin + tj.normalized() * mu) if jd > mu else (jn.global_position - tj.normalized() * (jd - upper) * JOINT_STIFFNESS)
	var te = en.global_position - jn.global_position; var ed = te.length()
	if ed > 0.01:
		var ml = lower * MAX_LIMB_STRETCH
		en.global_position = (jn.global_position + te.normalized() * ml) if ed > ml else (en.global_position - te.normalized() * (ed - lower) * LIMB_STIFFNESS)

# =============================================================================
#  OVERSTRETCH / OVERLOAD
# =============================================================================

func _check_leg_overstretch() -> void:
	var max_safe = (LEG_UPPER_LENGTH + LEG_LOWER_LENGTH) * LEG_FORCE_RELEASE_THRESHOLD
	for s in _feet:
		if s.hold and not s.is_grabbing:
			if s.hold.has_method("is_top_out") and s.hold.is_top_out():
				continue
			var hip = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
			if hip.distance_to(s.hold.get_limb_anchor(s.node)) > max_safe:
				release_limb(s)

func _check_limb_overload() -> void:
	for s in _hands:
		if s.hold:
			if s.hold.has_method("is_top_out") and s.hold.is_top_out():
				continue
			var shoulder = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
			if shoulder.distance_to(s.hold.get_limb_anchor(s.node)) > (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * HAND_LOAD_TOLERANCE:
				release_limb(s)
	for s in _feet:
		if s.hold:
			if s.hold.has_method("is_top_out") and s.hold.is_top_out():
				continue
			var hip = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
			if hip.distance_to(s.hold.get_limb_anchor(s.node)) > (LEG_UPPER_LENGTH + LEG_LOWER_LENGTH) * FOOT_RELEASE_THRESHOLD:
				release_limb(s)

# =============================================================================
#  LOAD DISTRIBUTION
# =============================================================================

func _update_load_distribution(delta: float) -> void:
	var anchors: Array[Vector2] = []
	var ids:     Array[int]     = []
	var raw:     Array[float]   = [0.0, 0.0, 0.0, 0.0]
	for i in range(4):
		var s: LimbState = _limbs[i]
		if s.hold and not s.is_grabbing: anchors.append(s.hold.get_limb_anchor(s.node)); ids.append(i)
	match anchors.size():
		0: pass
		1: raw[ids[0]] = 1.0
		2:
			var span = anchors[0].distance_to(anchors[1])
			if span < 1.0: raw[ids[0]] = 0.5; raw[ids[1]] = 0.5
			else:
				var t = clamp((com_position - anchors[0]).dot((anchors[1] - anchors[0]).normalized()) / span, 0.0, 1.0)
				raw[ids[0]] = 1.0 - t; raw[ids[1]] = t
		_:
			var tw = 0.0; var wts: Array[float] = []
			for a in anchors:
				var w = 1.0 / maxf(com_position.distance_to(a), 1.0); wts.append(w); tw += w
			for i in range(anchors.size()): raw[ids[i]] = wts[i] / tw
	for i in range(4): _load[i] = lerp(_load[i], raw[i], LOAD_LERP_SPEED * delta)

# =============================================================================
#  GRAB & RELEASE
# =============================================================================

func attempt_grab(s: LimbState) -> void:
	var is_foot = s.is_foot()
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = GRAB_RADIUS
	query.shape = circle; query.transform = Transform2D(0, s.node.global_position)
	query.collision_mask = 2; query.collide_with_areas = true; query.collide_with_bodies = false
	var results = space_state.intersect_shape(query, 16)
	if results.is_empty(): return

	var best: Area2D = null; var bd: float = INF; var bp: Vector2 = Vector2.ZERO
	for result in results:
		var hold: Area2D = result.collider
		if not hold.can_grab(s.node, is_foot): continue
		var hp = hold.get_node_or_null("HoldPoint")
		var hp_pos: Vector2 = hp.global_position if hp else hold.global_position
		# replace: if hp == null: continue
		var m: float
		if hold.get("snap_to_point"):
			m = s.node.global_position.distance_to(hp_pos)
		else:
			var sn = hold.get_node_or_null("CollisionShape2D")
			m = s.node.global_position.distance_to(hold.to_global(sn.position) if sn else hold.global_position)
		if m < bd: bd = m; best = hold; bp = hp_pos
	if best == null: return

	var occupants = _limbs.filter(func(o): return o != s and o.hold == best)
	var registry = get_node_or_null("/root/HoldRegistry")
	var max_limbs = 2  # safe default
	if registry:
		var type_key = best.get("hold_type")
		if type_key != null:
			var type_name = ClimbingHold.HoldType.keys()[type_key]
			max_limbs = registry.get_config_value(type_name, "max_limbs", 2)
	if occupants.size() >= max_limbs:
		return

	var grab_pos = _calculate_grab_position(s, best, bp) if best.get("snap_to_point") else s.node.global_position
	if not best.try_claim(s.node, is_foot, grab_pos): return

	var resolved  = best.get_limb_anchor(s.node)
	s.hold        = best; s.grab_target = resolved; s.pin = resolved
	s.is_grabbing = true; s.reset_velocity()

	s.ghost      = resolved
	s.ghost_init = true

	if s.is_hand(): _apply_catch_penalty(s as HandState)
	if not climb_started:
		climb_started = true
		var gs = get_tree().get_current_scene()
		if gs and gs.has_method("on_climb_start"): gs.on_climb_start()

func _calculate_grab_position(s: LimbState, hold: Area2D, hold_point: Vector2) -> Vector2:
	var others = _limbs.filter(func(o): return o != s and o.hold == hold and not o.is_grabbing)
	if others.is_empty(): return hold_point
	var side = -SHARED_HOLD_HAND_OFFSET if s.is_left else SHARED_HOLD_HAND_OFFSET
	if s.is_foot():
		for o in others:
			if o.is_foot(): return hold_point + Vector2(side, 0)
		return hold_point + Vector2((-SHARED_HOLD_HAND_FOOT_OFFSET if s.is_left else SHARED_HOLD_HAND_FOOT_OFFSET), SHARED_HOLD_HAND_FOOT_OFFSET)
	else:
		for o in others:
			if o.is_hand(): return hold_point + Vector2(side, 0)
		return hold_point + Vector2((-SHARED_HOLD_HAND_FOOT_OFFSET if s.is_left else SHARED_HOLD_HAND_FOOT_OFFSET), -SHARED_HOLD_HAND_FOOT_OFFSET)


func release_limb(s: LimbState) -> void:
	if s.hold: s.hold.release(s.node); s.hold = null
	s.pin = Vector2.ZERO
	if s.is_foot(): (s as FootState).manual = false

# =============================================================================
#  DYNO IMPULSE
# =============================================================================

func _fire_dyno_impulse() -> void:
	if not use_mouse_aim: return
	var aim_dir  = (mouse_aim_position - com_position).normalized()
	var hand_vel = Vector2.ZERO
	for s in selected_limbs:
		if s.is_hand() and s.hold == null: hand_vel += s.node.global_position - s.previous_pos
	var dt    = get_process_delta_time()
	var speed = hand_vel.length() / dt if dt > 0 else 0.0
	if speed < 30.0: return
	var dot = clamp(hand_vel.normalized().dot(aim_dir) if hand_vel.length() > 1.0 else 0.5, 0.0, 1.0)
	com_velocity += aim_dir * clamp(speed * 0.18, 60.0, 420.0) * dot

# =============================================================================
#  SPAWN / RESET
# =============================================================================

func _find_nearest_hold_radius(from: Vector2, radius: float) -> Area2D:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0, from)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var nearest: Area2D = null
	var nd = INF
	for result in space_state.intersect_shape(query, 32):
		var hold: Area2D = result.collider
		if not hold.can_grab(lh.node, false): continue  # hand-grabbable only
		var hp = hold.get_node_or_null("HoldPoint")
		var sn = hold.get_node_or_null("CollisionShape2D")
		var pos: Vector2 = hp.global_position if hp else (hold.to_global(sn.position) if sn else hold.global_position)
		var d = from.distance_to(pos)
		if d < nd:
			nd = d
			nearest = hold
	return nearest

func initial_grab() -> void:
	_zero_all()
	global_position = spawn_position
	com_position    = spawn_position + Vector2(0, COM_OFFSET_Y)
	await get_tree().process_frame
	await get_tree().process_frame
	for s in _limbs:
		if s.hold: release_limb(s)
		s.is_grabbing = false
	_zero_all()

	var start_holds = _find_start_holds()
	if start_holds.size() == 1:
		var hold = start_holds[0]
		var hp = hold.get_node_or_null("HoldPoint") as Marker2D
		var pos = hp.global_position if hp else hold.global_position
		# Try to place both hands with slight offsets so _max_limbs=1 isn't hit twice
		var offsets = [Vector2(-SHARED_HOLD_HAND_OFFSET, 0), Vector2(SHARED_HOLD_HAND_OFFSET, 0)]
		var hand_idx = 0
		for s in _hands:
			if hold.can_grab(s.node, false):
				var grab_pos = pos + offsets[hand_idx] if hand_idx < offsets.size() else pos
				if hold.try_claim(s.node, false, grab_pos):
					s.hold = hold
					s.node.global_position = hold.get_limb_anchor(s.node)
					s.anchor = s.node.global_position
					s.pin    = s.node.global_position
			hand_idx += 1
		# Position body below whichever hand(s) grabbed
		global_position = Vector2(pos.x, pos.y + 80)
	elif start_holds.size() >= 2:
		var ha = start_holds[0].get_node_or_null("HoldPoint") as Marker2D
		var hb = start_holds[1].get_node_or_null("HoldPoint") as Marker2D
		if not ha or not hb: return
		var ls = start_holds[0] if ha.global_position.x <= hb.global_position.x else start_holds[1]
		var rs = start_holds[1] if ha.global_position.x <= hb.global_position.x else start_holds[0]
		var lp = (ls.get_node("HoldPoint") as Marker2D).global_position
		var rp = (rs.get_node("HoldPoint") as Marker2D).global_position
		if ls.can_grab(lh.node, false) and ls.try_claim(lh.node, false, lp):
			lh.hold = ls; lh.node.global_position = lp; lh.anchor = lp; lh.pin = lp
		if rs.can_grab(rh.node, false) and rs.try_claim(rh.node, false, rp):
			rh.hold = rs; rh.node.global_position = rp; rh.anchor = rp; rh.pin = rp
		global_position = Vector2((lp.x + rp.x) / 2.0, lp.y + 80)
	else:
		# No tagged start holds — search near spawn position for any grabbable hand hold
		for s in _hands:
			var other = rh if s == lh else lh
			# Search from spawn position, not default hand position
			var nearest = _find_nearest_hold(com_position)
			if nearest == null:
				# Widen search
				nearest = _find_nearest_hold_radius(com_position, 400.0)
			if nearest and nearest != other.hold and nearest.can_grab(s.node, false):
				var hp = nearest.get_node_or_null("HoldPoint")
				var sn = nearest.get_node_or_null("CollisionShape2D")
				var grab_pos: Vector2
				if hp:
					grab_pos = hp.global_position
				elif sn:
					grab_pos = nearest.to_global(sn.position)
				else:
					grab_pos = nearest.global_position
				# Offset hands slightly so both can claim if _max_limbs=1
				var side_offset = Vector2(-SHARED_HOLD_HAND_OFFSET if s.is_left else SHARED_HOLD_HAND_OFFSET, 0)
				var final_pos = grab_pos + side_offset
				if nearest.try_claim(s.node, false, final_pos):
					s.hold = nearest
					s.node.global_position = nearest.get_limb_anchor(s.node)
					s.anchor = s.node.global_position
					s.pin = s.node.global_position

	com_position = global_position + Vector2(0, COM_OFFSET_Y)
	_snap_feet_on_spawn()
	for _i in range(15): _apply_joint_constraints()
	_pin_held_limbs(); _zero_all(); _reset_ghost_targets()
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("notify_climb_start"): hold.notify_climb_start()
	_grab_initialized = true


func _snap_feet_on_spawn() -> void:
	var saved = {}
	for s in _feet: saved[s] = s.node.global_position
	for s in _feet: s.node.global_position = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
	for s in _feet:
		var other = rf if s == lf else lf
		var best  = _find_best_foot_hold(s, s.node.global_position)
		s.node.global_position = saved[s]
		if best == null or best == lh.hold or best == rh.hold or best == other.hold: continue
		if not best.can_grab(s.node, true): continue
		var hp       = best.get_node_or_null("HoldPoint")
		var snap_pos = hp.global_position if hp else best.global_position
		if best.try_claim(s.node, true, snap_pos):
			s.hold = best; s.node.global_position = best.get_limb_anchor(s.node)
			s.anchor = s.node.global_position; s.pin = s.node.global_position; s.reset_velocity()


func reset_climb() -> void:
	_grab_initialized = false
	global_position   = spawn_position
	com_position      = spawn_position + Vector2(0, COM_OFFSET_Y)
	com_velocity      = Vector2.ZERO; body_velocity = Vector2.ZERO
	_hip_shift_offset = Vector2.ZERO; last_held_limbs = 0
	fall_timer = 0.0; _ragdoll_active = false; _ragdoll_elapsed = 0.0
	climb_started = false; climb_completed = false
	rest_mode_active = false; _leg_bonus_smooth = 1.0
	_load = [0.0, 0.0, 0.0, 0.0]; selected_limbs.clear(); use_mouse_aim = false
	_lh_draw_scale = 1.0; _rh_draw_scale = 1.0
	_lf_draw_scale = 1.0; _rf_draw_scale = 1.0
	_lh_hover_jitter = Vector2.ZERO; _rh_hover_jitter = Vector2.ZERO
	_lf_hover_jitter = Vector2.ZERO; _rf_hover_jitter = Vector2.ZERO
	_lh_press_time = 0.0; _rh_press_time = 0.0
	_lf_press_time = 0.0; _rf_press_time = 0.0
	_input_enabled = true
	for s in _limbs:
		if s.hold: s.hold.release(s.node)
		s.reset_all()
	_set_default_local_positions(); _reset_ghost_targets()
	if not is_instance_valid(rope_system):
		rope_system = null
	elif rope_system.has_method("setup_rope"):
		var loader = get_tree().current_scene.get_node_or_null("LevelLoader")
		if loader and loader.has_method("get_belayer_position"):
			rope_system.setup_rope(loader.get_belayer_position(), self)

	if speed_timer and is_instance_valid(speed_timer) and speed_timer.has_method("stop_timer"):
		speed_timer.stop_timer()
	_weather_modifier = get_tree().get_first_node_in_group("weather_modifier")
	_spotlight        = get_node_or_null("SpotLight2D")

	# ── Synchronous initial grab — no frame delays so player appears at start holds immediately ──
	_zero_all()
	global_position = spawn_position
	com_position    = spawn_position + Vector2(0, COM_OFFSET_Y)

	for s in _limbs:
		if s.hold: release_limb(s)
		s.is_grabbing = false
	_zero_all()

	var start_holds := _find_start_holds()
	if start_holds.size() == 1:
		var hold := start_holds[0]
		var hp := hold.get_node_or_null("HoldPoint") as Marker2D
		var pos := hp.global_position if hp else hold.global_position
		var offsets: Array[Vector2] = [Vector2(-SHARED_HOLD_HAND_OFFSET, 0), Vector2(SHARED_HOLD_HAND_OFFSET, 0)]
		var hand_idx := 0
		for s in _hands:
			if hold.can_grab(s.node, false):
				var grab_pos: Vector2 = pos + offsets[hand_idx] if hand_idx < offsets.size() else pos
				if hold.try_claim(s.node, false, grab_pos):
					s.hold = hold
					s.node.global_position = hold.get_limb_anchor(s.node)
					s.anchor = s.node.global_position
					s.pin    = s.node.global_position
			hand_idx += 1
		global_position = Vector2(pos.x, pos.y + 80)
	elif start_holds.size() >= 2:
		var ha := start_holds[0].get_node_or_null("HoldPoint") as Marker2D
		var hb := start_holds[1].get_node_or_null("HoldPoint") as Marker2D
		if ha and hb:
			var ls := start_holds[0] if ha.global_position.x <= hb.global_position.x else start_holds[1]
			var rs := start_holds[1] if ha.global_position.x <= hb.global_position.x else start_holds[0]
			var lp := (ls.get_node("HoldPoint") as Marker2D).global_position
			var rp := (rs.get_node("HoldPoint") as Marker2D).global_position
			if ls.can_grab(lh.node, false) and ls.try_claim(lh.node, false, lp):
				lh.hold = ls; lh.node.global_position = lp; lh.anchor = lp; lh.pin = lp
			if rs.can_grab(rh.node, false) and rs.try_claim(rh.node, false, rp):
				rh.hold = rs; rh.node.global_position = rp; rh.anchor = rp; rh.pin = rp
			global_position = Vector2((lp.x + rp.x) / 2.0, lp.y + 80)
	else:
		for s in _hands:
			var other := rh if s == lh else lh
			var nearest := _find_nearest_hold(com_position)
			if nearest == null:
				nearest = _find_nearest_hold_radius(com_position, 400.0)
			if nearest and nearest != other.hold and nearest.can_grab(s.node, false):
				var hp := nearest.get_node_or_null("HoldPoint")
				var sn := nearest.get_node_or_null("CollisionShape2D")
				var grab_pos: Vector2
				if hp:
					grab_pos = hp.global_position
				elif sn:
					grab_pos = nearest.to_global(sn.position)
				else:
					grab_pos = nearest.global_position
				var side_offset := Vector2(-SHARED_HOLD_HAND_OFFSET if s.is_left else SHARED_HOLD_HAND_OFFSET, 0)
				var final_pos := grab_pos + side_offset
				if nearest.try_claim(s.node, false, final_pos):
					s.hold = nearest
					s.node.global_position = nearest.get_limb_anchor(s.node)
					s.anchor = s.node.global_position
					s.pin = s.node.global_position

	com_position = global_position + Vector2(0, COM_OFFSET_Y)
	_snap_feet_on_spawn()
	for _i in range(15): _apply_joint_constraints()
	_pin_held_limbs(); _zero_all(); _reset_ghost_targets()
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("notify_climb_start"): hold.notify_climb_start()
	_grab_initialized = true


func _zero_all() -> void:
	com_velocity = Vector2.ZERO; body_velocity = Vector2.ZERO
	for s in _limbs: s.reset_velocity()


func _reset_ghost_targets() -> void:
	for s in _limbs: s.ghost = s.node.global_position; s.ghost_init = true

func _reset_limb_ghost(limb_node: Node2D) -> void:
	for s in _limbs:
		if s.node == limb_node:
			s.ghost      = limb_node.global_position
			s.ghost_init = true
			return

# =============================================================================
#  HOLD QUERIES
# =============================================================================

func _find_start_holds() -> Array[Area2D]:
	var out: Array[Area2D] = []
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold is Area2D and hold.has_method("is_start_hold") and hold.is_start_hold():
			out.append(hold)
	return out


func _find_nearest_hold(from: Vector2) -> Area2D:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 200.0
	query.shape = circle
	query.transform = Transform2D(0, from)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var nearest: Area2D = null
	var nd = INF
	for result in space_state.intersect_shape(query, 32):
		var hold: Area2D = result.collider
		# Use HoldPoint if available, otherwise fall back to CollisionShape2D center or hold origin
		var hp = hold.get_node_or_null("HoldPoint")
		var pos: Vector2
		if hp != null:
			pos = hp.global_position
		else:
			var sn = hold.get_node_or_null("CollisionShape2D")
			pos = hold.to_global(sn.position) if sn else hold.global_position
		var d = from.distance_to(pos)
		if d < nd:
			nd = d
			nearest = hold
	return nearest

func _find_best_foot_hold(s: FootState, search_center: Vector2) -> Area2D:
	var hip   = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
	var max_r = (LEG_UPPER_LENGTH + LEG_LOWER_LENGTH) * 0.95
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new(); var circle = CircleShape2D.new()
	circle.radius = 110.0; query.shape = circle; query.transform = Transform2D(0, search_center)
	query.collision_mask = 2; query.collide_with_areas = true; query.collide_with_bodies = false
	var results = space_state.intersect_shape(query, 32)
	if results.is_empty(): return null
	var best: Area2D = null; var bs = -INF
	for result in results:
		var hold: Area2D = result.collider
		var hp = hold.get_node_or_null("HoldPoint")
		if hp == null: continue
		var hpos: Vector2 = hp.global_position
		if hip.distance_to(hpos) > max_r: continue
		var rel_y = hpos.y - global_position.y
		if rel_y < -20.0: continue
		var ds    = 1.0 - search_center.distance_to(hpos) / 110.0
		var bels  = 3.0 if rel_y >= 0.0 and rel_y <= 80.0 else (3.0 - (rel_y - 80.0) / 60.0 if rel_y > 80.0 else 0.5)
		var sds   = 1.0 if (s.is_left and (hpos.x - global_position.x) <= 0) or (not s.is_left and (hpos.x - global_position.x) >= 0) else 0.4
		var rr    = hip.distance_to(hpos) / (LEG_UPPER_LENGTH + LEG_LOWER_LENGTH)
		var cs    = 2.0 if rr >= 0.3 and rr <= 0.75 else (rr / 0.3 if rr < 0.3 else 2.0 - (rr - 0.75) / 0.2)
		var ts    = 1.5 if hold.is_foothold() else 0.5
		var sc    = ds + bels + sds * 0.6 + cs + ts
		if sc > bs: bs = sc; best = hold
	return best

# =============================================================================
#  METRICS
# =============================================================================

func _count_held_limbs() -> int:
	var n = 0
	for s in _limbs:
		if s.hold != null and not s.is_grabbing and s not in selected_limbs: n += 1
	return n


func _count_held_array(arr: Array) -> int:
	var n = 0
	for s in arr: if s.hold != null: n += 1
	return n


func _get_loading_multiplier(held: int) -> float:
	match held:
		1: return ONE_ARM_PRESSURE_MULTIPLIER
		2: return TWO_ARM_PRESSURE_MULTIPLIER
		3: return THREE_LIMB_PRESSURE_MULTIPLIER
		4: return FOUR_LIMB_PRESSURE_MULTIPLIER
	return 1.0


func _calculate_arm_extension(s: HandState) -> float:
	var shoulder = s.origin(global_position, SHOULDER_OFFSET, HIP_OFFSET, HIP_DOWN)
	return clamp(shoulder.distance_to(s.node.global_position) / (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH), 0.0, 1.0)


func _calculate_body_offset(s: LimbState) -> float:
	var anc = s.anchor if s.anchor != Vector2.ZERO else s.node.global_position
	if anc == Vector2.ZERO: return 0.0
	return clamp(com_position.distance_to(anc + Vector2(0, 60)) / 100.0, 0.0, 1.0)


func _calculate_body_balance() -> float:
	var balance = 0.0
	if   lf.hold and rf.hold: balance += 0.5
	elif lf.hold or  rf.hold: balance += 0.25
	if lh.hold and rh.hold: balance += 0.3
	return clamp(balance + clamp(1.0 - com_velocity.length() / 100.0, 0.0, 0.2), 0.0, 1.0)


func _calculate_foot_support_ratio() -> float:
	return (0.5 if lf.hold else 0.0) + (0.5 if rf.hold else 0.0)


func get_highest_hand_y() -> float:
	var ys: Array[float] = []
	for s in _hands:
		if s.hold: ys.append(s.hold.get_limb_anchor(s.node).y)
	return ys.min() if not ys.is_empty() else global_position.y

# =============================================================================
#  FALL DETECTION & COMPLETION
# =============================================================================

func check_fall_detection(delta: float) -> void:
	var in_water = _query_water(com_position, com_velocity)["in_water"] as bool
	if _count_held_limbs() == 0 and com_velocity.y > FALL_VELOCITY_THRESHOLD and not in_water:
		fall_timer += delta
		if fall_timer >= FALL_DETECTION_TIME:
			if current_discipline == 2 and speed_timer and speed_timer.has_method("pause_timer"):
				speed_timer.pause_timer()
			var main = get_tree().current_scene
			if main and main.has_method("on_player_reset"):
				main.on_player_reset()
			else:
				reset_climb()
	else:
		fall_timer = 0.0


func check_climb_completion() -> void:
	if climb_completed: return
	if lh.hold and rh.hold \
			and lh.hold.has_method("is_top_out") and lh.hold.is_top_out() \
			and rh.hold.has_method("is_top_out") and rh.hold.is_top_out():
		climb_completed = true
		if current_discipline == 2 and speed_timer and speed_timer.has_method("pause_timer"):
			speed_timer.pause_timer()
		var gs = get_tree().get_current_scene()
		if gs and gs.has_method("on_level_complete"): gs.on_level_complete()

# =============================================================================
#  RAGDOLL
# =============================================================================

func play_crashpad_ragdoll(duration: float) -> void:
	if _ragdoll_active: return
	_ragdoll_active = true; _ragdoll_elapsed = 0.0; _ragdoll_max_time = duration
	for s in _limbs: release_limb(s)
	selected_limbs.clear(); use_mouse_aim = false
	com_velocity = Vector2.ZERO; body_velocity = Vector2.ZERO
	var t = create_tween(); t.set_parallel(true)
	t.tween_property(_lh_joint, "position", Vector2(-55,  5),  0.10)
	t.tween_property(_lh_node,  "position", Vector2(-85, 30),  0.10)
	t.tween_property(_rh_joint, "position", Vector2( 55,  5),  0.10)
	t.tween_property(_rh_node,  "position", Vector2( 85, 30),  0.10)
	t.tween_property(_lf_joint, "position", Vector2(-28, 35),  0.10)
	t.tween_property(_lf_node,  "position", Vector2(-38, 80),  0.10)
	t.tween_property(_rf_joint, "position", Vector2( 28, 35),  0.10)
	t.tween_property(_rf_node,  "position", Vector2( 38, 80),  0.10)
	t.tween_property(_lh_joint, "position", Vector2(-32, 12),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_lh_node,  "position", Vector2(-48, 52),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_rh_joint, "position", Vector2( 32, 12),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_rh_node,  "position", Vector2( 48, 52),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_lf_joint, "position", Vector2(-14, 28),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_lf_node,  "position", Vector2(-18, 68),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_rf_joint, "position", Vector2( 14, 28),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_rf_node,  "position", Vector2( 18, 68),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)

# =============================================================================
#  CAMERA (defers to main.gd during route preview)
# =============================================================================

func update_camera() -> void:
	var main = get_tree().get_first_node_in_group("main_scene")
	if main and main.get("camera_owned_by_main") == true:
		return
	if cam:
		cam.global_position = cam.global_position.lerp(global_position, CAM_LERP)

# =============================================================================
#  DRAW
# =============================================================================

func _draw() -> void:
	if aesthetic:
		_draw_stick_figure()

# =============================================================================
#  SHADOW CHILD NODE
# =============================================================================

func _ensure_shadow_node() -> void:
	if _shadow_node != null and is_instance_valid(_shadow_node):
		return
	_shadow_node = _ShadowDrawer.new()
	_shadow_node.z_index = -1
	_shadow_node.name    = "ShadowLayer"
	add_child(_shadow_node)
	_shadow_node.owner_ref = self


var _shadow_node: Node2D = null


class _ShadowDrawer extends Node2D:
	var owner_ref: Node2D = null

	func _draw() -> void:
		if owner_ref == null:
			return
		var o = owner_ref
		var light: Dictionary = o._get_light_info()
		var intensity: float  = light["intensity"] as float
		if intensity <= 0.01:
			modulate.a = 0.0
			return

		modulate.a = clamp(intensity * 0.30, 0.0, 0.30)

		var light_dir: Vector2 = light["direction"] as Vector2
		var off: Vector2 = Vector2(-light_dir.x * 8.0, light_dir.y * 5.0)

		var lhd  = o.lh.node.position   + o.lh.shake_offset + o.lh.visual_offset + off
		var rhd  = o.rh.node.position   + o.rh.shake_offset + o.rh.visual_offset + off
		var lfd  = o.lf.node.position   + o.lf.shake_offset + o.lf.visual_offset + off
		var rfd  = o.rf.node.position   + o.rf.shake_offset + o.rf.visual_offset + off
		var lhj  = o._lh_joint.position + off
		var rhj  = o._rh_joint.position + off
		var lfj  = o._lf_joint.position + off
		var rfj  = o._rf_joint.position + off

		var head_pos  = Vector2(0.0, o.HEAD_OFFSET)        + off
		var left_sh   = Vector2(-o.SHOULDER_OFFSET, 0.0)   + off
		var right_sh  = Vector2( o.SHOULDER_OFFSET, 0.0)   + off
		var left_hip  = Vector2(-o.HIP_OFFSET, o.HIP_DOWN) + off
		var right_hip = Vector2( o.HIP_OFFSET, o.HIP_DOWN) + off
		var hip_pos   = Vector2(0.0, o.HIP_DOWN)           + off
		var left_sl   = left_sh.lerp(lhj,  0.35)
		var right_sl  = right_sh.lerp(rhj, 0.35)

		var sc = Color(0.0, 0.0, 0.0, 1.0)

		draw_line(left_hip,  lfj,  sc, 12.0); draw_line(lfj, lfd, sc, 11.0)
		draw_circle(lfj, 5, sc); draw_circle(lfd, 9, sc)
		draw_line(right_hip, rfj, sc, 12.0); draw_line(rfj, rfd, sc, 11.0)
		draw_circle(rfj, 5, sc); draw_circle(rfd, 9, sc)
		draw_line(left_hip,  right_hip,                         sc, 17.0)
		draw_line(hip_pos,   Vector2.ZERO + off,                 sc, 19.0)
		draw_line(Vector2.ZERO + off, head_pos + Vector2(0, 16), sc, 17.0)
		draw_circle(left_sh,  5, sc); draw_circle(right_sh, 5, sc)
		draw_line(left_sh,  left_sl,  sc, 12.0); draw_line(left_sl,  lhj, sc, 12.0)
		draw_circle(lhj, 5, sc); draw_line(lhj, lhd, sc, 10.0); draw_circle(lhd, 8, sc)
		draw_line(right_sh, right_sl, sc, 12.0); draw_line(right_sl, rhj, sc, 12.0)
		draw_circle(rhj, 5, sc); draw_line(rhj, rhd, sc, 10.0); draw_circle(rhd, 8, sc)
		draw_line(head_pos + Vector2(0, 14), head_pos + Vector2(0, 4), sc, 10.0)
		draw_circle(head_pos, 16, sc)

# =============================================================================
#  STICK FIGURE + TONAL OUTLINE
# =============================================================================

func _outline_color(col: Color) -> Color:
	var lum = col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	var r   = lerp(col.r, lum, figure_outline_darken * 0.3)
	var g   = lerp(col.g, lum, figure_outline_darken * 0.3)
	var b   = lerp(col.b, lum, figure_outline_darken * 0.3)
	r = lerp(r, 0.0, figure_outline_darken)
	g = lerp(g, 0.0, figure_outline_darken)
	b = lerp(b, 0.0, figure_outline_darken)
	return Color(r, g, b, figure_outline_alpha)


func _draw_stick_figure() -> void:
	var skin_color    = Color("#C68642")
	var shirt_color   = Color("#2E4A6B")
	var pants_color   = Color("#1A1A2E")
	var shoe_color    = Color("d89418ff")
	var harness_color = Color("#E8A020")

	var lh_skin = skin_color
	var rh_skin = skin_color

	var lh_scale = _lh_draw_scale
	var rh_scale = _rh_draw_scale
	var lf_scale = _lf_draw_scale
	var rf_scale = _rf_draw_scale

	var lhd = lh.node.position + lh.shake_offset + lh.visual_offset + _lh_hover_jitter
	var rhd = rh.node.position + rh.shake_offset + rh.visual_offset + _rh_hover_jitter
	var lfd = lf.node.position + lf.shake_offset + lf.visual_offset + _lf_hover_jitter
	var rfd = rf.node.position + rf.shake_offset + rf.visual_offset + _rf_hover_jitter

	var head_pos  = Vector2(0, HEAD_OFFSET)
	var left_sh   = Vector2(-SHOULDER_OFFSET, 0)
	var right_sh  = Vector2( SHOULDER_OFFSET, 0)
	var left_hip  = Vector2(-HIP_OFFSET, HIP_DOWN)
	var right_hip = Vector2( HIP_OFFSET, HIP_DOWN)
	var hip_pos   = Vector2(0, HIP_DOWN)
	var left_sl   = left_sh.lerp(_lh_joint.position,  0.35)
	var right_sl  = right_sh.lerp(_rh_joint.position, 0.35)

	var ow = figure_outline_width

	# ── OUTLINE PASS ─────────────────────────────────────────────────────────
	if figure_outline_enabled:
		var oc_pants   = _outline_color(pants_color)
		var oc_shoe    = _outline_color(shoe_color)
		var oc_shirt   = _outline_color(shirt_color)
		var oc_harness = _outline_color(harness_color)
		var oc_skin    = _outline_color(skin_color)

		draw_line(left_hip,  _lf_joint.position, oc_pants, (12.0 + ow) * lf_scale)
		draw_circle(_lf_joint.position, (5.0 + ow * 0.5) * lf_scale, oc_pants)
		draw_line(_lf_joint.position, lfd, oc_pants, (11.0 + ow) * lf_scale)
		draw_circle(lfd, (9.0 + ow * 0.5) * lf_scale, oc_shoe)
		draw_line(right_hip, _rf_joint.position, oc_pants, (12.0 + ow) * rf_scale)
		draw_circle(_rf_joint.position, (5.0 + ow * 0.5) * rf_scale, oc_pants)
		draw_line(_rf_joint.position, rfd, oc_pants, (11.0 + ow) * rf_scale)
		draw_circle(rfd, (9.0 + ow * 0.5) * rf_scale, oc_shoe)
		draw_line(left_hip,  right_hip,        oc_pants,    17.0 + ow)
		draw_line(left_hip,  right_hip,        oc_harness,   4.0 + ow * 0.5)
		draw_line(hip_pos,   Vector2.ZERO,     oc_shirt,    19.0 + ow)
		draw_line(Vector2.ZERO, head_pos + Vector2(0, 16), oc_shirt, 17.0 + ow)
		for pt in [left_sh, right_sh, _lh_joint.position, _rh_joint.position]:
			draw_circle(pt, 5.0 + ow * 0.5, oc_shirt)
		draw_line(left_sh,   left_sl,            oc_shirt, (12.0 + ow) * lh_scale)
		draw_line(left_sl,   _lh_joint.position, oc_skin,  (12.0 + ow) * lh_scale)
		draw_circle(_lh_joint.position, (5.0 + ow * 0.5) * lh_scale, oc_skin)
		draw_line(_lh_joint.position, lhd, oc_skin, (10.0 + ow) * lh_scale)
		draw_circle(lhd, (8.0 + ow * 0.5) * lh_scale, _outline_color(lh_skin))
		draw_line(right_sh,  right_sl,           oc_shirt, (12.0 + ow) * rh_scale)
		draw_line(right_sl,  _rh_joint.position, oc_skin,  (12.0 + ow) * rh_scale)
		draw_circle(_rh_joint.position, (5.0 + ow * 0.5) * rh_scale, oc_skin)
		draw_line(_rh_joint.position, rhd, oc_skin, (10.0 + ow) * rh_scale)
		draw_circle(rhd, (8.0 + ow * 0.5) * rh_scale, _outline_color(rh_skin))
		draw_line(head_pos + Vector2(0, 14), head_pos + Vector2(0, 4), oc_skin, 10.0 + ow)
		draw_circle(head_pos, 16.0 + ow * 0.5, oc_skin)

	# ── FILL PASS ─────────────────────────────────────────────────────────────
	draw_line(left_hip,  _lf_joint.position, pants_color, 12.0 * lf_scale)
	draw_circle(_lf_joint.position, 5 * lf_scale, pants_color)
	draw_line(_lf_joint.position, lfd, pants_color, 11.0 * lf_scale)
	draw_circle(lfd, 9 * lf_scale, shoe_color)
	draw_line(right_hip, _rf_joint.position, pants_color, 12.0 * rf_scale)
	draw_circle(_rf_joint.position, 5 * rf_scale, pants_color)
	draw_line(_rf_joint.position, rfd, pants_color, 11.0 * rf_scale)
	draw_circle(rfd, 9 * rf_scale, shoe_color)
	draw_line(left_hip,  right_hip,        pants_color,   17.0)
	draw_line(left_hip,  right_hip,        harness_color,  4.0)
	draw_line(hip_pos,   Vector2.ZERO,     shirt_color,   19.0)
	draw_line(Vector2.ZERO, head_pos + Vector2(0, 16), shirt_color, 17.0)
	draw_circle(left_sh,  5, shirt_color)
	draw_line(left_sh,   left_sl,            shirt_color, 12.0 * lh_scale)
	draw_line(left_sl,   _lh_joint.position, skin_color,  12.0 * lh_scale)
	draw_circle(_lh_joint.position, 5 * lh_scale, skin_color)
	draw_line(_lh_joint.position, lhd, skin_color, 10.0 * lh_scale)
	draw_circle(lhd, 8 * lh_scale, lh_skin)
	draw_circle(right_sh, 5, shirt_color)
	draw_line(right_sh,  right_sl,           shirt_color, 12.0 * rh_scale)
	draw_line(right_sl,  _rh_joint.position, skin_color,  12.0 * rh_scale)
	draw_circle(_rh_joint.position, 5 * rh_scale, skin_color)
	draw_line(_rh_joint.position, rhd, skin_color, 10.0 * rh_scale)
	draw_circle(rhd, 8 * rh_scale, rh_skin)
	draw_line(head_pos + Vector2(0, 14), head_pos + Vector2(0, 4), skin_color, 10.0)
	draw_circle(head_pos, 16, skin_color)
	if rest_mode_active:
		var alpha = 0.5 + sin(Time.get_ticks_msec() * 0.004) * 0.25
		draw_circle(Vector2.ZERO, 10, Color(0.4, 0.8, 1.0, alpha))

# =============================================================================
#  ENVIRONMENT
# =============================================================================

func _update_spotlight() -> void:
	if not _spotlight: return
	for node in get_tree().get_nodes_in_group("weather_modifier"):
		if "weather" in node: _spotlight.visible = node.weather == 2; return
	for node in get_tree().get_nodes_in_group("dynamic_wall"):
		if "weather" in node: _spotlight.visible = node.weather == 2; return
	_spotlight.visible = false


func _update_weather_modifier() -> void:
	if _weather_modifier and _weather_modifier.has_method("update_player_data"):
		_weather_modifier.update_player_data(
			global_position + Vector2(0, HEAD_OFFSET), get_global_mouse_position())


func _query_water(pos: Vector2, vel: Vector2) -> Dictionary:
	var dwall: Node2D = get_tree().get_first_node_in_group("environment_walls")
	if dwall and dwall.has_method("check_water_collision"):
		return dwall.check_water_collision(pos, vel)
	return {"in_water": false, "depth": 0.0, "surface_y": 0.0,
			"drag": Vector2(1.0, 1.0), "buoyancy": 0.0}


func _get_light_info() -> Dictionary:
	var env_wall: Node2D = get_tree().get_first_node_in_group("environment_walls")
	if not env_wall:
		return {"direction": Vector2(0.3, 1.0).normalized(), "intensity": 0.38, "ambient": 0.14}
	var env: Dictionary = env_wall.get("_env") if env_wall.get("_env") != null else {}
	var wmod: Node        = _weather_modifier
	var weather_type: int = 0
	if wmod and "weather" in wmod: weather_type = int(wmod.weather)
	if weather_type == 2:
		var blend: float = float(wmod.get_blend()) if wmod.has_method("get_blend") else 1.0
		return {"direction": Vector2(0.0, 1.0), "intensity": 0.05 * blend, "ambient": 0.02}
	if weather_type == 5:
		var blend: float = float(wmod.get_blend()) if wmod.has_method("get_blend") else 1.0
		return {"direction": Vector2(0.0, 1.0), "intensity": lerp(0.34, 0.07, blend), "ambient": lerp(0.12, 0.20, blend)}
	var weather_shadow_mult: float = 1.0
	if weather_type in [1, 4, 6]:
		var blend: float = float(wmod.get_blend()) if wmod.has_method("get_blend") else 0.0
		weather_shadow_mult = lerp(1.0, 0.42, blend)
	if not env.get("has_sun", true):
		return {"direction": Vector2(0.0, 1.0), "intensity": 0.11 * weather_shadow_mult, "ambient": 0.07}
	var sun_color: Color = env.get("sun_color", Color(1.0, 0.95, 0.70)) as Color
	var sun_lum:   float = sun_color.r * 0.299 + sun_color.g * 0.587 + sun_color.b * 0.114
	var sky_top:   Color = env.get("sky_top",   Color(0.20, 0.45, 0.78)) as Color
	var sky_lum:   float = sky_top.r * 0.299 + sky_top.g * 0.587 + sky_top.b * 0.114
	var sky_horiz: Color = env.get("sky_horizon", Color(0.72, 0.85, 0.95)) as Color
	var is_dusk:   bool  = sky_horiz.r > sky_horiz.b + 0.15
	var direction: Vector2; var intensity: float; var ambient: float
	if is_dusk:
		direction = Vector2(0.55, 0.95).normalized(); intensity = 0.44 * sun_lum * weather_shadow_mult; ambient = 0.17
	elif sky_lum < 0.15:
		direction = Vector2(0.0, 1.0); intensity = 0.05 * weather_shadow_mult; ambient = 0.03
	else:
		direction = Vector2(0.28, 0.96).normalized(); intensity = clamp(sun_lum * 0.54, 0.20, 0.54) * weather_shadow_mult; ambient = 0.11
	if env.get("has_gym_interior", false):
		direction = Vector2(0.12, 1.0).normalized(); intensity = 0.18 * weather_shadow_mult; ambient = 0.22
	return {"direction": direction, "intensity": intensity, "ambient": ambient}

# =============================================================================
#  EXTERNAL API
# =============================================================================

func set_climbing_discipline(discipline: int) -> void:
	current_discipline = discipline
	if discipline == 2: speed_climb_active = true

func set_rope_system(rope: Node2D) -> void:
	if rope == null or not is_instance_valid(rope):
		rope_system = null
	else:
		rope_system = rope

func set_speed_timer(timer: Node) -> void:    speed_timer = timer
func get_climbing_discipline() -> int:        return current_discipline
