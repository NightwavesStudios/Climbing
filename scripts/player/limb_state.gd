extends RefCounted
class_name LimbState
## Base class for tracking the state of a climber's limb (hand or foot).

var node:  Node2D
var joint: Node2D

var hold:   Area2D  = null
var pin:    Vector2 = Vector2.ZERO
var anchor: Vector2 = Vector2.ZERO

var pressure:    float = 0.0
var grip:        int   = 0
var static_time: float = 0.0
var force:       float = 0.0

var velocity:       Vector2 = Vector2.ZERO
var joint_velocity: Vector2 = Vector2.ZERO
var grab_target:    Vector2 = Vector2.ZERO
var previous_pos:   Vector2 = Vector2.ZERO

var is_grabbing: bool = false
var selected:    bool = false
var is_left:     bool = false

var shake_offset:  Vector2 = Vector2.ZERO
var visual_offset: Vector2 = Vector2.ZERO
var shake_lerp:    float   = 0.0

var ghost:      Vector2 = Vector2.ZERO
var ghost_init: bool    = false

func is_hand() -> bool:
	return false

func is_foot() -> bool:
	return false

## Returns the origin position of this limb relative to the body.
func origin(_body: Vector2, _soff: float, _hoff: float, _hdown: float) -> Vector2:
	return Vector2.ZERO

## Returns the effective reach distance for this limb.
func reach(_au: float, _al: float, _lu: float, _ll: float) -> float:
	return 0.0

func is_load_bearing() -> bool:
	return hold != null and not is_grabbing

func reset_velocity() -> void:
	velocity = Vector2.ZERO
	joint_velocity = Vector2.ZERO

func reset_all() -> void:
	hold = null
	pin = Vector2.ZERO
	anchor = Vector2.ZERO
	pressure = 0.0
	grip = 0
	static_time = 0.0
	force = 0.0
	reset_velocity()
	grab_target = Vector2.ZERO
	is_grabbing = false
	selected = false
	shake_offset = Vector2.ZERO
	visual_offset = Vector2.ZERO
	shake_lerp = 0.0
	ghost_init = false
