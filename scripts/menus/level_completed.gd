extends CanvasLayer

signal next_level_requested(next_level_path: String)
signal menu_requested
signal restart_requested

@onready var next_button: Button = get_node_or_null("Control/NextButton")
@onready var menu_button: Button = get_node_or_null("Control/MenuButton")
@onready var restart_button: Button = get_node_or_null("Control/RestartButton")

var _completed_level_path: String = ""
var _active_tweens: Array = []

func _ready() -> void:
	visible = false
	layer = 10
	call_deferred("_set_buttons_alpha", 0.0)

func _get_next_destination(level_path: String) -> String:
	var next_in_collection: String = GameState.get_next_level(level_path)
	if next_in_collection != "":
		return next_in_collection

	var collection_ids: Array = GameState.get_all_collection_ids()
	var current_col: String = GameState.get_current_collection()
	var current_col_index: int = collection_ids.find(current_col)

	for i in range(current_col_index + 1, collection_ids.size()):
		var candidate: String = collection_ids[i]
		if GameState.is_collection_unlocked(candidate):
			var data: Dictionary = GameState.get_collection_data(candidate)
			if not data.is_empty() and data.levels.size() > 0:
				return data.levels[0]

	return ""

func _is_last_in_collection(level_path: String) -> bool:
	return GameState.get_next_level(level_path) == ""

func show_overlay(completed_level_path: String) -> void:
	_completed_level_path = completed_level_path

	var next_dest: String = _get_next_destination(_completed_level_path)

	if next_button:
		if next_dest == "":
			next_button.visible = false
			next_button.disabled = true
		else:
			next_button.visible = true
			next_button.disabled = false
			if _is_last_in_collection(_completed_level_path):
				next_button.text = "Next Area"
			else:
				next_button.text = "Next Climb"

	_kill_active_tweens()
	_set_buttons_alpha(0.0)
	_set_buttons_disabled(false)
	visible = true

	_fade_in_button(menu_button,    0.25)
	_fade_in_button(restart_button, 0.40)
	_fade_in_button(next_button,    0.55)

func _fade_in_button(button: Button, delay: float) -> void:
	if not button or not button.visible:
		return
	var tween = create_tween()
	_active_tweens.append(tween)
	tween.tween_interval(delay)
	tween.tween_property(button, "modulate:a", 1.0, 0.35) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_CUBIC)

func _fade_out_buttons() -> void:
	_kill_active_tweens()
	var tween = create_tween()
	tween.set_parallel(true)
	var any_added = false
	for button in [menu_button, restart_button, next_button]:
		if button and button.visible:
			tween.tween_property(button, "modulate:a", 0.0, 0.2) \
				.set_ease(Tween.EASE_IN) \
				.set_trans(Tween.TRANS_CUBIC)
			any_added = true
	if any_added:
		await tween.finished
	else:
		tween.kill()
	visible = false
	_set_buttons_alpha(0.0)

func _kill_active_tweens() -> void:
	for t in _active_tweens:
		if t and is_instance_valid(t):
			t.kill()
	_active_tweens.clear()

func _set_buttons_alpha(alpha: float) -> void:
	for button in [menu_button, restart_button, next_button]:
		if button:
			button.modulate.a = alpha

func _set_buttons_disabled(disabled: bool) -> void:
	for button in [menu_button, restart_button, next_button]:
		if button:
			button.disabled = disabled

func _on_next_button_pressed() -> void:
	var next_dest: String = _get_next_destination(_completed_level_path)
	if next_dest == "":
		if next_button:
			next_button.visible = false
			next_button.disabled = true
		return
	GameState.set_current_level(next_dest)
	_set_buttons_disabled(true)
	await _fade_out_buttons()
	next_level_requested.emit(next_dest)

func _on_menu_button_pressed() -> void:
	_set_buttons_disabled(true)
	await _fade_out_buttons()
	menu_requested.emit()

func _on_restart_button_pressed() -> void:
	_set_buttons_disabled(true)
	await _fade_out_buttons()
	restart_requested.emit()
