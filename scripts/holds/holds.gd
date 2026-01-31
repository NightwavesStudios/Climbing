extends Area2D
class_name ClimbingHold

enum HoldType { JUG, START, TOP_OUT }

@export var hold_type: HoldType = HoldType.JUG
@onready var hold_point: Marker2D = $HoldPoint

func _ready():
	collision_layer = 2
	collision_mask = 0
	monitoring = true

func get_hold_color() -> Color:
	match hold_type:
		HoldType.START:
			return Color.RED
		HoldType.TOP_OUT:
			return Color.BLUE
		HoldType.JUG:
			return Color.DARK_GRAY
		_:
			return Color.GRAY

func get_hold_inner_color() -> Color:
	match hold_type:
		HoldType.START:
			return Color.DARK_RED
		HoldType.TOP_OUT:
			return Color.DARK_BLUE
		HoldType.JUG:
			return Color.GRAY
		_:
			return Color.LIGHT_GRAY

func is_start_hold() -> bool:
	return hold_type == HoldType.START

func is_top_out() -> bool:
	return hold_type == HoldType.TOP_OUT

func is_jug() -> bool:
	return hold_type == HoldType.JUG

func _draw():
	var outer_color = get_hold_color()
	var inner_color = get_hold_inner_color()
	
	draw_circle(Vector2.ZERO, 50, outer_color)
	draw_circle(Vector2.ZERO, 48, inner_color)
	
	if hold_point:
		draw_circle(hold_point.position, 2, Color.YELLOW)
