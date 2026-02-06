extends CanvasLayer

signal fade_out_finished
signal fade_in_finished

@onready var color_rect = $ColorRect
@onready var animation_player = $AnimationPlayer

func _ready() -> void:
	color_rect.visible = false
	animation_player.animation_finished.connect(_on_animation_finished)

func fade_out() -> void:
	color_rect.visible = true
	animation_player.play("fade_out")  # alpha 0 -> 1

func fade_in() -> void:
	animation_player.play("fade_in")   # alpha 1 -> 0

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "fade_out":
		emit_signal("fade_out_finished")
	elif anim_name == "fade_in":
		color_rect.visible = false
		emit_signal("fade_in_finished")
