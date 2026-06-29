## Simplified falling hold modifier used by the Level Editor during test mode.
## This is a lightweight version (not the full FallingHoldModifier from the
## modifier system) designed for editor preview only.
extends Node

var fall_delay: float = 2.2
var fall_gravity: float = 1800.0

var _timer: float = 0.0
var _falling: bool = false
var _vel_y: float = 0.0
var _origin: Vector2
var _grabbed: bool = false

func _ready() -> void:
	_origin = get_parent().global_position
	var p = get_parent()
	if p.has_signal("grabbed"):
		p.grabbed.connect(_on_grabbed)
	elif p.has_signal("hold_grabbed"):
		p.hold_grabbed.connect(_on_grabbed)
	_timer = fall_delay

func _on_grabbed() -> void:
	_grabbed = true

func reset() -> void:
	_falling = false
	_vel_y = 0.0
	_timer = fall_delay
	_grabbed = false
	get_parent().global_position = _origin

func _physics_process(delta: float) -> void:
	var p = get_parent()
	if not is_instance_valid(p):
		return
	if _falling:
		_vel_y += fall_gravity * delta
		p.global_position.y += _vel_y * delta
		if p.global_position.y > 3000.0:
			reset()
		return
	if _grabbed:
		_timer -= delta
		if _timer <= 0.0:
			_falling = true
