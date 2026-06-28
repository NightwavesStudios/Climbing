# hold_modifier_registry.gd
# res://scripts/holds/hold_modifier_registry.gd
# ═══════════════════════════════════════════════════════════════════════════════
# Autoload singleton. Register in Project → Autoloads as "HoldModifierRegistry".
#
# FallingHoldModifier lives as an inner class inside hold_modifiers.gd.
# We load that file and call .FallingHoldModifier.new() to instantiate it.
#
# To add a new modifier:
#   Option A — add another inner class to hold_modifiers.gd, register below.
#   Option B — standalone script extending HoldModifierBase, register below.
# ═══════════════════════════════════════════════════════════════════════════════

extends Node

# Path to hold_modifiers.gd (contains HoldModifierBase + all inner-class modifiers)
const HOLD_MODIFIERS_PATH := "res://scripts/climbing/hold_modifiers.gd"

const MODIFIER_DISPLAY_NAMES: Dictionary = {
	"falling": "Falling",
}

var _hold_modifiers_script = null   # the loaded hold_modifiers.gd GDScript resource

func _ready() -> void:
	if ResourceLoader.exists(HOLD_MODIFIERS_PATH):
		_hold_modifiers_script = load(HOLD_MODIFIERS_PATH)
	else:
		push_warning("HoldModifierRegistry: hold_modifiers.gd not found at: %s" % HOLD_MODIFIERS_PATH)

func get_all_modifier_types() -> Array:
	return MODIFIER_DISPLAY_NAMES.keys()

func get_display_name(type_key: String) -> String:
	return MODIFIER_DISPLAY_NAMES.get(type_key, type_key.capitalize())

## Instantiate a blank modifier node by type key.
func create_modifier(type_key: String) -> Node:
	if _hold_modifiers_script == null:
		push_warning("HoldModifierRegistry: hold_modifiers.gd not loaded")
		return null

	match type_key:
		"falling":
			return _hold_modifiers_script.FallingHoldModifier.new()
		_:
			return null

## Instantiate and deserialize a modifier from saved JSON data.
func create_modifier_from_data(data: Dictionary) -> Node:
	var modifier := create_modifier(data.get("type", ""))
	if modifier and modifier.has_method("deserialize"):
		modifier.deserialize(data)
	return modifier
