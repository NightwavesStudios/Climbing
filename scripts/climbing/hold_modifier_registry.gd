# hold_modifier_registry.gd
# ═══════════════════════════════════════════════════════════════════════════════
# Autoload singleton that creates and manages hold modifiers.
# Each modifier type is a standalone class extending HoldModifierBase.
# Register new modifiers by adding them to MODIFIER_DISPLAY_NAMES and the
# create_modifier() match statement.
# ═══════════════════════════════════════════════════════════════════════════════

extends Node

const MODIFIER_DISPLAY_NAMES: Dictionary = {
	"falling": "Falling",
	"undercling": "Undercling",
	"soft_hold": "Soft Hold",
	"moving": "Moving",
}

func get_all_modifier_types() -> Array:
	return MODIFIER_DISPLAY_NAMES.keys()

func get_display_name(type_key: String) -> String:
	return MODIFIER_DISPLAY_NAMES.get(type_key, type_key.capitalize())

## Instantiate a blank modifier node by type key.
func create_modifier(type_key: String) -> Node:
	match type_key:
		"falling":
			return FallingHoldModifier.new()
		"undercling":
			return UnderclingModifier.new()
		"soft_hold":
			return SoftHoldModifier.new()
		"moving":
			return MovingHoldModifier.new()
		_:
			return null

## Instantiate and deserialize a modifier from saved JSON data.
func create_modifier_from_data(data: Dictionary) -> Node:
	var modifier := create_modifier(data.get("type", ""))
	if modifier and modifier.has_method("deserialize"):
		modifier.deserialize(data)
	return modifier

# =============================================================================
# RUNTIME COMPONENT MANAGEMENT
# (Used by the level editor to attach modifiers to hold nodes live)
# =============================================================================

## Resolve the node a modifier should attach to. Hold scenes use a plain Node2D
## wrapper root with the scripted Area2D as a child — modifiers must go on the
## Area2D so holds.gd's _process() drives them.
func _resolve_target(hold: Node2D) -> Node2D:
	if hold.get_script() != null:
		return hold
	for child in hold.get_children():
		if child is Area2D and child.get_script() != null:
			return child
	return hold

## Find an already-attached modifier component of the given type on a hold.
func find_modifier(hold: Node2D, type_key: String) -> Node:
	var target := _resolve_target(hold)
	for child in target.get_children():
		if "modifier_type" in child and child.modifier_type == type_key:
			return child
	return null

## Attach a modifier component to a hold node. Dedupes by type so a hold never
## ends up with two copies of the same modifier (e.g. an undercling hold that
## auto-attaches its modifier in _ready() and also has one in saved level data).
func attach_modifier(hold: Node2D, data: Dictionary) -> Node:
	var type_key: String = data.get("type", "")
	var existing := find_modifier(hold, type_key)
	if existing:
		return existing
	var modifier := create_modifier_from_data(data)
	if modifier == null:
		return null
	var target := _resolve_target(hold)
	target.add_child(modifier)
	if modifier.has_method("on_hold_ready"):
		modifier.on_hold_ready()
	return modifier

## Remove an attached modifier component by type.
func detach_modifier(hold: Node2D, type_key: String) -> void:
	var existing := find_modifier(hold, type_key)
	if existing and is_instance_valid(existing):
		existing.queue_free()
