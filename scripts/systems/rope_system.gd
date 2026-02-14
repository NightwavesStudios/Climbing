extends Node2D
class_name RopeSystem

## Physics-based rope system for roped climbing - FINAL VERSION

@export var rope_color := Color.BLACK
@export var rope_thickness := 2.5

# Rope physics constants - FIXED to prevent infinite droop
const ROPE_LENGTH := 450.0  # Absolute maximum rope length
const ROPE_SEGMENTS := 10  # Fewer segments = more stable
const ROPE_STIFFNESS := 0.99  # Very stiff
const ROPE_DAMPING := 0.99
const ROPE_MAX_STRETCH := 1.02  # Only 2% stretch
const GRAVITY := 400.0  # Less gravity on rope
const SEGMENT_DRAG := 0.99

# Belayer settings
var belayer_position: Vector2 = Vector2.ZERO

# Belayer drawing constants (more realistic proportions)
const ARM_UPPER_LENGTH := 42.0
const ARM_LOWER_LENGTH := 42.0
const LEG_UPPER_LENGTH := 48.0
const LEG_LOWER_LENGTH := 48.0
const SHOULDER_OFFSET := 11.0
const HIP_OFFSET := 9.0
const HIP_DOWN := 20.0
const HEAD_OFFSET := -20.0

# Rope state
var rope_points: Array[Vector2] = []
var rope_velocities: Array[Vector2] = []
var current_rope_length: float = ROPE_LENGTH
var rope_tension: float = 0.0
var is_setup: bool = false

# Player reference
var player: Node2D = null
var player_attach_offset: Vector2 = Vector2(0, -5)  # Chest attachment

# Visual rope line
var rope_line: Line2D = null

func _ready():
	global_position = Vector2.ZERO
	z_index = 50
	set_process(true)
	
	# Create Line2D for rope visualization
	rope_line = Line2D.new()
	rope_line.width = rope_thickness
	rope_line.default_color = rope_color
	rope_line.z_index = 49
	rope_line.top_level = true
	rope_line.antialiased = true
	add_child(rope_line)
	
	print("RopeSystem: Ready")

func _process(delta):
	if not is_setup:
		return
	
	if player and rope_points.size() == ROPE_SEGMENTS:
		simulate_rope(delta)
		update_rope_visual()
	
	# Always redraw belayer
	queue_redraw()

func setup_rope(belayer_pos: Vector2, player_node: Node2D):
	"""Initialize rope system"""
	belayer_position = belayer_pos
	player = player_node
	
	print("RopeSystem: Setup starting")
	print("  Belayer: ", belayer_position)
	print("  Player: ", player.global_position if player else "NONE")
	
	# Only initialize rope points if not already setup
	if rope_points.size() == 0:
		rope_points.clear()
		rope_velocities.clear()
		
		var player_pos = player.global_position + player_attach_offset if player else belayer_position + Vector2(0, 100)
		
		# Initialize rope segments in straight line
		for i in range(ROPE_SEGMENTS):
			var t = float(i) / float(ROPE_SEGMENTS - 1)
			rope_points.append(belayer_position.lerp(player_pos, t))
			rope_velocities.append(Vector2.ZERO)
		
		# Set initial rope length to ACTUAL distance (clamped)
		var actual_distance = belayer_position.distance_to(player_pos)
		current_rope_length = min(actual_distance, ROPE_LENGTH)
		
		print("  Initial rope length: ", current_rope_length)
	
	is_setup = true
	visible = true
	
	if rope_line:
		rope_line.visible = true
	
	update_rope_visual()
	
	print("RopeSystem: Setup complete")

func simulate_rope(delta: float):
	"""Update rope physics - FIXED to prevent infinite stretch"""
	if rope_points.size() != ROPE_SEGMENTS or not player:
		return
	
	var player_pos = player.global_position + player_attach_offset
	var actual_distance = belayer_position.distance_to(player_pos)
	
	# CRITICAL FIX: Rope length CANNOT exceed maximum
	if actual_distance > ROPE_LENGTH:
		# Player is beyond rope limit - enforce hard constraint
		var direction = (belayer_position - player_pos).normalized()
		var excess = actual_distance - ROPE_LENGTH
		
		# Apply strong corrective force to player
		if player.has_method("get") and player.get("com_velocity") != null:
			# Pull player back toward belayer
			var pull_force = direction * excess * 15.0
			player.com_velocity += pull_force * delta
		
		actual_distance = ROPE_LENGTH
		player_pos = belayer_position + (player_pos - belayer_position).normalized() * ROPE_LENGTH
	
	# Set rope length to EXACT distance (no slack, no stretch)
	current_rope_length = actual_distance
	
	# Apply minimal gravity to middle segments only
	for i in range(1, ROPE_SEGMENTS - 1):
		# Less gravity = less droop
		rope_velocities[i].y += GRAVITY * delta * 0.15
		rope_velocities[i] *= SEGMENT_DRAG
		rope_points[i] += rope_velocities[i] * delta
	
	rope_tension = 0.0
	
	# Many constraint iterations for very stiff rope
	for _iter in range(12):
		# Pin endpoints
		rope_points[0] = belayer_position
		rope_points[ROPE_SEGMENTS - 1] = player_pos
		
		# Calculate exact segment length
		var segment_length = current_rope_length / float(ROPE_SEGMENTS - 1)
		
		# Enforce distance constraints strictly
		for i in range(ROPE_SEGMENTS - 1):
			var p1 = rope_points[i]
			var p2 = rope_points[i + 1]
			var delta_pos = p2 - p1
			var distance = delta_pos.length()
			
			if distance < 0.1:
				continue
			
			var stretch_ratio = distance / segment_length
			rope_tension = max(rope_tension, (stretch_ratio - 1.0) * 20.0)
			
			# VERY strict: Do not allow ANY stretch
			var max_distance = segment_length * ROPE_MAX_STRETCH
			if distance > max_distance:
				distance = max_distance
			
			var correction = (distance - segment_length) * ROPE_STIFFNESS
			var correction_vector = delta_pos.normalized() * correction * 0.5
			
			# Apply corrections only to middle segments
			if i > 0 and i < ROPE_SEGMENTS - 1:
				rope_points[i] += correction_vector
				rope_velocities[i] += correction_vector * 0.03
			if i + 1 < ROPE_SEGMENTS - 1:
				rope_points[i + 1] -= correction_vector
				rope_velocities[i + 1] -= correction_vector * 0.03
	
	rope_tension *= ROPE_DAMPING

func update_rope_visual():
	"""Update the Line2D to match rope physics"""
	if not rope_line or rope_points.size() < 2:
		return
	
	var points = PackedVector2Array()
	for point in rope_points:
		points.append(point)
	
	rope_line.points = points
	rope_line.width = rope_thickness

func get_rope_tension() -> float:
	return clamp(rope_tension, 0.0, 1.0)

func is_rope_taut() -> bool:
	return rope_tension > 0.5

func apply_rope_force_to_player(player_velocity: Vector2) -> Vector2:
	"""Calculate rope force affecting player - ENFORCES hard limit"""
	if rope_points.size() < 2 or not player:
		return player_velocity
	
	var player_pos = player.global_position + player_attach_offset
	var distance_to_belayer = belayer_position.distance_to(player_pos)
	
	# CRITICAL: If at rope limit, prevent further movement away
	if distance_to_belayer >= ROPE_LENGTH * 0.99:
		var to_belayer = (belayer_position - player_pos).normalized()
		var velocity_away = player_velocity.dot(-to_belayer)
		
		if velocity_away > 0:
			# Moving away from belayer - STOP IT
			var resistance = -to_belayer * velocity_away * 0.95
			return player_velocity + resistance
	
	return player_velocity

func _draw():
	"""Draw realistic belayer with proper stance"""
	if not is_setup:
		return
	
	# Convert belayer position to local coordinates
	var b = to_local(belayer_position)
	
	var black = Color.BLACK
	var line_width = 4.0
	
	# Head
	draw_circle(b + Vector2(0, HEAD_OFFSET), 10, black)
	
	# Torso
	var neck = b + Vector2(0, HEAD_OFFSET + 10)
	var hips = b + Vector2(0, HIP_DOWN)
	draw_line(neck, hips, black, line_width)
	
	# REALISTIC BELAYING STANCE
	# Belayer facing right, rope in proper position
	
	# Right hand (brake hand) - down and behind hip
	var right_shoulder = b + Vector2(SHOULDER_OFFSET, 0)
	var right_elbow = b + Vector2(SHOULDER_OFFSET + 6, 18)
	var right_hand = b + Vector2(SHOULDER_OFFSET + 8, 38)  # Low brake position
	
	# Left hand (guide hand) - up near rope, controlling slack
	var left_shoulder = b + Vector2(-SHOULDER_OFFSET, 0)
	var left_elbow = b + Vector2(-SHOULDER_OFFSET - 12, -5)
	var left_hand = b + Vector2(-SHOULDER_OFFSET - 16, -8)  # At rope level
	
	# Draw arms with proper thickness
	draw_line(left_shoulder, left_elbow, black, line_width)
	draw_line(left_elbow, left_hand, black, line_width - 1)
	draw_line(right_shoulder, right_elbow, black, line_width)
	draw_line(right_elbow, right_hand, black, line_width - 1)
	
	# Legs - athletic stance (slightly bent, stable)
	var left_hip = b + Vector2(-HIP_OFFSET, HIP_DOWN)
	var right_hip = b + Vector2(HIP_OFFSET, HIP_DOWN)
	
	# Bent knees for proper belay stance
	var left_knee = b + Vector2(-HIP_OFFSET - 2, HIP_DOWN + 26)
	var left_foot = b + Vector2(-HIP_OFFSET - 4, HIP_DOWN + 52)
	
	var right_knee = b + Vector2(HIP_OFFSET + 2, HIP_DOWN + 26)
	var right_foot = b + Vector2(HIP_OFFSET + 4, HIP_DOWN + 52)
	
	draw_line(left_hip, left_knee, black, line_width)
	draw_line(left_knee, left_foot, black, line_width - 1)
	draw_line(right_hip, right_knee, black, line_width)
	draw_line(right_knee, right_foot, black, line_width - 1)
	
	# Hands (clean circles)
	draw_circle(left_hand, 4, black)
	draw_circle(right_hand, 4, black)
	
	# Feet (slightly larger for stability)
	draw_circle(left_foot, 5, black)
	draw_circle(right_foot, 5, black)
	
	# Rope connection - from left (guide) hand to rope start
	var rope_start = to_local(belayer_position)
	draw_line(left_hand, rope_start, black, 2.0)
	
	# Belt/Harness indicator (optional detail)
	draw_line(b + Vector2(-HIP_OFFSET, HIP_DOWN), b + Vector2(HIP_OFFSET, HIP_DOWN), black, 3.0)

func cleanup():
	"""Clean up"""
	print("RopeSystem: Cleanup called")
	if rope_line:
		rope_line.queue_free()
	queue_free()
