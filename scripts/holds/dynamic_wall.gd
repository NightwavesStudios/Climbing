extends Node2D
class_name DynamicWall
## Dynamic wall with click-to-select top edges

# =============================================================================
# ENVIRONMENT COLORS
# =============================================================================
var gym_wall_color := Color(0.82, 0.75, 0.62)
var granite_wall_color := Color(0.607, 0.607, 0.655, 1.0)
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
var top_edge_color := Color(0.9, 0.4, 0.2)  # Orange for top edges (EDITOR ONLY)

# =============================================================================
# WALL BOUNDS
# =============================================================================
var wall_min := Vector2.ZERO
var wall_max := Vector2.ZERO
var wall_valid := false

const WALL_PADDING_TOP = 100.0
const WALL_PADDING_BOTTOM = 150.0
const WALL_PADDING_SIDES = 100.0
const BACKGROUND_EXPANSION = 2000.0

# =============================================================================
# POLYGON EDITING
# =============================================================================
@export var use_polygon_mode: bool = false  ## Custom polygon vs auto-rectangle
@export var edit_mode: bool = false         ## Show draggable points
var control_points: Array[Vector2] = []

# Ground constraint - always exactly 2 bottom points at fixed Y
var ground_y: float = 0.0
var ground_left_index: int = -1
var ground_right_index: int = -1

# Top edges - USER SELECTED by clicking (not auto-detected)
var top_edge_indices: Array[int] = []  # Which edges are marked as "top out"

# Visual settings
var point_color := Color(0.7, 0.7, 0.7, 0.6)  # Subtle gray (always visible IN EDITOR)
var point_hover_color := Color(1, 0.7, 0, 1.0)
var point_drag_color := Color(1, 1, 0, 1.0)
var ground_point_color := Color(0.3, 0.8, 0.3, 0.8)
var line_color := Color(0.4, 0.7, 1.0, 0.6)
var edge_hover_color := Color(0.6, 0.9, 1.0, 0.8)

const POINT_RADIUS = 10.0
const POINT_GRAB_RADIUS = 20.0
const EDGE_CLICK_DISTANCE = 15.0

# Interaction state
var hovered_point: int = -1
var dragging_point: int = -1
var drag_offset: Vector2 = Vector2.ZERO
var hovered_edge: int = -1

# =============================================================================
# ENVIRONMENT STATE
# =============================================================================
var current_wall_color: Color = gym_wall_color
var show_bolt_holes: bool = true
var is_granite := false
var current_environment: String = "gym"

# NEW: Editor mode detection
var is_in_editor: bool = false  # Set by editor scene

# =============================================================================
# GROUND SETTINGS
# =============================================================================
var ground_enabled := true
var ground_height := 1000.0
var ground_color := Color(0.298, 0.298, 0.298, 1.0)

# =============================================================================
# LIFECYCLE
# =============================================================================
func _ready():
	z_index = -10
	add_to_group("environment_walls")
	call_deferred("update_environment_settings")

# =============================================================================
# EDITOR MODE
# =============================================================================
func set_editor_mode(enabled: bool):
	"""Called by LevelEditor to enable editor features"""
	is_in_editor = enabled
	print("DynamicWall: Editor mode set to ", enabled)
	queue_redraw()

# =============================================================================
# INPUT - Polygon Editing (EDITOR ONLY)
# =============================================================================
func _input(event: InputEvent):
	# ONLY process input in editor when edit mode is active
	if not is_in_editor or not edit_mode:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_start_drag()
			else:
				_end_drag()
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var mouse_pos = get_global_mouse_position()
			
			# Check if clicking on a point to remove it
			for i in range(control_points.size()):
				if i == ground_left_index or i == ground_right_index:
					continue
					
				if mouse_pos.distance_to(control_points[i]) < POINT_GRAB_RADIUS:
					remove_point(i)
					return
			
			# Check if clicking near an edge to add point OR toggle top edge
			if hovered_edge >= 0:
				# If CTRL/CMD/SHIFT held, toggle top edge
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_SHIFT):
					toggle_top_edge(hovered_edge)
				else:
					add_point_between_nearest_edge(mouse_pos)
	
	elif event is InputEventMouseMotion:
		if dragging_point >= 0:
			_update_drag()
		else:
			_update_hover()

# FIX: Better debug output and feedback
func toggle_top_edge(edge_index: int):
	"""Toggle whether an edge is marked as a top-out edge"""
	if _is_ground_edge(edge_index):
		print("❌ Cannot mark ground edge as top-out")
		return
	
	if edge_index in top_edge_indices:
		# Remove from top edges
		top_edge_indices.erase(edge_index)
		print("✓ Unmarked edge ", edge_index, " as top-out | Remaining: ", top_edge_indices)
	else:
		# Add to top edges
		top_edge_indices.append(edge_index)
		print("✓ Marked edge ", edge_index, " as top-out | All marked: ", top_edge_indices)
	
	# Recreate top edge holds
	_create_top_edge_holds()
	queue_redraw()

func _try_start_drag():
	var mouse_pos = get_global_mouse_position()
	
	for i in range(control_points.size()):
		var point = control_points[i]
		if mouse_pos.distance_to(point) < POINT_GRAB_RADIUS:
			dragging_point = i
			drag_offset = point - mouse_pos
			queue_redraw()
			return

func _update_drag():
	if dragging_point < 0 or dragging_point >= control_points.size():
		return
	
	var mouse_pos = get_global_mouse_position()
	var new_pos = mouse_pos + drag_offset
	
	# Ground points can only move horizontally
	if dragging_point == ground_left_index or dragging_point == ground_right_index:
		new_pos.y = ground_y
		
		if dragging_point == ground_left_index:
			var right_x = control_points[ground_right_index].x
			new_pos.x = min(new_pos.x, right_x - 50.0)
		else:
			var left_x = control_points[ground_left_index].x
			new_pos.x = max(new_pos.x, left_x + 50.0)
	
	control_points[dragging_point] = new_pos
	_update_bounds_from_polygon()
	
	# Recreate top edge holds if any are marked
	if not top_edge_indices.is_empty():
		_create_top_edge_holds()
	
	queue_redraw()

func _end_drag():
	dragging_point = -1
	queue_redraw()

func _update_hover():
	var mouse_pos = get_global_mouse_position()
	var old_hover_point = hovered_point
	var old_hover_edge = hovered_edge
	hovered_point = -1
	hovered_edge = -1
	
	for i in range(control_points.size()):
		var point = control_points[i]
		if mouse_pos.distance_to(point) < POINT_GRAB_RADIUS:
			hovered_point = i
			if old_hover_point != hovered_point or old_hover_edge != hovered_edge:
				queue_redraw()
			return
	
	for i in range(control_points.size()):
		if _is_ground_edge(i):
			continue
			
		var p1 = control_points[i]
		var p2 = control_points[(i + 1) % control_points.size()]
		
		var dist = _point_to_segment_distance(mouse_pos, p1, p2)
		if dist < EDGE_CLICK_DISTANCE:
			hovered_edge = i
			break
	
	if old_hover_point != hovered_point or old_hover_edge != hovered_edge:
		queue_redraw()

func _is_ground_edge(edge_index: int) -> bool:
	if ground_left_index < 0 or ground_right_index < 0:
		return false
	
	var next_index = (edge_index + 1) % control_points.size()
	
	return (edge_index == ground_left_index and next_index == ground_right_index) or \
		   (edge_index == ground_right_index and next_index == ground_left_index)

# =============================================================================
# DRAWING
# =============================================================================
func _draw():
	if not wall_valid:
		return
	
	# Background
	var bg_min = wall_min - Vector2(BACKGROUND_EXPANSION, BACKGROUND_EXPANSION)
	var bg_max = wall_max + Vector2(BACKGROUND_EXPANSION, BACKGROUND_EXPANSION)
	draw_rect(Rect2(bg_min, bg_max - bg_min), background_color, true)
	
	# Wall (polygon or rectangle)
	if use_polygon_mode and control_points.size() >= 3:
		_draw_polygon_wall()
	else:
		_draw_rectangle_wall()
	
	# Bolt holes (gym only)
	if show_bolt_holes and not is_granite:
		draw_bolt_holes(wall_min, wall_max)
	
	# Granite texture
	if is_granite:
		draw_granite_texture()
	
	# Ground
	if ground_enabled:
		_draw_ground()
	
	# Edges (with special color for top edges - EDITOR ONLY)
	draw_edges()
	
	# ONLY show control points in editor
	if is_in_editor and use_polygon_mode and control_points.size() > 0:
		_draw_control_points()
		
	# Only show edge highlights when editing
	if is_in_editor and edit_mode and use_polygon_mode:
		_draw_edge_highlights()

func _draw_rectangle_wall():
	var wall_size = wall_max - wall_min
	
	if wall_texture_enabled:
		draw_textured_wall(wall_min, wall_size)
	else:
		draw_rect(Rect2(wall_min, wall_size), current_wall_color, true)

func _draw_polygon_wall():
	var poly_points = PackedVector2Array(control_points)
	draw_colored_polygon(poly_points, current_wall_color)

# FIX: Much better visual feedback for edge selection
func _draw_edge_highlights():
	if hovered_edge < 0 or control_points.size() < 2:
		return
	
	if _is_ground_edge(hovered_edge):
		return
	
	var p1 = control_points[hovered_edge]
	var p2 = control_points[(hovered_edge + 1) % control_points.size()]
	
	# Show whether this edge is a top edge
	var color = edge_hover_color
	var label_text = "RIGHT-CLICK: Add point | SHIFT+RIGHT-CLICK: Mark as TOP-OUT"
	
	if hovered_edge in top_edge_indices:
		color = Color(1.0, 0.5, 0.0, 0.9)  # Orange if already marked
		label_text = "MARKED AS TOP-OUT | SHIFT+RIGHT-CLICK: Unmark"
	
	# Draw thick highlight
	draw_line(p1, p2, color, 8.0)
	
	# Draw hover indicator at mouse position
	var mouse_pos = get_global_mouse_position()
	var segment = p2 - p1
	var segment_length_sq = segment.length_squared()
	
	if segment_length_sq > 0:
		var t = clamp((mouse_pos - p1).dot(segment) / segment_length_sq, 0.0, 1.0)
		var nearest_point = p1 + t * segment
		draw_circle(nearest_point, 8.0, color)
		
		# Draw label above the line
		var label_pos = nearest_point + Vector2(0, -30)
		var label_size = ThemeDB.fallback_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_rect(Rect2(label_pos - Vector2(label_size.x/2 + 8, 8), 
						label_size + Vector2(16, 16)), 
				  Color(0, 0, 0, 0.9), true)
		draw_string(ThemeDB.fallback_font, label_pos, label_text,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 14, color)

# FIX: Show which edges are marked as top-out in the instructions
func _draw_control_points():
	for i in range(control_points.size()):
		var point = control_points[i]
		var color = point_color
		
		# Color coding
		if i == ground_left_index or i == ground_right_index:
			color = ground_point_color
		elif edit_mode:
			if dragging_point == i:
				color = point_drag_color
			elif hovered_point == i:
				color = point_hover_color
		
		# Shadow
		draw_circle(point, POINT_RADIUS + 3, Color(0, 0, 0, 0.5))
		# Point
		draw_circle(point, POINT_RADIUS, color)
		
		# Number label
		var label = str(i + 1)
		draw_string(ThemeDB.fallback_font, point + Vector2(-5, 6), label, 
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	
	# Instructions (only when editing)
	if edit_mode and control_points.size() > 0:
		# NEW: Show current marked edges
		var marked_edges_text = ""
		if not top_edge_indices.is_empty():
			marked_edges_text = " | MARKED TOP EDGES: " + str(top_edge_indices)
		
		var text = "LEFT-DRAG: Move | RIGHT-CLICK: Add Point | SHIFT+RIGHT-CLICK on EDGE: Mark Top Edge" + marked_edges_text
		var pos = Vector2(wall_min.x, wall_min.y - 40)
		
		var size = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_rect(Rect2(pos - Vector2(8, 22), size + Vector2(16, 30)), Color(0, 0, 0, 0.8), true)
		
		draw_string(ThemeDB.fallback_font, pos, text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.6))

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
# BOLT HOLES
# =============================================================================
func draw_bolt_holes(start_pos: Vector2, end_pos: Vector2):
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
			
			if hole_pos.x >= draw_min_x and hole_pos.x <= draw_max_x and \
			   hole_pos.y >= draw_min_y and hole_pos.y <= draw_max_y:
				draw_circle(hole_pos, hole_radius, hole_color)
			y += hole_spacing.y
		x += hole_spacing.x

# =============================================================================
# GRANITE TEXTURE
# =============================================================================
func draw_granite_texture():
	var wall_size = wall_max - wall_min
	var rng_seed = int(wall_min.x + wall_min.y)
	var num_cracks = int(wall_size.x / 200.0) + 2
	
	for i in range(num_cracks):
		var x_offset = (float(i) / num_cracks) * wall_size.x
		var x_pos = wall_min.x + x_offset + (hash(rng_seed + i) % 50 - 25)
		
		var start_y = wall_min.y
		var end_y = wall_max.y
		
		if x_pos >= wall_min.x and x_pos <= wall_max.x:
			draw_line(Vector2(x_pos, start_y),
					  Vector2(x_pos, end_y),
					  Color(0.45, 0.43, 0.4, 0.3),
					  2.0)

# =============================================================================
# EDGE RENDERING
# =============================================================================
func draw_edges():
	if use_polygon_mode and control_points.size() >= 3:
		# Draw each edge individually
		for i in range(control_points.size()):
			var p1 = control_points[i]
			var p2 = control_points[(i + 1) % control_points.size()]
			
			# ONLY show orange color in editor
			var color = edge_color
			var thickness = edge_thickness
			
			if is_in_editor and i in top_edge_indices:
				color = top_edge_color
				thickness = edge_thickness + 2.0  # Slightly thicker
			
			draw_line(p1, p2, color, thickness)
	else:
		# Rectangle mode - standard edges
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
	
	# Recreate top edge holds
	if not top_edge_indices.is_empty():
		_create_top_edge_holds()
	
	queue_redraw()

# =============================================================================
# BOUNDS MANAGEMENT
# =============================================================================
func calculate_bounds_from_holds(holds_container: Node2D):
	if not holds_container or holds_container.get_child_count() == 0:
		wall_valid = false
		# Don't reset polygon - keep it for when holds are added back
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
	
	ground_y = wall_max.y
	
	# ALWAYS auto-initialize 4 corner points if not in polygon mode
	if control_points.is_empty():
		control_points = [
			wall_min,                           # 0: Top-left
			Vector2(wall_max.x, wall_min.y),    # 1: Top-right
			Vector2(wall_max.x, wall_max.y),    # 2: Bottom-right (ground)
			Vector2(wall_min.x, wall_max.y)     # 3: Bottom-left (ground)
		]
		ground_left_index = 3
		ground_right_index = 2
		use_polygon_mode = true  # Auto-enable polygon mode
	else:
		# Update existing polygon to fit new bounds
		if ground_left_index >= 0 and ground_left_index < control_points.size():
			control_points[ground_left_index].y = ground_y
		if ground_right_index >= 0 and ground_right_index < control_points.size():
			control_points[ground_right_index].y = ground_y
	
	# Create top edge holds if any are marked
	if not top_edge_indices.is_empty():
		_create_top_edge_holds()
	
	queue_redraw()

func _update_bounds_from_polygon():
	if control_points.is_empty():
		return
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for point in control_points:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	
	wall_min = Vector2(min_x, min_y)
	wall_max = Vector2(max_x, max_y)
	wall_valid = true

# =============================================================================
# POLYGON MANIPULATION - PUBLIC API
# =============================================================================
func add_point_between_nearest_edge(pos: Vector2):
	"""Add a point on the nearest edge (except ground edge)"""
	if control_points.size() < 2:
		control_points.append(pos)
		_update_bounds_from_polygon()
		queue_redraw()
		return
	
	var nearest_edge_index = -1
	var nearest_dist = INF
	
	for i in range(control_points.size()):
		if _is_ground_edge(i):
			continue
			
		var p1 = control_points[i]
		var p2 = control_points[(i + 1) % control_points.size()]
		var dist = _point_to_segment_distance(pos, p1, p2)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_edge_index = i
	
	if nearest_edge_index < 0:
		return
	
	var new_index = nearest_edge_index + 1
	control_points.insert(new_index, pos)
	
	# Update indices after insertion
	if ground_left_index >= new_index:
		ground_left_index += 1
	if ground_right_index >= new_index:
		ground_right_index += 1
	
	# Update top edge indices (they shift too)
	var updated_top_edges: Array[int] = []
	for edge_idx in top_edge_indices:
		if edge_idx >= nearest_edge_index:
			updated_top_edges.append(edge_idx + 1)
		else:
			updated_top_edges.append(edge_idx)
	top_edge_indices = updated_top_edges
	
	_update_bounds_from_polygon()
	
	# Recreate top edge holds
	if not top_edge_indices.is_empty():
		_create_top_edge_holds()
	
	queue_redraw()

func remove_point(index: int):
	"""Remove a control point"""
	if index == ground_left_index or index == ground_right_index:
		push_warning("Cannot remove ground points")
		return
	
	if control_points.size() <= 4:
		push_warning("Cannot remove - need at least 4 points")
		return
	
	if index >= 0 and index < control_points.size():
		control_points.remove_at(index)
		
		if ground_left_index > index:
			ground_left_index -= 1
		if ground_right_index > index:
			ground_right_index -= 1
		
		if dragging_point == index:
			dragging_point = -1
		elif dragging_point > index:
			dragging_point -= 1
		
		if hovered_point == index:
			hovered_point = -1
		elif hovered_point > index:
			hovered_point -= 1
		
		# Update top edge indices
		var updated_top_edges: Array[int] = []
		for edge_idx in top_edge_indices:
			if edge_idx == index:
				continue  # Remove this edge
			elif edge_idx > index:
				updated_top_edges.append(edge_idx - 1)
			else:
				updated_top_edges.append(edge_idx)
		top_edge_indices = updated_top_edges
		
		_update_bounds_from_polygon()
		
		# Recreate top edge holds
		if not top_edge_indices.is_empty():
			_create_top_edge_holds()
		
		queue_redraw()

func enable_polygon_mode(enabled: bool = true):
	"""Switch to custom polygon"""
	use_polygon_mode = enabled
	
	if enabled and control_points.is_empty() and wall_valid:
		control_points = [
			wall_min,
			Vector2(wall_max.x, wall_min.y),
			Vector2(wall_max.x, wall_max.y),
			Vector2(wall_min.x, wall_max.y)
		]
		ground_left_index = 3
		ground_right_index = 2
		ground_y = wall_max.y
	
	queue_redraw()

func enable_edit_mode(enabled: bool = true):
	"""Show/hide control points"""
	edit_mode = enabled
	
	if not enabled:
		dragging_point = -1
		hovered_point = -1
		hovered_edge = -1
	
	queue_redraw()

func reset_polygon():
	"""Reset to default rectangle (called when clearing holds)"""
	use_polygon_mode = false
	edit_mode = false
	control_points.clear()
	top_edge_indices.clear()
	ground_left_index = -1
	ground_right_index = -1
	dragging_point = -1
	hovered_point = -1
	hovered_edge = -1
	
	# Remove all top edge holds
	for child in get_children():
		if child.has_meta("is_top_edge_hold"):
			child.queue_free()
	
	queue_redraw()

func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var segment = seg_end - seg_start
	var segment_length_sq = segment.length_squared()
	
	if segment_length_sq == 0:
		return point.distance_to(seg_start)
	
	var t = clamp((point - seg_start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var projection = seg_start + t * segment
	return point.distance_to(projection)

# =============================================================================
# TOP EDGE HOLDS - User-selected edges become grabbable
# =============================================================================
func _create_top_edge_holds():
	"""Create grabbable holds for user-marked top edges"""
	# Remove old ones
	for child in get_children():
		if child.has_meta("is_top_edge_hold"):
			child.queue_free()
	
	if not use_polygon_mode or top_edge_indices.is_empty():
		return
	
	print("Creating top edge holds for edges: ", top_edge_indices)
	
	# Create hold for each marked top edge
	for edge_idx in top_edge_indices:
		if edge_idx >= control_points.size():
			continue
		
		var p1 = control_points[edge_idx]
		var p2 = control_points[(edge_idx + 1) % control_points.size()]
		_create_edge_hold(p1, p2)
		print("  Created top hold between ", p1, " and ", p2)

func _create_edge_hold(p1: Vector2, p2: Vector2):
	"""Create a hold along an edge"""
	var center = (p1 + p2) / 2.0
	var width = p1.distance_to(p2)
	_create_top_hold_at(center, width)

func _create_top_hold_at(position: Vector2, width: float):
	"""Create a top-out hold at given position"""
	var top_hold = Area2D.new()
	top_hold.set_meta("is_top_edge_hold", true)
	top_hold.collision_layer = 2  # Same as regular holds
	top_hold.collision_mask = 0
	top_hold.monitoring = false  # Don't need to detect other areas
	top_hold.monitorable = true  # BUT must be detectable by limbs
	top_hold.name = "TopEdgeHold"

	var shape = RectangleShape2D.new()
	shape.size = Vector2(width, 50)  # Use size instead of extents for Godot 4
	var collision = CollisionShape2D.new()
	collision.shape = shape
	top_hold.add_child(collision)

	var hold_point = Marker2D.new()
	hold_point.name = "HoldPoint"
	hold_point.position = Vector2(0, 0)
	top_hold.add_child(hold_point)

	top_hold.global_position = position

	# Add immediately, not deferred - this ensures collision is set up properly
	add_child(top_hold)
	top_hold.add_to_group("holds")
	call_deferred("_assign_top_hold_script", top_hold)
	
	print("    DEBUG: Created top hold at ", position, " with width ", width)

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

func _draw_ground():
	if not wall_valid:
		return

	var ground_min = Vector2(
		wall_min.x - BACKGROUND_EXPANSION,
		ground_y
	)

	var ground_size = Vector2(
		(wall_max.x - wall_min.x) + BACKGROUND_EXPANSION * 2,
		ground_height
	)

	draw_rect(Rect2(ground_min, ground_size), ground_color, true)

	draw_line(
		Vector2(ground_min.x, ground_y),
		Vector2(ground_min.x + ground_size.x, ground_y),
		ground_color.lightened(0.2),
		4.0
	)

# =============================================================================
# QUERIES
# =============================================================================
func get_bounds() -> Dictionary:
	return {"min": wall_min, "max": wall_max, "valid": wall_valid}

func get_top_edge_y() -> float:
	# Find lowest Y from all top edge points
	if use_polygon_mode and not top_edge_indices.is_empty():
		var top_y = INF
		for edge_idx in top_edge_indices:
			if edge_idx >= control_points.size():
				continue
			var p1 = control_points[edge_idx]
			var p2 = control_points[(edge_idx + 1) % control_points.size()]
			top_y = min(top_y, p1.y)
			top_y = min(top_y, p2.y)
		return top_y if top_y != INF else wall_min.y
	
	return wall_min.y

func get_wall_height() -> float:
	return ground_y - get_top_edge_y()

func get_wall_width() -> float:
	return wall_max.x - wall_min.x

func hash_to_float(v: int) -> float:
	return float(hash(v) % 10000) / 10000.0

# =============================================================================
# POLYGON SAVE/LOAD
# =============================================================================
func get_polygon_data() -> Dictionary:
	"""Export polygon data for JSON"""
	if not use_polygon_mode or control_points.is_empty():
		return {}
	
	var points_data = []
	for point in control_points:
		points_data.append({"x": point.x, "y": point.y})
	
	return {
		"enabled": true,
		"points": points_data,
		"ground_left_index": ground_left_index,
		"ground_right_index": ground_right_index,
		"top_edge_indices": top_edge_indices.duplicate()  # Save user-selected top edges
	}

func set_polygon_data(data: Dictionary):
	"""Load polygon data from JSON"""
	if not data or data.is_empty():
		return
	
	if not data.get("enabled", false):
		return
	
	use_polygon_mode = true
	control_points.clear()
	
	for point_data in data.get("points", []):
		var point = Vector2(point_data.get("x", 0), point_data.get("y", 0))
		control_points.append(point)
	
	ground_left_index = data.get("ground_left_index", -1)
	ground_right_index = data.get("ground_right_index", -1)
	
	# Load user-selected top edges
	top_edge_indices.clear()
	if "top_edge_indices" in data:
		var loaded_edges = data.get("top_edge_indices", [])
		for edge_idx in loaded_edges:
			# JSON may load numbers as float or int, so convert to int
			if edge_idx is float or edge_idx is int:
				top_edge_indices.append(int(edge_idx))
		
		print("  DEBUG: Loaded top edge indices: ", top_edge_indices)
	
	if ground_left_index >= 0 and ground_left_index < control_points.size():
		ground_y = control_points[ground_left_index].y
	
	_update_bounds_from_polygon()
	
	# Create top edge holds
	if not top_edge_indices.is_empty():
		_create_top_edge_holds()
	
	queue_redraw()
	
	print("  Polygon loaded: " + str(control_points.size()) + " points, " + str(top_edge_indices.size()) + " top edges")
