extends CanvasLayer

signal resumed

var sfx_click: AudioStreamPlayer
var _is_animating: bool = false
var _panel: Control = null

func _ready() -> void:
	layer = 10
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio()
	await get_tree().process_frame
	_panel = _get_panel()
	if _panel:
		_panel.pivot_offset = _panel.size / 2.0
	_setup_button_hooks()

func _setup_audio() -> void:
	sfx_click = AudioStreamPlayer.new()
	sfx_click.process_mode = Node.PROCESS_MODE_ALWAYS
	sfx_click.bus = "SFX"
	add_child(sfx_click)
	var click_stream = load("res://assets/audio/sfx/button-clicked.wav")
	if click_stream:
		sfx_click.stream = click_stream

func _play_click() -> void:
	if sfx_click and sfx_click.stream:
		sfx_click.play()

func _setup_button_hooks() -> void:
	for btn in _get_all_buttons():
		btn.pressed.connect(_play_click)

func _get_all_buttons() -> Array:
	var buttons: Array = []
	_collect_buttons(self, buttons)
	return buttons

func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button or node is TextureButton:
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out)

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
