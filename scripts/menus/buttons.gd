extends Button
class_name UniversalButton

@export_group("Visual")
@export var hover_scale: float = 1.05
@export var press_scale: float = 0.94
@export var animation_speed: float = 14.0
@export var use_squish_effect := true

@export_group("Outline Pulse")
@export var enable_outline_pulse := false
@export var outline_pulse_strength := 0.05
@export var outline_pulse_speed := 6.0

@export_group("Audio")
@export var enable_click_sound := true
@export var click_volume_db := 0.0
@export var randomize_pitch := true
@export var pitch_range := 0.1

const CLICK_SOUND := preload("res://assets/audio/sfx/button-clicked.wav")

var _target_scale := Vector2.ONE
var _is_hovered := false
var _audio_player: AudioStreamPlayer

func _ready() -> void:
	_update_pivot()

	_setup_audio()
	_connect_signals()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_pivot()

func _process(delta: float) -> void:
	_update_scale(delta)
	_update_outline_pulse()

func _setup_audio() -> void:
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

	_audio_player.stream = CLICK_SOUND
	_audio_player.volume_db = click_volume_db

func _connect_signals() -> void:
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)

	button_down.connect(_on_pressed)
	button_up.connect(_on_released)

func _update_pivot() -> void:
	pivot_offset = size / 2.0

func _update_scale(delta: float) -> void:
	scale = scale.lerp(_target_scale, animation_speed * delta)

func _update_outline_pulse() -> void:
	if !enable_outline_pulse or !_is_hovered:
		modulate = Color.WHITE
		return

	var pulse := 1.0 + sin(
		Time.get_ticks_msec() * 0.001 * outline_pulse_speed
	) * outline_pulse_strength

	modulate = Color(pulse, pulse, pulse)

func _on_hover() -> void:
	if !_can_interact():
		return

	_is_hovered = true
	_set_hover_scale()

func _on_unhover() -> void:
	_is_hovered = false
	_set_normal_scale()

func _on_pressed() -> void:
	if !_can_interact():
		return

	if use_squish_effect:
		_set_pressed_scale()

	_play_click_sound()

func _on_released() -> void:
	if !_can_interact():
		return

	if _is_hovered:
		_set_hover_scale()
	else:
		_set_normal_scale()

func _set_normal_scale() -> void:
	_target_scale = Vector2.ONE

func _set_hover_scale() -> void:
	_target_scale = Vector2.ONE * hover_scale

func _set_pressed_scale() -> void:
	_target_scale = Vector2(press_scale, hover_scale)

func _play_click_sound() -> void:
	if !enable_click_sound:
		return

	if randomize_pitch:
		_audio_player.pitch_scale = 1.0 + randf_range(-pitch_range, pitch_range)
	else:
		_audio_player.pitch_scale = 1.0

	_audio_player.play()

func _can_interact() -> bool:
	return !disabled

func set_visual_state(color: Color) -> void:
	modulate = color
