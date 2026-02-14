extends Node2D
class_name RopeSystem

## WORKING rope system - straight line, no physics bugs, instant

@export var rope_color := Color.BLACK
@export var rope_thickness := 2.5

# Simple rigid rope
const ROPE_LENGTH := 500.0
const ROPE_FORCE_STRENGTH := 0.85  # How hard rope stops player

# Belayer drawing
const SHOULDER_OFFSET := 11.0
const HIP_OFFSET := 9.0
const HIP_DOWN := 20.0
const HEAD_OFFSET := -18.0

# State
var belayer_position: Vector2 = Vector2.ZERO
var player: Node2D = null
var player_attach_offset: Vector2 = Vector2(0, -5)
var is_setup: bool = false

# Visual
var rope_line: Line2D = null

func _ready():
	global_position = Vector2.ZERO
	z_index = 50
	
	# Instant Line2D creation
	rope_line = Line2D.new()
	rope_line.width = rope_thickness
	rope_line.default_color = rope_color
	rope_line.z_index = 49
	rope_line.top_level = true
	rope_line.antialiased = true
	add_child(rope_line)
	
	set_process(true)

func _process(_delta):
	if is_setup and player:
		update_rope_visual()
	queue_redraw()

func setup_rope(belayer_pos: Vector2, player_node: Node2D):
	"""Instant setup"""
	belayer_position = belayer_pos
	player = player_node
	is_setup = true
	visible = true
	
	if rope_line:
		rope_line.visible = true
	
	update_rope_visual()

func update_rope_visual():
	"""Draw STRAIGHT rope - NO SAG, NO PHYSICS"""
	if not rope_line or not player:
		return
	
	var player_pos = player.global_position + player_attach_offset
	var distance = belayer_position.distance_to(player_pos)
	
	# Clamp to rope length
	if distance > ROPE_LENGTH:
		var direction = (player_pos - belayer_position).normalized()
		player_pos = belayer_position + direction * ROPE_LENGTH
	
	# STRAIGHT LINE - 8 segments for smooth appearance
	var points = PackedVector2Array()
	for i in range(8):
		var t = float(i) / 7.0
		points.append(belayer_position.lerp(player_pos, t))
	
	rope_line.points = points

func apply_rope_force_to_player(player_velocity: Vector2) -> Vector2:
	"""Hard stop at rope limit - NO ROCKETS"""
	if not player:
		return player_velocity
	
	var player_pos = player.global_position + player_attach_offset
	var distance = belayer_position.distance_to(player_pos)
	
	# At rope limit
	if distance >= ROPE_LENGTH * 0.97:
		var to_belayer = (belayer_position - player_pos).normalized()
		
		# CRITICAL FIX: Only stop outward velocity, don't add force
		var velocity_away = player_velocity.dot(-to_belayer)
		if velocity_away > 0:
			# Remove only the outward component
			return player_velocity + (to_belayer * velocity_away * ROPE_FORCE_STRENGTH)
	
	return player_velocity

func _draw():
	"""Clean belayer figure"""
	if not is_setup:
		return
	
	var b = to_local(belayer_position)
	var black = Color.BLACK
	var w = 3.5
	
	# Head
	draw_circle(b + Vector2(0, HEAD_OFFSET), 9, black)
	
	# Body
	var neck = b + Vector2(0, HEAD_OFFSET + 9)
	var hips = b + Vector2(0, HIP_DOWN)
	draw_line(neck, hips, black, w)
	
	# Arms
	var ls = b + Vector2(-SHOULDER_OFFSET, 0)
	var le = b + Vector2(-SHOULDER_OFFSET - 10, -3)
	var lh = b + Vector2(-SHOULDER_OFFSET - 14, -5)
	
	var rs = b + Vector2(SHOULDER_OFFSET, 0)
	var re = b + Vector2(SHOULDER_OFFSET + 6, 16)
	var rh = b + Vector2(SHOULDER_OFFSET + 7, 35)
	
	draw_line(ls, le, black, w)
	draw_line(le, lh, black, w - 0.5)
	draw_line(rs, re, black, w)
	draw_line(re, rh, black, w - 0.5)
	
	# Legs
	var lhip = b + Vector2(-HIP_OFFSET, HIP_DOWN)
	var rhip = b + Vector2(HIP_OFFSET, HIP_DOWN)
	
	var lk = b + Vector2(-HIP_OFFSET - 2, HIP_DOWN + 24)
	var lf = b + Vector2(-HIP_OFFSET - 3, HIP_DOWN + 48)
	
	var rk = b + Vector2(HIP_OFFSET + 2, HIP_DOWN + 24)
	var rf = b + Vector2(HIP_OFFSET + 3, HIP_DOWN + 48)
	
	draw_line(lhip, lk, black, w)
	draw_line(lk, lf, black, w - 0.5)
	draw_line(rhip, rk, black, w)
	draw_line(rk, rf, black, w - 0.5)
	
	# Extremities
	draw_circle(lh, 4, black)
	draw_circle(rh, 4, black)
	draw_circle(lf, 4, black)
	draw_circle(rf, 4, black)
	
	# Rope from guide hand
	draw_line(lh, to_local(belayer_position), black, 2.0)

func cleanup():
	if rope_line:
		rope_line.queue_free()
	queue_free()
