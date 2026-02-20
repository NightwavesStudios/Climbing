extends CanvasLayer
## Level Complete Overlay - renders above the game world, independent of camera

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

func show_overlay(completed_level_path: String) -> void:
	_completed_level_path = completed_level_path

	print("=== LEVEL COMPLETE OVERLAY ===")
	print("Completed level: ", _completed_level_path)

	var next_level: String = GameState.get_next_level(_completed_level_path)
	print("Next level found: ", next_level)
	print("==============================")

	if next_button:
		next_button.visible = next_level != ""
		next_button.disabled = next_level == ""

	_kill_active_tweens()
	_set_buttons_alpha(0.0)
	_set_buttons_disabled(false)
	visible = true

	# Wait 0.25s after top-out before any button appears, then stagger
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

# =============================================================================
# BUTTON HANDLERS
# =============================================================================

func _on_next_button_pressed() -> void:
	var next_level: String = GameState.get_next_level(_completed_level_path)

	if next_level == "":
		print("ERROR: No next level found!")
		if next_button:
			next_button.visible = false
			next_button.disabled = true
		return

	print("Next level: ", next_level)
	GameState.set_current_level(next_level)

	_set_buttons_disabled(true)
	await _fade_out_buttons()
	next_level_requested.emit(next_level)

func _on_menu_button_pressed() -> void:
	_set_buttons_disabled(true)
	await _fade_out_buttons()
	menu_requested.emit()

func _on_restart_button_pressed() -> void:
	_set_buttons_disabled(true)
	await _fade_out_buttons()
	restart_requested.emit()
