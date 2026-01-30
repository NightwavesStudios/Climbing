extends Area2D

@onready var hold_point: Marker2D = $HoldPoint

func _ready():
	collision_layer = 2
	collision_mask = 0
	monitoring = true

func _draw():
	draw_circle(Vector2.ZERO, 50, Color.DARK_BLUE)
	draw_circle(Vector2.ZERO, 48, Color.BLUE)

	if hold_point:
		draw_circle(hold_point.position, 2, Color.YELLOW)
