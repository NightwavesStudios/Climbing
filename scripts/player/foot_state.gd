extends LimbState
class_name FootState
## State for a climber's foot limb, including manual override tracking.

var manual:        bool = false
var user_override: bool = false

func is_foot() -> bool:
	return true

func origin(body: Vector2, _soff: float, hoff: float, hdown: float) -> Vector2:
	return body + Vector2(-hoff if is_left else hoff, hdown)

func reach(_au: float, _al: float, lu: float, ll: float) -> float:
	return lu + ll

func reset_all() -> void:
	super.reset_all()
	manual = false
	user_override = false
