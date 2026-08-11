extends CanvasLayer

const SETTINGS_SCRIPT := preload("res://scripts/ui/menus/settings.gd")
const MAIN_SCENE_PATH := "res://scenes/main/main_scene.tscn"

signal resumed

var _is_animating: bool = false
var _menu: Control = null
var _backdrop: ColorRect = null

# Transition singleton (or any external system) sets this to false
# before starting a transition and back to true once the scene is ready
static var pausing_enabled: bool = true

func _ready() -> void:
	layer = 10
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backdrop = get_node_or_null("Backdrop") as ColorRect
	_menu = get_node_or_null("Menu") as Control

## Safety net: if this node leaves the scene tree (e.g. transitioning to a
## menu while a [code]hide_pause_menu()[/code] call early-returned mid-animation),
## make sure the global pause flag is never left stuck on. Otherwise the next
## scene (a menu) would load already frozen.
func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false

func show_pause_menu() -> void:
	if _is_animating or not pausing_enabled:
		return
	_is_animating = true
	visible = true

	# Reset visuals for animation
	if _backdrop:
		_backdrop.color = Color(0, 0, 0, 0)
	if _menu:
		_menu.modulate = Color(1, 1, 1, 0)

	get_tree().paused = true

	# Animate backdrop and menu simultaneously
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	if _backdrop:
		tween.tween_property(_backdrop, "color:a", 0.55, 0.25)
	if _menu:
		tween.tween_property(_menu, "modulate", Color(1, 1, 1, 1), 0.18)
	await tween.finished
	_is_animating = false
	# Focus the first button for controller navigation
	call_deferred(&"_focus_pause_button")

func _focus_pause_button() -> void:
	var vbox := get_node_or_null("Menu") as VBoxContainer
	if vbox:
		for child in vbox.get_children():
			if child is Button and not child.disabled and child.visible:
				child.grab_focus()
				return

func hide_pause_menu() -> void:
	if _is_animating:
		return
	_is_animating = true
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	if _backdrop:
		tween.tween_property(_backdrop, "color:a", 0.0, 0.18)
	if _menu:
		tween.tween_property(_menu, "modulate", Color(1, 1, 1, 0), 0.14)
	await tween.finished
	get_tree().paused = false
	visible = false
	_is_animating = false

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _is_animating or not pausing_enabled:  # <-- guard added
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
	# Tell the settings scene to return to the level (not the main menu)
	# when the user backs out, so they resume where they were.
	SETTINGS_SCRIPT.return_scene = MAIN_SCENE_PATH
	await hide_pause_menu()
	Transition.to("res://scenes/menus/settings.tscn")

func _on_main_menu_pressed() -> void:
	await hide_pause_menu()
	var main = get_tree().get_first_node_in_group("main_scene")
	if main and main.has_method("cleanup_discipline_systems"):
		main.cleanup_discipline_systems()
	Transition.to("res://scenes/menus/main_menu.tscn")

func _on_skip_pressed() -> void:
	# Skip Level disabled
	pass
