extends Control

@export var load_scene : PackedScene
@export var in_time : float = 0.5
@export var fade_in_time : float = 1.0
@export var pause_time : float = 1.5
@export var fade_out_time : float = 1.2
@export var out_time : float = 0.3
@export var splash_screen : TextureRect

@onready var version_label: Label = $CenterContainer2/VersionLabel


func _ready() -> void:
	fade()


func fade() -> void:
	# Initialize states — both elements start invisible
	splash_screen.modulate.a = 0.0
	version_label.modulate.a = 0.0

	var tween := create_tween()

	# ── Initial delay ──
	tween.tween_interval(in_time)

	# ── Phase 1: Fade in both elements together ──
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(splash_screen, "modulate:a", 1.0, fade_in_time)
	tween.parallel().tween_property(version_label, "modulate:a", 1.0, fade_in_time)

	# ── Phase 2: Hold ──
	tween.tween_interval(pause_time)

	# ── Phase 3: Fade out both elements together ──
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(splash_screen, "modulate:a", 0.0, fade_out_time)
	tween.parallel().tween_property(version_label, "modulate:a", 0.0, fade_out_time)

	# ── Final delay ──
	tween.tween_interval(out_time)

	await tween.finished
	MusicPlayer.start()
	# Use the project's Transition autoload for a smooth fade-to-black,
	# scene swap, then fade-in — consistent with every other scene change.
	Transition.to(load_scene.resource_path)
