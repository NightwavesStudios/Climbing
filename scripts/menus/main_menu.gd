extends Control

@onready var buttons: VBoxContainer = $Buttons

var hover_scale := Vector2(1.1, 1.1)
var pressed_scale := Vector2(0.94, 0.94)
var normal_scale := Vector2.ONE

func _ready() -> void:
	_setup_buttons()

	if buttons.get_child_count() > 0:
		buttons.get_child(0).grab_focus()


# --------------------------
# BUTTON CALLBACKS
# --------------------------

func _on_play_pressed() -> void:
	Transition.to("res://scenes/main/main_scene.tscn")

func _on_level_maker_pressed() -> void:
	Transition.to("res://scenes/editor/level_editor.tscn")

func _on_settings_pressed() -> void:
	Transition.to("res://scenes/menus/settings.tscn")

func _on_quit_pressed() -> void:
	Transition.to("")  # We'll handle quitting separately in Transition manager
	# Or if you want immediate quit: get_tree().quit()


# --------------------------
# BUTTON HOVER/CLICK ANIMATIONS
# --------------------------

func _setup_buttons() -> void:
	for b in buttons.get_children():
		if b is Button:
			b.pivot_offset = b.size / 2
			b.focus_mode = Control.FOCUS_ALL

			b.mouse_entered.connect(_hover.bind(b))
			b.mouse_exited.connect(_unhover.bind(b))
			b.focus_entered.connect(_hover.bind(b))
			b.focus_exited.connect(_unhover.bind(b))
			b.pressed.connect(_press.bind(b))


func _hover(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", hover_scale, 0.12)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)


func _unhover(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", normal_scale, 0.12)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)


func _press(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", pressed_scale, 0.06)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(button, "scale", hover_scale, 0.08)
