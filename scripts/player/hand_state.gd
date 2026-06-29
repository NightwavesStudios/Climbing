extends LimbState
class_name HandState
## State for a climber's hand limb, including failure tracking and catch boost.

var fail_stage:     int   = 0
var struggle_timer: float = 0.0
var catch_boost:    float = 1.0
var catch_timer:    float = 0.0

func is_hand() -> bool:
	return true

func origin(body: Vector2, soff: float, _hoff: float, _hdown: float) -> Vector2:
	return body + Vector2(-soff if is_left else soff, 0.0)

func reach(au: float, al: float, _lu: float, _ll: float) -> float:
	return au + al

func reset_all() -> void:
	super.reset_all()
	fail_stage = 0
	struggle_timer = 0.0
	catch_boost = 1.0
	catch_timer = 0.0
