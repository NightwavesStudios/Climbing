extends CanvasLayer
signal resumed
var _is_animating: bool = false
var _panel: Control = null
func _ready() -> void:
	layer = 10
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_panel = _get_panel()
	if _panel:
		_panel.pivot_offset = _panel.size / 2.0
func _get_panel() -> Control:
	for child in get_children():
		if child is Control:
			return child
	return null
func show_pause_menu() -> void:
	if _is_animating:
		return
	_is_animating = true
	visible = true
	if _panel:
		_panel.modulate = Color(1, 1, 1, 0)
		_panel.scale = Vector2(0.85, 0.85)
		_panel.pivot_offset = _panel.size / 2.0
	get_tree().paused = true
	if _panel:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(_panel, "modulate", Color(1, 1, 1, 1), 0.18)
		tween.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.22)
		await tween.finished
	_is_animating = false
func hide_pause_menu() -> void:
	if _is_animating:
		return
	_is_animating = true
	if _panel:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(_panel, "modulate", Color(1, 1, 1, 0), 0.14)
		tween.tween_property(_panel, "scale", Vector2(0.85, 0.85), 0.14)
		await tween.finished
	get_tree().paused = false
	visible = false
	_is_animating = false
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _is_animating:
		return
	get_viewport().set_input_as_handled()
	if visible:
		_on_resume_pressed()
	else:
		show_pause_menu()
func _on_resume_pressed() -> void:
	await hide_pause_menu()
	resumed.emit()
func _on_settings_pressed() -> void:
	await hide_pause_menu()
	Transition.to("res://scenes/menus/settings.tscn")
func _on_main_menu_pressed() -> void:
	await hide_pause_menu()
	var main = get_tree().get_first_node_in_group("main_scene")
	if main and main.has_method("cleanup_discipline_systems"):
		main.cleanup_discipline_systems()
	Transition.to("res://scenes/menus/main_menu.tscn")
