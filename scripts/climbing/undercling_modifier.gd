class_name UnderclingModifier
extends HoldModifierBase
## Undercling hold modifier.
##
## Underclings hang easily (like jugs) but demand foot support:
## - Hands can only grab an undercling while at least one foot is on a hold.
## - If every foot cuts loose while a hand is on the undercling, the hand is
##   force-released and the climber falls.
## - Hanging on an undercling slowly drains stamina (no rest recovery).

## Pressure added per second to each hand holding the undercling.
@export var stamina_drain_per_sec: float = 2.0

const PRESSURE_FAIL = 100.0

var _claimed_hands: Array[Node2D] = []

func _ready() -> void:
	modifier_type = "undercling"
	super._ready()

# ── Grab / release hooks ──────────────────────────────────────────────────

func allow_grab(limb_node: Node2D, is_foot: bool) -> bool:
	# Underclings are hand holds — feet can't grab them.
	if is_foot:
		return false
	# You can't use an undercling without at least one foot on the wall.
	var character := _find_character(limb_node)
	if character == null:
		return false
	return _count_feet_on_holds(character) > 0

func on_grab(limb_node: Node2D) -> void:
	if limb_node not in _claimed_hands:
		_claimed_hands.append(limb_node)

func on_release(limb_node: Node2D) -> void:
	_claimed_hands.erase(limb_node)

# ── Per-frame ─────────────────────────────────────────────────────────────

func on_process(delta: float) -> void:
	if _claimed_hands.is_empty():
		return
	var character := _find_character(_claimed_hands[0])
	if character == null or not is_instance_valid(character):
		return

	# Ever-so-slight stamina drain while hanging on the undercling.
	_apply_stamina_drain(character, delta)

	# Feet cut loose → the undercling can't hold you → fall.
	if _count_feet_on_holds(character) == 0:
		_force_release_all()

# ── Helpers ───────────────────────────────────────────────────────────────

func _find_character(limb_node: Node2D) -> Node2D:
	if limb_node == null:
		return null
	var parent: Node = limb_node.get_parent()
	if parent is CharacterBody2D:
		return parent as Node2D
	return null

func _count_feet_on_holds(character: Node2D) -> int:
	var count := 0
	if "lf" in character and character.lf != null and character.lf.hold != null:
		count += 1
	if "rf" in character and character.rf != null and character.rf.hold != null:
		count += 1
	return count

func _apply_stamina_drain(character: Node2D, delta: float) -> void:
	var drain := stamina_drain_per_sec * delta
	var hands: Array = []
	if "lh" in character and character.lh != null:
		hands.append(character.lh)
	if "rh" in character and character.rh != null:
		hands.append(character.rh)
	for s in hands:
		if s.hold == hold:
			s.pressure = minf(s.pressure + drain, PRESSURE_FAIL)

func _force_release_all() -> void:
	var to_release := _claimed_hands.duplicate()
	_claimed_hands.clear()
	for limb in to_release:
		if not is_instance_valid(limb):
			continue
		var character := _find_character(limb)
		if character != null and "_limbs" in character:
			# Use the climber's canonical release so its LimbState is cleared too.
			for s in character._limbs:
				if s.node == limb:
					character.release_limb(s)
					s.is_grabbing = false
					if character.has_method("_reset_limb_ghost"):
						character._reset_limb_ghost(limb)
					# Small downward kick so the cut-loose fall feels immediate.
					character.com_velocity.y = maxf(character.com_velocity.y, 150.0)
					break
		elif hold.has_method("release"):
			hold.release(limb)

# ── Serialization ─────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"type": "undercling",
		"stamina_drain_per_sec": stamina_drain_per_sec,
	}

func deserialize(data: Dictionary) -> void:
	stamina_drain_per_sec = float(data.get("stamina_drain_per_sec", stamina_drain_per_sec))
