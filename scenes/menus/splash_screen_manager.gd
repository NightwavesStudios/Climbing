extends Control

@export var load_scene : PackedScene
@export var in_time : float = 0.5
@export var fade_in_time : float = 1.0
@export var pause_time : float = 1.5
@export var fade_out_time : float = 1.2
@export var out_time : float = 0.3
@export var splash_screen : TextureRect

func _ready() -> void:
	fade()

func fade() -> void:
	splash_screen.modulate.a = 0.0
	splash_screen.scale = Vector2(0.92, 0.92)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_interval(in_time)
	tween.tween_property(splash_screen, "modulate:a", 1.0, fade_in_time)
	tween.tween_property(splash_screen, "scale", Vector2(1.0, 1.0), fade_in_time)
	tween.tween_interval(pause_time)
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(splash_screen, "modulate:a", 0.0, fade_out_time)
	tween.tween_interval(out_time)
	await tween.finished
	MusicPlayer.start()
	get_tree().change_scene_to_packed(load_scene)
