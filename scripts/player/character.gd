extends CharacterBody2D

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

const CAM_LERP := 0.08

@export var debug: bool = false
@export var aesthetic: bool = true

enum GripState { RELAXED, ENGAGED, PUMPED, FAIL }

var left_hand_state: GripState = GripState.RELAXED
var right_hand_state: GripState = GripState.RELAXED
var left_foot_state: GripState = GripState.RELAXED
var right_foot_state: GripState = GripState.RELAXED

var left_hand_pressure: float = 0.0
var right_hand_pressure: float = 0.0
var left_foot_pressure: float = 0.0
var right_foot_pressure: float = 0.0

const PRESSURE_ENGAGED := 20.0
const PRESSURE_PUMPED := 50.0
const PRESSURE_FAIL := 100.0

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

var spawn_position: Vector2
var climb_started := false
var climb_completed := false

const ARM_UPPER_LENGTH := 50.0
const ARM_LOWER_LENGTH := 50.0
const LEG_UPPER_LENGTH := 45.0
const LEG_LOWER_LENGTH := 45.0
const SHOULDER_OFFSET := 10.0
const HIP_OFFSET := 10.0
const HIP_DOWN := 20.0
const HEAD_OFFSET := -20.0

const BODY_PULL_STRENGTH := 0.35
const JOINT_STIFFNESS := 0.98
const LIMB_STIFFNESS := 0.98
const FOOT_SUPPORT_STRENGTH := 0.15
const FOOT_SUPPORT_MIN_Y := -20.0
const FOOT_SUPPORT_MAX_PUSH := 50.0
const FOOT_LATERAL_ASSIST := 0.08
const GRAVITY := 2200.0
const BODY_DRAG := 0.92
const LIMB_DRAG := 0.88
const MAX_JOINT_STRETCH := 1.15
const MAX_LIMB_STRETCH := 1.15
const PREVENT_UPSIDE_DOWN := false

const COM_OFFSET_Y := 15.0
const FOOT_CUT_THRESHOLD := 150.0
const HAND_LOAD_TOLERANCE := 1.5
const MOMENTUM_TRANSFER_STRENGTH := 0.3
const DYNO_VELOCITY_BOOST := 1.3

const ARM_NATURAL_ANGLE := 25.0
const ARM_NATURAL_BEND := 0.7
const LEG_NATURAL_SPLAY := 15.0
const FREE_LIMB_RELAXATION_SPEED := 0.15

const ENABLE_ADAPTIVE_LEGS := true
const LEG_ASSIST_THRESHOLD := 0.8
const LEG_ASSIST_STRENGTH := 0.6
const LEG_ASSIST_SPEED := 0.3
const LEG_ASSIST_MAX_EXTENSION := 0.92

@export var AUTO_FOOT_PLACEMENT := true
const FOOT_SEARCH_RADIUS := 80.0
const FOOT_PLACEMENT_TIMER := 0.5
const FOOT_PREFERENCE_BELOW := 40.0
const FOOT_RELEASE_THRESHOLD := 1.5

const CRIMP_LEG_SPEED_FACTOR := 0.45

const ONE_ARM_PRESSURE_MULTIPLIER := 4.0
const TWO_ARM_PRESSURE_MULTIPLIER := 3.0
const THREE_LIMB_PRESSURE_MULTIPLIER := 2.0
const FOUR_LIMB_PRESSURE_MULTIPLIER := 1.5

const FOOT_PRESSURE_REDUCTION := 0.4

const EASY_HOLD_BASE_PRESSURE := 1.5

const POOR_POSITION_PRESSURE_MULT := 2.5
const LOCK_OFF_PRESSURE_MULT := 2.2
const LOCK_OFF_THRESHOLD := 0.7

const SHAKE_OUT_RECOVERY_RATE := 6.0

const FALL_DETECTION_TIME := 2.0
const FALL_VELOCITY_THRESHOLD := 400.0

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
const LIMB_GRAB_SPEED := 1.0

const BASE_HAND_MOVE_SPEED := 0.92
const BASE_REACH_DISTANCE := 200.0

func get_hand_modifiers(state: GripState) -> Dictionary:
	match state:
		GripState.RELAXED:
			return {"reach_mult": 1.0, "speed_mult": 1.0, "latency": 0.0, "shake": 0.0}
		GripState.ENGAGED:
			return {"reach_mult": 0.9, "speed_mult": 0.95, "latency": 0.05, "shake": 0.1}
		GripState.PUMPED:
			return {"reach_mult": 0.75, "speed_mult": 0.7, "latency": 0.15, "shake": 0.35}
		GripState.FAIL:
			return {"reach_mult": 0.0, "speed_mult": 0.0, "latency": 1.0, "shake": 1.0}
	
	return get_hand_modifiers(GripState.RELAXED)

func get_foot_modifiers(state: GripState) -> Dictionary:
	match state:
		GripState.RELAXED:
			return {"shake": 0.0}
		GripState.ENGAGED:
			return {"shake": 0.08}
		GripState.PUMPED:
			return {"shake": 0.25}
		GripState.FAIL:
			return {"shake": 0.8}
	
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

var left_hand_shake_lerp: float = 0.0
var right_hand_shake_lerp: float = 0.0
var left_foot_shake_lerp: float = 0.0
var right_foot_shake_lerp: float = 0.0

const SHAKE_LERP_SPEED := 3.0

var fall_timer: float = 0.0

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
	initial_grab()

func _process(delta):
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

func update_grip_states(delta: float):
	update_hand_grip_state(Limb.LEFT_HAND, delta)
	update_hand_grip_state(Limb.RIGHT_HAND, delta)
	update_foot_grip_state(Limb.LEFT_FOOT, delta)
	update_foot_grip_state(Limb.RIGHT_FOOT, delta)

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
		
		if hold_pressure < EASY_HOLD_BASE_PRESSURE:
			hold_pressure = EASY_HOLD_BASE_PRESSURE * delta
		
		if body_offset > 0.5:
			hold_pressure *= POOR_POSITION_PRESSURE_MULT
		
		pressure += hold_pressure
		
		var body_balance = calculate_body_balance()
		var recovery = hold.get_recovery_rate(delta, body_balance, foot_support)
		if recovery > 0.0:
			pressure -= recovery
	else:
		force = 0.0
		if hand not in selected_limbs:
			pressure -= SHAKE_OUT_RECOVERY_RATE * delta
	
	pressure = clamp(pressure, 0.0, PRESSURE_FAIL)
	
	if pressure >= PRESSURE_FAIL:
		state = GripState.FAIL
		release_limb(hand)
	elif pressure >= PRESSURE_PUMPED:
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
		1:
			return ONE_ARM_PRESSURE_MULTIPLIER
		2:
			return TWO_ARM_PRESSURE_MULTIPLIER
		3:
			return THREE_LIMB_PRESSURE_MULTIPLIER
		4:
			return FOUR_LIMB_PRESSURE_MULTIPLIER
		_:
			return 1.0

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
	var left_hand_mods = get_hand_modifiers(left_hand_state)
	var target_left_hand_shake = left_hand_mods.shake
	left_hand_shake_lerp = lerp(left_hand_shake_lerp, target_left_hand_shake, SHAKE_LERP_SPEED * delta)
	
	if left_hand_shake_lerp > 0.01:
		var shake_freq = 30.0 + (left_hand_shake_lerp * 20.0)
		var shake_amp = left_hand_shake_lerp * 3.0
		var t = Time.get_ticks_msec() * 0.001
		left_hand_shake_offset = Vector2(
			sin(t * shake_freq) * shake_amp,
			sin(t * shake_freq * 1.3 + 1.7) * shake_amp
		)
	else:
		left_hand_shake_offset = Vector2.ZERO
	
	var right_hand_mods = get_hand_modifiers(right_hand_state)
	var target_right_hand_shake = right_hand_mods.shake
	right_hand_shake_lerp = lerp(right_hand_shake_lerp, target_right_hand_shake, SHAKE_LERP_SPEED * delta)
	
	if right_hand_shake_lerp > 0.01:
		var shake_freq = 30.0 + (right_hand_shake_lerp * 20.0)
		var shake_amp = right_hand_shake_lerp * 3.0
		var t = Time.get_ticks_msec() * 0.001
		right_hand_shake_offset = Vector2(
			sin(t * shake_freq + 0.5) * shake_amp,
			sin(t * shake_freq * 1.3 + 2.2) * shake_amp
		)
	else:
		right_hand_shake_offset = Vector2.ZERO
	
	var left_foot_mods = get_foot_modifiers(left_foot_state)
	var target_left_foot_shake = left_foot_mods.shake
	left_foot_shake_lerp = lerp(left_foot_shake_lerp, target_left_foot_shake, SHAKE_LERP_SPEED * delta)
	
	if left_foot_shake_lerp > 0.01:
		var shake_freq = 25.0 + (left_foot_shake_lerp * 15.0)
		var shake_amp = left_foot_shake_lerp * 2.5
		var t = Time.get_ticks_msec() * 0.001
		left_foot_shake_offset = Vector2(
			sin(t * shake_freq + 1.0) * shake_amp,
			sin(t * shake_freq * 1.2 + 0.8) * shake_amp
		)
	else:
		left_foot_shake_offset = Vector2.ZERO
	
	var right_foot_mods = get_foot_modifiers(right_foot_state)
	var target_right_foot_shake = right_foot_mods.shake
	right_foot_shake_lerp = lerp(right_foot_shake_lerp, target_right_foot_shake, SHAKE_LERP_SPEED * delta)
	
	if right_foot_shake_lerp > 0.01:
		var shake_freq = 25.0 + (right_foot_shake_lerp * 15.0)
		var shake_amp = right_foot_shake_lerp * 2.5
		var t = Time.get_ticks_msec() * 0.001
		right_foot_shake_offset = Vector2(
			sin(t * shake_freq + 1.5) * shake_amp,
			sin(t * shake_freq * 1.2 + 1.3) * shake_amp
		)
	else:
		right_foot_shake_offset = Vector2.ZERO

func handle_input():
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_pressed(KEY_R):
		reset_climb()
		return
	
	building_momentum = false
	
	var shift_held = Input.is_key_pressed(KEY_SHIFT)
	
	if Input.is_action_just_pressed("select_left"):
		if shift_held:
			toggle_limb_selection(Limb.LEFT_HAND)
		else:
			selected_limbs.clear()
			selected_limbs.append(Limb.LEFT_HAND)
		
		if left_hand_hold != null and Limb.LEFT_HAND in selected_limbs:
			release_limb(Limb.LEFT_HAND)
	
	elif Input.is_action_just_pressed("select_right"):
		if shift_held:
			toggle_limb_selection(Limb.RIGHT_HAND)
		else:
			selected_limbs.clear()
			selected_limbs.append(Limb.RIGHT_HAND)
		
		if right_hand_hold != null and Limb.RIGHT_HAND in selected_limbs:
			release_limb(Limb.RIGHT_HAND)
	
	if Input.is_action_just_pressed("select_left_foot"):
		if shift_held:
			toggle_limb_selection(Limb.LEFT_FOOT)
		else:
			if Limb.LEFT_HAND not in selected_limbs and Limb.RIGHT_HAND not in selected_limbs:
				selected_limbs.clear()
			selected_limbs.append(Limb.LEFT_FOOT)
		
		left_foot_auto_disabled = true
		if left_foot_hold != null and Limb.LEFT_FOOT in selected_limbs:
			release_limb(Limb.LEFT_FOOT)
	
	elif Input.is_action_just_pressed("select_right_foot"):
		if shift_held:
			toggle_limb_selection(Limb.RIGHT_FOOT)
		else:
			if Limb.LEFT_HAND not in selected_limbs and Limb.RIGHT_HAND not in selected_limbs:
				selected_limbs.clear()
			selected_limbs.append(Limb.RIGHT_FOOT)
		
		right_foot_auto_disabled = true
		if right_foot_hold != null and Limb.RIGHT_FOOT in selected_limbs:
			release_limb(Limb.RIGHT_FOOT)
	
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
			attempt_grab(Limb.LEFT_HAND)
		if not shift_held:
			selected_limbs.clear()
		use_mouse_aim = false
	
	if Input.is_action_just_released("select_right"):
		if Limb.RIGHT_HAND in selected_limbs:
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
		if left_foot_hold == null:
			left_foot_auto_disabled = false
	
	if Input.is_action_just_released("select_right_foot"):
		if Limb.RIGHT_FOOT in selected_limbs:
			attempt_grab(Limb.RIGHT_FOOT)
			right_foot_manual = true
		if not shift_held and Limb.LEFT_HAND not in selected_limbs and Limb.RIGHT_HAND not in selected_limbs:
			selected_limbs.clear()
		use_mouse_aim = false
		if right_foot_hold == null:
			right_foot_auto_disabled = false

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
	climb_started = false
	climb_completed = false
	
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
	
	await get_tree().process_frame
	initial_grab()

func simulate_physics(delta):
	var held_hand_count := 0
	var held_foot_count := 0
	if left_hand_hold: held_hand_count += 1
	if right_hand_hold: held_hand_count += 1
	if left_foot_hold: held_foot_count += 1
	if right_foot_hold: held_foot_count += 1
	
	var total_held_limbs = held_hand_count + held_foot_count
	
	if total_held_limbs < last_held_limbs:
		com_velocity += Vector2(randf_range(-20, 20), 30) * 0.08
	last_held_limbs = total_held_limbs
	
	if held_hand_count > 0:
		com_velocity.y += GRAVITY * delta * 0.15
	else:
		com_velocity.y += GRAVITY * delta * 2.0
		
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
	
	pin_held_limbs()
	apply_limb_gravity(delta)
	
	if use_mouse_aim and selected_limbs.size() > 0:
		apply_mouse_control_multi(delta)
	
	apply_natural_limb_positions(delta)
	
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
	
	check_limb_overload(held_hand_count, held_foot_count)
	
	for i in range(5):
		apply_joint_constraints()
	
	update_grab_animations()
	pin_held_limbs()
	
	com_velocity *= BODY_DRAG
	apply_limb_drag()

func pin_held_limbs():
	if left_hand_hold and not left_hand_grabbing:
		left_hand.global_position = left_hand_hold.get_limb_anchor(left_hand)
		left_hand_velocity = Vector2.ZERO
		left_hand_joint_velocity = Vector2.ZERO
	
	if right_hand_hold and not right_hand_grabbing:
		right_hand.global_position = right_hand_hold.get_limb_anchor(right_hand)
		right_hand_velocity = Vector2.ZERO
		right_hand_joint_velocity = Vector2.ZERO
	
	if left_foot_hold and not left_foot_grabbing:
		left_foot.global_position = left_foot_hold.get_limb_anchor(left_foot)
		left_foot_velocity = Vector2.ZERO
		left_foot_joint_velocity = Vector2.ZERO
	
	if right_foot_hold and not right_foot_grabbing:
		right_foot.global_position = right_foot_hold.get_limb_anchor(right_foot)
		right_foot_velocity = Vector2.ZERO
		right_foot_joint_velocity = Vector2.ZERO

func apply_limb_gravity(delta: float):
	if left_hand_hold == null and Limb.LEFT_HAND not in selected_limbs and not left_hand_grabbing:
		left_hand_velocity.y += GRAVITY * delta * 0.4
		left_hand_joint_velocity.y += GRAVITY * delta * 0.3
	
	if right_hand_hold == null and Limb.RIGHT_HAND not in selected_limbs and not right_hand_grabbing:
		right_hand_velocity.y += GRAVITY * delta * 0.4
		right_hand_joint_velocity.y += GRAVITY * delta * 0.3
	
	if left_foot_hold == null and Limb.LEFT_FOOT not in selected_limbs and not left_foot_grabbing:
		left_foot_velocity.y += GRAVITY * delta * 0.5
		left_foot_joint_velocity.y += GRAVITY * delta * 0.4
	
	if right_foot_hold == null and Limb.RIGHT_FOOT not in selected_limbs and not right_foot_grabbing:
		right_foot_velocity.y += GRAVITY * delta * 0.5
		right_foot_joint_velocity.y += GRAVITY * delta * 0.4

func apply_limb_velocities(delta: float):
	if left_hand_hold == null and Limb.LEFT_HAND not in selected_limbs and not left_hand_grabbing:
		left_hand.global_position += left_hand_velocity * delta
		left_hand_joint.global_position += left_hand_joint_velocity * delta
	
	if right_hand_hold == null and Limb.RIGHT_HAND not in selected_limbs and not right_hand_grabbing:
		right_hand.global_position += right_hand_velocity * delta
		right_hand_joint.global_position += right_hand_joint_velocity * delta
	
	if left_foot_hold == null and Limb.LEFT_FOOT not in selected_limbs and not left_foot_grabbing:
		left_foot.global_position += left_foot_velocity * delta
		left_foot_joint.global_position += left_foot_joint_velocity * delta
	
	if right_foot_hold == null and Limb.RIGHT_FOOT not in selected_limbs and not right_foot_grabbing:
		right_foot.global_position += right_foot_velocity * delta
		right_foot_joint.global_position += right_foot_joint_velocity * delta

func apply_limb_drag():
	if left_hand_hold == null and Limb.LEFT_HAND not in selected_limbs:
		left_hand_velocity *= LIMB_DRAG
		left_hand_joint_velocity *= LIMB_DRAG
	
	if right_hand_hold == null and Limb.RIGHT_HAND not in selected_limbs:
		right_hand_velocity *= LIMB_DRAG
		right_hand_joint_velocity *= LIMB_DRAG
	
	if left_foot_hold == null and Limb.LEFT_FOOT not in selected_limbs:
		left_foot_velocity *= LIMB_DRAG
		left_foot_joint_velocity *= LIMB_DRAG
	
	if right_foot_hold == null and Limb.RIGHT_FOOT not in selected_limbs:
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
					apply_hand_control(left_hand, left_hand_state, Vector2(-SHOULDER_OFFSET, 0), 
									   target_pos, true, delta)
			
			Limb.RIGHT_HAND:
				if right_hand_hold == null and not right_hand_grabbing:
					apply_hand_control(right_hand, right_hand_state, Vector2(SHOULDER_OFFSET, 0), 
									   target_pos, false, delta)
			
			Limb.LEFT_FOOT:
				if left_foot_hold == null and not left_foot_grabbing:
					apply_foot_control(left_foot, Vector2(-HIP_OFFSET, HIP_DOWN), 
									   target_pos, true, delta)
			
			Limb.RIGHT_FOOT:
				if right_foot_hold == null and not right_foot_grabbing:
					apply_foot_control(right_foot, Vector2(HIP_OFFSET, HIP_DOWN), 
									   target_pos, false, delta)

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
	pass

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
		var current_extension = current_dist / max_leg_len
		
		if current_extension < LEG_ASSIST_MAX_EXTENSION:
			var leg_push = reach_direction * assist_amount * LEG_ASSIST_SPEED * 100.0
			com_velocity += leg_push
	
	if right_foot_hold:
		var right_hip = body_pos + Vector2(HIP_OFFSET, HIP_DOWN)
		var right_anchor = right_foot_hold.get_limb_anchor(right_foot)
		var current_dist = right_hip.distance_to(right_anchor)
		var max_leg_len = LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
		var current_extension = current_dist / max_leg_len
		
		if current_extension < LEG_ASSIST_MAX_EXTENSION:
			var leg_push = reach_direction * assist_amount * LEG_ASSIST_SPEED * 100.0
			com_velocity += leg_push
	
	if left_foot_hold and right_foot_hold:
		var lean_push = reach_direction * assist_amount * LEG_ASSIST_SPEED * 50.0
		com_velocity += lean_push

func update_grab_animations():
	if left_hand_grabbing:
		left_hand.global_position = left_hand.global_position.lerp(left_hand_grab_target, LIMB_GRAB_SPEED)
		if left_hand.global_position.distance_to(left_hand_grab_target) < 1.0:
			left_hand.global_position = left_hand_grab_target
			left_hand_grabbing = false
	
	if right_hand_grabbing:
		right_hand.global_position = right_hand.global_position.lerp(right_hand_grab_target, LIMB_GRAB_SPEED)
		if right_hand.global_position.distance_to(right_hand_grab_target) < 1.0:
			right_hand.global_position = right_hand_grab_target
			right_hand_grabbing = false
	
	if left_foot_grabbing:
		left_foot.global_position = left_foot.global_position.lerp(left_foot_grab_target, LIMB_GRAB_SPEED)
		if left_foot.global_position.distance_to(left_foot_grab_target) < 1.0:
			left_foot.global_position = left_foot_grab_target
			left_foot_grabbing = false
	
	if right_foot_grabbing:
		right_foot.global_position = right_foot.global_position.lerp(right_foot_grab_target, LIMB_GRAB_SPEED)
		if right_foot.global_position.distance_to(right_foot_grab_target) < 1.0:
			right_foot.global_position = right_foot_grab_target
			right_foot_grabbing = false

func apply_limb_momentum(current_pos: Vector2, previous_pos: Vector2, delta: float):
	if delta <= 0:
		return
	
	var limb_velocity = (current_pos - previous_pos) / delta
	com_velocity += limb_velocity * MOMENTUM_TRANSFER_STRENGTH * delta * DYNO_VELOCITY_BOOST

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
	
	if left_foot_hold:
		var anchor = left_foot_hold.get_limb_anchor(left_foot)
		var foot_relative_y = anchor.y - com_position.y
		if foot_relative_y > FOOT_SUPPORT_MIN_Y:
			var push_distance = min(foot_relative_y, FOOT_SUPPORT_MAX_PUSH)
			support_force.y -= FOOT_SUPPORT_STRENGTH * push_distance
	
	if right_foot_hold:
		var anchor = right_foot_hold.get_limb_anchor(right_foot)
		var foot_relative_y = anchor.y - com_position.y
		if foot_relative_y > FOOT_SUPPORT_MIN_Y:
			var push_distance = min(foot_relative_y, FOOT_SUPPORT_MAX_PUSH)
			support_force.y -= FOOT_SUPPORT_STRENGTH * push_distance
	
	if total_foot_count > 0:
		var foot_offset_x = foot_center.x - com_position.x
		support_force.x += FOOT_LATERAL_ASSIST * foot_offset_x
	
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
		var vertical_offset = 60.0 if held_foot_count == 0 else 30.0
		target_pos += Vector2(0, vertical_offset)
		var pull := (target_pos - com_position) * BODY_PULL_STRENGTH
		com_velocity += pull

func check_limb_overload(held_hand_count: int, held_foot_count: int):
	if left_hand_hold:
		var left_shoulder := global_position + Vector2(-SHOULDER_OFFSET, 0)
		var anchor = left_hand_hold.get_limb_anchor(left_hand)
		var stretch = left_shoulder.distance_to(anchor)
		var max_len = (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * HAND_LOAD_TOLERANCE
		if stretch > max_len:
			release_limb(Limb.LEFT_HAND)
	
	if right_hand_hold:
		var right_shoulder := global_position + Vector2(SHOULDER_OFFSET, 0)
		var anchor = right_hand_hold.get_limb_anchor(right_hand)
		var stretch = right_shoulder.distance_to(anchor)
		var max_len = (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * HAND_LOAD_TOLERANCE
		if stretch > max_len:
			release_limb(Limb.RIGHT_HAND)
	
	var left_hip := global_position + Vector2(-HIP_OFFSET, HIP_DOWN)
	var right_hip := global_position + Vector2(HIP_OFFSET, HIP_DOWN)
	var leg_total_len := LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
	
	if left_foot_hold:
		var anchor = left_foot_hold.get_limb_anchor(left_foot)
		if left_hip.distance_to(anchor) > leg_total_len * FOOT_RELEASE_THRESHOLD:
			release_limb(Limb.LEFT_FOOT)
	
	if right_foot_hold:
		var anchor = right_foot_hold.get_limb_anchor(right_foot)
		if right_hip.distance_to(anchor) > leg_total_len * FOOT_RELEASE_THRESHOLD:
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
	constrain_leg(left_foot_joint, left_foot, left_hip, LEG_UPPER_LENGTH, LEG_LOWER_LENGTH, left_foot_pinned, true)
	constrain_leg(right_foot_joint, right_foot, right_hip, LEG_UPPER_LENGTH, LEG_LOWER_LENGTH, right_foot_pinned, false)

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
			var a := upper_len
			var b := lower_len
			var c = clamp(dist, abs(a - b) + 0.1, a + b - 0.1)
			var cos_angle = clamp((a * a + c * c - b * b) / (2.0 * a * c), -1.0, 1.0)
			var angle := acos(cos_angle)
			var forward := dir * (a * cos(angle))
			var perpendicular := Vector2(-dir.y, dir.x)
			var bend_dir := -1.0 if is_left else 1.0
			var sideways := perpendicular * (a * sin(angle)) * bend_dir
			elbow.global_position = shoulder + forward + sideways
	else:
		var to_elbow := elbow.global_position - shoulder
		var elbow_dist := to_elbow.length()
		if elbow_dist > 0.01:
			var max_upper := upper_len * MAX_JOINT_STRETCH
			if elbow_dist > max_upper:
				elbow.global_position = shoulder + to_elbow.normalized() * max_upper
			else:
				var error := elbow_dist - upper_len
				elbow.global_position -= to_elbow.normalized() * error * JOINT_STIFFNESS
		
		var elbow_to_hand := hand.global_position - elbow.global_position
		var hand_dist := elbow_to_hand.length()
		if hand_dist > 0.01:
			var max_lower := lower_len * MAX_LIMB_STRETCH
			if hand_dist > max_lower:
				hand.global_position = elbow.global_position + elbow_to_hand.normalized() * max_lower
			else:
				var error := hand_dist - lower_len
				hand.global_position -= elbow_to_hand.normalized() * error * LIMB_STIFFNESS

func constrain_leg(knee: Node2D, foot: Node2D, hip: Vector2, upper_len: float, lower_len: float, foot_pinned: bool, is_left: bool):
	var to_foot := foot.global_position - hip
	var dist := to_foot.length()
	if dist < 0.01:
		return
	
	var total_len := upper_len + lower_len
	var max_reach := total_len * MAX_JOINT_STRETCH
	
	if dist > max_reach:
		foot.global_position = hip + to_foot.normalized() * max_reach
		to_foot = foot.global_position - hip
		dist = max_reach
	
	if foot_pinned or dist >= total_len * 0.98:
		if dist >= total_len * 0.98:
			knee.global_position = hip + to_foot * (upper_len / total_len)
		else:
			var dir := to_foot.normalized()
			var a := upper_len
			var b := lower_len
			var c = clamp(dist, abs(a - b) + 0.1, a + b - 0.1)
			var cos_angle = clamp((a * a + c * c - b * b) / (2.0 * a * c), -1.0, 1.0)
			var angle := acos(cos_angle)
			var forward := dir * (a * cos(angle))
			var perpendicular := Vector2(-dir.y, dir.x)
			var bend_dir := 1.0
			var sideways := perpendicular * (a * sin(angle)) * bend_dir
			knee.global_position = hip + forward + sideways
	else:
		var to_knee := knee.global_position - hip
		var knee_dist := to_knee.length()
		if knee_dist > 0.01:
			var max_upper := upper_len * MAX_JOINT_STRETCH
			if knee_dist > max_upper:
				knee.global_position = hip + to_knee.normalized() * max_upper
			else:
				var error := knee_dist - upper_len
				knee.global_position -= to_knee.normalized() * error * JOINT_STIFFNESS
		
		var knee_to_foot := foot.global_position - knee.global_position
		var foot_dist := knee_to_foot.length()
		if foot_dist > 0.01:
			var max_lower := lower_len * MAX_LIMB_STRETCH
			if foot_dist > max_lower:
				foot.global_position = knee.global_position + knee_to_foot.normalized() * max_lower
			else:
				var error := foot_dist - lower_len
				foot.global_position -= knee_to_foot.normalized() * error * LIMB_STIFFNESS

func auto_place_feet(delta):
	foot_placement_timer -= delta
	if foot_placement_timer > 0:
		return
	
	var held_hands := 0
	if left_hand_hold:
		held_hands += 1
	if right_hand_hold:
		held_hands += 1
	
	if held_hands == 0:
		if left_foot_hold and not left_foot_manual:
			left_foot_hold.release(left_foot)
			left_foot_hold = null
			left_foot_auto_disabled = false
		if right_foot_hold and not right_foot_manual:
			right_foot_hold.release(right_foot)
			right_foot_hold = null
			right_foot_auto_disabled = false
		return
	
	if left_foot_hold == null and not left_foot_manual and not left_foot_auto_disabled:
		var best_hold := find_best_foot_hold(left_foot.global_position, true)
		if best_hold and best_hold.can_grab(left_foot, true):
			var snap_pos = left_foot.global_position
			if best_hold.try_claim(left_foot, true, snap_pos):
				left_foot_hold = best_hold
				left_foot.global_position = best_hold.get_limb_anchor(left_foot)
				left_foot_velocity = Vector2.ZERO
				left_foot_joint_velocity = Vector2.ZERO
				foot_placement_timer = FOOT_PLACEMENT_TIMER
				return
	
	if right_foot_hold == null and not right_foot_manual and not right_foot_auto_disabled:
		var best_hold := find_best_foot_hold(right_foot.global_position, false)
		if best_hold and best_hold.can_grab(right_foot, true):
			var snap_pos = right_foot.global_position
			if best_hold.try_claim(right_foot, true, snap_pos):
				right_foot_hold = best_hold
				right_foot.global_position = best_hold.get_limb_anchor(right_foot)
				right_foot_velocity = Vector2.ZERO
				right_foot_joint_velocity = Vector2.ZERO
				foot_placement_timer = FOOT_PLACEMENT_TIMER
				return

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
	
	for result in results:
		var hold: Area2D = result.collider
		
		if (is_left and hold == right_foot_hold) or (not is_left and hold == left_foot_hold):
			continue
		
		if hold == left_hand_hold or hold == right_hand_hold:
			continue
		
		var hold_point := hold.get_node_or_null("HoldPoint")
		if hold_point == null:
			continue
		
		var hold_pos = hold_point.global_position
		
		var relative_y = hold_pos.y - global_position.y
		if relative_y < 0:
			continue
		
		var dist := foot_position.distance_to(hold_pos)
		var dist_score := 1.0 - (dist / FOOT_SEARCH_RADIUS)
		var below_score = clamp(relative_y / FOOT_PREFERENCE_BELOW, 0.0, 2.0)
		
		var relative_x = hold_pos.x - global_position.x
		var side_score := 0.5
		if is_left and relative_x < 0:
			side_score = 1.0
		elif not is_left and relative_x > 0:
			side_score = 1.0
		
		var max_reach := LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
		var hip_pos := global_position + Vector2(-HIP_OFFSET if is_left else HIP_OFFSET, HIP_DOWN)
		var reach_dist := hip_pos.distance_to(hold_pos)
		if reach_dist > max_reach * 1.2:
			continue
		
		var type_bonus = 0.5
		if hold.is_foothold():
			type_bonus = 1.5
		
		var total_score = dist_score * 1.0 + below_score * 3.0 + side_score * 0.8 + type_bonus
		
		if total_score > best_score:
			best_score = total_score
			best_hold = hold
	
	return best_hold

func initial_grab():
	var start_holds := find_start_holds()
	
	if start_holds.size() == 1:
		var hold = start_holds[0]
		var snap_point: Marker2D = hold.get_node("HoldPoint")
		var hold_pos = snap_point.global_position
		
		hold.try_claim(left_hand, false, hold_pos)
		left_hand_hold = hold
		left_hand.global_position = hold_pos
		
		hold.try_claim(right_hand, false, hold_pos)
		right_hand_hold = hold
		right_hand.global_position = hold_pos
		
		global_position.x = hold_pos.x
		global_position.y = hold_pos.y + 80
		
	elif start_holds.size() >= 2:
		var a_x = start_holds[0].get_node("HoldPoint").global_position.x
		var b_x = start_holds[1].get_node("HoldPoint").global_position.x
		var left_start = start_holds[0] if a_x <= b_x else start_holds[1]
		var right_start = start_holds[1] if a_x <= b_x else start_holds[0]
		
		var lp: Marker2D = left_start.get_node("HoldPoint")
		left_start.try_claim(left_hand, false, lp.global_position)
		left_hand_hold = left_start
		left_hand.global_position = lp.global_position
		
		var rp: Marker2D = right_start.get_node("HoldPoint")
		right_start.try_claim(right_hand, false, rp.global_position)
		right_hand_hold = right_start
		right_hand.global_position = rp.global_position
		
		global_position.x = (lp.global_position.x + rp.global_position.x) / 2.0
		global_position.y = lp.global_position.y + 80
		
	else:
		var left_hold := find_nearest_hold(left_hand.global_position)
		var right_hold := find_nearest_hold(right_hand.global_position)
		
		if left_hold and left_hold.can_grab(left_hand, false):
			var snap_point: Marker2D = left_hold.get_node("HoldPoint")
			left_hold.try_claim(left_hand, false, snap_point.global_position)
			left_hand_hold = left_hold
			left_hand.global_position = snap_point.global_position
		
		if right_hold and right_hold != left_hold and right_hold.can_grab(right_hand, false):
			var snap_point: Marker2D = right_hold.get_node("HoldPoint")
			right_hold.try_claim(right_hand, false, snap_point.global_position)
			right_hand_hold = right_hold
			right_hand.global_position = snap_point.global_position
	
	com_position = global_position + Vector2(0, COM_OFFSET_Y)
	
	var left_foot_start := find_nearest_hold(left_foot.global_position)
	var right_foot_start := find_nearest_hold(right_foot.global_position)
	
	if (left_foot_start 
			and left_foot_start != left_hand_hold 
			and left_foot_start != right_hand_hold
			and left_foot_start.can_grab(left_foot, true)):
		var snap_pos = left_foot.global_position
		if left_foot_start.try_claim(left_foot, true, snap_pos):
			left_foot_hold = left_foot_start
			left_foot.global_position = left_foot_start.get_limb_anchor(left_foot)
	
	if (right_foot_start 
			and right_foot_start != left_hand_hold 
			and right_foot_start != right_hand_hold 
			and right_foot_start != left_foot_hold
			and right_foot_start.can_grab(right_foot, true)):
		var snap_pos = right_foot.global_position
		if right_foot_start.try_claim(right_foot, true, snap_pos):
			right_foot_hold = right_foot_start
			right_foot.global_position = right_foot_start.get_limb_anchor(right_foot)

func find_start_holds() -> Array[Area2D]:
	var start_holds: Array[Area2D] = []
	var all_holds = get_tree().get_nodes_in_group("holds")
	
	for hold in all_holds:
		if hold is Area2D and hold.has_method("is_start_hold"):
			if hold.is_start_hold():
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
		if hold_point == null:
			continue
		
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
		Limb.LEFT_HAND:
			limb_area = left_hand_area
			limb_node = left_hand
			is_foot = false
		Limb.RIGHT_HAND:
			limb_area = right_hand_area
			limb_node = right_hand
			is_foot = false
		Limb.LEFT_FOOT:
			limb_area = left_foot_area
			limb_node = left_foot
			is_foot = true
		Limb.RIGHT_FOOT:
			limb_area = right_foot_area
			limb_node = right_foot
			is_foot = true
		_:
			return
	
	var overlaps := limb_area.get_overlapping_areas()
	if overlaps.size() == 0:
		return
	
	var closest_hold: Area2D = null
	var closest_dist := INF
	var closest_hold_point: Vector2 = Vector2.ZERO
	
	for hold in overlaps:
		var hold_point := hold.get_node_or_null("HoldPoint")
		if hold_point == null:
			continue
		
		if not hold.can_grab(limb_node, is_foot):
			continue
		
		var d := limb_node.global_position.distance_to(hold_point.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_hold = hold
			closest_hold_point = hold_point.global_position
	
	if closest_hold == null:
		return
	
	var limb_pos = limb_node.global_position
	var to_hold = closest_hold_point - limb_pos
	var dist_to_hold = to_hold.length()
	
	var grab_pos: Vector2
	if dist_to_hold < 15.0:
		grab_pos = closest_hold_point
	else:
		grab_pos = limb_pos + to_hold * 0.7
	
	if not closest_hold.try_claim(limb_node, is_foot, grab_pos):
		return
	
	match limb:
		Limb.LEFT_HAND:
			left_hand_hold = closest_hold
			left_hand_grab_target = grab_pos
			left_hand_grabbing = true
			left_hand_velocity = Vector2.ZERO
			left_hand_joint_velocity = Vector2.ZERO
		
		Limb.RIGHT_HAND:
			right_hand_hold = closest_hold
			right_hand_grab_target = grab_pos
			right_hand_grabbing = true
			right_hand_velocity = Vector2.ZERO
			right_hand_joint_velocity = Vector2.ZERO
		
		Limb.LEFT_FOOT:
			left_foot_hold = closest_hold
			left_foot_grab_target = grab_pos
			left_foot_grabbing = true
			left_foot_velocity = Vector2.ZERO
			left_foot_joint_velocity = Vector2.ZERO
		
		Limb.RIGHT_FOOT:
			right_foot_hold = closest_hold
			right_foot_grab_target = grab_pos
			right_foot_grabbing = true
			right_foot_velocity = Vector2.ZERO
			right_foot_joint_velocity = Vector2.ZERO
	
	if not climb_started:
		climb_started = true

func release_limb(limb: Limb):
	match limb:
		Limb.LEFT_HAND:
			if left_hand_hold:
				left_hand_hold.release(left_hand)
				left_hand_hold = null
		
		Limb.RIGHT_HAND:
			if right_hand_hold:
				right_hand_hold.release(right_hand)
				right_hand_hold = null
		
		Limb.LEFT_FOOT:
			if left_foot_hold:
				left_foot_hold.release(left_foot)
				left_foot_hold = null
				left_foot_manual = false
				left_foot_auto_disabled = false
		
		Limb.RIGHT_FOOT:
			if right_foot_hold:
				right_foot_hold.release(right_foot)
				right_foot_hold = null
				right_foot_manual = false
				right_foot_auto_disabled = false

func check_fall_detection(delta: float):
	var held_limbs = count_held_limbs()
	
	if held_limbs == 0 and com_velocity.y > FALL_VELOCITY_THRESHOLD:
		fall_timer += delta
		if fall_timer >= FALL_DETECTION_TIME:
			print("Fell off - resetting climb")
			reset_climb()
	else:
		fall_timer = 0.0

func check_climb_completion():
	if climb_completed:
		return
	
	var left_on_top = false
	var right_on_top = false
	
	if left_hand_hold and left_hand_hold.is_top_out():
		left_on_top = true
	if right_hand_hold and right_hand_hold.is_top_out():
		right_on_top = true
	
	if left_on_top and right_on_top:
		climb_completed = true
		print("Climb completed!")
		var game_scene = get_parent()
		if game_scene.has_method("on_level_complete"):
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
	var black = Color.BLACK
	var line_width = 4.0
	
	draw_circle(Vector2(0, HEAD_OFFSET), 12, black)
	draw_line(Vector2(0, HEAD_OFFSET + 12), Vector2(0, HIP_DOWN + 5), black, line_width)
	
	draw_line(Vector2(-SHOULDER_OFFSET, 0), left_hand_joint.position, black, line_width)
	draw_line(left_hand_joint.position, left_hand.position + left_hand_shake_offset, black, line_width - 1)
	draw_line(Vector2(SHOULDER_OFFSET, 0), right_hand_joint.position, black, line_width)
	draw_line(right_hand_joint.position, right_hand.position + right_hand_shake_offset, black, line_width - 1)
	
	draw_line(Vector2(-HIP_OFFSET, HIP_DOWN), left_foot_joint.position, black, line_width)
	draw_line(left_foot_joint.position, left_foot.position + left_foot_shake_offset, black, line_width - 1)
	draw_line(Vector2(HIP_OFFSET, HIP_DOWN), right_foot_joint.position, black, line_width)
	draw_line(right_foot_joint.position, right_foot.position + right_foot_shake_offset, black, line_width - 1)
	
	var left_hand_draw_pos = left_hand.position + left_hand_shake_offset
	var right_hand_draw_pos = right_hand.position + right_hand_shake_offset
	var left_foot_draw_pos = left_foot.position + left_foot_shake_offset
	var right_foot_draw_pos = right_foot.position + right_foot_shake_offset
	
	var left_hand_color = get_grip_state_color(left_hand_state, Limb.LEFT_HAND)
	var right_hand_color = get_grip_state_color(right_hand_state, Limb.RIGHT_HAND)
	var left_foot_color = get_grip_state_color(left_foot_state, Limb.LEFT_FOOT)
	var right_foot_color = get_grip_state_color(right_foot_state, Limb.RIGHT_FOOT)
	
	draw_circle(left_hand_draw_pos, 6, black)
	draw_circle(left_hand_draw_pos, 5, left_hand_color)
	draw_circle(right_hand_draw_pos, 6, black)
	draw_circle(right_hand_draw_pos, 5, right_hand_color)
	
	draw_circle(left_foot_draw_pos, 6, black)
	draw_circle(left_foot_draw_pos, 5, left_foot_color)
	draw_circle(right_foot_draw_pos, 6, black)
	draw_circle(right_foot_draw_pos, 5, right_foot_color)
	
	if use_mouse_aim and selected_limbs.size() > 0:
		var mouse_local = to_local(mouse_aim_position)
		draw_circle(mouse_local, 6, Color(1, 1, 0, 0.5))
		draw_arc(mouse_local, 10, 0, TAU, 12, Color(1, 1, 0, 0.7), 1.5)

func get_grip_state_color(state: GripState, limb: Limb) -> Color:
	var on_hold_settled = false
	match limb:
		Limb.LEFT_HAND:
			on_hold_settled = left_hand_hold != null and not left_hand_grabbing
		Limb.RIGHT_HAND:
			on_hold_settled = right_hand_hold != null and not right_hand_grabbing
		Limb.LEFT_FOOT:
			on_hold_settled = left_foot_hold != null and not left_foot_grabbing
		Limb.RIGHT_FOOT:
			on_hold_settled = right_foot_hold != null and not right_foot_grabbing
	
	if not on_hold_settled:
		return Color.BLACK
	
	match state:
		GripState.RELAXED:
			return Color.GREEN
		GripState.ENGAGED:
			return Color(0.8, 0.8, 0.2)
		GripState.PUMPED:
			return Color.ORANGE
		GripState.FAIL:
			return Color.RED
	
	return Color.BLACK

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
