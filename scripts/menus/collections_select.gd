extends Control

@onready var map_container: Control = $HBoxContainer

var button_to_collection: Dictionary = {}

const COLOR_UNLOCKED    := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_COMPLETED   := Color(0.4, 1.0, 0.4, 1.0)
const COLOR_LOCKED      := Color(0.3, 0.3, 0.3, 0.5)


# =============================================================================
# READY
# =============================================================================

func _ready() -> void:
	if not map_container:
		push_error("collection_select: $HBoxContainer node not found!")
		return

	_find_and_map_buttons()
	_update_collection_states()


# =============================================================================
# BUTTON DISCOVERY
# =============================================================================

func _find_and_map_buttons() -> void:
	var active_ids: Array = GameState.get_all_collection_ids()
	print("=== COLLECTION SELECT: Active collection IDs: ", active_ids)

	for child in map_container.get_children():
		if not child is Button:
			continue

		var btn_lower := child.name.to_lower()
		var matched_id := _match_collection_id(btn_lower, active_ids)

		print("  Button '%s' (lower: '%s') → matched: '%s'" % [child.name, btn_lower, matched_id])

		if matched_id != "":
			button_to_collection[child] = matched_id
			child.visible = true
			if not child.pressed.is_connected(_on_button_pressed):
				child.pressed.connect(_on_button_pressed.bind(child))
		else:
			child.visible = false

	print("  Total mapped buttons: ", button_to_collection.size())


func _match_collection_id(btn_lower: String, all_ids: Array) -> String:
	var sorted := all_ids.duplicate()
	sorted.sort_custom(func(a, b): return a.length() > b.length())
	for id in sorted:
		if _button_matches(btn_lower, id):
			return id
	return ""


func _button_matches(btn_lower: String, collection_id: String) -> bool:
	var id_lower := collection_id.to_lower()

	if id_lower in btn_lower:
		return true

	var id_nosep  := id_lower.replace("-", "").replace("_", "")
	var btn_nosep := btn_lower.replace("-", "").replace("_", "")
	if id_nosep in btn_nosep:
		return true

	for token in id_lower.replace("_", "-").split("-", false):
		if token.length() >= 3 and token in btn_lower:
			return true

	return false


# =============================================================================
# VISUAL STATE
# =============================================================================

func _update_collection_states() -> void:
	for button in button_to_collection.keys():
		var id = button_to_collection[button]
		var unlocked  := GameState.is_collection_unlocked(id)
		var completed := GameState.is_collection_completed(id)

		button.disabled = false

		if completed:
			button.modulate = COLOR_COMPLETED
			_set_indicator(button, "completion")
		elif unlocked:
			button.modulate = COLOR_UNLOCKED
			_set_indicator(button, "none")
		else:
			button.modulate = COLOR_LOCKED
			_set_indicator(button, "lock")


func _set_indicator(button: Button, mode: String) -> void:
	for node_name in ["CompletionIndicator", "LockIndicator"]:
		var n := button.get_node_or_null(node_name)
		if n:
			n.queue_free()

	match mode:
		"completion":
			var lbl := Label.new()
			lbl.name     = "CompletionIndicator"
			lbl.text     = "✓"
			lbl.add_theme_font_size_override("font_size", 32)
			lbl.modulate = Color(0.0, 1.0, 0.0, 1.0)
			lbl.position = Vector2(button.size.x - 40, -10)
			lbl.z_index  = 1
			button.add_child(lbl)

		"lock":
			var lbl := Label.new()
			lbl.name     = "LockIndicator"
			lbl.text     = "🔒"
			lbl.add_theme_font_size_override("font_size", 32)
			lbl.position = Vector2(button.size.x / 2.0 - 16, button.size.y / 2.0 - 16)
			lbl.z_index  = 1
			button.add_child(lbl)


# =============================================================================
# BUTTON PRESS
# =============================================================================

func _on_button_pressed(button: Button) -> void:
	if button in button_to_collection:
		_select_collection(button_to_collection[button])


func _select_collection(id: String) -> void:
	print("collection_select: Selected '%s', unlocked=%s" % [id, GameState.is_collection_unlocked(id)])

	if not GameState.is_collection_unlocked(id):
		_show_unlock_requirement(id)
		return

	GameState.set_current_collection(id)
	print("collection_select: GameState.current_collection = ", GameState.current_collection)
	Transition.to("res://scenes/menus/level_select.tscn")


func _show_unlock_requirement(id: String) -> void:
	var data := GameState.get_collection_data(id)
	var req  = data.unlock_requirement
	var msg  := "LOCKED\n\n"

	match req.type:
		"collection_complete":
			var req_name = GameState.get_collection_data(req.collection).get("name", req.collection)
			msg += "Complete '%s' to unlock" % req_name
		"total_levels":
			msg += "Complete %d levels to unlock\nProgress: %d/%d" \
				% [req.count, GameState.get_total_completed_levels(), req.count]
		"collections_complete":
			msg += "Complete %d collections to unlock\nProgress: %d/%d" \
				% [req.count, GameState.completed_collections.size(), req.count]

	print(msg)


# =============================================================================
# BACK
# =============================================================================

func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/main_menu.tscn")
