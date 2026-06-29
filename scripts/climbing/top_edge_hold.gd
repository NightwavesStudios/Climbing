class_name TopEdgeHold
extends Area2D
## A dynamically created top-out hold placed along a polygon wall's top edge.
## Created by DynamicWall when top_edge_indices are set.

var edge_start: Vector2 = Vector2.ZERO
var edge_end:   Vector2 = Vector2.ZERO
var claimed_left_hand:  Node2D = null
var claimed_right_hand: Node2D = null
var left_hand_x:  float = 0.0
var right_hand_x: float = 0.0

static func _edge_y_at_x(x: float, p1: Vector2, p2: Vector2) -> float:
	if absf(p2.x - p1.x) < 1.0:
		return (p1.y + p2.y) * 0.5
	var t := clampf((x - p1.x) / (p2.x - p1.x), 0.0, 1.0)
	return p1.y + (p2.y - p1.y) * t

func is_start_hold() -> bool: return false
func is_top_out()    -> bool: return true
func is_crimp()      -> bool: return false
func is_sloper()     -> bool: return false
func is_pocket()     -> bool: return false
func is_foothold()   -> bool: return false

func can_grab(_limb: Node2D, is_foot: bool) -> bool:
	return not is_foot

func try_claim(limb: Node2D, is_foot: bool, snap_pos: Vector2) -> bool:
	if not can_grab(limb, is_foot):
		return false
	if limb.name == "LeftHand":
		claimed_left_hand = limb
		left_hand_x = snap_pos.x
	elif limb.name == "RightHand":
		claimed_right_hand = limb
		right_hand_x = snap_pos.x
	return true

func release(limb: Node2D) -> void:
	if limb.name == "LeftHand" and claimed_left_hand == limb:
		claimed_left_hand = null
		left_hand_x = 0.0
	elif limb.name == "RightHand" and claimed_right_hand == limb:
		claimed_right_hand = null
		right_hand_x = 0.0

func get_limb_anchor(limb: Node2D) -> Vector2:
	var x := left_hand_x if (limb.name == "LeftHand" and claimed_left_hand == limb) \
		else right_hand_x if (limb.name == "RightHand" and claimed_right_hand == limb) \
		else limb.global_position.x
	var ey := _edge_y_at_x(x, edge_start, edge_end)
	return Vector2(x, ey)

func get_state_pressure(_delta: float, _bo: float, _st: float, _fs: float, _limb: Node2D) -> float:
	return 0.0  # No stamina drain while holding the top edge

func get_recovery_rate(delta: float, _body_balance: float, _fs: float) -> float:
	return 30.0 * delta  # Fast recovery back to zero
