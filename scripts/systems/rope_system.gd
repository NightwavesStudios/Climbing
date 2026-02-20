extends Node2D
class_name RopeSystem

## Top-rope climbing system - PURELY VISUAL

@export var rope_color := Color.BLACK
@export var rope_thickness := 2.5

# Rope physics - purely visual
const ROPE_SEGMENTS := 25
const ROPE_STIFFNESS := 0.95  # Very stiff = straighter
const ROPE_DAMPING := 0.98
const GRAVITY := 50.0  # Minimal droop
const SEGMENT_DRAG := 0.95

# Belayer constants (matching player)
const ARM_UPPER_LENGTH := 50.0
const ARM_LOWER_LENGTH := 50.0
const LEG_UPPER_LENGTH := 45.0
const LEG_LOWER_LENGTH := 45.0
const SHOULDER_OFFSET := 10.0
const HIP_OFFSET := 10.0
const HIP_DOWN := 20.0
const HEAD_OFFSET := -20.0

# Belayer animation
var belayer_lean := 0.0
var belayer_arm_tension := 0.0
var guide_hand_pull := 0.0
var brake_hand_lock := 0.0
var belayer_facing_right := true
const LEAN_SPEED := 3.0
const MAX_LEAN := 7.0
const ARM_SPEED := 4.0

# Rope state
var belayer_position: Vector2 = Vector2.ZERO
var anchor_position: Vector2 = Vector2.ZERO
var rope_points: Array[Vector2] = []
var rope_velocities: Array[Vector2] = []
var rope_tension: float = 0.0
var is_setup: bool = false

# Player reference
var player: Node2D = null
var player_attach_offset: Vector2 = Vector2(0, -10)

# Visual
var rope_line: Line2D = null

func _ready():
	global_position = Vector2.ZERO
	z_index = 50
	
	rope_line = Line2D.new()
	rope_line.width = rope_thickness
	rope_line.default_color = rope_color
	rope_line.z_index = 49
	rope_line.top_level = true
	rope_line.antialiased = true
	rope_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rope_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	rope_line.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(rope_line)
	
	set_process(true)

func _process(delta):
	if not is_setup:
		return
	
	if player and rope_points.size() > 0:
		simulate_rope_physics(delta)
		update_rope_visual()
		update_belayer_animation(delta)
	
	queue_redraw()

func setup_rope(belayer_pos: Vector2, player_node: Node2D, anchor_pos: Vector2 = Vector2.ZERO):
	"""Initialize top-rope system"""
	belayer_position = belayer_pos
	player = player_node
	
	# Find anchor at top of wall
	if anchor_pos == Vector2.ZERO:
		anchor_position = find_top_anchor()
	else:
		anchor_position = anchor_pos
	
	var player_chest = get_player_chest_position()
	
	# Determine which side player is on relative to anchor
	belayer_facing_right = player_chest.x > anchor_position.x
	
	# Get belayer hand position
	var belayer_hand = get_belayer_hand_position()
	
	# Initialize rope segments - distributed evenly along path
	rope_points.clear()
	rope_velocities.clear()
	
	# Create path: belayer → anchor → player
	var path_points = [belayer_hand, anchor_position, player_chest]
	
	# Calculate total path length
	var total_length = 0.0
	for i in range(path_points.size() - 1):
		total_length += path_points[i].distance_to(path_points[i + 1])
	
	# Distribute segments evenly along the path
	var segment_length = total_length / float(ROPE_SEGMENTS - 1)
	var current_section = 0
	var distance_in_section = 0.0
	var section_start = path_points[0]
	var section_end = path_points[1]
	var section_length = section_start.distance_to(section_end)
	
	for i in range(ROPE_SEGMENTS):
		var target_distance = i * segment_length
		
		# Find which section we should be in
		while target_distance > distance_in_section + section_length and current_section < path_points.size() - 2:
			distance_in_section += section_length
			current_section += 1
			section_start = path_points[current_section]
			section_end = path_points[current_section + 1]
			section_length = section_start.distance_to(section_end)
		
		# Interpolate within current section
		var t = 0.0
		if section_length > 0:
			t = (target_distance - distance_in_section) / section_length
		
		var point = section_start.lerp(section_end, t)
		rope_points.append(point)
		rope_velocities.append(Vector2.ZERO)
	
	is_setup = true
	visible = true
	
	if rope_line:
		rope_line.visible = true
	
	print("Top-rope setup: ", rope_points.size(), " segments")
	print("  Belayer hand: ", belayer_hand)
	print("  Anchor: ", anchor_position)
	print("  Player: ", player_chest)

func find_top_anchor() -> Vector2:
	"""Find anchor point at top of wall"""
	var highest_y = player.global_position.y
	
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.global_position.y < highest_y:
			highest_y = hold.global_position.y
	
	return Vector2(belayer_position.x, highest_y - 60.0)

func get_player_chest_position() -> Vector2:
	if player:
		return player.global_position + player_attach_offset
	return belayer_position + Vector2(0, 100)

func get_belayer_hand_position() -> Vector2:
	var side_mult = 1.0 if belayer_facing_right else -1.0
	
	var hand_offset = Vector2(
		SHOULDER_OFFSET * side_mult + (12.0 * side_mult),
		HEAD_OFFSET + 9.0 - 5.0 + guide_hand_pull
	)
	
	return belayer_position + hand_offset

func simulate_rope_physics(delta: float):
	"""Smooth rope physics with natural curves - PURELY VISUAL"""
	if rope_points.size() < 3 or not player:
		return
	
	var belayer_hand = get_belayer_hand_position()
	var player_chest = get_player_chest_position()
	
	# Apply gravity to create natural droop
	for i in range(1, rope_points.size() - 1):
		rope_velocities[i].y += GRAVITY * delta
		rope_velocities[i] *= SEGMENT_DRAG
	
	# Apply velocities
	for i in range(1, rope_points.size() - 1):
		rope_points[i] += rope_velocities[i] * delta
	
	# Calculate rope tension for visual feedback
	rope_tension = 0.0
	
	# Constraint iterations to maintain rope structure
	for _iter in range(15):  # More iterations = straighter rope
		# Pin endpoints to belayer and player
		rope_points[0] = belayer_hand
		rope_points[rope_points.size() - 1] = player_chest
		
		# Find which point is closest to anchor (becomes the anchor point)
		var anchor_index = 0
		var min_dist = rope_points[0].distance_to(anchor_position)
		for i in range(1, rope_points.size()):
			var dist = rope_points[i].distance_to(anchor_position)
			if dist < min_dist:
				min_dist = dist
				anchor_index = i
		
		# Pin anchor point
		rope_points[anchor_index] = anchor_position
		
		# Calculate segment lengths for two sections
		var up_segment_count = anchor_index
		var down_segment_count = rope_points.size() - anchor_index - 1
		
		var up_distance = belayer_hand.distance_to(anchor_position)
		var down_distance = anchor_position.distance_to(player_chest)
		
		var up_segment_length = up_distance / max(1.0, float(up_segment_count))
		var down_segment_length = down_distance / max(1.0, float(down_segment_count))
		
		# Enforce segment lengths - up section
		for i in range(up_segment_count):
			var p1 = rope_points[i]
			var p2 = rope_points[i + 1]
			var delta_pos = p2 - p1
			var distance = delta_pos.length()
			
			if distance < 0.1:
				continue
			
			var correction = (distance - up_segment_length) * ROPE_STIFFNESS
			var correction_vector = delta_pos.normalized() * correction * 0.5
			
			if i > 0:
				rope_points[i] += correction_vector
			if i + 1 < rope_points.size() - 1 and i + 1 != anchor_index:
				rope_points[i + 1] -= correction_vector
		
		# Enforce segment lengths - down section
		for i in range(anchor_index, rope_points.size() - 1):
			var p1 = rope_points[i]
			var p2 = rope_points[i + 1]
			var delta_pos = p2 - p1
			var distance = delta_pos.length()
			
			if distance < 0.1:
				continue
			
			var correction = (distance - down_segment_length) * ROPE_STIFFNESS
			var correction_vector = delta_pos.normalized() * correction * 0.5
			
			if i != anchor_index:
				rope_points[i] += correction_vector
			if i + 1 < rope_points.size() - 1:
				rope_points[i + 1] -= correction_vector
	
	# Update facing based on player position
	var target_facing = player_chest.x > anchor_position.x
	if target_facing != belayer_facing_right:
		belayer_facing_right = target_facing
	
	# Smooth the rope to remove sharp angles
	smooth_rope_points()

func smooth_rope_points():
	"""Smooth rope points to create gradual curves instead of sharp angles"""
	if rope_points.size() < 3:
		return
	
	# Create smoothed copy
	var smoothed = rope_points.duplicate()
	
	# Apply Catmull-Rom smoothing (skip first and last points)
	for i in range(1, rope_points.size() - 1):
		# Skip anchor point - keep it fixed
		var is_anchor = rope_points[i].distance_to(anchor_position) < 5.0
		if is_anchor:
			continue
		
		# Average with neighbors for smooth curve
		var prev = rope_points[i - 1]
		var curr = rope_points[i]
		var next = rope_points[i + 1]
		
		# Weighted average: 20% prev, 60% curr, 20% next
		smoothed[i] = prev * 0.2 + curr * 0.6 + next * 0.2
	
	# Apply smoothing (keep endpoints and anchor fixed)
	for i in range(1, rope_points.size() - 1):
		var is_anchor = rope_points[i].distance_to(anchor_position) < 5.0
		if not is_anchor:
			rope_points[i] = smoothed[i]

func update_rope_visual():
	if not rope_line or rope_points.size() < 2:
		return
	
	var points = PackedVector2Array()
	for point in rope_points:
		points.append(point)
	
	rope_line.points = points
	rope_line.width = rope_thickness

func update_belayer_animation(delta: float):
	"""Animate belayer - minimal movement"""
	# Slight lean
	var target_lean = 0.0
	if not belayer_facing_right:
		target_lean *= -1
	belayer_lean = lerp(belayer_lean, target_lean, LEAN_SPEED * delta)
	
	# Minimal hand movement
	var pull_motion = sin(Time.get_ticks_msec() * 0.004) * 2.0
	guide_hand_pull = lerp(guide_hand_pull, pull_motion, ARM_SPEED * delta)

func _draw():
	"""Draw realistic belayer matching player style"""
	if not is_setup:
		return
	
	var b = to_local(belayer_position)
	var black = Color.BLACK
	var skin  = Color(0.9, 0.75, 0.6)
	var shirt = Color(0.25, 0.45, 0.75)
	var pant  = Color(0.2, 0.2, 0.35)
	var shoe  = Color(0.15, 0.1, 0.1)
	var lw    = 4.0

	# sm: +1 = facing right (wall is to the right of belayer)
	# All offsets are expressed as "toward wall" (sm) or "away from wall" (-sm)
	# This means the same code works for both directions — no if/else needed.
	var sm = 1.0 if belayer_facing_right else -1.0

	# ── Body anchor points ────────────────────────────────────────────────
	var head_c  = b + Vector2(sm * 3,  HEAD_OFFSET)          # head tilted toward wall
	var neck    = b + Vector2(sm * 1,  HEAD_OFFSET + 12)
	var hips_c  = b + Vector2(0,       HIP_DOWN)

	var near_shoulder = neck    + Vector2( sm * SHOULDER_OFFSET,  2)  # toward wall
	var far_shoulder  = neck    + Vector2(-sm * SHOULDER_OFFSET,  2)  # away from wall
	var near_hip      = hips_c  + Vector2( sm * HIP_OFFSET,       0)
	var far_hip       = hips_c  + Vector2(-sm * HIP_OFFSET,       0)

	# ── LEGS (far leg drawn first = behind) ───────────────────────────────
	var far_knee  = b + Vector2(-sm * (HIP_OFFSET + 2),  HIP_DOWN + LEG_UPPER_LENGTH * 0.50)
	var far_foot  = b + Vector2(-sm * (HIP_OFFSET + 3),  HIP_DOWN + LEG_UPPER_LENGTH + LEG_LOWER_LENGTH * 0.50)

	var near_knee = b + Vector2( sm * (HIP_OFFSET + 5),  HIP_DOWN + LEG_UPPER_LENGTH * 0.55)
	var near_foot = b + Vector2( sm * (HIP_OFFSET + 9),  HIP_DOWN + LEG_UPPER_LENGTH + LEG_LOWER_LENGTH * 0.55)

	draw_line(far_hip,   far_knee,   pant, lw + 1)
	draw_line(far_knee,  far_foot,   pant, lw)
	draw_circle(far_foot, 7, shoe)

	draw_line(near_hip,  near_knee,  pant, lw + 1)
	draw_line(near_knee, near_foot,  pant, lw)
	draw_circle(near_foot, 7, shoe)

	# ── TORSO ─────────────────────────────────────────────────────────────
	draw_line(neck,          hips_c,       shirt, lw + 2)
	draw_line(near_hip,      far_hip,      pant,  lw)
	draw_line(near_shoulder, far_shoulder, shirt, lw)

	# ── ARMS ──────────────────────────────────────────────────────────────
	# Guide hand (near/toward-wall arm): reaches UP toward the rope coming from anchor
	var guide_elbow = near_shoulder + Vector2( sm * 10,  -6 + guide_hand_pull * 0.4)
	var guide_hand  = near_shoulder + Vector2( sm * 20,  -14 + guide_hand_pull)

	# Brake hand (far arm): points DOWN to lock off the rope
	var brake_elbow = far_shoulder + Vector2(-sm * 6,   14)
	var brake_hand  = far_shoulder + Vector2(-sm * 10,  26)

	# Brake arm behind torso
	draw_line(far_shoulder,  brake_elbow, shirt, lw)
	draw_line(brake_elbow,   brake_hand,  skin,  lw - 1)
	draw_circle(brake_hand, 5, skin)

	# Guide arm in front
	draw_line(near_shoulder, guide_elbow, shirt, lw)
	draw_line(guide_elbow,   guide_hand,  skin,  lw - 1)
	draw_circle(guide_hand, 5, skin)

	# ── BELAY DEVICE (ATC) ────────────────────────────────────────────────
	var device_pos = guide_hand + Vector2(sm * 2, 5)
	draw_rect(Rect2(device_pos - Vector2(4, 3), Vector2(8, 6)), Color(0.4, 0.4, 0.4))
	draw_rect(Rect2(device_pos - Vector2(4, 3), Vector2(8, 6)), black, false, 1.5)

	# ── HARNESS hint ──────────────────────────────────────────────────────
	draw_arc(hips_c, 11, 0, PI, 12, Color(0.9, 0.7, 0.1), 3)

	# ── HEAD ──────────────────────────────────────────────────────────────
	draw_circle(head_c, 12, skin)
	# Helmet (top half arc + brim line)
	draw_arc(head_c, 13, PI, 2 * PI, 14, Color(0.8, 0.3, 0.1), 4)
	draw_line(head_c + Vector2(-13, 0), head_c + Vector2(13, 0), Color(0.8, 0.3, 0.1), 3)
	# Eye toward wall
	draw_circle(head_c + Vector2(sm * 5, 1), 2, black)

	# ── ANCHOR ────────────────────────────────────────────────────────────
	var anchor_local = to_local(anchor_position)
	draw_circle(anchor_local, 8, black)
	draw_circle(anchor_local, 6, Color.WHITE)
	draw_circle(anchor_local, 4, black)

func cleanup():
	if rope_line:
		rope_line.queue_free()
	queue_free()
