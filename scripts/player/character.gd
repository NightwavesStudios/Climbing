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

# ===============================================
# State
# ===============================================
enum Limb { NONE, LEFT_HAND, RIGHT_HAND, LEFT_FOOT, RIGHT_FOOT }
var selected_limb: Limb = Limb.NONE
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

# ===============================================
# Physics Settings
# ===============================================
const REACH_DISTANCE := 200.0
const HAND_MOVE_SPEED := 0.85
const ARM_UPPER_LENGTH := 45.0
const ARM_LOWER_LENGTH := 45.0
const LEG_UPPER_LENGTH := 40.0
const LEG_LOWER_LENGTH := 40.0
const SHOULDER_OFFSET := 10.0
const HIP_OFFSET := 10.0
const HIP_DOWN := 20.0
const HEAD_OFFSET := -20.0
const TORSO_LENGTH := 25.0

# Physics forces
const BODY_PULL_STRENGTH := 0.25
const JOINT_STIFFNESS := 0.98  # Very tight to prevent stretch
const LIMB_STIFFNESS := 0.98
const FOOT_SUPPORT_STRENGTH := 0.15
const FOOT_SUPPORT_MIN_Y := -20.0
const FOOT_SUPPORT_MAX_PUSH := 50.0
const FOOT_LATERAL_ASSIST := 0.08
const GRAVITY := 2400.0
const BODY_DRAG := 0.88
const LIMB_DRAG := 0.85
const MAX_JOINT_STRETCH := 1.08  # Reduced to prevent infinite stretch!
const MAX_LIMB_STRETCH := 1.08
const PREVENT_UPSIDE_DOWN := true

# Center of Mass (COM) Physics
const COM_OFFSET_Y := 15.0
const FOOT_CUT_THRESHOLD := 150.0
const HAND_LOAD_TOLERANCE := 1.35  # Hands pop off earlier to prevent stretch
const COM_SHIFT_SPEED := 0.08
const LIMB_GRAB_SPEED := 1.0

# Momentum and Dyno
const MOMENTUM_TRANSFER_STRENGTH := 0.4
const DYNO_VELOCITY_BOOST := 1.2

# Natural Limb Positioning
const ARM_NATURAL_ANGLE := 25.0  # Degrees from vertical when hanging
const ARM_NATURAL_BEND := 0.7  # How bent arms are when free
const LEG_NATURAL_SPLAY := 15.0  # Degrees outward when free
const FREE_LIMB_RELAXATION_SPEED := 0.15  # Speed to natural pose

# Adaptive Leg Assistance
const ENABLE_ADAPTIVE_LEGS := true  # Toggle ON/OFF
const LEG_ASSIST_THRESHOLD := 0.8  # How far to reach before legs help (0.0-1.5)
const LEG_ASSIST_STRENGTH := 0.6  # Push strength toward target
const LEG_ASSIST_SPEED := 0.3  # Response speed
const LEG_ASSIST_MAX_EXTENSION := 0.92  # Max leg extension

# Foot placement
const FOOT_SEARCH_RADIUS := 80.0
const FOOT_PLACEMENT_TIMER := 0.5
const FOOT_PREFERENCE_BELOW := 40.0
const FOOT_RELEASE_THRESHOLD := 1.35  # Feet release earlier

# ===============================================
# Feature Toggles
# ===============================================
const AUTO_FOOT_PLACEMENT := true
const ALLOW_ARM_CROSSING := false
const ALLOW_FOOT_CROSSING := false
const MIN_HAND_SEPARATION := 20.0
const MIN_FOOT_SEPARATION := 15.0
const MOUSE_CONTROL_ENABLED := true
const MOUSE_DEADZONE := 5.0

# ===============================================
# Physics State
# ===============================================
var body_velocity := Vector2.ZERO
var left_hand_velocity := Vector2.ZERO
var right_hand_velocity := Vector2.ZERO
var left_foot_velocity := Vector2.ZERO
var right_foot_velocity := Vector2.ZERO
var left_hand_joint_velocity := Vector2.ZERO
var right_hand_joint_velocity := Vector2.ZERO
var left_foot_joint_velocity := Vector2.ZERO
var right_foot_joint_velocity := Vector2.ZERO
var foot_placement_timer := 0.0
var left_foot_manual := false
var right_foot_manual := false
var left_foot_auto_disabled := false
var right_foot_auto_disabled := false

var com_position := Vector2.ZERO
var com_velocity := Vector2.ZERO
var rotational_velocity := 0.0
var last_held_limbs := 0

var left_hand_grabbing := false
var right_hand_grabbing := false
var left_foot_grabbing := false
var right_foot_grabbing := false
var left_hand_grab_target := Vector2.ZERO
var right_hand_grab_target := Vector2.ZERO
var left_foot_grab_target := Vector2.ZERO
var right_foot_grab_target := Vector2.ZERO

var previous_left_hand_pos := Vector2.ZERO
var previous_right_hand_pos := Vector2.ZERO
var previous_left_foot_pos := Vector2.ZERO
var previous_right_foot_pos := Vector2.ZERO

var mouse_aim_position := Vector2.ZERO
var use_mouse_aim := false

# ===============================================
# Ready Function
# ===============================================
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
	simulate_physics(delta)
	if AUTO_FOOT_PLACEMENT:
		auto_place_feet(delta)
	check_climb_completion()
	update_camera()
	queue_redraw()

# ===============================================
# Input Handling
# ===============================================
func handle_input():
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_pressed(KEY_R):
		reset_climb()
		return
	
	if Input.is_action_just_pressed("select_left"):
		selected_limb = Limb.LEFT_HAND
		if left_hand_hold != null:
			left_hand_hold = null
	elif Input.is_action_just_pressed("select_right"):
		selected_limb = Limb.RIGHT_HAND
		if right_hand_hold != null:
			right_hand_hold = null
	
	if Input.is_action_just_pressed("select_left_foot"):
		selected_limb = Limb.LEFT_FOOT
		left_foot_auto_disabled = true
		if left_foot_hold != null:
			left_foot_hold = null
	elif Input.is_action_just_pressed("select_right_foot"):
		selected_limb = Limb.RIGHT_FOOT
		right_foot_auto_disabled = true
		if right_foot_hold != null:
			right_foot_hold = null
	
	if MOUSE_CONTROL_ENABLED and selected_limb != Limb.NONE:
		var mouse_global = get_global_mouse_position()
		var limb_pos = get_selected_limb_position()
		var dist_to_mouse = limb_pos.distance_to(mouse_global)
		if dist_to_mouse > MOUSE_DEADZONE:
			use_mouse_aim = true
			mouse_aim_position = mouse_global
		else:
			use_mouse_aim = false
	else:
		use_mouse_aim = false
	
	if Input.is_action_just_released("select_left"):
		if selected_limb == Limb.LEFT_HAND:
			attempt_grab(Limb.LEFT_HAND)
		selected_limb = Limb.NONE
		use_mouse_aim = false
	if Input.is_action_just_released("select_right"):
		if selected_limb == Limb.RIGHT_HAND:
			attempt_grab(Limb.RIGHT_HAND)
		selected_limb = Limb.NONE
		use_mouse_aim = false
	if Input.is_action_just_released("select_left_foot"):
		if selected_limb == Limb.LEFT_FOOT:
			attempt_grab(Limb.LEFT_FOOT)
			left_foot_manual = true
		selected_limb = Limb.NONE
		use_mouse_aim = false
		if left_foot_hold == null:
			left_foot_auto_disabled = false
	if Input.is_action_just_released("select_right_foot"):
		if selected_limb == Limb.RIGHT_FOOT:
			attempt_grab(Limb.RIGHT_FOOT)
			right_foot_manual = true
		selected_limb = Limb.NONE
		use_mouse_aim = false
		if right_foot_hold == null:
			right_foot_auto_disabled = false

func get_selected_limb_position() -> Vector2:
	match selected_limb:
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
	for vel in [left_hand_velocity, right_hand_velocity, left_foot_velocity, right_foot_velocity,
				left_hand_joint_velocity, right_hand_joint_velocity, left_foot_joint_velocity, right_foot_joint_velocity]:
		vel = Vector2.ZERO
	
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
	
	selected_limb = Limb.NONE
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
	
	await get_tree().process_frame
	initial_grab()

# ===============================================
# Physics Simulation
# ===============================================
func simulate_physics(delta):
	var held_hand_count := 0
	var held_foot_count := 0
	if left_hand_hold: held_hand_count += 1
	if right_hand_hold: held_hand_count += 1
	if left_foot_hold: held_foot_count += 1
	if right_foot_hold: held_foot_count += 1
	
	var total_held_limbs = held_hand_count + held_foot_count
	
	if total_held_limbs < last_held_limbs:
		com_velocity += Vector2(randf_range(-20, 20), 30) * COM_SHIFT_SPEED
	last_held_limbs = total_held_limbs
	
	var target_com = calculate_com()
	
	if held_hand_count > 0:
		com_velocity.y += GRAVITY * delta * 0.15
	else:
		com_velocity.y += GRAVITY * delta * 2.0
		left_foot_hold = null
		right_foot_hold = null
		left_foot_manual = false
		right_foot_manual = false
		left_foot_auto_disabled = false
		right_foot_auto_disabled = false
	
	# Pin held limbs - CRITICAL FOR NO STRETCH
	if left_hand_hold and not left_hand_grabbing:
		left_hand.global_position = left_hand_anchor
		left_hand_velocity = Vector2.ZERO
		left_hand_joint_velocity = Vector2.ZERO
	if right_hand_hold and not right_hand_grabbing:
		right_hand.global_position = right_hand_anchor
		right_hand_velocity = Vector2.ZERO
		right_hand_joint_velocity = Vector2.ZERO
	if left_foot_hold and not left_foot_grabbing:
		left_foot.global_position = left_foot_anchor
		left_foot_velocity = Vector2.ZERO
		left_foot_joint_velocity = Vector2.ZERO
	if right_foot_hold and not right_foot_grabbing:
		right_foot.global_position = right_foot_anchor
		right_foot_velocity = Vector2.ZERO
		right_foot_joint_velocity = Vector2.ZERO
	
	# Apply gravity to free limbs
	if left_hand_hold == null and selected_limb != Limb.LEFT_HAND and not left_hand_grabbing:
		left_hand_velocity.y += GRAVITY * delta * 0.4
		left_hand_joint_velocity.y += GRAVITY * delta * 0.3
	if right_hand_hold == null and selected_limb != Limb.RIGHT_HAND and not right_hand_grabbing:
		right_hand_velocity.y += GRAVITY * delta * 0.4
		right_hand_joint_velocity.y += GRAVITY * delta * 0.3
	if left_foot_hold == null and selected_limb != Limb.LEFT_FOOT and not left_foot_grabbing:
		left_foot_velocity.y += GRAVITY * delta * 0.5
		left_foot_joint_velocity.y += GRAVITY * delta * 0.4
	if right_foot_hold == null and selected_limb != Limb.RIGHT_FOOT and not right_foot_grabbing:
		right_foot_velocity.y += GRAVITY * delta * 0.5
		right_foot_joint_velocity.y += GRAVITY * delta * 0.4
	
	# Mouse control
	if use_mouse_aim and selected_limb != Limb.NONE:
		apply_mouse_control(delta)
	
	# NATURAL LIMB POSITIONING for free limbs
	apply_natural_limb_positions(delta)
	
	# ADAPTIVE LEG ASSISTANCE
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
			left_foot_hold = null
			right_foot_hold = null
			left_foot_manual = false
			right_foot_manual = false
			left_foot_auto_disabled = false
			right_foot_auto_disabled = false
	
	apply_limb_tension(delta, held_hand_count, held_foot_count)
	
	com_position += com_velocity * delta
	var com_to_body_offset = Vector2(0, -COM_OFFSET_Y)
	global_position = com_position + com_to_body_offset
	
	# Apply velocities to free limbs only
	if left_hand_hold == null and selected_limb != Limb.LEFT_HAND and not left_hand_grabbing:
		left_hand.global_position += left_hand_velocity * delta
		left_hand_joint.global_position += left_hand_joint_velocity * delta
	if right_hand_hold == null and selected_limb != Limb.RIGHT_HAND and not right_hand_grabbing:
		right_hand.global_position += right_hand_velocity * delta
		right_hand_joint.global_position += right_hand_joint_velocity * delta
	if left_foot_hold == null and selected_limb != Limb.LEFT_FOOT and not left_foot_grabbing:
		left_foot.global_position += left_foot_velocity * delta
		left_foot_joint.global_position += left_foot_joint_velocity * delta
	if right_foot_hold == null and selected_limb != Limb.RIGHT_FOOT and not right_foot_grabbing:
		right_foot.global_position += right_foot_velocity * delta
		right_foot_joint.global_position += right_foot_joint_velocity * delta
	
	if PREVENT_UPSIDE_DOWN and held_hand_count > 0:
		enforce_foot_below_hands()
	
	check_limb_overload(held_hand_count, held_foot_count)
	
	# CRITICAL: Apply constraints 5 times to prevent stretch
	for i in range(5):
		apply_joint_constraints()
	
	# Smooth grab animations
	update_grab_animations()
	
	# Re-pin held limbs AFTER constraints
	if left_hand_hold and not left_hand_grabbing:
		left_hand.global_position = left_hand_anchor
	if right_hand_hold and not right_hand_grabbing:
		right_hand.global_position = right_hand_anchor
	if left_foot_hold and not left_foot_grabbing:
		left_foot.global_position = left_foot_anchor
	if right_foot_hold and not right_foot_grabbing:
		right_foot.global_position = right_foot_anchor
	
	if not ALLOW_ARM_CROSSING or not ALLOW_FOOT_CROSSING:
		prevent_limb_crossing()
	
	com_velocity *= BODY_DRAG
	
	for limb_vel in [[left_hand_hold, left_hand_velocity, left_hand_joint_velocity, Limb.LEFT_HAND],
					 [right_hand_hold, right_hand_velocity, right_hand_joint_velocity, Limb.RIGHT_HAND],
					 [left_foot_hold, left_foot_velocity, left_foot_joint_velocity, Limb.LEFT_FOOT],
					 [right_foot_hold, right_foot_velocity, right_foot_joint_velocity, Limb.RIGHT_FOOT]]:
		if limb_vel[0] == null and selected_limb != limb_vel[3]:
			limb_vel[1] *= LIMB_DRAG
			limb_vel[2] *= LIMB_DRAG

func apply_mouse_control(delta):
	var target_pos = mouse_aim_position
	match selected_limb:
		Limb.LEFT_HAND:
			if left_hand_hold == null and not left_hand_grabbing:
				var attachment = global_position + Vector2(-SHOULDER_OFFSET, 0)
				if not ALLOW_ARM_CROSSING:
					target_pos.x = min(target_pos.x, global_position.x)
				var dist = attachment.distance_to(target_pos)
				var max_r = ARM_UPPER_LENGTH + ARM_LOWER_LENGTH
				if dist > max_r:
					target_pos = attachment + (target_pos - attachment).normalized() * max_r
				left_hand.global_position = left_hand.global_position.lerp(target_pos, HAND_MOVE_SPEED)
				left_hand_velocity = Vector2.ZERO
				left_hand_joint_velocity = Vector2.ZERO
				apply_limb_momentum(left_hand.global_position, previous_left_hand_pos, delta)
		Limb.RIGHT_HAND:
			if right_hand_hold == null and not right_hand_grabbing:
				var attachment = global_position + Vector2(SHOULDER_OFFSET, 0)
				if not ALLOW_ARM_CROSSING:
					target_pos.x = max(target_pos.x, global_position.x)
				var dist = attachment.distance_to(target_pos)
				var max_r = ARM_UPPER_LENGTH + ARM_LOWER_LENGTH
				if dist > max_r:
					target_pos = attachment + (target_pos - attachment).normalized() * max_r
				right_hand.global_position = right_hand.global_position.lerp(target_pos, HAND_MOVE_SPEED)
				right_hand_velocity = Vector2.ZERO
				right_hand_joint_velocity = Vector2.ZERO
				apply_limb_momentum(right_hand.global_position, previous_right_hand_pos, delta)
		Limb.LEFT_FOOT:
			if left_foot_hold == null and not left_foot_grabbing:
				var attachment = global_position + Vector2(-HIP_OFFSET, HIP_DOWN)
				var highest_hand_y = get_highest_hand_y()
				target_pos.y = max(target_pos.y, highest_hand_y)
				if not ALLOW_FOOT_CROSSING:
					target_pos.x = min(target_pos.x, global_position.x)
				var dist = attachment.distance_to(target_pos)
				var max_r = LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
				if dist > max_r:
					target_pos = attachment + (target_pos - attachment).normalized() * max_r
				left_foot.global_position = left_foot.global_position.lerp(target_pos, HAND_MOVE_SPEED)
				left_foot_velocity = Vector2.ZERO
				left_foot_joint_velocity = Vector2.ZERO
				apply_limb_momentum(left_foot.global_position, previous_left_foot_pos, delta)
		Limb.RIGHT_FOOT:
			if right_foot_hold == null and not right_foot_grabbing:
				var attachment = global_position + Vector2(HIP_OFFSET, HIP_DOWN)
				var highest_hand_y = get_highest_hand_y()
				target_pos.y = max(target_pos.y, highest_hand_y)
				if not ALLOW_FOOT_CROSSING:
					target_pos.x = max(target_pos.x, global_position.x)
				var dist = attachment.distance_to(target_pos)
				var max_r = LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
				if dist > max_r:
					target_pos = attachment + (target_pos - attachment).normalized() * max_r
				right_foot.global_position = right_foot.global_position.lerp(target_pos, HAND_MOVE_SPEED)
				right_foot_velocity = Vector2.ZERO
				right_foot_joint_velocity = Vector2.ZERO
				apply_limb_momentum(right_foot.global_position, previous_right_foot_pos, delta)

# Apply natural positioning to free limbs (bent, to the side)
func apply_natural_limb_positions(delta):
	var body_pos = global_position
	
	# Left arm natural position (bent, to the left)
	if left_hand_hold == null and selected_limb != Limb.LEFT_HAND and not left_hand_grabbing:
		var shoulder_pos = body_pos + Vector2(-SHOULDER_OFFSET, 0)
		var angle_rad = deg_to_rad(ARM_NATURAL_ANGLE)
		var natural_dist = (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * ARM_NATURAL_BEND
		var natural_target = shoulder_pos + Vector2(-sin(angle_rad), cos(angle_rad)) * natural_dist
		left_hand.global_position = left_hand.global_position.lerp(natural_target, FREE_LIMB_RELAXATION_SPEED)
	
	# Right arm natural position (bent, to the right)
	if right_hand_hold == null and selected_limb != Limb.RIGHT_HAND and not right_hand_grabbing:
		var shoulder_pos = body_pos + Vector2(SHOULDER_OFFSET, 0)
		var angle_rad = deg_to_rad(ARM_NATURAL_ANGLE)
		var natural_dist = (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * ARM_NATURAL_BEND
		var natural_target = shoulder_pos + Vector2(sin(angle_rad), cos(angle_rad)) * natural_dist
		right_hand.global_position = right_hand.global_position.lerp(natural_target, FREE_LIMB_RELAXATION_SPEED)

# Legs extend to help when arms are reaching far
func apply_adaptive_leg_assistance(delta):
	# Only assist when actively reaching with a hand
	if not use_mouse_aim:
		return
	
	if selected_limb != Limb.LEFT_HAND and selected_limb != Limb.RIGHT_HAND:
		return
	
	# Get the target position we're reaching for
	var target_pos = mouse_aim_position
	var body_pos = global_position
	
	# Calculate direction we're reaching
	var reach_direction = (target_pos - body_pos).normalized()
	
	# Calculate how far we're trying to reach
	var reach_distance = body_pos.distance_to(target_pos)
	var max_arm_reach = ARM_UPPER_LENGTH + ARM_LOWER_LENGTH
	var reach_ratio = clamp(reach_distance / max_arm_reach, 0.0, 1.5)
	
	# Only assist if reaching far enough
	if reach_ratio < LEG_ASSIST_THRESHOLD:
		return
	
	# Calculate assistance amount based on reach
	var assist_amount = (reach_ratio - LEG_ASSIST_THRESHOLD) / (1.5 - LEG_ASSIST_THRESHOLD)
	assist_amount = clamp(assist_amount, 0.0, 1.0) * LEG_ASSIST_STRENGTH
	
	# Push body in the direction we're reaching by extending legs
	# This gives more reach to grab distant holds
	
	# Left leg extension
	if left_foot_hold:
		var left_hip = body_pos + Vector2(-HIP_OFFSET, HIP_DOWN)
		var current_dist = left_hip.distance_to(left_foot_anchor)
		var max_leg_len = LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
		var current_extension = current_dist / max_leg_len
		var target_extension = LEG_ASSIST_MAX_EXTENSION
		
		# Only extend if not already extended
		if current_extension < target_extension:
			# Push body TOWARD the reach target
			var leg_push = reach_direction * assist_amount * LEG_ASSIST_SPEED * 100.0
			com_velocity += leg_push
	
	# Right leg extension
	if right_foot_hold:
		var right_hip = body_pos + Vector2(HIP_OFFSET, HIP_DOWN)
		var current_dist = right_hip.distance_to(right_foot_anchor)
		var max_leg_len = LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
		var current_extension = current_dist / max_leg_len
		var target_extension = LEG_ASSIST_MAX_EXTENSION
		
		# Only extend if not already extended
		if current_extension < target_extension:
			# Push body TOWARD the reach target
			var leg_push = reach_direction * assist_amount * LEG_ASSIST_SPEED * 100.0
			com_velocity += leg_push
	
	# If both feet are planted, give extra push
	if left_foot_hold and right_foot_hold:
		# Calculate average foot position for stable base
		var foot_center = (left_foot_anchor + right_foot_anchor) / 2.0
		var foot_to_body = body_pos - foot_center
		
		# Push body away from feet in the reach direction
		# This simulates "standing up" or "leaning" toward the target
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
	if delta <= 0: return
	var limb_velocity = (current_pos - previous_pos) / delta
	com_velocity += limb_velocity * MOMENTUM_TRANSFER_STRENGTH * delta * DYNO_VELOCITY_BOOST

func calculate_com() -> Vector2:
	var com := Vector2.ZERO
	var total_weight := 0.0
	
	com += global_position * 50.0
	total_weight += 50.0
	
	if left_hand_hold:
		com += left_hand_anchor * 5.0
		total_weight += 5.0
	else:
		com += left_hand.global_position * 5.0
		total_weight += 5.0
	
	if right_hand_hold:
		com += right_hand_anchor * 5.0
		total_weight += 5.0
	else:
		com += right_hand.global_position * 5.0
		total_weight += 5.0
	
	if left_foot_hold:
		com += left_foot_anchor * 8.0
		total_weight += 8.0
	else:
		com += left_foot.global_position * 8.0
		total_weight += 8.0
	
	if right_foot_hold:
		com += right_foot_anchor * 8.0
		total_weight += 8.0
	else:
		com += right_foot.global_position * 8.0
		total_weight += 8.0
	
	return com / total_weight

func apply_foot_support(delta):
	var support_force := Vector2.ZERO
	var total_foot_count := 0
	
	var foot_center := Vector2.ZERO
	if left_foot_hold:
		foot_center += left_foot_anchor
		total_foot_count += 1
	if right_foot_hold:
		foot_center += right_foot_anchor
		total_foot_count += 1
	if total_foot_count > 0:
		foot_center /= total_foot_count
	
	if left_foot_hold:
		var foot_relative_y = left_foot_anchor.y - com_position.y
		if foot_relative_y > FOOT_SUPPORT_MIN_Y:
			var push_distance = min(foot_relative_y, FOOT_SUPPORT_MAX_PUSH)
			support_force.y -= FOOT_SUPPORT_STRENGTH * push_distance
	if right_foot_hold:
		var foot_relative_y = right_foot_anchor.y - com_position.y
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
		target_pos += left_hand_anchor * 2.0
		total_weight += 2.0
	if right_hand_hold:
		target_pos += right_hand_anchor * 2.0
		total_weight += 2.0
	
	if left_foot_hold:
		target_pos += left_foot_anchor * 0.5
		total_weight += 0.5
	if right_foot_hold:
		target_pos += right_foot_anchor * 0.5
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
		var stretch = left_shoulder.distance_to(left_hand_anchor)
		var max_len = (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * HAND_LOAD_TOLERANCE
		if stretch > max_len:
			left_hand_hold = null
	
	if right_hand_hold:
		var right_shoulder := global_position + Vector2(SHOULDER_OFFSET, 0)
		var stretch = right_shoulder.distance_to(right_hand_anchor)
		var max_len = (ARM_UPPER_LENGTH + ARM_LOWER_LENGTH) * HAND_LOAD_TOLERANCE
		if stretch > max_len:
			right_hand_hold = null
	
	var left_hip := global_position + Vector2(-HIP_OFFSET, HIP_DOWN)
	var right_hip := global_position + Vector2(HIP_OFFSET, HIP_DOWN)
	var leg_total_len := LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
	
	if left_foot_hold and left_hip.distance_to(left_foot_anchor) > leg_total_len * FOOT_RELEASE_THRESHOLD:
		left_foot_hold = null
		left_foot_manual = false
		left_foot_auto_disabled = false
	if right_foot_hold and right_hip.distance_to(right_foot_anchor) > leg_total_len * FOOT_RELEASE_THRESHOLD:
		right_foot_hold = null
		right_foot_manual = false
		right_foot_auto_disabled = false

func get_highest_hand_y() -> float:
	if left_hand_hold and right_hand_hold:
		return min(left_hand_anchor.y, right_hand_anchor.y)
	elif left_hand_hold:
		return left_hand_anchor.y
	elif right_hand_hold:
		return right_hand_anchor.y
	else:
		return global_position.y

func enforce_foot_below_hands():
	var highest_hand_y = get_highest_hand_y()
	
	if left_foot_hold and left_foot_anchor.y < highest_hand_y:
		left_foot_hold = null
		left_foot_manual = false
		left_foot_auto_disabled = false
	if right_foot_hold and right_foot_anchor.y < highest_hand_y:
		right_foot_hold = null
		right_foot_manual = false
		right_foot_auto_disabled = false

func prevent_limb_crossing():
	if not ALLOW_ARM_CROSSING:
		if left_hand.global_position.x > right_hand.global_position.x - MIN_HAND_SEPARATION:
			var midpoint = (left_hand.global_position.x + right_hand.global_position.x) / 2.0
			left_hand.global_position.x = midpoint - MIN_HAND_SEPARATION / 2.0
			right_hand.global_position.x = midpoint + MIN_HAND_SEPARATION / 2.0
	if not ALLOW_FOOT_CROSSING:
		if left_foot.global_position.x > right_foot.global_position.x - MIN_FOOT_SEPARATION:
			var midpoint = (left_foot.global_position.x + right_foot.global_position.x) / 2.0
			left_foot.global_position.x = midpoint - MIN_FOOT_SEPARATION / 2.0
			right_foot.global_position.x = midpoint + MIN_FOOT_SEPARATION / 2.0

func apply_joint_constraints():
	var left_shoulder := global_position + Vector2(-SHOULDER_OFFSET, 0)
	var right_shoulder := global_position + Vector2(SHOULDER_OFFSET, 0)
	var left_hip := global_position + Vector2(-HIP_OFFSET, HIP_DOWN)
	var right_hip := global_position + Vector2(HIP_OFFSET, HIP_DOWN)
	var left_hand_pinned = left_hand_hold != null or selected_limb == Limb.LEFT_HAND or left_hand_grabbing
	var right_hand_pinned = right_hand_hold != null or selected_limb == Limb.RIGHT_HAND or right_hand_grabbing
	var left_foot_pinned = left_foot_hold != null or selected_limb == Limb.LEFT_FOOT or left_foot_grabbing
	var right_foot_pinned = right_foot_hold != null or selected_limb == Limb.RIGHT_FOOT or right_foot_grabbing
	constrain_arm(left_hand_joint, left_hand, left_shoulder, ARM_UPPER_LENGTH, ARM_LOWER_LENGTH, left_hand_pinned, true)
	constrain_arm(right_hand_joint, right_hand, right_shoulder, ARM_UPPER_LENGTH, ARM_LOWER_LENGTH, right_hand_pinned, false)
	constrain_leg(left_foot_joint, left_foot, left_hip, LEG_UPPER_LENGTH, LEG_LOWER_LENGTH, left_foot_pinned, true)
	constrain_leg(right_foot_joint, right_foot, right_hip, LEG_UPPER_LENGTH, LEG_LOWER_LENGTH, right_foot_pinned, false)

func constrain_arm(elbow: Node2D, hand: Node2D, shoulder: Vector2, upper_len: float, lower_len: float, hand_pinned: bool, is_left: bool):
	var to_hand := hand.global_position - shoulder
	var dist := to_hand.length()
	if dist < 0.01: return
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
	if dist < 0.01: return
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
	if foot_placement_timer > 0: return
	var held_hands := 0
	if left_hand_hold: held_hands += 1
	if right_hand_hold: held_hands += 1
	if held_hands == 0:
		if left_foot_hold and not left_foot_manual:
			left_foot_hold = null
			left_foot_auto_disabled = false
		if right_foot_hold and not right_foot_manual:
			right_foot_hold = null
			right_foot_auto_disabled = false
		return
	
	if left_foot_hold == null and not left_foot_manual and not left_foot_auto_disabled:
		var best_hold := find_best_foot_hold(left_foot.global_position, true)
		if best_hold:
			var snap_point: Marker2D = best_hold.get_node("HoldPoint")
			left_foot_hold = best_hold
			left_foot_anchor = snap_point.global_position
			left_foot.global_position = left_foot_anchor
			left_foot_velocity = Vector2.ZERO
			left_foot_joint_velocity = Vector2.ZERO
			foot_placement_timer = FOOT_PLACEMENT_TIMER
			return
	if right_foot_hold == null and not right_foot_manual and not right_foot_auto_disabled:
		var best_hold := find_best_foot_hold(right_foot.global_position, false)
		if best_hold:
			var snap_point: Marker2D = best_hold.get_node("HoldPoint")
			right_foot_hold = best_hold
			right_foot_anchor = snap_point.global_position
			right_foot.global_position = right_foot_anchor
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
	if results.size() == 0: return null
	var best_hold: Area2D = null
	var best_score := -INF
	var highest_hand_y = get_highest_hand_y()
	for result in results:
		var hold: Area2D = result.collider
		if (is_left and hold == right_foot_hold) or (not is_left and hold == left_foot_hold): continue
		if hold == left_hand_hold or hold == right_hand_hold: continue
		var hold_point := hold.get_node_or_null("HoldPoint")
		if hold_point == null: continue
		var hold_pos = hold_point.global_position
		if PREVENT_UPSIDE_DOWN and hold_pos.y < highest_hand_y: continue
		var relative_y = hold_pos.y - global_position.y
		if relative_y < 0: continue
		if not ALLOW_FOOT_CROSSING:
			var relative_x = hold_pos.x - global_position.x
			if is_left and relative_x > 0: continue
			elif not is_left and relative_x < 0: continue
		var dist := foot_position.distance_to(hold_pos)
		var dist_score := 1.0 - (dist / FOOT_SEARCH_RADIUS)
		var below_score = clamp(relative_y / FOOT_PREFERENCE_BELOW, 0.0, 2.0)
		var relative_x = hold_pos.x - global_position.x
		var side_score := 0.5
		if is_left and relative_x < 0: side_score = 1.0
		elif not is_left and relative_x > 0: side_score = 1.0
		var max_reach := LEG_UPPER_LENGTH + LEG_LOWER_LENGTH
		var hip_pos := global_position + Vector2(-HIP_OFFSET if is_left else HIP_OFFSET, HIP_DOWN)
		var reach_dist := hip_pos.distance_to(hold_pos)
		if reach_dist > max_reach * 1.2: continue
		var total_score = dist_score * 1.0 + below_score * 3.0 + side_score * 0.8
		if total_score > best_score:
			best_score = total_score
			best_hold = hold
	return best_hold

func initial_grab():
	var start_holds := find_start_holds()
	
	if start_holds.size() >= 2:
		var left_start = start_holds[0]
		var right_start = start_holds[1] if start_holds.size() > 1 else start_holds[0]
		
		if left_start:
			var snap_point: Marker2D = left_start.get_node("HoldPoint")
			left_hand_hold = left_start
			left_hand_anchor = snap_point.global_position
			left_hand.global_position = left_hand_anchor
			# POSITION BODY AT START HOLDS
			global_position.y = left_hand_anchor.y + 80  # Position body below holds
		if right_start and right_start != left_start:
			var snap_point: Marker2D = right_start.get_node("HoldPoint")
			right_hand_hold = right_start
			right_hand_anchor = snap_point.global_position
			right_hand.global_position = right_hand_anchor
			# Center body between holds
			global_position.x = (left_hand_anchor.x + right_hand_anchor.x) / 2.0
	else:
		var left_hold := find_nearest_hold(left_hand.global_position)
		var right_hold := find_nearest_hold(right_hand.global_position)
		
		if left_hold:
			var snap_point: Marker2D = left_hold.get_node("HoldPoint")
			left_hand_hold = left_hold
			left_hand_anchor = snap_point.global_position
			left_hand.global_position = left_hand_anchor
		if right_hold and right_hold != left_hold:
			var snap_point: Marker2D = right_hold.get_node("HoldPoint")
			right_hand_hold = right_hold
			right_hand_anchor = snap_point.global_position
			right_hand.global_position = right_hand_anchor
	
	# Update COM after body positioning
	com_position = global_position + Vector2(0, COM_OFFSET_Y)
	
	# Try to grab feet
	var left_foot_start := find_nearest_hold(left_foot.global_position)
	var right_foot_start := find_nearest_hold(right_foot.global_position)
	
	if left_foot_start and left_foot_start != left_hand_hold and left_foot_start != right_hand_hold:
		var snap_point: Marker2D = left_foot_start.get_node("HoldPoint")
		left_foot_hold = left_foot_start
		left_foot_anchor = snap_point.global_position
		left_foot.global_position = left_foot_anchor
	if right_foot_start and right_foot_start != left_hand_hold and right_foot_start != right_hand_hold and right_foot_start != left_foot_start:
		var snap_point: Marker2D = right_foot_start.get_node("HoldPoint")
		right_foot_hold = right_foot_start
		right_foot_anchor = snap_point.global_position
		right_foot.global_position = right_foot_anchor

func find_start_holds() -> Array[Area2D]:
	var start_holds: Array[Area2D] = []
	var all_holds = get_tree().get_nodes_in_group("holds")
	
	for hold in all_holds:
		if hold is Area2D and hold.has_method("is_start_hold"):
			if hold.is_start_hold():
				start_holds.append(hold)
	
	return start_holds

func check_climb_completion():
	if climb_completed:
		return
	
	var left_on_top = false
	var right_on_top = false
	
	if left_hand_hold and left_hand_hold.has_method("is_top_out"):
		left_on_top = left_hand_hold.is_top_out()
	if right_hand_hold and right_hand_hold.has_method("is_top_out"):
		right_on_top = right_hand_hold.is_top_out()
	
	if left_on_top and right_on_top:
		climb_completed = true
		print("Climb completed!")

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
	if results.size() == 0: return null
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
	match limb:
		Limb.LEFT_HAND:
			limb_area = left_hand_area
			limb_node = left_hand
		Limb.RIGHT_HAND:
			limb_area = right_hand_area
			limb_node = right_hand
		Limb.LEFT_FOOT:
			limb_area = left_foot_area
			limb_node = left_foot
		Limb.RIGHT_FOOT:
			limb_area = right_foot_area
			limb_node = right_foot
		_: return
	
	var overlaps := limb_area.get_overlapping_areas()
	if overlaps.size() == 0: return
	
	var closest_hold: Area2D = null
	var closest_dist := INF
	for hold in overlaps:
		var hold_point := hold.get_node_or_null("HoldPoint")
		if hold_point == null: continue
		var d := limb_node.global_position.distance_to(hold_point.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_hold = hold
	
	if closest_hold == null: return
	
	var snap_point: Marker2D = closest_hold.get_node("HoldPoint")
	
	if limb == Limb.LEFT_FOOT or limb == Limb.RIGHT_FOOT:
		if snap_point.global_position.y < global_position.y:
			return
		if PREVENT_UPSIDE_DOWN:
			var highest_hand_y = get_highest_hand_y()
			if snap_point.global_position.y < highest_hand_y:
				return
	
	match limb:
		Limb.LEFT_HAND:
			left_hand_hold = closest_hold
			left_hand_anchor = snap_point.global_position
			left_hand_grab_target = snap_point.global_position
			left_hand_grabbing = true
			left_hand_velocity = Vector2.ZERO
			left_hand_joint_velocity = Vector2.ZERO
		Limb.RIGHT_HAND:
			right_hand_hold = closest_hold
			right_hand_anchor = snap_point.global_position
			right_hand_grab_target = snap_point.global_position
			right_hand_grabbing = true
			right_hand_velocity = Vector2.ZERO
			right_hand_joint_velocity = Vector2.ZERO
		Limb.LEFT_FOOT:
			left_foot_hold = closest_hold
			left_foot_anchor = snap_point.global_position
			left_foot_grab_target = snap_point.global_position
			left_foot_grabbing = true
			left_foot_velocity = Vector2.ZERO
			left_foot_joint_velocity = Vector2.ZERO
		Limb.RIGHT_FOOT:
			right_foot_hold = closest_hold
			right_foot_anchor = snap_point.global_position
			right_foot_grab_target = snap_point.global_position
			right_foot_grabbing = true
			right_foot_velocity = Vector2.ZERO
			right_foot_joint_velocity = Vector2.ZERO
	
	if not climb_started:
		climb_started = true

func update_camera():
	if cam:
		cam.global_position = cam.global_position.lerp(global_position, CAM_LERP)

func _draw():
	var black = Color.BLACK
	var line_width = 4.0
	draw_circle(Vector2(0, HEAD_OFFSET), 18, black)
	draw_line(Vector2(0, HEAD_OFFSET + 8), Vector2(0, HIP_DOWN + 5), black, line_width)
	draw_line(Vector2(-SHOULDER_OFFSET, 0), left_hand_joint.position, black, line_width)
	draw_line(left_hand_joint.position, left_hand.position, black, line_width - 1)
	draw_line(Vector2(SHOULDER_OFFSET, 0), right_hand_joint.position, black, line_width)
	draw_line(right_hand_joint.position, right_hand.position, black, line_width - 1)
	draw_line(Vector2(-HIP_OFFSET, HIP_DOWN), left_foot_joint.position, black, line_width)
	draw_line(left_foot_joint.position, left_foot.position, black, line_width - 1)
	draw_line(Vector2(HIP_OFFSET, HIP_DOWN), right_foot_joint.position, black, line_width)
	draw_line(right_foot_joint.position, right_foot.position, black, line_width - 1)
	
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
	
	var left_hand_color := Color.YELLOW if selected_limb == Limb.LEFT_HAND else Color.WHITE
	var right_hand_color := Color.YELLOW if selected_limb == Limb.RIGHT_HAND else Color.WHITE
	if left_hand_hold: left_hand_color = Color.GREEN
	if right_hand_hold: right_hand_color = Color.GREEN
	draw_circle(left_hand.position, 6, black)
	draw_circle(left_hand.position, 5, left_hand_color)
	draw_circle(right_hand.position, 6, black)
	draw_circle(right_hand.position, 5, right_hand_color)
	
	var left_foot_color := Color.YELLOW if selected_limb == Limb.LEFT_FOOT else Color.WHITE
	var right_foot_color := Color.YELLOW if selected_limb == Limb.RIGHT_FOOT else Color.WHITE
	if left_foot_hold:
		left_foot_color = Color.CYAN if left_foot_manual else Color.GREEN
	if right_foot_hold:
		right_foot_color = Color.CYAN if right_foot_manual else Color.GREEN
	draw_circle(left_foot.position, 5, black)
	draw_circle(left_foot.position, 4, left_foot_color)
	draw_circle(right_foot.position, 5, black)
	draw_circle(right_foot.position, 4, right_foot_color)
	
	if use_mouse_aim and selected_limb != Limb.NONE:
		var mouse_local = to_local(mouse_aim_position)
		draw_circle(mouse_local, 6, Color(1, 1, 0, 0.5))
		draw_arc(mouse_local, 10, 0, TAU, 12, Color(1, 1, 0, 0.7), 1.5)
