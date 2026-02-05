extends Node2D

@export var wall_color := Color(0.82, 0.75, 0.62)
@export var wall_texture_enabled := true
@export var texture_variation := 0.05

@export var hole_spacing := Vector2(64, 64)
@export var hole_radius := 2.5
@export var hole_color := Color(0.15, 0.15, 0.15)
@export var hole_jitter := 4.0

@export var draw_margin := Vector2(300, 300)

func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_ENTER_TREE:
		queue_redraw()

func _process(_delta):
	queue_redraw()

func _draw():
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	var viewport_size := get_viewport_rect().size
	var cam_pos := camera.global_position

	var start := cam_pos - viewport_size * 0.5 - draw_margin
	var size := viewport_size + draw_margin * 2.0

	if wall_texture_enabled:
		draw_textured_wall(start, size)
	else:
		draw_rect(Rect2(start, size), wall_color)

	draw_bolt_holes(start, start + size)

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
					wall_color.r + v,
					wall_color.g + v,
					wall_color.b + v,
					wall_color.a
				)
			)

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

func hash_to_float(v: int) -> float:
	return float(hash(v) % 10000) / 10000.0
