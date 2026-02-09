extends Node2D
class_name DynamicWall
## Renders a climbing wall with environment-based textures, bolt holes, and dynamic bounds

# =============================================================================
# ENVIRONMENT COLORS
# =============================================================================
var gym_wall_color := Color(0.82, 0.75, 0.62)
var granite_wall_color := Color(0.5, 0.5, 0.55)
var background_color := Color(0.53, 0.81, 0.92)  # Sky blue background

# =============================================================================
# TEXTURE SETTINGS
# =============================================================================
var wall_texture_enabled := true
var texture_variation := 0.05

# =============================================================================
# BOLT HOLE SETTINGS (GYM ONLY)
# =============================================================================
var hole_spacing := Vector2(64, 64)
var hole_radius := 2.5
var hole_color := Color(0.15, 0.15, 0.15)
var hole_jitter := 4.0

# =============================================================================
# EDGE SETTINGS
# =============================================================================
var edge_color := Color(0.2, 0.2, 0.25)
var edge_thickness := 8.0

# =============================================================================
# WALL BOUNDS
# =============================================================================
var wall_min := Vector2.ZERO
var wall_max := Vector2.ZERO
var wall_valid := false

# Wall padding constants (match level editor)
const WALL_PADDING_TOP = 100.0
const WALL_PADDING_BOTTOM = 150.0
const WALL_PADDING_SIDES = 100.0
const BACKGROUND_EXPANSION = 2000.0

# =============================================================================
# CURRENT STATE
# =============================================================================
var current_wall_color: Color = gym_wall_color
var show_bolt_holes: bool = true
var is_granite := false
var current_environment: String = "gym"

# =============================================================================
# LIFECYCLE
# =============================================================================
func _ready():
	z_index = -10  # Behind holds
	add_to_group("environment_walls")
	update_environment_settings()

# =============================================================================
# DRAW
# =============================================================================
func _draw():
	if not wall_valid:
		return
	
	# Always draw background first (blue sky/void beyond wall)
	var bg_min = wall_min - Vector2(BACKGROUND_EXPANSION, BACKGROUND_EXPANSION)
	var bg_max = wall_max + Vector2(BACKGROUND_EXPANSION, BACKGROUND_EXPANSION)
	draw_rect(
		Rect2(bg_min, bg_max - bg_min),
		background_color,
		true
	)
	
	var wall_size = wall_max - wall_min
	
	# Draw textured wall surface (ONLY within bounds)
	if wall_texture_enabled:
		draw_textured_wall(wall_min, wall_size)
	else:
		draw_rect(Rect2(wall_min, wall_size), current_wall_color, true)
	
	# Draw bolt holes (gym only, ONLY within bounds)
	if show_bolt_holes and not is_granite:
		draw_bolt_holes(wall_min, wall_max)
	
	# Draw granite texture if needed (ONLY within bounds)
	if is_granite:
		draw_granite_texture()
	
	# Draw edge lines for depth
	draw_edges()

# =============================================================================
# WALL TEXTURE
# =============================================================================
func draw_textured_wall(start_pos: Vector2, size: Vector2):
	var tile := 128.0
	var cols := int(ceil(size.x / tile)) + 1
	var rows := int(ceil(size.y / tile)) + 1
	
	var gx = floor(start_pos.x / tile) * tile
	var gy = floor(start_pos.y / tile) * tile
	
	for x in cols:
		for y in rows:
			var px = gx + x * tile
			var py = gy + y * tile
			
			var seed := int(px / tile) + int(py / tile) * 1000
			var v := (hash_to_float(seed) - 0.5) * texture_variation
			
			draw_rect(
				Rect2(Vector2(px, py), Vector2(tile, tile)),
				Color(
					current_wall_color.r + v,
					current_wall_color.g + v,
					current_wall_color.b + v,
					current_wall_color.a
				)
			)

# =============================================================================
# BOLT HOLES
# =============================================================================
func draw_bolt_holes(start_pos: Vector2, end_pos: Vector2):
	var sx = floor(start_pos.x / hole_spacing.x) * hole_spacing.x
	var sy = floor(start_pos.y / hole_spacing.y) * hole_spacing.y
	var ex = ceil(end_pos.x / hole_spacing.x) * hole_spacing.x
	var ey = ceil(end_pos.y / hole_spacing.y) * hole_spacing.y
	
	var x = sx
	while x <= ex:
		var y = sy
		while y <= ey:
			var seed := int(x / hole_spacing.x) + int(y / hole_spacing.y) * 1000
			var jitter := Vector2(
				(hash_to_float(seed) - 0.5) * hole_jitter,
				(hash_to_float(seed + 1) - 0.5) * hole_jitter
			)
			
			draw_circle(Vector2(x, y) + jitter, hole_radius, hole_color)
			y += hole_spacing.y
		x += hole_spacing.x

# =============================================================================
# GRANITE TEXTURE
# =============================================================================
func draw_granite_texture():
	"""Draw subtle texture lines to suggest granite surface"""
	var wall_size = wall_max - wall_min
	
	# Random-ish vertical cracks
	var rng_seed = int(wall_min.x + wall_min.y)
	var num_cracks = int(wall_size.x / 200.0) + 2
	
	for i in range(num_cracks):
		var x_offset = (float(i) / num_cracks) * wall_size.x
		var x_pos = wall_min.x + x_offset + (hash(rng_seed + i) % 50 - 25)
		
		# Vertical crack line
		draw_line(
			Vector2(x_pos, wall_min.y),
			Vector2(x_pos, wall_max.y),
			Color(0.45, 0.43, 0.4, 0.3),
			2.0
		)

# =============================================================================
# EDGE RENDERING
# =============================================================================
func draw_edges():
	"""Draw edge lines for depth"""
	# Left edge - darker shadow
	draw_line(
		wall_min,
		Vector2(wall_min.x, wall_max.y),
		edge_color.darkened(0.3),
		edge_thickness
	)
	
	# Right edge - darker shadow
	draw_line(
		Vector2(wall_max.x, wall_min.y),
		wall_max,
		edge_color.darkened(0.3),
		edge_thickness
	)
	
	# Top edge (this is the "top-out" line for granite)
	if is_granite:
		# Bright top-out line for granite
		var top_color = Color(0.9, 0.85, 0.7, 1.0)
		draw_line(
			wall_min,
			Vector2(wall_max.x, wall_min.y),
			top_color,
			12.0
		)
		# Add glow effect
		draw_line(
			wall_min + Vector2(0, -2),
			Vector2(wall_max.x, wall_min.y) + Vector2(0, -2),
			Color(1.0, 0.95, 0.8, 0.5),
			6.0
		)
	else:
		# Simple edge for gym
		draw_line(
			wall_min,
			Vector2(wall_max.x, wall_min.y),
			edge_color,
			4.0
		)
	
	# Bottom edge
	draw_line(
		Vector2(wall_min.x, wall_max.y),
		wall_max,
		edge_color.darkened(0.3),
		6.0
	)

# =============================================================================
# ENVIRONMENT SYSTEM
# =============================================================================
func update_environment_settings():
	var env_config := get_node_or_null("/root/EnvironmentConfig")
	
	if env_config:
		if env_config.has_method("get_current_environment_name"):
			set_environment_by_name(env_config.get_current_environment_name())
		elif env_config.has_method("get_current_environment"):
			var env_id = env_config.get_current_environment()
			is_granite = (env_id == 1)
			set_environment_by_name("granite" if is_granite else "gym")
	else:
		set_environment_by_name("gym")
		print("Wall: EnvironmentConfig not found, defaulting to gym")

func set_environment_by_name(env_name: String):
	current_environment = env_name.to_lower()
	
	match current_environment:
		"gym":
			current_wall_color = gym_wall_color
			show_bolt_holes = true
			is_granite = false
		"granite":
			current_wall_color = granite_wall_color
			show_bolt_holes = false
			is_granite = true
		_:
			print("Wall: Unknown environment:", env_name, "→ defaulting to gym")
			current_wall_color = gym_wall_color
			show_bolt_holes = true
			is_granite = false
	
	print("Wall: Environment set to", current_environment)
	queue_redraw()

func update_environment():
	"""Update wall appearance based on current environment"""
	update_environment_settings()

# =============================================================================
# BOUNDS MANAGEMENT
# =============================================================================
func calculate_bounds_from_holds(holds_container: Node2D):
	"""Calculate tight wall bounds from holds"""
	if not holds_container or holds_container.get_child_count() == 0:
		wall_valid = false
		queue_redraw()
		return
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for hold in holds_container.get_children():
		if not hold is Node2D:
			continue
		
		var pos = hold.global_position
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x)
		min_y = min(min_y, pos.y)
		max_y = max(max_y, pos.y)
	
	# Apply tight padding
	wall_min = Vector2(min_x - WALL_PADDING_SIDES, min_y - WALL_PADDING_TOP)
	wall_max = Vector2(max_x + WALL_PADDING_SIDES, max_y + WALL_PADDING_BOTTOM)
	
	wall_valid = true
	
	# For granite environment, create invisible top-out holds along the top edge
	if is_granite:
		_create_granite_top_edge(holds_container)
	
	queue_redraw()

func _create_granite_top_edge(holds_container: Node2D):
	"""Create invisible holds along the top edge for granite top-out"""
	# Remove old top edge holds if they exist
	for child in get_children():
		if child.has_meta("is_top_edge_hold"):
			child.queue_free()
	
	# Create holds every 100px along the top edge
	var spacing = 100.0
	var x = wall_min.x
	
	while x <= wall_max.x:
		var top_hold = Area2D.new()
		top_hold.set_meta("is_top_edge_hold", true)
		top_hold.collision_layer = 2
		top_hold.collision_mask = 0
		top_hold.name = "TopEdgeHold_" + str(int(x))
		
		# Add collision shape
		var shape = CircleShape2D.new()
		shape.radius = 25.0
		var collision = CollisionShape2D.new()
		collision.shape = shape
		top_hold.add_child(collision)
		
		# Add HoldPoint marker
		var hold_point = Marker2D.new()
		hold_point.name = "HoldPoint"
		top_hold.add_child(hold_point)
		
		# Position at top edge
		top_hold.global_position = Vector2(x, wall_min.y)
		
		# Add to scene first
		add_child(top_hold)
		top_hold.add_to_group("holds")
		
		# Set up the hold behavior using a simple script attached inline
		var script_code = """
extends Area2D

var claimed_limb: Node2D = null
var claimed_is_foot: bool = false

func is_start_hold() -> bool:
	return false

func is_top_out() -> bool:
	return true

func is_crimp() -> bool:
	return false

func is_sloper() -> bool:
	return false

func is_pocket() -> bool:
	return false

func is_foothold() -> bool:
	return false

func can_grab(limb: Node2D, is_foot: bool) -> bool:
	if is_foot:
		return false
	if claimed_limb != null and claimed_limb != limb:
		return false
	return true

func try_claim(limb: Node2D, is_foot: bool, snap_pos: Vector2) -> bool:
	if not can_grab(limb, is_foot):
		return false
	claimed_limb = limb
	claimed_is_foot = is_foot
	return true

func release(limb: Node2D) -> void:
	if claimed_limb == limb:
		claimed_limb = null
		claimed_is_foot = false

func get_limb_anchor(limb: Node2D) -> Vector2:
	var hold_point = get_node_or_null("HoldPoint")
	if hold_point:
		return hold_point.global_position
	return global_position

func get_state_pressure(delta: float, body_offset: float, static_time: float, 
						foot_support: float, limb: Node2D) -> float:
	return 0.5 * delta

func get_recovery_rate(delta: float, body_balance: float, foot_support: float) -> float:
	return 3.0 * delta * body_balance
"""
		
		var hold_script = GDScript.new()
		hold_script.source_code = script_code
		hold_script.reload()
		top_hold.set_script(hold_script)
		
		x += spacing
	
	print("Created ", int((wall_max.x - wall_min.x) / spacing) + 1, " granite top edge holds")

func set_bounds(min_pos: Vector2, max_pos: Vector2):
	"""Manually set wall bounds"""
	wall_min = min_pos
	wall_max = max_pos
	wall_valid = true
	queue_redraw()

func get_bounds() -> Dictionary:
	return {
		"min": wall_min,
		"max": wall_max,
		"valid": wall_valid
	}

# =============================================================================
# WALL QUERIES
# =============================================================================
func is_position_on_wall(pos: Vector2) -> bool:
	"""Check if a position is within the wall bounds"""
	if not wall_valid:
		return false
	
	return pos.x >= wall_min.x and pos.x <= wall_max.x \
		and pos.y >= wall_min.y and pos.y <= wall_max.y

func get_top_edge_y() -> float:
	"""Get the Y coordinate of the top edge (for top-out detection)"""
	return wall_min.y

func get_wall_height() -> float:
	"""Get the total height of the wall"""
	return wall_max.y - wall_min.y

func get_wall_width() -> float:
	"""Get the total width of the wall"""
	return wall_max.x - wall_min.x

# =============================================================================
# UTIL
# =============================================================================
func hash_to_float(v: int) -> float:
	return float(hash(v) % 10000) / 10000.0
