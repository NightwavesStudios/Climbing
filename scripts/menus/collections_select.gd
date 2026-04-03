extends Control

@onready var map_container: Control = $HBoxContainer

var button_to_collection: Dictionary = {}

const COLOR_UNLOCKED    := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_COMPLETED   := Color(0.4, 1.0, 0.4, 1.0)
const COLOR_LOCKED      := Color(0.3, 0.3, 0.3, 0.5)

func _ready() -> void:
	if not map_container:
		push_error("collection_select: $HBoxContainer node not found!")
		return

	_find_and_map_buttons()
	_update_collection_states()

func _find_and_map_buttons() -> void:
	var active_ids: Array = GameState.get_all_collection_ids()
	print("=== COLLECTION SELECT: Active collection IDs: ", active_ids)

	for child in map_container.get_children():
		if not child is Button:
			continue

		# Never show buttons hidden in the editor
		if not child.visible:
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
	var id_nosep  := id_lower.replace("-", "").replace("_", "")
	var btn_nosep := btn_lower.replace("-", "").replace("_", "")

	# Exact match (with or without separators)
	if id_nosep == btn_nosep:
		return true

	# Button name is contained in ID or vice versa (no separators)
	if id_nosep in btn_nosep or btn_nosep in id_nosep:
		return true

	return false


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
			var check_tex := load("res://assets/checkmark.png")
			if check_tex:
				var sprite := Sprite2D.new()
				sprite.name     = "CompletionIndicator"
				sprite.texture  = check_tex
				var target_size := 48.0
				var tex_size    = check_tex.get_size()
				var scale_val   = target_size / max(tex_size.x, tex_size.y)
				sprite.scale    = Vector2(scale_val * 3, scale_val * 3)
				sprite.modulate = Color(0.0, 1.0, 0.0, 1.0)
				sprite.z_index  = 1
				button.add_child(sprite)
				# Defer so button.size is resolved before positioning
				sprite.set_deferred("position", Vector2(button.size.x / 2.0, button.size.y / 2.0))

		"lock":
			var lock_tex := load("res://assets/locked.png")
			if lock_tex:
				var sprite := Sprite2D.new()
				sprite.name     = "LockIndicator"
				sprite.texture  = lock_tex
				var target_size := 48.0
				var tex_size    = lock_tex.get_size()
				var scale_val   = target_size / max(tex_size.x, tex_size.y)
				sprite.scale    = Vector2(scale_val, scale_val)
				sprite.position = Vector2(button.size.x / 2.0, button.size.y / 2.0)
				sprite.z_index  = 1
				button.add_child(sprite)
			else:
				# Fallback: scaled-down TextureRect
				var tex_rect := TextureRect.new()
				tex_rect.name            = "LockIndicator"
				tex_rect.texture         = load("res://assets/locked.png")
				tex_rect.stretch_mode    = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.custom_minimum_size = Vector2(48, 48)
				tex_rect.size            = Vector2(48, 48)
				tex_rect.position        = Vector2(button.size.x / 2.0 - 24, button.size.y / 2.0 - 24)
				tex_rect.z_index         = 1
				button.add_child(tex_rect)


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

func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/main_menu.tscn")
