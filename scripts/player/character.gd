extends CharacterBody2D

@onready var main_scene: Node = get_tree().current_scene

@onready var left_hand: Node2D = $LeftHand
@onready var right_hand: Node2D = $RightHand
@onready var left_foot: Node2D = $LeftFoot
@onready var right_foot: Node2D = $RightFoot
@onready var left_hand_joint: Node2D = $LeftHandJoint
@onready var right_hand_joint: Node2D = $RightHandJoint
@onready var left_foot_joint: Node2D = $LeftFootJoint
@onready var right_foot_joint: Node2D = $RightFootJoint
@onready var left_hand_area: Area2D = $LeftHand/Area2D
@onready var right_hand_area: Area2D = $RightHand/Area2D
@onready var left_foot_area: Area2D = $LeftFoot/Area2D
@onready var right_foot_area: Area2D = $RightFoot/Area2D
@onready var cam: Camera2D = $"../Camera2D"

const CAM_LERP := 0.05  # Slower, smoother camera

@export var debug: bool = false
@export var aesthetic: bool = true

enum GripState { RELAXED, ENGAGED, PUMPED, FAIL }

var left_hand_state: GripState = GripState.RELAXED
var right_hand_state: GripState = GripState.RELAXED
var left_foot_state: GripState = GripState.RELAXED
var right_foot_state: GripState = GripState.RELAXED

# Climbing discipline
var current_discipline: int = 0  # 0=Bouldering, 1=Roped, 2=Speed
var rope_system: Node2D = null

# Speed climbing
var speed_timer: Node = null
var speed_climb_active := false

var left_hand_pressure: float = 0.0
var right_hand_pressure: float = 0.0
var left_foot_pressure: float = 0.0
var right_foot_pressure: float = 0.0

# --- Stamina thresholds — tighter range, faster drain ---
const PRESSURE_ENGAGED := 25.0
const PRESSURE_PUMPED  := 60.0
const PRESSURE_FAIL    := 100.0

var left_hand_static_time: float = 0.0
var right_hand_static_time: float = 0.0
var left_foot_static_time: float = 0.0
var right_foot_static_time: float = 0.0

var left_hand_force: float = 0.0
var right_hand_force: float = 0.0
var left_foot_force: float = 0.0
var right_foot_force: float = 0.0

enum Limb { NONE, LEFT_HAND, RIGHT_HAND, LEFT_FOOT, RIGHT_FOOT }

var selected_limbs: Array[Limb] = []

var left_hand_hold: Area2D = null
var right_hand_hold: Area2D = null
var left_foot_hold: Area2D = null
var right_foot_hold: Area2D = null

var left_hand_anchor: Vector2
var right_hand_anchor: Vector2
var left_foot_anchor: Vector2
var right_foot_anchor: Vector2

var left_hand_pin: Vector2 = Vector2.ZERO
var right_hand_pin: Vector2 = Vector2.ZERO
var left_foot_pin: Vector2 = Vector2.ZERO
var right_foot_pin: Vector2 = Vector2.ZERO

var spawn_position: Vector2
var climb_started := false
var climb_completed := false

const ARM_UPPER_LENGTH := 50.0
const ARM_LOWER_LENGTH := 50.0
const LEG_UPPER_LENGTH := 45.0
const LEG_LOWER_LENGTH := 45.0
const SHOULDER_OFFSET := 0.0
const HIP_OFFSET := 0.0
const HIP_DOWN := 20.0
const HEAD_OFFSET := -20.0

const BODY_PULL_STRENGTH := 0.35   # stronger pull keeps body under holds, reduces arm tension
const JOINT_STIFFNESS := 0.98
const LIMB_STIFFNESS := 0.98
const FOOT_SUPPORT_STRENGTH := 0.15
const FOOT_SUPPORT_MIN_Y := -30.0
const FOOT_SUPPORT_MAX_PUSH := 80.0
const FOOT_LATERAL_ASSIST := 0.08
const GRAVITY := 2200.0
const BODY_DRAG := 0.96
const LIMB_DRAG := 0.94
const MAX_JOINT_STRETCH := 1.0   # arms never stretch — hard anatomical limit
const MAX_LIMB_STRETCH := 1.0    # forearm hard limit too
const PREVENT_UPSIDE_DOWN := false

const MAX_LEG_TOTAL_STRETCH := 1.0    # legs also hard limited
const LEG_FORCE_RELEASE_THRESHOLD := 1.04  # release a bit before visual pop

const COM_OFFSET_Y := 15.0
const FOOT_CUT_THRESHOLD := 150.0
const HAND_LOAD_TOLERANCE := 1.25   # safety release — arm visually can't stretch (MAX_JOINT_STRETCH=1.0)
									 # so this only fires on extreme body swings, not micro-movements
const MOMENTUM_TRANSFER_STRENGTH := 0.2
const DYNO_VELOCITY_BOOST := 0.8

const ARM_NATURAL_ANGLE_DEG := 45.0
const ARM_NATURAL_BEND := 0
const LEG_NATURAL_SPLAY_DEG := 95.0
const FREE_LIMB_RELAXATION_SPEED := 0.10

const ENABLE_ADAPTIVE_LEGS := true
const LEG_ASSIST_THRESHOLD := 0.8
const LEG_ASSIST_STRENGTH := 0.4
const LEG_ASSIST_SPEED := 0.3
const LEG_ASSIST_MAX_EXTENSION := 0.92

@export var AUTO_FOOT_PLACEMENT := false
const FOOT_SEARCH_RADIUS := 110.0
const FOOT_PLACEMENT_TIMER := 0.35
const FOOT_PREFERENCE_BELOW := 30.0
const FOOT_RELEASE_THRESHOLD := 1.8
const FOOT_SNAP_SPEED := 0.12
const FOOT_RESTABILIZE_TIME := 0.6
const CRIMP_LEG_SPEED_FACTOR := 0.45

const ONE_ARM_PRESSURE_MULTIPLIER := 2.5
const TWO_ARM_PRESSURE_MULTIPLIER := 1.5
const THREE_LIMB_PRESSURE_MULTIPLIER := 1.0
const FOUR_LIMB_PRESSURE_MULTIPLIER := 0.6

const FOOT_PRESSURE_REDUCTION := 0.3
const EASY_HOLD_BASE_PRESSURE := 0.8

const POOR_POSITION_PRESSURE_MULT := 1.6
const LOCK_OFF_PRESSURE_MULT := 1.5
const LOCK_OFF_THRESHOLD := 0.7

const SHAKE_OUT_RECOVERY_RATE := 14.0

const FALL_DETECTION_TIME := 2.0
const FALL_VELOCITY_THRESHOLD := 400.0

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1 — EXERTION MODIFIER CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
const UPWARD_VELOCITY_THRESHOLD    := -80.0   # px/s (negative = upward in screen-space)
const UPWARD_DRAIN_MULT            := 1.5     # +50% drain while driving upward movement
const SOLE_SUPPORT_DRAIN_MULT      := 1.75    # +75% drain when sole limb holding body

# PHASE 1 — CATCH PENALTY CONSTANTS
const CATCH_BURST_1_LIMB           := 0.20    # fraction of PRESSURE_FAIL burst on 1-limb catch
const CATCH_BURST_2_LIMB           := 0.08    # fraction of PRESSURE_FAIL burst on 2-limb catch
const CATCH_DRAIN_BOOST_1          := 1.5     # drain multiplier after 1-limb catch
const CATCH_DRAIN_BOOST_2          := 1.2     # drain multiplier after 2-limb catch
const CATCH_DRAIN_BOOST_DURATION_1 := 1.0     # seconds the boost lasts (1-limb)
const CATCH_DRAIN_BOOST_DURATION_2 := 0.5     # seconds the boost lasts (2-limb)

# Catch boost timers — one per hand limb (feet don't catch falling body weight)
var left_hand_catch_boost: float  = 1.0   # current drain multiplier
var right_hand_catch_boost: float = 1.0
var left_hand_catch_timer: float  = 0.0   # seconds remaining on boost
var right_hand_catch_timer: float = 0.0
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — PROGRESSIVE STRENGTH LOSS
# ─────────────────────────────────────────────────────────────────────────────
# Force scalar breakpoints (pressure as fraction of PRESSURE_FAIL)
const P2_FORCE_ONSET   := 0.45   # below this: full strength
const P2_FORCE_MID     := 0.70   # 0.45→0.70: 100%→75%
const P2_FORCE_HIGH    := 0.90   # 0.70→0.90: 75%→50%
								  # 0.90→1.00: 50%→0%

# Body sag: how far (px) the CoM drops at max fatigue
const P2_MAX_SAG_PX    := 10.0

# Arm straightening removed — not readable, keeping physics-driven elbow only
const P2_ARM_STRAIGHTEN_ONSET := 0.60   # unused — kept so Phase 2 refs compile
const P2_ARM_STRAIGHTEN_MAX   := 0.85   # unused

# PHASE 2 — REST MODE
const P2_REST_DRAIN_BOTH_FEET  := 0.30  # drain multiplier when both feet on wall
const P2_REST_DRAIN_ONE_FOOT   := 0.65  # drain multiplier when one foot on wall
const P2_REST_RECOVERY_SCALE   := 1.5   # extra recovery rate multiplier during rest

# PHASE 2 — IMPROVED PUMP FEEDBACK (shake is now pressure-driven, not state-driven)
# Shake amplitude (px) at various pressure fractions
const P2_SHAKE_ONSET      := 0.15   # shake only begins well into pump
const P2_SHAKE_MAX_AMP    := 3.0    # max shake amplitude (px) at 100% — subtle
const P2_SHAKE_LERP_IN    := 0.2    # how fast shake builds  (lower = slower ramp-in)
const P2_SHAKE_LERP_OUT   := 1.2    # how fast shake fades when pressure drops
# Pulse: slow rhythmic bob at very high pump, layered on top of fast shake
const P2_PULSE_ONSET   := 0.65
const P2_PULSE_AMP     := 1.8    # px — kept subtle
const P2_PULSE_FREQ    := 3.0    # Hz
# Darkening: forearm tints very slightly toward brown-grey — NOT red
# Blend stays very low so it reads as "darker" not "coloured"
const P2_DARK_ONSET    := 0.35
const P2_DARK_COLOR    := Color(0.18, 0.12, 0.12, 1.0)   # very dark warm grey at 100%
const P2_DARK_MAX_BLEND := 0.55   # never fully reach P2_DARK_COLOR — cap the blend

# Runtime state
var rest_mode_active: bool = false
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3 CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
# 3.1 Leg Efficiency Bonus
const P3_LEG_BONUS_DRAIN_MULT := 0.88   # global drain multiplier when well-positioned
const P3_LEG_BONUS_COM_TOL    := 50.0   # px horizontal tolerance for "on-balance"
const P3_LEG_BONUS_RAMP       := 0.5    # lerp speed for smoothing the bonus in/out

# 3.2 Failure Escalation
const P3_SLIP_THRESHOLD       := 0.90   # fraction of PRESSURE_FAIL that triggers slip
const P3_STRUGGLE_THRESHOLD   := 1.00   # fraction that triggers struggle
const P3_STRUGGLE_WINDOW      := 0.55   # seconds the player has to shift load
const P3_SLIP_SHAKE_MULT      := 1.4    # modest boost at slip — still readable
const P3_STRUGGLE_SHAKE_MULT  := 2.0    # visible burst during struggle window

enum FailureStage { NONE, SLIP, STRUGGLE, FALLING }

# Per-hand failure state (feet don't escalate the same way)
var left_hand_fail_stage:  FailureStage = FailureStage.NONE
var right_hand_fail_stage: FailureStage = FailureStage.NONE
var left_hand_struggle_timer:  float = 0.0
var right_hand_struggle_timer: float = 0.0

# Smoothed leg efficiency bonus (lerped to avoid flicker)
var _leg_bonus_smooth: float = 1.0
# ─────────────────────────────────────────────────────────────────────────────

var swing_momentum: Vector2 = Vector2.ZERO
const SWING_DAMPENING := 0.92
const SWING_ACCELERATION := 1200.0
const MAX_SWING_SPEED := 1500.0
const SWING_BUILDUP_RATE := 1.8

var last_swing_direction: Vector2 = Vector2.ZERO
var swing_combo_count: int = 0
const SWING_DIRECTION_THRESHOLD := 0.3

var building_momentum := false
var momentum_buildup_time := 0.0

var limb_swing_velocities: Dictionary = {}

const MOUSE_CONTROL_ENABLED := true
const MOUSE_DEADZONE := 5.0
const ALLOW_ARM_CROSSING := true
const ALLOW_FOOT_CROSSING := true
const MIN_HAND_SEPARATION := 20.0
const MIN_FOOT_SEPARATION := 15.0

const BASE_HAND_MOVE_SPEED := 0.75
const BASE_REACH_DISTANCE := 200.0

@export var GRAB_RADIUS := 35.0

const SHARED_HOLD_HAND_OFFSET := 15.0
const SHARED_HOLD_HAND_FOOT_OFFSET := 20.0

func get_hand_modifiers(state: GripState) -> Dictionary:
	match state:
		GripState.RELAXED:
			return {"reach_mult": 1.0, "speed_mult": 1.0, "latency": 0.0, "shake": 0.0}
		GripState.ENGAGED:
			return {"reach_mult": 0.95, "speed_mult": 0.98, "latency": 0.02, "shake": 0.05}
		GripState.PUMPED:
			return {"reach_mult": 0.82, "speed_mult": 0.78, "latency": 0.10, "shake": 0.20}
		GripState.FAIL:
			return {"reach_mult": 0.0, "speed_mult": 0.0, "latency": 1.0, "shake": 1.0}
	return get_hand_modifiers(GripState.RELAXED)

func get_foot_modifiers(state: GripState) -> Dictionary:
	match state:
		GripState.RELAXED:
			return {"shake": 0.0}
		GripState.ENGAGED:
			return {"shake": 0.04}
		GripState.PUMPED:
			return {"shake": 0.14}
		GripState.FAIL:
			return {"shake": 0.6}
	return get_foot_modifiers(GripState.RELAXED)

var body_velocity := Vector2.ZERO
var left_hand_velocity := Vector2.ZERO
var right_hand_velocity := Vector2.ZERO
var left_foot_velocity := Vector2.ZERO
var right_foot_velocity := Vector2.ZERO
var left_hand_joint_velocity := Vector2.ZERO
var right_hand_joint_velocity := Vector2.ZERO
var left_foot_joint_velocity := Vector2.ZERO
var right_foot_joint_velocity := Vector2.ZERO

var com_position := Vector2.ZERO
var com_velocity := Vector2.ZERO
var last_held_limbs := 0

var left_hand_grabbing := false
var right_hand_grabbing := false
var left_foot_grabbing := false
var right_foot_grabbing := false
var left_hand_grab_target := Vector2.ZERO
var right_hand_grab_target := Vector2.ZERO
var left_foot_grab_target := Vector2.ZERO
var right_foot_grab_target := Vector2.ZERO

var foot_placement_timer := 0.0
var left_foot_manual := false
var right_foot_manual := false
var left_foot_auto_disabled := false
var right_foot_auto_disabled := false

var left_foot_auto_target: Vector2 = Vector2.ZERO
var right_foot_auto_target: Vector2 = Vector2.ZERO
var left_foot_auto_animating := false
var right_foot_auto_animating := false

var left_foot_settle_timer: float = 0.0
var right_foot_settle_timer: float = 0.0

var left_foot_user_override := false
var right_foot_user_override := false

var previous_left_hand_pos := Vector2.ZERO
var previous_right_hand_pos := Vector2.ZERO
var previous_left_foot_pos := Vector2.ZERO
var previous_right_foot_pos := Vector2.ZERO

var mouse_aim_position := Vector2.ZERO
var use_mouse_aim := false

var left_hand_shake_offset := Vector2.ZERO
var right_hand_shake_offset := Vector2.ZERO
var left_foot_shake_offset := Vector2.ZERO
var right_foot_shake_offset := Vector2.ZERO

var left_hand_visual_offset := Vector2.ZERO
var right_hand_visual_offset := Vector2.ZERO
var left_foot_visual_offset := Vector2.ZERO
var right_foot_visual_offset := Vector2.ZERO

const VISUAL_ANIMATION_SPEED := 0.25

var left_hand_shake_lerp: float = 0.0
var right_hand_shake_lerp: float = 0.0
var left_foot_shake_lerp: float = 0.0
var right_foot_shake_lerp: float = 0.0

const SHAKE_LERP_SPEED := 2.0

var fall_timer: float = 0.0

var _ragdoll_active: bool = false
var _ragdoll_elapsed: float = 0.0
var _ragdoll_max_time: float = 2.0

var _saved_lh_pos:  Vector2
var _saved_rh_pos:  Vector2
var _saved_lf_pos:  Vector2
var _saved_rf_pos:  Vector2
var _saved_lhj_pos: Vector2
var _saved_rhj_pos: Vector2
var _saved_lfj_pos: Vector2
var _saved_rfj_pos: Vector2

func _ready():
	spawn_position = global_position

	left_hand_joint.position = Vector2(-SHOULDER_OFFSET, 10)
	right_hand_joint.position = Vector2(SHOULDER_OFFSET, 10)
	left_hand.position = Vector2(-SHOULDER_OFFSET, 10 + ARM_LOWER_LENGTH)
	right_hand.position = Vector2(SHOULDER_OFFSET, 10 + ARM_LOWER_LENGTH)
	left_foot_joint.position = Vector2(-HIP_OFFSET, HIP_DOWN + 20)
	right_foot_joint.position = Vector2(HIP_OFFSET, HIP_DOWN + 20)
	left_foot.position = Vector2(-HIP_OFFSET, HIP_DOWN + LEG_UPPER_LENGTH + LEG_LOWER_LENGTH / 2)
	right_foot.position = Vector2(HIP_OFFSET, HIP_DOWN + LEG_UPPER_LENGTH + LEG_LOWER_LENGTH / 2)

	for area in [left_hand_area, right_hand_area, left_foot_area, right_foot_area]:
		area.collision_mask = 2

	com_position = global_position + Vector2(0, COM_OFFSET_Y)

	previous_left_hand_pos = left_hand.global_position
	previous_right_hand_pos = right_hand.global_position
	previous_left_foot_pos = left_foot.global_position
	previous_right_foot_pos = right_foot.global_position

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	call_deferred("initial_grab")

func _process(delta):
	if _ragdoll_active:
		_ragdoll_elapsed += delta
		if _ragdoll_elapsed >= _ragdoll_max_time:
			_ragdoll_active = false
		update_camera()
		queue_redraw()
		return

	handle_input()
	update_grip_states(delta)
	update_shake_effects(delta)
	update_momentum_system(delta)
	simulate_physics(delta)

	if AUTO_FOOT_PLACEMENT:
		auto_place_feet(delta)

	check_fall_detection(delta)
	check_climb_completion()
	update_camera()
	queue_redraw()

func play_crashpad_ragdoll(duration: float) -> void:
	if _ragdoll_active:
		return
	_ragdoll_active   = true
	_ragdoll_elapsed  = 0.0
	_ragdoll_max_time = duration

	if left_hand_hold:  left_hand_hold.release(left_hand);   left_hand_hold  = null
	if right_hand_hold: right_hand_hold.release(right_hand); right_hand_hold = null
	if left_foot_hold:  left_foot_hold.release(left_foot);   left_foot_hold  = null
	if right_foot_hold: right_foot_hold.release(right_foot); right_foot_hold = null
	selected_limbs.clear()
	use_mouse_aim = false
	com_velocity  = Vector2.ZERO
	body_velocity = Vector2.ZERO

	var t := create_tween()
	t.set_parallel(true)

	t.tween_property(left_hand_joint,  "position", Vector2(-55,  5),  0.10)
	t.tween_property(left_hand,        "position", Vector2(-85, 30),  0.10)
	t.tween_property(right_hand_joint, "position", Vector2( 55,  5),  0.10)
	t.tween_property(right_hand,       "position", Vector2( 85, 30),  0.10)
	t.tween_property(left_foot_joint,  "position", Vector2(-28, 35),  0.10)
	t.tween_property(left_foot,        "position", Vector2(-38, 80),  0.10)
	t.tween_property(right_foot_joint, "position", Vector2( 28, 35),  0.10)
	t.tween_property(right_foot,       "position", Vector2( 38, 80),  0.10)

	t.tween_property(left_hand_joint,  "position", Vector2(-32, 12),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(left_hand,        "position", Vector2(-48, 52),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(right_hand_joint, "position", Vector2( 32, 12),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(right_hand,       "position", Vector2( 48, 52),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(left_foot_joint,  "position", Vector2(-14, 28),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(left_foot,        "position", Vector2(-18, 68),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(right_foot_joint, "position", Vector2( 14, 28),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(right_foot,       "position", Vector2( 18, 68),  0.5).set_delay(0.3).set_trans(Tween.TRANS_SINE)

func update_grip_states(delta: float):
	# ── PHASE 3: tick leg efficiency bonus before hand states ─────────────────
	var leg_bonus_target := _compute_leg_bonus_target()
	_leg_bonus_smooth = lerp(_leg_bonus_smooth, leg_bonus_target, P3_LEG_BONUS_RAMP * delta)
	# ─────────────────────────────────────────────────────────────────────────
	update_hand_grip_state(Limb.LEFT_HAND, delta)
	update_hand_grip_state(Limb.RIGHT_HAND, delta)
	update_foot_grip_state(Limb.LEFT_FOOT, delta)
	update_foot_grip_state(Limb.RIGHT_FOOT, delta)

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1 HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Returns true when this hand limb is the primary structure holding the body up.
# Used to decide whether the "upward movement" multiplier should fire.
func _is_hand_load_bearing(hand: Limb) -> bool:
	var hold = left_hand_hold if hand == Limb.LEFT_HAND else right_hand_hold
	return hold != null and not (left_hand_grabbing if hand == Limb.LEFT_HAND else right_hand_grabbing)

# Exertion multiplier for hand limbs.
#   - Sole support (1 total limb held): x1.75
#   - Driving upward movement while load-bearing: x1.5
#   - Otherwise: x1.0 (base, combined with the catch boost below)
func _get_hand_exertion_mult(hand: Limb) -> float:
	var held := count_held_limbs()
	if held == 1 and _is_hand_load_bearing(hand):
		return SOLE_SUPPORT_DRAIN_MULT
	if com_velocity.y < UPWARD_VELOCITY_THRESHOLD and _is_hand_load_bearing(hand):
		return UPWARD_DRAIN_MULT
	return 1.0

# Returns the current catch-boost multiplier for a hand and ticks its timer down.
func _tick_catch_boost(hand: Limb, delta: float) -> float:
	if hand == Limb.LEFT_HAND:
		if left_hand_catch_timer > 0.0:
			left_hand_catch_timer -= delta
			if left_hand_catch_timer <= 0.0:
				left_hand_catch_timer = 0.0
				left_hand_catch_boost = 1.0
		return left_hand_catch_boost
	else:
		if right_hand_catch_timer > 0.0:
			right_hand_catch_timer -= delta
			if right_hand_catch_timer <= 0.0:
				right_hand_catch_timer = 0.0
				right_hand_catch_boost = 1.0
		return right_hand_catch_boost

# Called from attempt_grab() immediately after a successful hand catch.
# Applies burst pressure and starts the elevated-drain window.
func _apply_catch_penalty(hand: Limb) -> void:
	# Only penalise if the body was genuinely falling hard
	if com_velocity.y < FALL_VELOCITY_THRESHOLD:
		return

	var held := count_held_limbs()   # count AFTER this grab registered
	var burst: float
	var boost: float
	var duration: float

	if held == 1:
		burst    = PRESSURE_FAIL * CATCH_BURST_1_LIMB
		boost    = CATCH_DRAIN_BOOST_1
		duration = CATCH_DRAIN_BOOST_DURATION_1
	else:
		burst    = PRESSURE_FAIL * CATCH_BURST_2_LIMB
		boost    = CATCH_DRAIN_BOOST_2
		duration = CATCH_DRAIN_BOOST_DURATION_2

	if hand == Limb.LEFT_HAND:
		left_hand_pressure    = minf(left_hand_pressure + burst, PRESSURE_FAIL)
		left_hand_catch_boost = boost
		left_hand_catch_timer = duration
		if debug:
			print("CATCH PENALTY [LH] burst=%.1f boost=%.2f for %.2fs" % [burst, boost, duration])
	else:
		right_hand_pressure    = minf(right_hand_pressure + burst, PRESSURE_FAIL)
		right_hand_catch_boost = boost
		right_hand_catch_timer = duration
		if debug:
			print("CATCH PENALTY [RH] burst=%.1f boost=%.2f for %.2fs" % [burst, boost, duration])

# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Returns a 0→1 grip force scalar. At full pump the hand contributes nothing to
# pulling the body up; applied to BODY_PULL_STRENGTH in apply_limb_tension.
func _get_grip_force_scalar(pressure: float) -> float:
	var t := pressure / PRESSURE_FAIL
	if t < P2_FORCE_ONSET:
		return 1.0
	if t < P2_FORCE_MID:
		return lerp(1.0, 0.75, (t - P2_FORCE_ONSET) / (P2_FORCE_MID - P2_FORCE_ONSET))
	if t < P2_FORCE_HIGH:
		return lerp(0.75, 0.50, (t - P2_FORCE_MID) / (P2_FORCE_HIGH - P2_FORCE_MID))
	return lerp(0.50, 0.0, (t - P2_FORCE_HIGH) / (1.0 - P2_FORCE_HIGH))

# Returns the average grip scalar across all held hands — used for body sag.
func _get_body_fatigue_t() -> float:
	var total := 0.0
	var count := 0
	if left_hand_hold:
		total += left_hand_pressure / PRESSURE_FAIL
		count += 1
	if right_hand_hold:
		total += right_hand_pressure / PRESSURE_FAIL
		count += 1
	return total / max(count, 1)

# Pressure-driven shake amplitude for a hand limb (replaces state-based shake).
# Returns a target shake amplitude in pixels.
# Returns a 0→1 shake fraction (not pixels — multiply by P2_SHAKE_MAX_AMP in the caller).
func _get_pressure_shake_frac(pressure: float) -> float:
	var t := pressure / PRESSURE_FAIL
	if t < P2_SHAKE_ONSET:
		return 0.0
	return (t - P2_SHAKE_ONSET) / (1.0 - P2_SHAKE_ONSET)  # 0→1 over onset→100%

# Slow rhythmic pulse offset for very high pump.
func _get_pulse_offset(pressure: float, phase_offset: float) -> Vector2:
	var t := pressure / PRESSURE_FAIL
	if t < P2_PULSE_ONSET:
		return Vector2.ZERO
	var strength := (t - P2_PULSE_ONSET) / (1.0 - P2_PULSE_ONSET)
	var time := Time.get_ticks_msec() * 0.001
	var pulse := sin(time * P2_PULSE_FREQ * TAU + phase_offset) * P2_PULSE_AMP * strength
	return Vector2(pulse * 0.25, pulse)

# Forearm colour: stays very close to black — just a barely-perceptible warm darkening.
# P2_DARK_MAX_BLEND caps how far toward P2_DARK_COLOR we ever go.
func _get_limb_color(pressure: float) -> Color:
	var t := pressure / PRESSURE_FAIL
	if t < P2_DARK_ONSET:
		return Color.BLACK
	var blend := minf((t - P2_DARK_ONSET) / (1.0 - P2_DARK_ONSET), 1.0) * P2_DARK_MAX_BLEND
	return Color.BLACK.lerp(P2_DARK_COLOR, blend)

# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3 HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Returns a drain multiplier for the leg efficiency bonus.
# Smoothly lerped via _leg_bonus_smooth each frame to avoid flicker.
func _compute_leg_bonus_target() -> float:
	if not (left_foot_hold and right_foot_hold):
		return 1.0
	var mid_x = (left_foot_hold.get_limb_anchor(left_foot).x +
				  right_foot_hold.get_limb_anchor(right_foot).x) * 0.5
	if abs(com_position.x - mid_x) <= P3_LEG_BONUS_COM_TOL:
		return P3_LEG_BONUS_DRAIN_MULT
	return 1.0

# Called from update_grip_states. Advances failure escalation for one hand limb.
# Returns the current FailureStage so the grip-state function can use it.
func _update_hand_failure_stage(hand: Limb, pressure: float, delta: float) -> FailureStage:
	# Only escalate when the hand is actually gripping something
	var hold := left_hand_hold if hand == Limb.LEFT_HAND else right_hand_hold
	if hold == null:
		if hand == Limb.LEFT_HAND:
			left_hand_fail_stage = FailureStage.NONE
			left_hand_struggle_timer = 0.0
		else:
			right_hand_fail_stage = FailureStage.NONE
			right_hand_struggle_timer = 0.0
		return FailureStage.NONE

	var t := pressure / PRESSURE_FAIL
	var stage: FailureStage = left_hand_fail_stage if hand == Limb.LEFT_HAND else right_hand_fail_stage
	var struggle_timer: float = left_hand_struggle_timer if hand == Limb.LEFT_HAND else right_hand_struggle_timer

	if t < P3_SLIP_THRESHOLD:
		# Recovering — reset cleanly
		stage = FailureStage.NONE
		struggle_timer = 0.0
	elif t < P3_STRUGGLE_THRESHOLD:
		# In the slip zone — visual-only, no timer
		stage = FailureStage.SLIP
		struggle_timer = 0.0
	else:
		# At 100% — begin struggle window
		if stage != FailureStage.STRUGGLE:
			stage = FailureStage.STRUGGLE
			struggle_timer = P3_STRUGGLE_WINDOW
		else:
			struggle_timer -= delta
			if struggle_timer <= 0.0:
				stage = FailureStage.FALLING

	if hand == Limb.LEFT_HAND:
		left_hand_fail_stage = stage
		left_hand_struggle_timer = struggle_timer
	else:
		right_hand_fail_stage = stage
		right_hand_struggle_timer = struggle_timer

	return stage

# ─────────────────────────────────────────────────────────────────────────────

func update_hand_grip_state(hand: Limb, delta: float):
	var hold: Area2D
	var pressure: float
	var state: GripState
	var static_time: float
	var limb_node: Node2D
	var force: float

	if hand == Limb.LEFT_HAND:
		hold = left_hand_hold
		pressure = left_hand_pressure
		state = left_hand_state
		static_time = left_hand_static_time
		limb_node = left_hand
		force = left_hand_force
	else:
		hold = right_hand_hold
		pressure = right_hand_pressure
		state = right_hand_state
		static_time = right_hand_static_time
		limb_node = right_hand
		force = right_hand_force

	if hold != null and hand not in selected_limbs:
		static_time += delta
	else:
		static_time = 0.0

	if hold != null:
		var body_offset = calculate_body_offset(hand)
		var foot_support = calculate_foot_support_ratio()

		var held_limb_count = count_held_limbs()
		var loading_multiplier = get_loading_multiplier(held_limb_count)

		var shoulder_pos = global_position + Vector2(-SHOULDER_OFFSET if hand == Limb.LEFT_HAND else SHOULDER_OFFSET, 0)
		var hand_pos = limb_node.global_position
		var to_hand = hand_pos - shoulder_pos
		var pull_force = abs(com_velocity.y) + (abs(com_velocity.x) * 0.3)
		force = pull_force * (1.0 - foot_support)

		var arm_extension = calculate_arm_extension(hand)
		var lock_off_mult = 1.0
		if arm_extension < LOCK_OFF_THRESHOLD:
			lock_off_mult = LOCK_OFF_PRESSURE_MULT

		var hold_pressure = hold.get_state_pressure(delta, body_offset, static_time, foot_support, limb_node)

		var force_multiplier = 1.0 + (force * 0.01)
		hold_pressure *= force_multiplier
		hold_pressure *= loading_multiplier
		hold_pressure *= lock_off_mult

		# ── PHASE 1: exertion multiplier ─────────────────────────────────────
		hold_pressure *= _get_hand_exertion_mult(hand)
		# ── PHASE 1: catch drain boost (ticks timer, returns current boost) ──
		hold_pressure *= _tick_catch_boost(hand, delta)
		# ─────────────────────────────────────────────────────────────────────

		# ── PHASE 2: Rest Mode drain reduction ───────────────────────────────
		if rest_mode_active:
			foot_support = calculate_foot_support_ratio()  # 0.0, 0.5, or 1.0
			if foot_support >= 1.0:
				hold_pressure *= P2_REST_DRAIN_BOTH_FEET
			elif foot_support > 0.0:
				hold_pressure *= P2_REST_DRAIN_ONE_FOOT
			# no feet = no benefit, hold_pressure unchanged
		# ─────────────────────────────────────────────────────────────────────

		# ── PHASE 3: Leg Efficiency Bonus ────────────────────────────────────
		hold_pressure *= _leg_bonus_smooth
		# ─────────────────────────────────────────────────────────────────────

		var pressure_floor = EASY_HOLD_BASE_PRESSURE * loading_multiplier * 0.5 * delta
		if hold_pressure < pressure_floor:
			hold_pressure = pressure_floor

		if body_offset > 0.5:
			hold_pressure *= POOR_POSITION_PRESSURE_MULT

		pressure += hold_pressure

		var body_balance = calculate_body_balance()
		var recovery = hold.get_recovery_rate(delta, body_balance, foot_support)
		if recovery > 0.0:
			# ── PHASE 2: extra recovery while resting ─────────────────────────
			if rest_mode_active and foot_support > 0.0:
				recovery *= P2_REST_RECOVERY_SCALE
			# ─────────────────────────────────────────────────────────────────
			pressure -= recovery
	else:
		force = 0.0
		if hand not in selected_limbs:
			pressure -= SHAKE_OUT_RECOVERY_RATE * delta

	pressure = clamp(pressure, 0.0, PRESSURE_FAIL)

	# ── PHASE 3: Failure Escalation replaces binary pop-off ──────────────────
	var fail_stage := _update_hand_failure_stage(hand, pressure, delta)
	if fail_stage == FailureStage.FALLING:
		state = GripState.FAIL
		release_limb(hand)
	elif pressure >= PRESSURE_FAIL:
		# Clamp at max — struggle window will resolve it via escalation above
		state = GripState.PUMPED
	elif pressure >= PRESSURE_PUMPED:
	# ─────────────────────────────────────────────────────────────────────────
		state = GripState.PUMPED
	elif pressure >= PRESSURE_ENGAGED:
		state = GripState.ENGAGED
	else:
		state = GripState.RELAXED

	if hand == Limb.LEFT_HAND:
		left_hand_pressure = pressure
		left_hand_state = state
		left_hand_static_time = static_time
		left_hand_force = force
	else:
		right_hand_pressure = pressure
		right_hand_state = state
		right_hand_static_time = static_time
		right_hand_force = force

func update_foot_grip_state(foot: Limb, delta: float):
	var hold: Area2D
	var pressure: float
	var state: GripState
	var static_time: float
	var limb_node: Node2D
	var force: float

	if foot == Limb.LEFT_FOOT:
		hold = left_foot_hold
		pressure = left_foot_pressure
		state = left_foot_state
		static_time = left_foot_static_time
		limb_node = left_foot
		force = left_foot_force
	else:
		hold = right_foot_hold
		pressure = right_foot_pressure
		state = right_foot_state
		static_time = right_foot_static_time
		limb_node = right_foot
		force = right_foot_force

	if hold != null and foot not in selected_limbs:
		static_time += delta
	else:
		static_time = 0.0

	if hold != null:
		var body_offset = calculate_body_offset(foot)
		var foot_support = calculate_foot_support_ratio()

		var held_limb_count = count_held_limbs()
		var loading_multiplier = get_loading_multiplier(held_limb_count)

		var hip_pos = global_position + Vector2(-HIP_OFFSET if foot == Limb.LEFT_FOOT else HIP_OFFSET, HIP_DOWN)
		var foot_pos = limb_node.global_position
		var to_foot = foot_pos - hip_pos
		var push_force = abs(com_velocity.y) * 0.3
		force = push_force

		var hold_pressure = hold.get_state_pressure(delta, body_offset, static_time, foot_support, limb_node)

		var force_multiplier = 1.0 + (force * 0.005)
		hold_pressure *= force_multiplier
		hold_pressure *= FOOT_PRESSURE_REDUCTION
		hold_pressure *= loading_multiplier

		if hold_pressure < EASY_HOLD_BASE_PRESSURE * FOOT_PRESSURE_REDUCTION:
			hold_pressure = EASY_HOLD_BASE_PRESSURE * FOOT_PRESSURE_REDUCTION * delta

		if body_offset > 0.5:
			hold_pressure *= 1.2

		pressure += hold_pressure
	else:
		force = 0.0
		if foot not in selected_limbs:
			pressure -= SHAKE_OUT_RECOVERY_RATE * delta

	pressure = clamp(pressure, 0.0, PRESSURE_FAIL)

	if pressure >= PRESSURE_FAIL:
		state = GripState.FAIL
		release_limb(foot)
	elif pressure >= PRESSURE_PUMPED:
		state = GripState.PUMPED
	elif pressure >= PRESSURE_ENGAGED:
		state = GripState.ENGAGED
	else:
		state = GripState.RELAXED

	if foot == Limb.LEFT_FOOT:
		left_foot_pressure = pressure
		left_foot_state = state
		left_foot_static_time = static_time
		left_foot_force = force
	else:
		right_foot_pressure = pressure
		right_foot_state = state
		right_foot_static_time = static_time
		right_foot_force = force

func count_held_limbs() -> int:
	var count = 0
	if left_hand_hold and not left_hand_grabbing and Limb.LEFT_HAND not in selected_limbs:
		count += 1
	if right_hand_hold and not right_hand_grabbing and Limb.RIGHT_HAND not in selected_limbs:
		count += 1
	if left_foot_hold and not left_foot_grabbing and Limb.LEFT_FOOT not in selected_limbs:
		count += 1
	if right_foot_hold and not right_foot_grabbing and Limb.RIGHT_FOOT not in selected_limbs:
		count += 1
	return count

func get_loading_multiplier(held_limbs: int) -> float:
	match held_limbs:
		1: return ONE_ARM_PRESSURE_MULTIPLIER
		2: return TWO_ARM_PRESSURE_MULTIPLIER
		3: return THREE_LIMB_PRESSURE_MULTIPLIER
		4: return FOUR_LIMB_PRESSURE_MULTIPLIER
		_: return 1.0

func calculate_arm_extension(hand: Limb) -> float:
	var shoulder_pos: Vector2
	var hand_pos: Vector2

	if hand == Limb.LEFT_HAND:
		shoulder_pos = global_position + Vector2(-SHOULDER_OFFSET, 0)
		hand_pos = left_hand.global_position
	else:
		shoulder_pos = global_position + Vector2(SHOULDER_OFFSET, 0)
		hand_pos = right_hand.global_position

	var current_dist = shoulder_pos.distance_to(hand_pos)
	var max_dist = ARM_UPPER_LENGTH + ARM_LOWER_LENGTH
	return clamp(current_dist / max_dist, 0.0, 1.0)

func calculate_body_offset(limb: Limb) -> float:
	var anchor: Vector2

	match limb:
		Limb.LEFT_HAND:
			anchor = left_hand_anchor if left_hand_anchor != Vector2.ZERO else left_hand.global_position
		Limb.RIGHT_HAND:
			anchor = right_hand_anchor if right_hand_anchor != Vector2.ZERO else right_hand.global_position
		Limb.LEFT_FOOT:
			anchor = left_foot_anchor if left_foot_anchor != Vector2.ZERO else left_foot.global_position
		Limb.RIGHT_FOOT:
			anchor = right_foot_anchor if right_foot_anchor != Vector2.ZERO else right_foot.global_position
		_:
			return 0.0

	if anchor == Vector2.ZERO:
		return 0.0

	var ideal_body = anchor + Vector2(0, 60)
	var offset = com_position.distance_to(ideal_body)
	return clamp(offset / 100.0, 0.0, 1.0)

func calculate_body_balance() -> float:
	var balance = 0.0
	if left_foot_hold and right_foot_hold:
		balance += 0.5
	elif left_foot_hold or right_foot_hold:
		balance += 0.25
	if left_hand_hold and right_hand_hold:
		balance += 0.3
	var vel_factor = clamp(1.0 - (com_velocity.length() / 100.0), 0.0, 0.2)
	balance += vel_factor
	return clamp(balance, 0.0, 1.0)

func calculate_foot_support_ratio() -> float:
	var support = 0.0
	if left_foot_hold:
		support += 0.5
	if right_foot_hold:
		support += 0.5
	return support

func update_momentum_system(delta: float):
	pass

func get_limb_swing_velocity(limb: Limb, delta: float) -> Vector2:
	if delta <= 0:
		return Vector2.ZERO
	var current_pos := Vector2.ZERO
	var previous_pos := Vector2.ZERO
	match limb:
		Limb.LEFT_HAND:
			current_pos = left_hand.global_position
			previous_pos = previous_left_hand_pos
		Limb.RIGHT_HAND:
			current_pos = right_hand.global_position
			previous_pos = previous_right_hand_pos
		Limb.LEFT_FOOT:
			current_pos = left_foot.global_position
			previous_pos = previous_left_foot_pos
		Limb.RIGHT_FOOT:
			current_pos = right_foot.global_position
			previous_pos = previous_right_foot_pos
	return (current_pos - previous_pos) / delta

func update_shake_effects(delta: float):
	var t_now := Time.get_ticks_msec() * 0.001

	# ── PHASE 2: pressure-driven shake replaces coarse state-based shake ─────
	# shake_lerp tracks a 0→1 fraction; multiply by P2_SHAKE_MAX_AMP for pixels.
	# Separate lerp speeds: slow ramp-in, faster fade-out.

	# Left hand
	var lh_base_frac := _get_pressure_shake_frac(left_hand_pressure)
	# ── PHASE 3: failure stage adds a small flat bump on top ─────────────────
	var lh_fail_add := 0.0
	match left_hand_fail_stage:
		FailureStage.SLIP:     lh_fail_add = 0.15
		FailureStage.STRUGGLE: lh_fail_add = 0.35
	var lh_target_frac := minf(lh_base_frac + lh_fail_add, 1.0)
	# ─────────────────────────────────────────────────────────────────────────
	var lh_lerp_speed := P2_SHAKE_LERP_IN if lh_target_frac > left_hand_shake_lerp else P2_SHAKE_LERP_OUT
	left_hand_shake_lerp = lerp(left_hand_shake_lerp, lh_target_frac, lh_lerp_speed * delta)
	if left_hand_shake_lerp > 0.01:
		var amp  := left_hand_shake_lerp * P2_SHAKE_MAX_AMP
		var freq := 28.0 + left_hand_shake_lerp * 8.0
		left_hand_shake_offset = Vector2(
			sin(t_now * freq)              * amp,
			sin(t_now * freq * 1.3 + 1.7) * amp
		) + _get_pulse_offset(left_hand_pressure, 0.0)
	else:
		left_hand_shake_offset = Vector2.ZERO

	# Right hand
	var rh_base_frac := _get_pressure_shake_frac(right_hand_pressure)
	var rh_fail_add := 0.0
	match right_hand_fail_stage:
		FailureStage.SLIP:     rh_fail_add = 0.15
		FailureStage.STRUGGLE: rh_fail_add = 0.35
	var rh_target_frac := minf(rh_base_frac + rh_fail_add, 1.0)
	var rh_lerp_speed := P2_SHAKE_LERP_IN if rh_target_frac > right_hand_shake_lerp else P2_SHAKE_LERP_OUT
	right_hand_shake_lerp = lerp(right_hand_shake_lerp, rh_target_frac, rh_lerp_speed * delta)
	if right_hand_shake_lerp > 0.01:
		var amp  := right_hand_shake_lerp * P2_SHAKE_MAX_AMP
		var freq := 28.0 + right_hand_shake_lerp * 8.0
		right_hand_shake_offset = Vector2(
			sin(t_now * freq + 0.5)        * amp,
			sin(t_now * freq * 1.3 + 2.2)  * amp
		) + _get_pulse_offset(right_hand_pressure, PI)
	else:
		right_hand_shake_offset = Vector2.ZERO

	# Left foot (state-based — feet matter less visually)
	var left_foot_mods := get_foot_modifiers(left_foot_state)
	var target_lf_shake = left_foot_mods.shake
	left_foot_shake_lerp = lerp(left_foot_shake_lerp, target_lf_shake, SHAKE_LERP_SPEED * delta)
	if left_foot_shake_lerp > 0.01:
		var freq := 25.0 + left_foot_shake_lerp * 15.0
		var amp  := left_foot_shake_lerp * 2.5
		left_foot_shake_offset = Vector2(sin(t_now * freq + 1.0) * amp, sin(t_now * freq * 1.2 + 0.8) * amp)
	else:
		left_foot_shake_offset = Vector2.ZERO

	# Right foot
	var right_foot_mods := get_foot_modifiers(right_foot_state)
	var target_rf_shake = right_foot_mods.shake
	right_foot_shake_lerp = lerp(right_foot_shake_lerp, target_rf_shake, SHAKE_LERP_SPEED * delta)
	if right_foot_shake_lerp > 0.01:
		var freq := 25.0 + right_foot_shake_lerp * 15.0
		var amp  := right_foot_shake_lerp * 2.5
		right_foot_shake_offset = Vector2(sin(t_now * freq + 1.5) * amp, sin(t_now * freq * 1.2 + 1.3) * amp)
	else:
		right_foot_shake_offset = Vector2.ZERO
	# ─────────────────────────────────────────────────────────────────────────

func handle_input():
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_pressed(KEY_R):
		reset_climb()
		return

	building_momentum = false
	var shift_held = Input.is_key_pressed(KEY_SHIFT)

	# ── PHASE 2: Rest Mode — Shift with no limb selected ─────────────────────
	# We evaluate this every frame so it turns on/off smoothly.
	# Must be done before the limb-select block so shift_held is still plain shift.
	rest_mode_active = shift_held and selected_limbs.is_empty() and \
		(left_hand_hold != null or right_hand_hold != null)
	# ─────────────────────────────────────────────────────────────────────────

	if Input.is_action_just_pressed("select_left"):
		if shift_held:
			toggle_limb_selection(Limb.LEFT_HAND)
		else:
			selected_limbs.clear()
			selected_limbs.append(Limb.LEFT_HAND)
		if left_hand_hold != null and Limb.LEFT_HAND in selected_limbs:
			release_limb(Limb.LEFT_HAND)
			left_hand_grabbing = false

	elif Input.is_action_just_pressed("select_right"):
		if shift_held:
			toggle_limb_selection(Limb.RIGHT_HAND)
		else:
			selected_limbs.clear()
			selected_limbs.append(Limb.RIGHT_HAND)
		if right_hand_hold != null and Limb.RIGHT_HAND in selected_limbs:
			release_limb(Limb.RIGHT_HAND)
			right_hand_grabbing = false

	if Input.is_action_just_pressed("select_left_foot"):
		if shift_held:
			toggle_limb_selection(Limb.LEFT_FOOT)
		else:
			if Limb.LEFT_HAND not in selected_limbs and Limb.RIGHT_HAND not in selected_limbs:
				selected_limbs.clear()
			selected_limbs.append(Limb.LEFT_FOOT)
		left_foot_user_override = true
		left_foot_auto_disabled = true
		left_foot_auto_animating = false
		if left_foot_hold != null and Limb.LEFT_FOOT in selected_limbs:
			release_limb(Limb.LEFT_FOOT)
			left_foot_grabbing = false

	elif Input.is_action_just_pressed("select_right_foot"):
		if shift_held:
			toggle_limb_selection(Limb.RIGHT_FOOT)
		else:
			if Limb.LEFT_HAND not in selected_limbs and Limb.RIGHT_HAND not in selected_limbs:
				selected_limbs.clear()
			selected_limbs.append(Limb.RIGHT_FOOT)
		right_foot_user_override = true
		right_foot_auto_disabled = true
		right_foot_auto_animating = false
		if right_foot_hold != null and Limb.RIGHT_FOOT in selected_limbs:
			release_limb(Limb.RIGHT_FOOT)
			right_foot_grabbing = false

	if MOUSE_CONTROL_ENABLED and selected_limbs.size() > 0:
		var mouse_global = get_global_mouse_position()
		var centroid = get_selected_limbs_centroid()
		var dist_to_mouse = centroid.distance_to(mouse_global)
		if dist_to_mouse > MOUSE_DEADZONE:
			use_mouse_aim = true
			mouse_aim_position = mouse_global
			building_momentum = true
		else:
			use_mouse_aim = false
	else:
		use_mouse_aim = false

	if Input.is_action_just_released("select_left"):
		if Limb.LEFT_HAND in selected_limbs:
			_fire_dyno_impulse()   # ── dyno: impulse before grab attempt clears selection
			attempt_grab(Limb.LEFT_HAND)
		if not shift_held:
			selected_limbs.clear()
		use_mouse_aim = false

	if Input.is_action_just_released("select_right"):
		if Limb.RIGHT_HAND in selected_limbs:
			_fire_dyno_impulse()
			attempt_grab(Limb.RIGHT_HAND)
		if not shift_held:
			selected_limbs.clear()
		use_mouse_aim = false

	if Input.is_action_just_released("select_left_foot"):
		if Limb.LEFT_FOOT in selected_limbs:
			attempt_grab(Limb.LEFT_FOOT)
			left_foot_manual = true
		if not shift_held and Limb.LEFT_HAND not in selected_limbs and Limb.RIGHT_HAND not in selected_limbs:
			selected_limbs.clear()
		use_mouse_aim = false
		left_foot_user_override = false
		if left_foot_hold == null:
			left_foot_manual = false
			left_foot_auto_disabled = false
			left_foot_settle_timer = FOOT_RESTABILIZE_TIME

	if Input.is_action_just_released("select_right_foot"):
		if Limb.RIGHT_FOOT in selected_limbs:
			attempt_grab(Limb.RIGHT_FOOT)
			right_foot_manual = true
		if not shift_held and Limb.LEFT_HAND not in selected_limbs and Limb.RIGHT_HAND not in selected_limbs:
			selected_limbs.clear()
		use_mouse_aim = false
		right_foot_user_override = false
		if right_foot_hold == null:
			right_foot_manual = false
			right_foot_auto_disabled = false
			right_foot_settle_timer = FOOT_RESTABILIZE_TIME

func toggle_limb_selection(limb: Limb):
	if limb in selected_limbs:
		selected_limbs.erase(limb)
	else:
		selected_limbs.append(limb)

func get_selected_limbs_centroid() -> Vector2:
	if selected_limbs.size() == 0:
		return global_position
	var sum = Vector2.ZERO
	for limb in selected_limbs:
		sum += get_limb_position(limb)
	return sum / selected_limbs.size()

func get_limb_position(limb: Limb) -> Vector2:
	match limb:
		Limb.LEFT_HAND: return left_hand.global_position
		Limb.RIGHT_HAND: return right_hand.global_position
		Limb.LEFT_FOOT: return left_foot.global_position
		Limb.RIGHT_FOOT: return right_foot.global_position
		_: return global_position

func reset_climb():
	global_position = spawn_position
	com_position = spawn_position + Vector2(0, COM_OFFSET_Y)

	body_velocity = Vector2.ZERO
	com_velocity = Vector2.ZERO
	swing_momentum = Vector2.ZERO
	swing_combo_count = 0
	last_swing_direction = Vector2.ZERO
	momentum_buildup_time = 0.0
	left_hand_velocity = Vector2.ZERO
	right_hand_velocity = Vector2.ZERO
	left_foot_velocity = Vector2.ZERO
	right_foot_velocity = Vector2.ZERO
	left_hand_joint_velocity = Vector2.ZERO
	right_hand_joint_velocity = Vector2.ZERO
	left_foot_joint_velocity = Vector2.ZERO
	right_foot_joint_velocity = Vector2.ZERO

	if left_hand_hold:
		left_hand_hold.release(left_hand)
	if right_hand_hold:
		right_hand_hold.release(right_hand)
	if left_foot_hold:
		left_foot_hold.release(left_foot)
	if right_foot_hold:
		right_foot_hold.release(right_foot)

	left_hand_hold = null
	right_hand_hold = null
	left_foot_hold = null
	right_foot_hold = null

	left_hand_joint.position = Vector2(-SHOULDER_OFFSET, 10)
	right_hand_joint.position = Vector2(SHOULDER_OFFSET, 10)
	left_hand.position = Vector2(-SHOULDER_OFFSET, 10 + ARM_LOWER_LENGTH)
	right_hand.position = Vector2(SHOULDER_OFFSET, 10 + ARM_LOWER_LENGTH)
	left_foot_joint.position = Vector2(-HIP_OFFSET, HIP_DOWN + 20)
	right_foot_joint.position = Vector2(HIP_OFFSET, HIP_DOWN + 20)
	left_foot.position = Vector2(-HIP_OFFSET, HIP_DOWN + LEG_UPPER_LENGTH + LEG_LOWER_LENGTH / 2)
	right_foot.position = Vector2(HIP_OFFSET, HIP_DOWN + LEG_UPPER_LENGTH + LEG_LOWER_LENGTH / 2)

	selected_limbs.clear()
	use_mouse_aim = false
	left_foot_manual = false
	right_foot_manual = false
	left_foot_auto_disabled = false
	right_foot_auto_disabled = false
	left_hand_grabbing = false
	right_hand_grabbing = false
	left_foot_grabbing = false
	right_foot_grabbing = false
	_ragdoll_active = false
	_ragdoll_elapsed = 0.0
	climb_started = false
	climb_completed = false

	left_hand_pin = Vector2.ZERO
	right_hand_pin = Vector2.ZERO
	left_foot_pin = Vector2.ZERO
	right_foot_pin = Vector2.ZERO

	left_hand_state = GripState.RELAXED
	right_hand_state = GripState.RELAXED
	left_foot_state = GripState.RELAXED
	right_foot_state = GripState.RELAXED
	left_hand_pressure = 0.0
	right_hand_pressure = 0.0
	left_foot_pressure = 0.0
	right_foot_pressure = 0.0
	left_hand_static_time = 0.0
	right_hand_static_time = 0.0
	left_foot_static_time = 0.0
	right_foot_static_time = 0.0
	left_hand_force = 0.0
	right_hand_force = 0.0
	left_foot_force = 0.0
	right_foot_force = 0.0
	left_hand_shake_lerp = 0.0
	right_hand_shake_lerp = 0.0
	left_foot_shake_lerp = 0.0
	right_foot_shake_lerp = 0.0
	fall_timer = 0.0

	# ── PHASE 1: reset catch boost state ─────────────────────────────────────
	left_hand_catch_boost  = 1.0
	right_hand_catch_boost = 1.0
	left_hand_catch_timer  = 0.0
	right_hand_catch_timer = 0.0
	# ── PHASE 2: reset rest mode ──────────────────────────────────────────────
	rest_mode_active = false
	# ── PHASE 3: reset failure escalation and leg bonus ───────────────────────
	left_hand_fail_stage  = FailureStage.NONE
	right_hand_fail_stage = FailureStage.NONE
	left_hand_struggle_timer  = 0.0
	right_hand_struggle_timer = 0.0
	_leg_bonus_smooth = 1.0
	# ─────────────────────────────────────────────────────────────────────────

	left_foot_auto_animating = false
	right_foot_auto_animating = false
	left_foot_auto_target = Vector2.ZERO
	right_foot_auto_target = Vector2.ZERO
	left_foot_settle_timer = 0.0
	right_foot_settle_timer = 0.0
	left_foot_user_override = false
	right_foot_user_override = false

	if rope_system and is_instance_valid(rope_system):
		if rope_system.has_method("setup_rope"):
			var main = get_tree().current_scene
			if main and main.has_method("get_node"):
				var loader = main.get_node_or_null("LevelLoader")
				if loader and loader.has_method("get_belayer_position"):
					var belayer_pos = loader.get_belayer_position()
					rope_system.setup_rope(belayer_pos, self)

	if speed_timer and is_instance_valid(speed_timer):
		if speed_timer.has_method("stop_timer"):
			speed_timer.stop_timer()

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	call_deferred("initial_grab")

func _query_water(pos: Vector2, vel: Vector2) -> Dictionary:
	var dwall: Node2D = get_tree().get_first_node_in_group("environment_walls")
	if dwall and dwall.has_method("check_water_collision"):
		return dwall.check_water_collision(pos, vel)
	return {"in_water": false, "depth": 0.0, "surface_y": 0.0,
			"drag": Vector2(1.0, 1.0), "buoyancy": 0.0}

func simulate_physics(delta):
	var held_hand_count := 0
	var held_foot_count := 0
	if left_hand_hold: held_hand_count += 1
	if right_hand_hold: held_hand_count += 1
	if left_foot_hold: held_foot_count += 1
	if right_foot_hold: held_foot_count += 1

	var total_held_limbs = held_hand_count + held_foot_count

	if total_held_limbs < last_held_limbs:
		com_velocity += Vector2(randf_range(-20, 20), 30) * 0.05
	last_held_limbs = total_held_limbs

	var _in_water := false
	var _water_drag := Vector2(1.0, 1.0)
	var _buoyancy := 0.0
	var wdata = _query_water(com_position, com_velocity)
	_in_water = wdata["in_water"]
	if _in_water:
		_water_drag = wdata["drag"]
		_buoyancy   = wdata["buoyancy"]
		com_velocity.x *= _water_drag.x
		com_velocity.y *= _water_drag.y
		com_velocity.y -= _buoyancy * delta

	if held_hand_count > 0:
		var no_foot_gravity_mult = 1.0 if held_foot_count > 0 else 2.2
		com_velocity.y += GRAVITY * delta * 0.15 * no_foot_gravity_mult
	else:
		if _in_water:
			com_velocity.y += GRAVITY * delta * 0.4
		else:
			com_velocity.y += GRAVITY * delta * 1.4
			if left_foot_hold:
				left_foot_hold.release(left_foot)
				left_foot_hold = null
			if right_foot_hold:
				right_foot_hold.release(right_foot)
				right_foot_hold = null
			left_foot_manual = false
			right_foot_manual = false
			left_foot_auto_disabled = false
			right_foot_auto_disabled = false
			left_foot_auto_animating = false
			right_foot_auto_animating = false

	if current_discipline == 1 and rope_system:
		if rope_system.has_method("apply_rope_force_to_player"):
			com_velocity = rope_system.apply_rope_force_to_player(com_velocity)

	pin_held_limbs()
	apply_limb_gravity(delta)

	if use_mouse_aim and selected_limbs.size() > 0:
		apply_mouse_control_multi(delta)

	if ENABLE_ADAPTIVE_LEGS:
		apply_adaptive_leg_assistance(delta)

	previous_left_hand_pos = left_hand.global_position
	previous_right_hand_pos = right_hand.global_position
	previous_left_foot_pos = left_foot.global_position
	previous_right_foot_pos = right_foot.global_position

	if held_foot_count > 0 and held_hand_count > 0:
		apply_foot_support(delta)

	if held_foot_count > 0:
		var lateral_force = abs(com_velocity.x)
		if lateral_force > FOOT_CUT_THRESHOLD:
			if left_foot_hold:
				left_foot_hold.release(left_foot)
				left_foot_hold = null
			if right_foot_hold:
				right_foot_hold.release(right_foot)
				right_foot_hold = null
			left_foot_manual = false
			right_foot_manual = false
			left_foot_auto_disabled = false
			right_foot_auto_disabled = false

	apply_limb_tension(delta, held_hand_count, held_foot_count)

	com_position += com_velocity * delta
	var com_to_body_offset = Vector2(0, -COM_OFFSET_Y)
	global_position = com_position + com_to_body_offset

	apply_limb_velocities(delta)

	check_leg_overstretch()
	check_limb_overload(held_hand_count, held_foot_count)

	for i in range(5):
		apply_joint_constraints()

	apply_natural_limb_positions(delta)
	update_grab_animations()
	pin_held_limbs()

	if _in_water:
		com_velocity *= 0.88
	else:
		com_velocity *= BODY_DRAG
	apply_limb_drag()

func check_leg_overstretch():
	var left_hip := global_position + Vector2(-HIP_OFFSET, HIP_DOWN)
	var right_hip := global_position + Vector2(HIP_OFFSET, HIP_DOWN)
	var leg_natural_length := LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
	var max_safe_length := leg_natural_length * LEG_FORCE_RELEASE_THRESHOLD

	if left_foot_hold and not left_foot_grabbing:
		var left_anchor = left_foot_hold.get_limb_anchor(left_foot)
		if left_hip.distance_to(left_anchor) > max_safe_length:
			left_foot_hold.release(left_foot)
			left_foot_hold = null
			left_foot_manual = false
			left_foot_auto_disabled = false

	if right_foot_hold and not right_foot_grabbing:
		var right_anchor = right_foot_hold.get_limb_anchor(right_foot)
		if right_hip.distance_to(right_anchor) > max_safe_length:
			right_foot_hold.release(right_foot)
			right_foot_hold = null
			right_foot_manual = false
			right_foot_auto_disabled = false

func pin_held_limbs():
	if left_hand_hold and not left_hand_grabbing:
		left_hand.global_position = left_hand_pin if left_hand_pin != Vector2.ZERO else left_hand_hold.get_limb_anchor(left_hand)
		left_hand_velocity = Vector2.ZERO
		left_hand_joint_velocity = Vector2.ZERO
	if right_hand_hold and not right_hand_grabbing:
		right_hand.global_position = right_hand_pin if right_hand_pin != Vector2.ZERO else right_hand_hold.get_limb_anchor(right_hand)
		right_hand_velocity = Vector2.ZERO
		right_hand_joint_velocity = Vector2.ZERO
	if left_foot_hold and not left_foot_grabbing:
		left_foot.global_position = left_foot_pin if left_foot_pin != Vector2.ZERO else left_foot_hold.get_limb_anchor(left_foot)
		left_foot_velocity = Vector2.ZERO
		left_foot_joint_velocity = Vector2.ZERO
	if right_foot_hold and not right_foot_grabbing:
		right_foot.global_position = right_foot_pin if right_foot_pin != Vector2.ZERO else right_foot_hold.get_limb_anchor(right_foot)
		right_foot_velocity = Vector2.ZERO
		right_foot_joint_velocity = Vector2.ZERO

func apply_limb_gravity(delta: float):
	if left_hand_hold == null and Limb.LEFT_HAND in selected_limbs and not left_hand_grabbing:
		left_hand_velocity.y += GRAVITY * delta * 0.18
		left_hand_joint_velocity.y += GRAVITY * delta * 0.12
	if right_hand_hold == null and Limb.RIGHT_HAND in selected_limbs and not right_hand_grabbing:
		right_hand_velocity.y += GRAVITY * delta * 0.18
		right_hand_joint_velocity.y += GRAVITY * delta * 0.12
	if left_foot_hold == null and Limb.LEFT_FOOT in selected_limbs and not left_foot_grabbing:
		left_foot_velocity.y += GRAVITY * delta * 0.22
		left_foot_joint_velocity.y += GRAVITY * delta * 0.16
	if right_foot_hold == null and Limb.RIGHT_FOOT in selected_limbs and not right_foot_grabbing:
		right_foot_velocity.y += GRAVITY * delta * 0.22
		right_foot_joint_velocity.y += GRAVITY * delta * 0.16

func apply_limb_velocities(delta: float):
	if left_hand_hold == null and Limb.LEFT_HAND in selected_limbs and not left_hand_grabbing:
		left_hand.global_position += left_hand_velocity * delta
		left_hand_joint.global_position += left_hand_joint_velocity * delta
	if right_hand_hold == null and Limb.RIGHT_HAND in selected_limbs and not right_hand_grabbing:
		right_hand.global_position += right_hand_velocity * delta
		right_hand_joint.global_position += right_hand_joint_velocity * delta
	if left_foot_hold == null and Limb.LEFT_FOOT in selected_limbs and not left_foot_grabbing:
		left_foot.global_position += left_foot_velocity * delta
		left_foot_joint.global_position += left_foot_joint_velocity * delta
	if right_foot_hold == null and Limb.RIGHT_FOOT in selected_limbs and not right_foot_grabbing:
		right_foot.global_position += right_foot_velocity * delta
		right_foot_joint.global_position += right_foot_joint_velocity * delta

func apply_limb_drag():
	if left_hand_hold == null and Limb.LEFT_HAND in selected_limbs:
		left_hand_velocity *= LIMB_DRAG
		left_hand_joint_velocity *= LIMB_DRAG
	if right_hand_hold == null and Limb.RIGHT_HAND in selected_limbs:
		right_hand_velocity *= LIMB_DRAG
		right_hand_joint_velocity *= LIMB_DRAG
	if left_foot_hold == null and Limb.LEFT_FOOT in selected_limbs:
		left_foot_velocity *= LIMB_DRAG
		left_foot_joint_velocity *= LIMB_DRAG
	if right_foot_hold == null and Limb.RIGHT_FOOT in selected_limbs:
		right_foot_velocity *= LIMB_DRAG
		right_foot_joint_velocity *= LIMB_DRAG

func get_foot_move_speed(limb: Limb) -> float:
	var hold = left_foot_hold if limb == Limb.LEFT_FOOT else right_foot_hold
	if hold and hold.is_crimp():
		return BASE_HAND_MOVE_SPEED * CRIMP_LEG_SPEED_FACTOR
	return BASE_HAND_MOVE_SPEED

func apply_mouse_control_multi(delta):
	var target_pos = mouse_aim_position
	for limb in selected_limbs:
		match limb:
			Limb.LEFT_HAND:
				if left_hand_hold == null and not left_hand_grabbing:
					apply_hand_control(left_hand, left_hand_state, Vector2(-SHOULDER_OFFSET, 0), target_pos, true, delta)
			Limb.RIGHT_HAND:
				if right_hand_hold == null and not right_hand_grabbing:
					apply_hand_control(right_hand, right_hand_state, Vector2(SHOULDER_OFFSET, 0), target_pos, false, delta)
			Limb.LEFT_FOOT:
				if left_foot_hold == null and not left_foot_grabbing:
					apply_foot_control(left_foot, Vector2(-HIP_OFFSET, HIP_DOWN), target_pos, true, delta)
			Limb.RIGHT_FOOT:
				if right_foot_hold == null and not right_foot_grabbing:
					apply_foot_control(right_foot, Vector2(HIP_OFFSET, HIP_DOWN), target_pos, false, delta)

func apply_hand_control(hand: Node2D, state: GripState, shoulder_offset: Vector2,
						target: Vector2, is_left: bool, delta: float):
	var mods = get_hand_modifiers(state)
	var move_speed = BASE_HAND_MOVE_SPEED * mods.speed_mult
	hand.global_position = hand.global_position.lerp(target, move_speed)
	if is_left:
		left_hand_velocity = Vector2.ZERO
		left_hand_joint_velocity = Vector2.ZERO
		apply_limb_momentum(left_hand.global_position, previous_left_hand_pos, delta)
	else:
		right_hand_velocity = Vector2.ZERO
		right_hand_joint_velocity = Vector2.ZERO
		apply_limb_momentum(right_hand.global_position, previous_right_hand_pos, delta)

func apply_foot_control(foot: Node2D, hip_offset: Vector2, target: Vector2,
						is_left: bool, delta: float):
	var foot_speed = get_foot_move_speed(Limb.LEFT_FOOT if is_left else Limb.RIGHT_FOOT)
	foot.global_position = foot.global_position.lerp(target, foot_speed)
	if is_left:
		left_foot_velocity = Vector2.ZERO
		left_foot_joint_velocity = Vector2.ZERO
		apply_limb_momentum(left_foot.global_position, previous_left_foot_pos, delta)
	else:
		right_foot_velocity = Vector2.ZERO
		right_foot_joint_velocity = Vector2.ZERO
		apply_limb_momentum(right_foot.global_position, previous_right_foot_pos, delta)

func apply_natural_limb_positions(delta):
	var relax = 0.18
	if left_hand_hold == null and Limb.LEFT_HAND not in selected_limbs and not left_hand_grabbing:
		var shoulder = global_position + Vector2(-SHOULDER_OFFSET, 0)
		var angle_rad = deg_to_rad(ARM_NATURAL_ANGLE_DEG)
		var target_elbow = shoulder + Vector2(-ARM_UPPER_LENGTH * sin(angle_rad), ARM_UPPER_LENGTH * cos(angle_rad))
		var target_hand = target_elbow + Vector2(0, ARM_LOWER_LENGTH)
		left_hand_joint.global_position = left_hand_joint.global_position.lerp(target_elbow, relax)
		left_hand.global_position = left_hand.global_position.lerp(target_hand, relax)
		left_hand_velocity = Vector2.ZERO
		left_hand_joint_velocity = Vector2.ZERO

	if right_hand_hold == null and Limb.RIGHT_HAND not in selected_limbs and not right_hand_grabbing:
		var shoulder = global_position + Vector2(SHOULDER_OFFSET, 0)
		var angle_rad = deg_to_rad(ARM_NATURAL_ANGLE_DEG)
		var target_elbow = shoulder + Vector2(ARM_UPPER_LENGTH * sin(angle_rad), ARM_UPPER_LENGTH * cos(angle_rad))
		var target_hand = target_elbow + Vector2(0, ARM_LOWER_LENGTH)
		right_hand_joint.global_position = right_hand_joint.global_position.lerp(target_elbow, relax)
		right_hand.global_position = right_hand.global_position.lerp(target_hand, relax)
		right_hand_velocity = Vector2.ZERO
		right_hand_joint_velocity = Vector2.ZERO

	var leg_splay = 8.0
	if left_foot_hold == null and Limb.LEFT_FOOT not in selected_limbs and not left_foot_grabbing and not left_foot_auto_animating:
		var hip = global_position + Vector2(-HIP_OFFSET, HIP_DOWN)
		var target_knee = hip + Vector2(-leg_splay, LEG_UPPER_LENGTH)
		var target_foot = target_knee + Vector2(-leg_splay * 0.5, LEG_LOWER_LENGTH)
		left_foot_joint.global_position = left_foot_joint.global_position.lerp(target_knee, relax)
		left_foot.global_position = left_foot.global_position.lerp(target_foot, relax)
		left_foot_velocity = Vector2.ZERO
		left_foot_joint_velocity = Vector2.ZERO

	if right_foot_hold == null and Limb.RIGHT_FOOT not in selected_limbs and not right_foot_grabbing and not right_foot_auto_animating:
		var hip = global_position + Vector2(HIP_OFFSET, HIP_DOWN)
		var target_knee = hip + Vector2(leg_splay, LEG_UPPER_LENGTH)
		var target_foot = target_knee + Vector2(leg_splay * 0.5, LEG_LOWER_LENGTH)
		right_foot_joint.global_position = right_foot_joint.global_position.lerp(target_knee, relax)
		right_foot.global_position = right_foot.global_position.lerp(target_foot, relax)
		right_foot_velocity = Vector2.ZERO
		right_foot_joint_velocity = Vector2.ZERO

func apply_adaptive_leg_assistance(delta):
	if not use_mouse_aim:
		return
	if Limb.LEFT_HAND not in selected_limbs and Limb.RIGHT_HAND not in selected_limbs:
		return

	var target_pos = mouse_aim_position
	var body_pos = global_position
	var reach_direction = (target_pos - body_pos).normalized()
	var reach_distance = body_pos.distance_to(target_pos)
	var max_arm_reach = ARM_UPPER_LENGTH + ARM_LOWER_LENGTH
	var reach_ratio = clamp(reach_distance / max_arm_reach, 0.0, 1.5)

	if reach_ratio < LEG_ASSIST_THRESHOLD:
		return

	var assist_amount = (reach_ratio - LEG_ASSIST_THRESHOLD) / (1.5 - LEG_ASSIST_THRESHOLD)
	assist_amount = clamp(assist_amount, 0.0, 1.0) * LEG_ASSIST_STRENGTH

	if left_foot_hold:
		var left_hip = body_pos + Vector2(-HIP_OFFSET, HIP_DOWN)
		var left_anchor = left_foot_hold.get_limb_anchor(left_foot)
		var current_dist = left_hip.distance_to(left_anchor)
		var max_leg_len = LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
		if current_dist / max_leg_len < LEG_ASSIST_MAX_EXTENSION:
			com_velocity += reach_direction * assist_amount * LEG_ASSIST_SPEED * 100.0

	if right_foot_hold:
		var right_hip = body_pos + Vector2(HIP_OFFSET, HIP_DOWN)
		var right_anchor = right_foot_hold.get_limb_anchor(right_foot)
		var current_dist = right_hip.distance_to(right_anchor)
		var max_leg_len = LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
		if current_dist / max_leg_len < LEG_ASSIST_MAX_EXTENSION:
			com_velocity += reach_direction * assist_amount * LEG_ASSIST_SPEED * 100.0

	if left_foot_hold and right_foot_hold:
		com_velocity += reach_direction * assist_amount * LEG_ASSIST_SPEED * 50.0

func update_grab_animations():
	if left_hand_grabbing:
		left_hand_visual_offset = left_hand.global_position - left_hand_grab_target
		left_hand.global_position = left_hand_grab_target
		left_hand_grabbing = false
	if right_hand_grabbing:
		right_hand_visual_offset = right_hand.global_position - right_hand_grab_target
		right_hand.global_position = right_hand_grab_target
		right_hand_grabbing = false
	if left_foot_grabbing:
		left_foot_visual_offset = left_foot.global_position - left_foot_grab_target
		left_foot.global_position = left_foot_grab_target
		left_foot_grabbing = false
	if right_foot_grabbing:
		right_foot_visual_offset = right_foot.global_position - right_foot_grab_target
		right_foot.global_position = right_foot_grab_target
		right_foot_grabbing = false

	left_hand_visual_offset = left_hand_visual_offset.lerp(Vector2.ZERO, VISUAL_ANIMATION_SPEED)
	right_hand_visual_offset = right_hand_visual_offset.lerp(Vector2.ZERO, VISUAL_ANIMATION_SPEED)
	left_foot_visual_offset = left_foot_visual_offset.lerp(Vector2.ZERO, VISUAL_ANIMATION_SPEED)
	right_foot_visual_offset = right_foot_visual_offset.lerp(Vector2.ZERO, VISUAL_ANIMATION_SPEED)

	if left_hand_visual_offset.length() < 0.5: left_hand_visual_offset = Vector2.ZERO
	if right_hand_visual_offset.length() < 0.5: right_hand_visual_offset = Vector2.ZERO
	if left_foot_visual_offset.length() < 0.5: left_foot_visual_offset = Vector2.ZERO
	if right_foot_visual_offset.length() < 0.5: right_foot_visual_offset = Vector2.ZERO

func apply_limb_momentum(current_pos: Vector2, previous_pos: Vector2, delta: float):
	# Legacy: small continuous nudge while moving a free limb (minimal now — dyno handled separately)
	if delta <= 0:
		return
	var limb_velocity := (current_pos - previous_pos) / delta
	# Tiny nudge — the real momentum is from _fire_dyno_impulse at release
	com_velocity += limb_velocity * 0.04 * delta

# Fired once when a hand is released mid-swing toward a target.
# Adds a single velocity impulse in the aim direction scaled by how fast the
# hand was moving — makes dynos feel like you actually threw yourself.
func _fire_dyno_impulse():
	if not use_mouse_aim:
		return
	var aim_dir := (mouse_aim_position - com_position).normalized()
	# How fast was the hand travelling toward the target this frame?
	var hand_vel := Vector2.ZERO
	for limb in selected_limbs:
		match limb:
			Limb.LEFT_HAND:
				if left_hand_hold == null:
					hand_vel += (left_hand.global_position - previous_left_hand_pos)
			Limb.RIGHT_HAND:
				if right_hand_hold == null:
					hand_vel += (right_hand.global_position - previous_right_hand_pos)
	var speed := hand_vel.length() / get_process_delta_time() if get_process_delta_time() > 0 else 0.0
	# Only fire if there's real movement (not a stationary click)
	if speed < 30.0:
		return
	# Impulse strength: proportional to hand speed, capped, biased toward aim direction
	var dot := hand_vel.normalized().dot(aim_dir) if hand_vel.length() > 1.0 else 0.5
	dot = clamp(dot, 0.0, 1.0)
	var impulse_strength = clamp(speed * 0.18, 60.0, 420.0) * dot
	com_velocity += aim_dir * impulse_strength
	if debug:
		print("DYNO impulse: speed=%.0f dot=%.2f strength=%.0f" % [speed, dot, impulse_strength])

func apply_foot_support(delta):
	var support_force := Vector2.ZERO
	var total_foot_count := 0
	var foot_center := Vector2.ZERO

	if left_foot_hold:
		foot_center += left_foot_hold.get_limb_anchor(left_foot)
		total_foot_count += 1
	if right_foot_hold:
		foot_center += right_foot_hold.get_limb_anchor(right_foot)
		total_foot_count += 1
	if total_foot_count > 0:
		foot_center /= total_foot_count

	var max_arm_reach := ARM_UPPER_LENGTH + ARM_LOWER_LENGTH
	var hand_reach_sum := 0.0
	var hand_count := 0
	if left_hand_hold:
		var lh_anchor = left_hand_hold.get_limb_anchor(left_hand)
		var reach_up = com_position.y - lh_anchor.y
		hand_reach_sum += clamp(reach_up / max_arm_reach, 0.0, 1.0)
		hand_count += 1
	if right_hand_hold:
		var rh_anchor = right_hand_hold.get_limb_anchor(right_hand)
		var reach_up = com_position.y - rh_anchor.y
		hand_reach_sum += clamp(reach_up / max_arm_reach, 0.0, 1.0)
		hand_count += 1

	var raw_reach = hand_reach_sum / max(hand_count, 1)
	var reach_factor := smoothstep(0.05, 0.85, raw_reach)

	if not "foot_push_smooth" in self:
		set_meta("foot_push_smooth", reach_factor)
	var prev_smooth: float = get_meta("foot_push_smooth")
	var ramp_rate = 0.6 if reach_factor > prev_smooth else 0.35
	var smoothed_reach = lerp(prev_smooth, reach_factor, ramp_rate * delta)
	set_meta("foot_push_smooth", smoothed_reach)

	var effective_strength = FOOT_SUPPORT_STRENGTH * smoothed_reach

	if left_foot_hold:
		var anchor = left_foot_hold.get_limb_anchor(left_foot)
		var foot_relative_y = anchor.y - com_position.y
		if foot_relative_y > FOOT_SUPPORT_MIN_Y:
			var push_amount = clamp(foot_relative_y, 0.0, FOOT_SUPPORT_MAX_PUSH)
			support_force.y -= effective_strength * push_amount
	if right_foot_hold:
		var anchor = right_foot_hold.get_limb_anchor(right_foot)
		var foot_relative_y = anchor.y - com_position.y
		if foot_relative_y > FOOT_SUPPORT_MIN_Y:
			var push_amount = clamp(foot_relative_y, 0.0, FOOT_SUPPORT_MAX_PUSH)
			support_force.y -= effective_strength * push_amount

	if total_foot_count > 0:
		support_force.x += FOOT_LATERAL_ASSIST * (foot_center.x - com_position.x)

	if total_foot_count > 0 and com_velocity.y > 0:
		var friction_base = lerp(0.995, 0.96, smoothed_reach)
		com_velocity.y *= friction_base

	var max_upward_push = max(0.0, com_velocity.y * 0.6)
	support_force.y = max(support_force.y, -max_upward_push)

	com_velocity += support_force

func apply_limb_tension(delta, held_hand_count: int, held_foot_count: int):
	var target_pos := Vector2.ZERO
	var total_weight := 0.0

	if left_hand_hold:
		target_pos += left_hand_hold.get_limb_anchor(left_hand) * 2.0
		total_weight += 2.0
	if right_hand_hold:
		target_pos += right_hand_hold.get_limb_anchor(right_hand) * 2.0
		total_weight += 2.0
	if left_foot_hold:
		target_pos += left_foot_hold.get_limb_anchor(left_foot) * 0.5
		total_weight += 0.5
	if right_foot_hold:
		target_pos += right_foot_hold.get_limb_anchor(right_foot) * 0.5
		total_weight += 0.5

	if total_weight > 0:
		target_pos /= total_weight
		target_pos += Vector2(0, 60.0 if held_foot_count == 0 else 30.0)

		# ── PHASE 2: fatigue weakens the body-pull force ──────────────────────
		var fatigue_t    := _get_body_fatigue_t()                   # 0→1
		var force_scalar := _get_grip_force_scalar(fatigue_t * PRESSURE_FAIL)
		# Also add body sag: CoM drifts down as arms tire
		var sag_y := fatigue_t * P2_MAX_SAG_PX
		target_pos += Vector2(0, sag_y)
		com_velocity += (target_pos - com_position) * BODY_PULL_STRENGTH * force_scalar
		# ─────────────────────────────────────────────────────────────────────

func check_limb_overload(held_hand_count: int, held_foot_count: int):
	if left_hand_hold:
		var left_shoulder := global_position + Vector2(-SHOULDER_OFFSET, 0)
		var anchor = left_hand_hold.get_limb_anchor(left_hand)
		if left_shoulder.distance_to(anchor) > (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * HAND_LOAD_TOLERANCE:
			release_limb(Limb.LEFT_HAND)
	if right_hand_hold:
		var right_shoulder := global_position + Vector2(SHOULDER_OFFSET, 0)
		var anchor = right_hand_hold.get_limb_anchor(right_hand)
		if right_shoulder.distance_to(anchor) > (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * HAND_LOAD_TOLERANCE:
			release_limb(Limb.RIGHT_HAND)

	var left_hip := global_position + Vector2(-HIP_OFFSET, HIP_DOWN)
	var right_hip := global_position + Vector2(HIP_OFFSET, HIP_DOWN)
	var leg_total_len := LEG_UPPER_LENGTH + LEG_LOWER_LENGTH

	if left_foot_hold:
		if left_hip.distance_to(left_foot_hold.get_limb_anchor(left_foot)) > leg_total_len * FOOT_RELEASE_THRESHOLD:
			release_limb(Limb.LEFT_FOOT)
	if right_foot_hold:
		if right_hip.distance_to(right_foot_hold.get_limb_anchor(right_foot)) > leg_total_len * FOOT_RELEASE_THRESHOLD:
			release_limb(Limb.RIGHT_FOOT)

func get_highest_hand_y() -> float:
	var y_values = []
	if left_hand_hold:
		y_values.append(left_hand_hold.get_limb_anchor(left_hand).y)
	if right_hand_hold:
		y_values.append(right_hand_hold.get_limb_anchor(right_hand).y)
	if y_values.size() > 0:
		return y_values.min()
	return global_position.y

func apply_joint_constraints():
	var left_shoulder := global_position + Vector2(-SHOULDER_OFFSET, 0)
	var right_shoulder := global_position + Vector2(SHOULDER_OFFSET, 0)
	var left_hip := global_position + Vector2(-HIP_OFFSET, HIP_DOWN)
	var right_hip := global_position + Vector2(HIP_OFFSET, HIP_DOWN)

	var left_hand_pinned = left_hand_hold != null or Limb.LEFT_HAND in selected_limbs or left_hand_grabbing
	var right_hand_pinned = right_hand_hold != null or Limb.RIGHT_HAND in selected_limbs or right_hand_grabbing
	var left_foot_pinned = left_foot_hold != null or Limb.LEFT_FOOT in selected_limbs or left_foot_grabbing
	var right_foot_pinned = right_foot_hold != null or Limb.RIGHT_FOOT in selected_limbs or right_foot_grabbing

	constrain_arm(left_hand_joint, left_hand, left_shoulder, ARM_UPPER_LENGTH, ARM_LOWER_LENGTH, left_hand_pinned, true)
	constrain_arm(right_hand_joint, right_hand, right_shoulder, ARM_UPPER_LENGTH, ARM_LOWER_LENGTH, right_hand_pinned, false)
	constrain_leg_strict(left_foot_joint, left_foot, left_hip, LEG_UPPER_LENGTH, LEG_LOWER_LENGTH, left_foot_pinned, true)
	constrain_leg_strict(right_foot_joint, right_foot, right_hip, LEG_UPPER_LENGTH, LEG_LOWER_LENGTH, right_foot_pinned, false)

func constrain_arm(elbow: Node2D, hand: Node2D, shoulder: Vector2, upper_len: float, lower_len: float, hand_pinned: bool, is_left: bool):
	var to_hand := hand.global_position - shoulder
	var dist := to_hand.length()
	if dist < 0.01:
		return
	var total_len := upper_len + lower_len
	var max_reach := total_len * MAX_JOINT_STRETCH
	if dist > max_reach:
		hand.global_position = shoulder + to_hand.normalized() * max_reach
		to_hand = hand.global_position - shoulder
		dist = max_reach
	if hand_pinned or dist >= total_len * 0.98:
		if dist >= total_len * 0.98:
			elbow.global_position = shoulder + to_hand * (upper_len / total_len)
		else:
			var dir := to_hand.normalized()
			var a := upper_len; var b := lower_len
			var c = clamp(dist, abs(a - b) + 0.1, a + b - 0.1)
			var cos_angle = clamp((a * a + c * c - b * b) / (2.0 * a * c), -1.0, 1.0)
			var angle := acos(cos_angle)
			var forward := dir * (a * cos(angle))
			var perpendicular := Vector2(-dir.y, dir.x)
			var bend_dir := -1.0 if is_left else 1.0
			elbow.global_position = shoulder + forward + perpendicular * (a * sin(angle)) * bend_dir
	else:
		var to_elbow := elbow.global_position - shoulder
		var elbow_dist := to_elbow.length()
		if elbow_dist > 0.01:
			var max_upper := upper_len * MAX_JOINT_STRETCH
			if elbow_dist > max_upper:
				elbow.global_position = shoulder + to_elbow.normalized() * max_upper
			else:
				elbow.global_position -= to_elbow.normalized() * (elbow_dist - upper_len) * JOINT_STIFFNESS
		var elbow_to_hand := hand.global_position - elbow.global_position
		var hand_dist := elbow_to_hand.length()
		if hand_dist > 0.01:
			var max_lower := lower_len * MAX_LIMB_STRETCH
			if hand_dist > max_lower:
				hand.global_position = elbow.global_position + elbow_to_hand.normalized() * max_lower
			else:
				hand.global_position -= elbow_to_hand.normalized() * (hand_dist - lower_len) * LIMB_STIFFNESS

func constrain_leg_strict(knee: Node2D, foot: Node2D, hip: Vector2, upper_len: float, lower_len: float, foot_pinned: bool, is_left: bool):
	var to_foot := foot.global_position - hip
	var dist := to_foot.length()
	if dist < 0.01:
		return
	var total_len := upper_len + lower_len
	var max_reach := total_len * MAX_LEG_TOTAL_STRETCH
	if dist > max_reach:
		foot.global_position = hip + to_foot.normalized() * max_reach
		to_foot = foot.global_position - hip
		dist = max_reach
	if foot_pinned or dist >= total_len * 0.98:
		if dist >= total_len * 0.98:
			knee.global_position = hip + to_foot * (upper_len / total_len)
		else:
			var dir := to_foot.normalized()
			var a := upper_len; var b := lower_len
			var c = clamp(dist, abs(a - b) + 0.1, a + b - 0.1)
			var cos_angle = clamp((a * a + c * c - b * b) / (2.0 * a * c), -1.0, 1.0)
			var angle := acos(cos_angle)
			var forward := dir * (a * cos(angle))
			var perpendicular := Vector2(-dir.y, dir.x)
			knee.global_position = hip + forward + perpendicular * (a * sin(angle)) * 1.0
	else:
		var to_knee := knee.global_position - hip
		var knee_dist := to_knee.length()
		if knee_dist > 0.01:
			var max_upper := upper_len * MAX_JOINT_STRETCH
			if knee_dist > max_upper:
				knee.global_position = hip + to_knee.normalized() * max_upper
			else:
				knee.global_position -= to_knee.normalized() * (knee_dist - upper_len) * JOINT_STIFFNESS
		var knee_to_foot := foot.global_position - knee.global_position
		var foot_dist := knee_to_foot.length()
		if foot_dist > 0.01:
			var max_lower := lower_len * MAX_LIMB_STRETCH
			if foot_dist > max_lower:
				foot.global_position = knee.global_position + knee_to_foot.normalized() * max_lower
			else:
				foot.global_position -= knee_to_foot.normalized() * (foot_dist - lower_len) * LIMB_STIFFNESS

func auto_place_feet(delta):
	if left_foot_settle_timer > 0:
		left_foot_settle_timer -= delta
	if right_foot_settle_timer > 0:
		right_foot_settle_timer -= delta

	_animate_auto_foot(delta, true)
	_animate_auto_foot(delta, false)

	foot_placement_timer -= delta
	if foot_placement_timer > 0:
		return

	var held_hands := 0
	if left_hand_hold: held_hands += 1
	if right_hand_hold: held_hands += 1

	if held_hands == 0:
		if left_foot_hold and not left_foot_manual:
			left_foot_hold.release(left_foot)
			left_foot_hold = null
			left_foot_auto_disabled = false
			left_foot_auto_animating = false
		if right_foot_hold and not right_foot_manual:
			right_foot_hold.release(right_foot)
			right_foot_hold = null
			right_foot_auto_disabled = false
			right_foot_auto_animating = false
		return

	if (left_foot_hold == null
			and not left_foot_manual
			and not left_foot_auto_disabled
			and not left_foot_user_override
			and not left_foot_auto_animating
			and left_foot_settle_timer <= 0):
		var best_hold := find_best_foot_hold(left_foot.global_position, true)
		if best_hold and best_hold.can_grab(left_foot, true):
			var hold_point: Node = best_hold.get_node_or_null("HoldPoint")
			if hold_point:
				left_foot_auto_target = hold_point.global_position
				left_foot_auto_animating = true
				foot_placement_timer = FOOT_PLACEMENT_TIMER
				return

	if (right_foot_hold == null
			and not right_foot_manual
			and not right_foot_auto_disabled
			and not right_foot_user_override
			and not right_foot_auto_animating
			and right_foot_settle_timer <= 0):
		var best_hold := find_best_foot_hold(right_foot.global_position, false)
		if best_hold and best_hold.can_grab(right_foot, true):
			var hold_point: Node = best_hold.get_node_or_null("HoldPoint")
			if hold_point:
				right_foot_auto_target = hold_point.global_position
				right_foot_auto_animating = true
				foot_placement_timer = FOOT_PLACEMENT_TIMER
				return

func _animate_auto_foot(delta: float, is_left: bool):
	var animating  := left_foot_auto_animating  if is_left else right_foot_auto_animating
	if not animating:
		return

	var foot_node  := left_foot  if is_left else right_foot
	var foot_hold  := left_foot_hold  if is_left else right_foot_hold
	var target     := left_foot_auto_target if is_left else right_foot_auto_target
	var user_ovrd  := left_foot_user_override if is_left else right_foot_user_override
	var manual     := left_foot_manual if is_left else right_foot_manual

	if user_ovrd or manual or foot_hold != null:
		if is_left: left_foot_auto_animating = false
		else:       right_foot_auto_animating = false
		return

	foot_node.global_position = foot_node.global_position.lerp(target, FOOT_SNAP_SPEED)

	if foot_node.global_position.distance_to(target) < 8.0:
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 20.0
		query.shape = circle
		query.transform = Transform2D(0, target)
		query.collision_mask = 2
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var results := space_state.intersect_shape(query, 8)

		var claimed := false
		for result in results:
			var hold: Area2D = result.collider
			if not hold.can_grab(foot_node, true):
				continue
			if hold.try_claim(foot_node, true, target):
				if is_left:
					left_foot_hold = hold
					left_foot.global_position = hold.get_limb_anchor(left_foot)
					left_foot_pin = left_foot.global_position
					left_foot_velocity = Vector2.ZERO
					left_foot_joint_velocity = Vector2.ZERO
					left_foot_auto_animating = false
				else:
					right_foot_hold = hold
					right_foot.global_position = hold.get_limb_anchor(right_foot)
					right_foot_pin = right_foot.global_position
					right_foot_velocity = Vector2.ZERO
					right_foot_joint_velocity = Vector2.ZERO
					right_foot_auto_animating = false
				claimed = true
				break

		if not claimed:
			if is_left:
				left_foot_auto_animating = false
				left_foot_settle_timer = FOOT_RESTABILIZE_TIME
			else:
				right_foot_auto_animating = false
				right_foot_settle_timer = FOOT_RESTABILIZE_TIME

func find_best_foot_hold(foot_position: Vector2, is_left: bool) -> Area2D:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FOOT_SEARCH_RADIUS
	query.shape = circle
	query.transform = Transform2D(0, foot_position)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var results := space_state.intersect_shape(query, 32)
	if results.size() == 0:
		return null

	var best_hold: Area2D = null
	var best_score := -INF

	var hip_pos := global_position + Vector2(-HIP_OFFSET if is_left else HIP_OFFSET, HIP_DOWN)
	var max_reach := (LEG_UPPER_LENGTH + LEG_LOWER_LENGTH) * 0.95

	for result in results:
		var hold: Area2D = result.collider

		if (is_left  and hold == right_foot_hold) or \
		   (not is_left and hold == left_foot_hold):
			continue

		if hold == left_hand_hold or hold == right_hand_hold:
			continue

		var hold_point := hold.get_node_or_null("HoldPoint")
		if hold_point == null:
			continue

		var hold_pos: Vector2 = hold_point.global_position
		var hip_dist := hip_pos.distance_to(hold_pos)
		if hip_dist > max_reach:
			continue

		var relative_y := hold_pos.y - global_position.y
		if relative_y < -20.0:
			continue

		var dist_to_foot := foot_position.distance_to(hold_pos)
		var dist_score := 1.0 - (dist_to_foot / FOOT_SEARCH_RADIUS)

		var below_score: float
		if relative_y >= 0.0 and relative_y <= 80.0:
			below_score = 3.0
		elif relative_y > 80.0:
			below_score = 3.0 - ((relative_y - 80.0) / 60.0)
		else:
			below_score = 0.5

		var relative_x := hold_pos.x - global_position.x
		var side_score := 1.0 if ((is_left and relative_x <= 0) or (not is_left and relative_x >= 0)) else 0.4

		var reach_ratio := hip_dist / (LEG_UPPER_LENGTH + LEG_LOWER_LENGTH)
		var comfort_score: float
		if reach_ratio >= 0.3 and reach_ratio <= 0.75:
			comfort_score = 2.0
		elif reach_ratio < 0.3:
			comfort_score = reach_ratio / 0.3
		else:
			comfort_score = 2.0 - ((reach_ratio - 0.75) / 0.2)

		var type_bonus := 1.5 if hold.is_foothold() else 0.5
		var total_score := (dist_score * 1.0) + below_score + (side_score * 0.6) + comfort_score + type_bonus

		if total_score > best_score:
			best_score = total_score
			best_hold = hold

	return best_hold

func initial_grab():
	print("=== INITIAL GRAB SEQUENCE START ===")
	await get_tree().process_frame
	await get_tree().process_frame

	var start_holds := find_start_holds()
	print("Found " + str(start_holds.size()) + " start holds")

	if left_hand_hold: left_hand_hold.release(left_hand); left_hand_hold = null
	if right_hand_hold: right_hand_hold.release(right_hand); right_hand_hold = null
	if left_foot_hold: left_foot_hold.release(left_foot); left_foot_hold = null
	if right_foot_hold: right_foot_hold.release(right_foot); right_foot_hold = null

	body_velocity = Vector2.ZERO; com_velocity = Vector2.ZERO
	left_hand_velocity = Vector2.ZERO; right_hand_velocity = Vector2.ZERO
	left_foot_velocity = Vector2.ZERO; right_foot_velocity = Vector2.ZERO
	left_hand_joint_velocity = Vector2.ZERO; right_hand_joint_velocity = Vector2.ZERO
	left_foot_joint_velocity = Vector2.ZERO; right_foot_joint_velocity = Vector2.ZERO
	left_hand_grabbing = false; right_hand_grabbing = false
	left_foot_grabbing = false; right_foot_grabbing = false

	if start_holds.size() == 1:
		var hold = start_holds[0]
		var hold_point: Marker2D = hold.get_node_or_null("HoldPoint")
		if not hold_point:
			print("ERROR: Start hold missing HoldPoint!")
			return
		var hold_pos = hold_point.global_position
		print("Single start hold at: " + str(hold_pos))
		if hold.can_grab(left_hand, false):
			if hold.try_claim(left_hand, false, hold_pos):
				left_hand_hold = hold; left_hand.global_position = hold_pos; left_hand_anchor = hold_pos; left_hand_pin = hold_pos
				print("  ✓ Left hand claimed hold")
			else: print("  ✗ Left hand failed to claim hold")
		else: print("  ✗ Left hand cannot grab hold")
		if hold.can_grab(right_hand, false):
			if hold.try_claim(right_hand, false, hold_pos):
				right_hand_hold = hold; right_hand.global_position = hold_pos; right_hand_anchor = hold_pos; right_hand_pin = hold_pos
				print("  ✓ Right hand claimed hold")
			else: print("  ✗ Right hand failed to claim hold")
		else: print("  ✗ Right hand cannot grab hold")
		global_position.x = hold_pos.x
		global_position.y = hold_pos.y + 80

	elif start_holds.size() >= 2:
		var hold_0_point: Marker2D = start_holds[0].get_node_or_null("HoldPoint")
		var hold_1_point: Marker2D = start_holds[1].get_node_or_null("HoldPoint")
		if not hold_0_point or not hold_1_point:
			print("ERROR: Start holds missing HoldPoint!")
			return
		var a_x = hold_0_point.global_position.x
		var b_x = hold_1_point.global_position.x
		var left_start = start_holds[0] if a_x <= b_x else start_holds[1]
		var right_start = start_holds[1] if a_x <= b_x else start_holds[0]
		var lp: Marker2D = left_start.get_node("HoldPoint")
		var left_pos = lp.global_position
		print("Left start hold at: " + str(left_pos))
		if left_start.can_grab(left_hand, false):
			if left_start.try_claim(left_hand, false, left_pos):
				left_hand_hold = left_start; left_hand.global_position = left_pos; left_hand_anchor = left_pos; left_hand_pin = left_pos
				print("  ✓ Left hand claimed hold")
			else: print("  ✗ Left hand failed to claim hold")
		else: print("  ✗ Left hand cannot grab hold")
		var rp: Marker2D = right_start.get_node("HoldPoint")
		var right_pos = rp.global_position
		print("Right start hold at: " + str(right_pos))
		if right_start.can_grab(right_hand, false):
			if right_start.try_claim(right_hand, false, right_pos):
				right_hand_hold = right_start; right_hand.global_position = right_pos; right_hand_anchor = right_pos; right_hand_pin = right_pos
				print("  ✓ Right hand claimed hold")
			else: print("  ✗ Right hand failed to claim hold")
		else: print("  ✗ Right hand cannot grab hold")
		global_position.x = (left_pos.x + right_pos.x) / 2.0
		global_position.y = left_pos.y + 80

	else:
		print("No start holds found - using fallback")
		var left_hold := find_nearest_hold(left_hand.global_position)
		var right_hold := find_nearest_hold(right_hand.global_position)
		if left_hold and left_hold.can_grab(left_hand, false):
			var snap_point: Marker2D = left_hold.get_node_or_null("HoldPoint")
			if snap_point:
				var pos = snap_point.global_position
				if left_hold.try_claim(left_hand, false, pos):
					left_hand_hold = left_hold; left_hand.global_position = pos; left_hand_anchor = pos; left_hand_pin = pos
		if right_hold and right_hold != left_hold and right_hold.can_grab(right_hand, false):
			var snap_point: Marker2D = right_hold.get_node_or_null("HoldPoint")
			if snap_point:
				var pos = snap_point.global_position
				if right_hold.try_claim(right_hand, false, pos):
					right_hand_hold = right_hold; right_hand.global_position = pos; right_hand_anchor = pos; right_hand_pin = pos

	com_position = global_position + Vector2(0, COM_OFFSET_Y)

	var left_foot_start := find_nearest_hold(left_foot.global_position)
	var right_foot_start := find_nearest_hold(right_foot.global_position)

	if (left_foot_start and left_foot_start != left_hand_hold and left_foot_start != right_hand_hold
			and left_foot_start.can_grab(left_foot, true)):
		var snap_pos = left_foot.global_position
		if left_foot_start.try_claim(left_foot, true, snap_pos):
			left_foot_hold = left_foot_start
			left_foot.global_position = left_foot_start.get_limb_anchor(left_foot)
			left_foot_anchor = left_foot.global_position
			left_foot_pin = left_foot.global_position

	if (right_foot_start and right_foot_start != left_hand_hold and right_foot_start != right_hand_hold
			and right_foot_start != left_foot_hold and right_foot_start.can_grab(right_foot, true)):
		var snap_pos = right_foot.global_position
		if right_foot_start.try_claim(right_foot, true, snap_pos):
			right_foot_hold = right_foot_start
			right_foot.global_position = right_foot_start.get_limb_anchor(right_foot)
			right_foot_anchor = right_foot.global_position
			right_foot_pin = right_foot.global_position

	for i in range(15):
		apply_joint_constraints()
	pin_held_limbs()

	body_velocity = Vector2.ZERO; com_velocity = Vector2.ZERO
	left_hand_velocity = Vector2.ZERO; right_hand_velocity = Vector2.ZERO
	left_foot_velocity = Vector2.ZERO; right_foot_velocity = Vector2.ZERO
	left_hand_joint_velocity = Vector2.ZERO; right_hand_joint_velocity = Vector2.ZERO
	left_foot_joint_velocity = Vector2.ZERO; right_foot_joint_velocity = Vector2.ZERO

	print("=== NOTIFYING ALL HOLDS: CLIMB START ===")
	var notify_count = 0
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("notify_climb_start"):
			hold.notify_climb_start()
			notify_count += 1
	print("Notified " + str(notify_count) + " holds that climb has started")
	print("========================================")
	print("=== SPAWN STATE ===")
	print("Body position: " + str(global_position))
	print("Left hand hold: " + ("YES" if left_hand_hold else "NO"))
	print("Right hand hold: " + ("YES" if right_hand_hold else "NO"))
	print("Left foot hold: " + ("YES" if left_foot_hold else "NO"))
	print("Right foot hold: " + ("YES" if right_foot_hold else "NO"))
	print("===================")

func find_start_holds() -> Array[Area2D]:
	var start_holds: Array[Area2D] = []
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold is Area2D and hold.has_method("is_start_hold") and hold.is_start_hold():
			start_holds.append(hold)
	return start_holds

func find_nearest_hold(from_position: Vector2) -> Area2D:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 200.0
	query.shape = circle
	query.transform = Transform2D(0, from_position)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var results := space_state.intersect_shape(query, 32)
	if results.size() == 0:
		return null
	var nearest_hold: Area2D = null
	var nearest_dist := INF
	for result in results:
		var hold: Area2D = result.collider
		var hold_point := hold.get_node_or_null("HoldPoint")
		if hold_point == null: continue
		var dist := from_position.distance_to(hold_point.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_hold = hold
	return nearest_hold

func attempt_grab(limb: Limb):
	var limb_area: Area2D
	var limb_node: Node2D
	var is_foot := false
	match limb:
		Limb.LEFT_HAND:  limb_area = left_hand_area;  limb_node = left_hand;  is_foot = false
		Limb.RIGHT_HAND: limb_area = right_hand_area; limb_node = right_hand; is_foot = false
		Limb.LEFT_FOOT:  limb_area = left_foot_area;  limb_node = left_foot;  is_foot = true
		Limb.RIGHT_FOOT: limb_area = right_foot_area; limb_node = right_foot; is_foot = true
		_: return

	var overlaps := limb_area.get_overlapping_areas()
	if overlaps.size() == 0:
		return

	var closest_hold: Area2D = null
	var closest_dist := INF
	var closest_hold_point: Vector2 = Vector2.ZERO

	for hold in overlaps:
		var hold_point := hold.get_node_or_null("HoldPoint")
		if hold_point == null: continue
		if not hold.can_grab(limb_node, is_foot): continue
		# Distance used only for ranking — NOT as a pass/fail gate.
		# The limb area overlapping the hold is sufficient proof it's reachable.
		var d := limb_node.global_position.distance_to(hold_point.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_hold = hold
			closest_hold_point = hold_point.global_position

	if closest_hold == null:
		return

	var grab_pos: Vector2 = calculate_grab_position(limb, closest_hold, closest_hold_point, limb_node.global_position)
	if not closest_hold.try_claim(limb_node, is_foot, grab_pos):
		return

	match limb:
		Limb.LEFT_HAND:
			left_hand_hold = closest_hold; left_hand_grab_target = grab_pos; left_hand_pin = grab_pos
			left_hand_grabbing = true; left_hand_velocity = Vector2.ZERO; left_hand_joint_velocity = Vector2.ZERO
			# ── PHASE 1: catch penalty on successful hand grab ────────────────
			_apply_catch_penalty(Limb.LEFT_HAND)
			# ─────────────────────────────────────────────────────────────────
		Limb.RIGHT_HAND:
			right_hand_hold = closest_hold; right_hand_grab_target = grab_pos; right_hand_pin = grab_pos
			right_hand_grabbing = true; right_hand_velocity = Vector2.ZERO; right_hand_joint_velocity = Vector2.ZERO
			# ── PHASE 1: catch penalty on successful hand grab ────────────────
			_apply_catch_penalty(Limb.RIGHT_HAND)
			# ─────────────────────────────────────────────────────────────────
		Limb.LEFT_FOOT:
			left_foot_hold = closest_hold; left_foot_grab_target = grab_pos; left_foot_pin = grab_pos
			left_foot_grabbing = true; left_foot_velocity = Vector2.ZERO; left_foot_joint_velocity = Vector2.ZERO
		Limb.RIGHT_FOOT:
			right_foot_hold = closest_hold; right_foot_grab_target = grab_pos; right_foot_pin = grab_pos
			right_foot_grabbing = true; right_foot_velocity = Vector2.ZERO; right_foot_joint_velocity = Vector2.ZERO

	if not climb_started:
		climb_started = true
		print("🎬 FIRST GRAB - Climb started!")
		var game_scene = get_tree().get_current_scene()
		if game_scene and game_scene.has_method("on_climb_start"):
			print("  Notifying game scene...")
			game_scene.on_climb_start()

func calculate_grab_position(limb: Limb, hold: Area2D, hold_point: Vector2, limb_pos: Vector2) -> Vector2:
	# Top-out snaps to hold_point just like any other hold.
	# (Previously returned limb_pos which caused the hand to pin wherever it happened to be.)
	var is_hand := (limb == Limb.LEFT_HAND or limb == Limb.RIGHT_HAND)
	var left_hand_here  := (left_hand_hold  == hold and not left_hand_grabbing)
	var right_hand_here := (right_hand_hold == hold and not right_hand_grabbing)
	var left_foot_here  := (left_foot_hold  == hold and not left_foot_grabbing)
	var right_foot_here := (right_foot_hold == hold and not right_foot_grabbing)

	if not is_hand:
		if limb == Limb.LEFT_FOOT and right_foot_here:
			return hold_point + Vector2(-10.0, 0)
		elif limb == Limb.RIGHT_FOOT and left_foot_here:
			return hold_point + Vector2(10.0, 0)
		if left_hand_here or right_hand_here:
			var foot_x := -10.0 if limb == Limb.LEFT_FOOT else 10.0
			return hold_point + Vector2(foot_x, 10.0)

	if is_hand:
		if limb == Limb.LEFT_HAND and right_hand_here:
			return hold_point + Vector2(-10.0, 0)
		elif limb == Limb.RIGHT_HAND and left_hand_here:
			return hold_point + Vector2(10.0, 0)
		if left_foot_here or right_foot_here:
			var hand_x := -10.0 if limb == Limb.LEFT_HAND else 10.0
			return hold_point + Vector2(hand_x, -10.0)

	return hold_point

func release_limb(limb: Limb):
	match limb:
		Limb.LEFT_HAND:
			if left_hand_hold: left_hand_hold.release(left_hand); left_hand_hold = null
			left_hand_pin = Vector2.ZERO
		Limb.RIGHT_HAND:
			if right_hand_hold: right_hand_hold.release(right_hand); right_hand_hold = null
			right_hand_pin = Vector2.ZERO
		Limb.LEFT_FOOT:
			if left_foot_hold: left_foot_hold.release(left_foot); left_foot_hold = null
			left_foot_pin = Vector2.ZERO
			left_foot_manual = false; left_foot_auto_disabled = false
		Limb.RIGHT_FOOT:
			if right_foot_hold: right_foot_hold.release(right_foot); right_foot_hold = null
			right_foot_pin = Vector2.ZERO
			right_foot_manual = false; right_foot_auto_disabled = false

func check_fall_detection(delta: float):
	var held_limbs = count_held_limbs()
	var wdata = _query_water(com_position, com_velocity)
	var in_water = wdata["in_water"]

	if held_limbs == 0 and com_velocity.y > FALL_VELOCITY_THRESHOLD and not in_water:
		fall_timer += delta
		if fall_timer >= FALL_DETECTION_TIME:
			print("Fell off - resetting climb")
			if current_discipline == 2 and speed_timer:
				if speed_timer.has_method("pause_timer"):
					speed_timer.pause_timer()
			reset_climb()
	else:
		fall_timer = 0.0

func check_climb_completion():
	if climb_completed:
		return
	var left_on_top = left_hand_hold and left_hand_hold.has_method("is_top_out") and left_hand_hold.is_top_out()
	var right_on_top = right_hand_hold and right_hand_hold.has_method("is_top_out") and right_hand_hold.is_top_out()
	if left_on_top and right_on_top:
		climb_completed = true
		var is_granite := false
		if Engine.has_singleton("EnvironmentConfig"):
			var env_config = EnvironmentConfig
			is_granite = env_config.get_current_environment() == EnvironmentConfig.EnvironmentType.GRANITE
		match current_discipline:
			0:
				if is_granite: print("Climb completed via granite top-out!")
				else: print("Climb completed via top hold!")
			1: print("Roped climb completed!")
			2:
				if speed_timer and speed_timer.has_method("pause_timer"):
					speed_timer.pause_timer()
				var time = speed_timer.get_time_remaining() if speed_timer else 0
				print("Speed climb completed with ", time, " seconds remaining!")
		var game_scene = get_tree().get_current_scene()
		if game_scene and game_scene.has_method("on_level_complete"):
			game_scene.on_level_complete()

func update_camera():
	if cam:
		cam.global_position = cam.global_position.lerp(global_position, CAM_LERP)

func _draw():
	if aesthetic:
		draw_stick_figure()
	if debug:
		draw_debug_info()

func draw_stick_figure():
	var black := Color.BLACK
	var line_width := 4.0

	# ── PHASE 2: per-limb fatigue colour (forearm darkens subtly) ────────────
	var lh_color := _get_limb_color(left_hand_pressure)
	var rh_color := _get_limb_color(right_hand_pressure)
	# ─────────────────────────────────────────────────────────────────────────

	var lh_hand_draw := left_hand.position + left_hand_shake_offset + left_hand_visual_offset
	var rh_hand_draw := right_hand.position + right_hand_shake_offset + right_hand_visual_offset

	draw_circle(Vector2(0, HEAD_OFFSET), 16, black)
	draw_line(Vector2(0, HEAD_OFFSET + 12), Vector2(0, HIP_DOWN + 5), black, line_width)

	# Upper arms — always black
	draw_line(Vector2(-SHOULDER_OFFSET, 0), left_hand_joint.position, black, line_width)
	draw_line(Vector2( SHOULDER_OFFSET, 0), right_hand_joint.position, black, line_width)
	# Forearms — coloured by fatigue
	draw_line(left_hand_joint.position, lh_hand_draw, lh_color, line_width - 1)
	draw_line(right_hand_joint.position, rh_hand_draw, rh_color, line_width - 1)

	draw_line(Vector2(-HIP_OFFSET, HIP_DOWN), left_foot_joint.position, black, line_width)
	draw_line(left_foot_joint.position, left_foot.position + left_foot_shake_offset + left_foot_visual_offset, black, line_width - 1)
	draw_line(Vector2(HIP_OFFSET, HIP_DOWN), right_foot_joint.position, black, line_width)
	draw_line(right_foot_joint.position, right_foot.position + right_foot_shake_offset + right_foot_visual_offset, black, line_width - 1)

	# Hand dots coloured by fatigue
	draw_circle(lh_hand_draw, 5, lh_color)
	draw_circle(rh_hand_draw, 5, rh_color)
	draw_circle(left_foot.position + left_foot_shake_offset + left_foot_visual_offset, 5, black)
	draw_circle(right_foot.position + right_foot_shake_offset + right_foot_visual_offset, 5, black)

	if use_mouse_aim and selected_limbs.size() > 0:
		var mouse_local = to_local(mouse_aim_position)
		draw_circle(mouse_local, 6, Color(1, 1, 0, 0.5))
		draw_arc(mouse_local, 10, 0, TAU, 12, Color(1, 1, 0, 0.7), 1.5)

	# ── PHASE 2: Rest Mode indicator ─────────────────────────────────────────
	if rest_mode_active:
		var alpha := 0.5 + sin(Time.get_ticks_msec() * 0.004) * 0.25
		draw_circle(Vector2(0, 0), 8, Color(0.4, 0.8, 1.0, alpha))
	# ─────────────────────────────────────────────────────────────────────────

func draw_debug_info():
	var com_local = to_local(com_position)
	var vel_normalized = com_velocity.normalized() if com_velocity.length() > 10 else Vector2.ZERO
	if vel_normalized.length() > 0.1:
		var arrow_length = min(com_velocity.length() * 0.1, 15.0)
		var arrow_end = com_local + vel_normalized * arrow_length
		draw_line(com_local, arrow_end, Color(1, 0.3, 0, 0.9), 2.0)
		var perp = Vector2(-vel_normalized.y, vel_normalized.x) * 3.0
		draw_line(arrow_end, arrow_end - vel_normalized * 5.0 + perp, Color(1, 0.3, 0, 0.9), 2.0)
		draw_line(arrow_end, arrow_end - vel_normalized * 5.0 - perp, Color(1, 0.3, 0, 0.9), 2.0)
	draw_circle(com_local, 4, Color(1, 0.5, 0, 0.8))
	draw_arc(com_local, 6, 0, TAU, 12, Color(1, 0.5, 0, 1.0), 1.5)
	if swing_momentum.length() > 10:
		var swing_normalized = swing_momentum.normalized()
		var swing_length = min(swing_momentum.length() * 0.08, 20.0)
		var swing_end = com_local + swing_normalized * swing_length
		draw_line(com_local, swing_end, Color(0, 1, 1, 0.9), 2.5)
		var perp = Vector2(-swing_normalized.y, swing_normalized.x) * 4.0
		draw_line(swing_end, swing_end - swing_normalized * 6.0 + perp, Color(0, 1, 1, 0.9), 2.5)
		draw_line(swing_end, swing_end - swing_normalized * 6.0 - perp, Color(0, 1, 1, 0.9), 2.5)

func set_climbing_discipline(discipline: int):
	current_discipline = discipline
	match discipline:
		0: print("Character: Set to BOULDERING mode")
		1: print("Character: Set to ROPED CLIMBING mode")
		2: print("Character: Set to SPEED CLIMBING mode"); speed_climb_active = true

func set_rope_system(rope: Node2D):
	rope_system = rope
	print("Character: Rope system attached")

func set_speed_timer(timer: Node):
	speed_timer = timer
	print("Character: Speed timer attached")

func get_climbing_discipline() -> int:
	return current_discipline
