extends Node2D
class_name DynamicWall

# =============================================================================
# ENVIRONMENT COLORS
# =============================================================================
var gym_wall_color := Color(0.82, 0.75, 0.62)
var granite_wall_color := Color(0.5, 0.5, 0.55)
var background_color := Color(0.53, 0.81, 0.92)

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

# Wall padding constants
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
	z_index = -10
	add_to_group("environment_walls")
	call_deferred("update_environment_settings")

# =============================================================================
# DRAW
# =============================================================================
func _draw():
	if not wall_valid:
		return
	
	var bg_min = wall_min - Vector2(BACKGROUND_EXPANSION, BACKGROUND_EXPANSION)
	var bg_max = wall_max + Vector2(BACKGROUND_EXPANSION, BACKGROUND_EXPANSION)
	draw_rect(Rect2(bg_min, bg_max - bg_min), background_color, true)
	
	var wall_size = wall_max - wall_min
	
	if wall_texture_enabled:
		draw_textured_wall(wall_min, wall_size)
	else:
		draw_rect(Rect2(wall_min, wall_size), current_wall_color, true)
	
	if show_bolt_holes and not is_granite:
		draw_bolt_holes(wall_min, wall_max)
	
	if is_granite:
		draw_granite_texture()
	
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
			
			# Clamp tile to wall bounds
			var tile_rect = Rect2(Vector2(px, py), Vector2(tile, tile))
			var wall_rect = Rect2(wall_min, wall_max - wall_min)
			var clipped_rect = tile_rect.intersection(wall_rect)
			
			if clipped_rect.has_area():
				draw_rect(clipped_rect,
					Color(current_wall_color.r + v,
						  current_wall_color.g + v,
						  current_wall_color.b + v,
						  current_wall_color.a))

# =============================================================================
# BOLT HOLES - FIXED TO CLIP AT WALL EDGES
# =============================================================================
func draw_bolt_holes(start_pos: Vector2, end_pos: Vector2):
	# Apply strict margin to keep holes away from edges
	var margin = 15.0
	var draw_min_x = start_pos.x + margin
	var draw_max_x = end_pos.x - margin
	var draw_min_y = start_pos.y + margin
	var draw_max_y = end_pos.y - margin
	
	var sx = floor(draw_min_x / hole_spacing.x) * hole_spacing.x
	var sy = floor(draw_min_y / hole_spacing.y) * hole_spacing.y
	var ex = ceil(draw_max_x / hole_spacing.x) * hole_spacing.x
	var ey = ceil(draw_max_y / hole_spacing.y) * hole_spacing.y
	
	var x = sx
	while x <= ex:
		var y = sy
		while y <= ey:
			var seed := int(x / hole_spacing.x) + int(y / hole_spacing.y) * 1000
			var jitter := Vector2(
				(hash_to_float(seed) - 0.5) * hole_jitter,
				(hash_to_float(seed + 1) - 0.5) * hole_jitter
			)
			var hole_pos = Vector2(x, y) + jitter
			
			# Only draw if strictly within wall bounds (with margin)
			if hole_pos.x >= draw_min_x and hole_pos.x <= draw_max_x and \
			   hole_pos.y >= draw_min_y and hole_pos.y <= draw_max_y:
				draw_circle(hole_pos, hole_radius, hole_color)
			y += hole_spacing.y
		x += hole_spacing.x

# =============================================================================
# GRANITE TEXTURE - FIXED TO CLIP AT WALL EDGES
# =============================================================================
func draw_granite_texture():
	var wall_size = wall_max - wall_min
	var rng_seed = int(wall_min.x + wall_min.y)
	var num_cracks = int(wall_size.x / 200.0) + 2
	
	for i in range(num_cracks):
		var x_offset = (float(i) / num_cracks) * wall_size.x
		var x_pos = wall_min.x + x_offset + (hash(rng_seed + i) % 50 - 25)
		
		# Clamp crack lines to wall boundaries
		var start_y = max(wall_min.y, wall_min.y)
		var end_y = min(wall_max.y, wall_max.y)
		
		# Only draw if within wall bounds
		if x_pos >= wall_min.x and x_pos <= wall_max.x:
			draw_line(Vector2(x_pos, start_y),
					  Vector2(x_pos, end_y),
					  Color(0.45, 0.43, 0.4, 0.3),
					  2.0)

# =============================================================================
# EDGE RENDERING
# =============================================================================
func draw_edges():
	draw_line(wall_min, Vector2(wall_min.x, wall_max.y), edge_color.darkened(0.3), edge_thickness)
	draw_line(Vector2(wall_max.x, wall_min.y), wall_max, edge_color.darkened(0.3), edge_thickness)
	draw_line(wall_min, Vector2(wall_max.x, wall_min.y), edge_color, 4.0)
	draw_line(Vector2(wall_min.x, wall_max.y), wall_max, edge_color.darkened(0.3), 6.0)

# =============================================================================
# ENVIRONMENT SYSTEM
# =============================================================================
func update_environment_settings():
	var env_config := get_node_or_null("/root/EnvironmentConfig")
	if env_config == null:
		call_deferred("update_environment_settings")
		return
	
	if env_config.has_method("get_current_environment_name"):
		set_environment_by_name(env_config.get_current_environment_name())
	elif env_config.has_method("get_current_environment"):
		var env_id = env_config.get_current_environment()
		is_granite = (env_id == 1)
		set_environment_by_name("granite" if is_granite else "gym")
	else:
		set_environment_by_name("gym")

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
			current_wall_color = gym_wall_color
			show_bolt_holes = true
			is_granite = false
	queue_redraw()

# =============================================================================
# BOUNDS MANAGEMENT
# =============================================================================
func calculate_bounds_from_holds(holds_container: Node2D):
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
	
	wall_min = Vector2(min_x - WALL_PADDING_SIDES, min_y - WALL_PADDING_TOP)
	wall_max = Vector2(max_x + WALL_PADDING_SIDES, max_y + WALL_PADDING_BOTTOM)
	wall_valid = true
	
	if is_granite:
		_create_granite_top_edge(holds_container)
	
	queue_redraw()

func _create_granite_top_edge(holds_container: Node2D):
	for child in get_children():
		if child.has_meta("is_top_edge_hold"):
			child.queue_free()
	
	var top_hold = Area2D.new()
	top_hold.set_meta("is_top_edge_hold", true)
	top_hold.collision_layer = 2
	top_hold.collision_mask = 0
	top_hold.name = "TopEdgeHold"

	var shape = RectangleShape2D.new()
	shape.extents = Vector2((wall_max.x - wall_min.x)/2, 25)
	var collision = CollisionShape2D.new()
	collision.shape = shape
	top_hold.add_child(collision)

	var hold_point = Marker2D.new()
	hold_point.name = "HoldPoint"
	hold_point.position = Vector2(0, 0)
	top_hold.add_child(hold_point)

	top_hold.global_position = Vector2((wall_min.x + wall_max.x)/2, wall_min.y)

	add_child.call_deferred(top_hold)
	top_hold.add_to_group("holds")
	call_deferred("_assign_top_hold_script", top_hold)

func _assign_top_hold_script(top_hold):
	var script_code = """
extends Area2D
var claimed_left_hand: Node2D = null
var claimed_right_hand: Node2D = null
var left_hand_x: float = 0.0
var right_hand_x: float = 0.0

func is_start_hold() -> bool: return false
func is_top_out() -> bool: return true
func is_crimp() -> bool: return false
func is_sloper() -> bool: return false
func is_pocket() -> bool: return false
func is_foothold() -> bool: return false

func can_grab(limb: Node2D, is_foot: bool) -> bool:
	if is_foot: return false
	return true

func try_claim(limb: Node2D, is_foot: bool, snap_pos: Vector2) -> bool:
	if not can_grab(limb, is_foot): return false
	
	var limb_name = limb.name
	if limb_name == 'LeftHand':
		claimed_left_hand = limb
		left_hand_x = snap_pos.x
	elif limb_name == 'RightHand':
		claimed_right_hand = limb
		right_hand_x = snap_pos.x
	
	return true

func release(limb: Node2D) -> void:
	var limb_name = limb.name
	if limb_name == 'LeftHand' and claimed_left_hand == limb:
		claimed_left_hand = null
		left_hand_x = 0.0
	elif limb_name == 'RightHand' and claimed_right_hand == limb:
		claimed_right_hand = null
		right_hand_x = 0.0

func get_limb_anchor(limb: Node2D) -> Vector2:
	var limb_name = limb.name
	var x_pos = limb.global_position.x
	
	if limb_name == 'LeftHand' and claimed_left_hand == limb:
		x_pos = left_hand_x
	elif limb_name == 'RightHand' and claimed_right_hand == limb:
		x_pos = right_hand_x
	
	return Vector2(x_pos, global_position.y)

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

# =============================================================================
# MANUAL BOUNDS
# =============================================================================
func set_bounds(min_pos: Vector2, max_pos: Vector2):
	wall_min = min_pos
	wall_max = max_pos
	wall_valid = true
	queue_redraw()

func get_bounds() -> Dictionary:
	return {"min": wall_min, "max": wall_max, "valid": wall_valid}

# =============================================================================
# WALL QUERIES
# =============================================================================
func is_position_on_wall(pos: Vector2) -> bool:
	if not wall_valid: return false
	return pos.x >= wall_min.x and pos.x <= wall_max.x and pos.y >= wall_min.y and pos.y <= wall_max.y

func get_top_edge_y() -> float:
	return wall_min.y

func get_wall_height() -> float:
	return wall_max.y - wall_min.y

func get_wall_width() -> float:
	return wall_max.x - wall_min.x

# =============================================================================
# UTIL
# =============================================================================
func hash_to_float(v: int) -> float:
	return float(hash(v) % 10000) / 10000.0
