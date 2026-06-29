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
		_:
			return null

## Instantiate and deserialize a modifier from saved JSON data.
func create_modifier_from_data(data: Dictionary) -> Node:
	var modifier := create_modifier(data.get("type", ""))
	if modifier and modifier.has_method("deserialize"):
		modifier.deserialize(data)
	return modifier
