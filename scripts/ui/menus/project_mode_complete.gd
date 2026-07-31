extends CanvasLayer
class_name ProjectModeComplete

## Simple overlay shown when the player tops out in project mode.
## Displays a single button styled like the "Next Climb" button.
## Clicking it emits a signal so the main scene can reset the climb.

signal complete_requested

@onready var complete_button: Button = $CompleteButton


func _ready() -> void:
	complete_button.modulate.a = 0.0


func show_overlay() -> void:
	visible = true
	complete_button.modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_interval(0.15)
	tween.tween_property(complete_button, "modulate:a", 1.0, 0.35)


func hide_overlay() -> void:
	visible = false
	queue_free()


func _on_complete_button_pressed() -> void:
	complete_requested.emit()