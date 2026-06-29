# hold_modifiers.gd
# ═══════════════════════════════════════════════════════════════════════════════
# HoldModifierBase — base class, extend this for every modifier.
# Concrete modifiers (e.g. FallingHoldModifier) live in their own files.
# ═══════════════════════════════════════════════════════════════════════════════

class_name HoldModifierBase
extends Node

var modifier_type: String = "base"
var hold: Node2D = null

func _ready() -> void:
	hold = get_parent() as Node2D
	if hold == null:
		push_error("HoldModifierBase (%s): parent must be a Node2D hold." % modifier_type)

func on_hold_ready() -> void:
	pass

func on_process(_delta: float) -> void:
	pass

func allow_grab(_limb_node: Node2D, _is_foot: bool) -> bool:
	return true

func on_grab(_limb_node: Node2D) -> void:
	pass

func on_release(_limb_node: Node2D) -> void:
	pass

func modify_pressure(raw: float, _delta: float) -> float:
	return raw

func modify_recovery(raw: float, _delta: float) -> float:
	return raw

func serialize() -> Dictionary:
	return {"type": modifier_type}

func deserialize(_data: Dictionary) -> void:
	pass

func get_display_name() -> String:
	return modifier_type.capitalize()

