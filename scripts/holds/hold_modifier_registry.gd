# hold_modifier_registry.gd
# res://scripts/holds/hold_modifier_registry.gd
# ═══════════════════════════════════════════════════════════════════════════════
# Autoload singleton. Register in Project → Autoloads as "HoldModifierRegistry".
#
# To add a new modifier:
#   1. Add its class to hold_modifiers.gd (or a new file) extending HoldModifierBase
#   2. Add one entry to MODIFIER_CLASSES and one to MODIFIER_DISPLAY_NAMES below
#   3. Done — editor dropdown, level loader, and JSON all pick it up automatically
# ═══════════════════════════════════════════════════════════════════════════════

extends Node

# ── Registration ──────────────────────────────────────────────────────────────
# All modifier classes must be preloaded so GDScript can instantiate them.
# Using a script path means we don't need separate .tscn files.

const _HOLD_MODIFIERS = preload("res://scripts/holds/hold_modifiers.gd")

var _factories: Dictionary = {}

const MODIFIER_DISPLAY_NAMES: Dictionary = {
	"falling": "Falling",
	# "slippery":  "Slippery",
	# "crumbling": "Crumbling",
	# "moving":    "Moving",
}

func _ready() -> void:
	# Register each modifier type with a factory lambda.
	# Add one line here per new modifier class.
	_factories["falling"] = func() -> HoldModifierBase:
		return _HOLD_MODIFIERS.FallingHoldModifier.new()

	# Future modifiers:
	# _factories["slippery"] = func() -> HoldModifierBase:
	#     return SlipperyHoldModifier.new()

# ── Public API ────────────────────────────────────────────────────────────────

func get_all_modifier_types() -> Array:
	return _factories.keys()

func get_display_name(type_key: String) -> String:
	return MODIFIER_DISPLAY_NAMES.get(type_key, type_key.capitalize())

## Instantiate a blank modifier by type key. Returns null if unknown.
func create_modifier(type_key: String) -> HoldModifierBase:
	if not _factories.has(type_key):
		push_warning("HoldModifierRegistry: unknown modifier type '%s'" % type_key)
		return null
	return _factories[type_key].call()

## Instantiate and deserialize a modifier from a saved Dictionary.
func create_modifier_from_data(data: Dictionary) -> HoldModifierBase:
	var type_key: String = data.get("type", "")
	var modifier := create_modifier(type_key)
	if modifier:
		modifier.deserialize(data)
	return modifier
