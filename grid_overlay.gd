extends Node2D

# =============================================================================
# GRID OVERLAY - Visual grid for level editor
# =============================================================================

@export var grid_size: float = 32.0
@export var grid_color: Color = Color(0.3, 0.3, 0.3, 0.3)
@export var major_grid_size: float = 128.0
@export var major_grid_color: Color = Color(0.4, 0.4, 0.4, 0.5)

var camera: Camera2D

func _ready():
	camera = get_viewport().get_camera_2d()

func _draw():
	if not camera:
		camera = get_viewport().get_camera_2d()
		if not camera:
			return
	
	var viewport_size = get_viewport_rect().size
	var cam_pos = camera.global_position
	var zoom = camera.zoom.x
	
	# Calculate visible area
	var half_size = viewport_size / (2.0 * zoom)
	var start = cam_pos - half_size - Vector2(grid_size, grid_size)
	var end = cam_pos + half_size + Vector2(grid_size, grid_size)
	
	# Snap to grid
	start.x = floor(start.x / grid_size) * grid_size
	start.y = floor(start.y / grid_size) * grid_size
	
	# Draw minor grid
	var x = start.x
	while x <= end.x:
		draw_line(
			Vector2(x, start.y),
			Vector2(x, end.y),
			grid_color,
			1.0
		)
		x += grid_size
	
	var y = start.y
	while y <= end.y:
		draw_line(
			Vector2(start.x, y),
			Vector2(end.x, y),
			grid_color,
			1.0
		)
		y += grid_size
	
	# Draw major grid
	x = floor(start.x / major_grid_size) * major_grid_size
	while x <= end.x:
		draw_line(
			Vector2(x, start.y),
			Vector2(x, end.y),
			major_grid_color,
			2.0
		)
		x += major_grid_size
	
	y = floor(start.y / major_grid_size) * major_grid_size
	while y <= end.y:
		draw_line(
			Vector2(start.x, y),
			Vector2(end.x, y),
			major_grid_color,
			2.0
		)
		y += major_grid_size
	
	# Draw origin
	draw_circle(Vector2.ZERO, 5.0, Color(1, 0, 0, 0.8))
	draw_line(Vector2(-20, 0), Vector2(20, 0), Color(1, 0, 0), 2.0)
	draw_line(Vector2(0, -20), Vector2(0, 20), Color(0, 1, 0), 2.0)
