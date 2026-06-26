extends Button
class_name UniversalButton

@export var hover_scale: float = 1.05
@export var press_scale: float = 0.94
@export var animation_speed: float = 14.0
@export var use_squish_effect: bool = true

@export var enable_outline_pulse: bool = false
@export var outline_pulse_strength: float = 0.05
@export var outline_pulse_speed: float = 6.0

@export var enable_click_sound: bool = true
@export var click_volume_db: float = 0.0
@export var randomize_pitch: bool = true
@export var pitch_range: float = 0.1

const CLICK_SOUND = preload("res://assets/audio/sfx/button-clicked.wav")

var _target_scale: Vector2 = Vector2.ONE
var _is_hovered := false
var _audio_player: AudioStreamPlayer

func _ready() -> void:
	pivot_offset = size / 2.0
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.stream = CLICK_SOUND
	_audio_player.volume_db = click_volume_db
	
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	button_down.connect(_on_pressed)
	button_up.connect(_on_released)

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size / 2.0

func _process(delta: float) -> void:
	scale = scale.lerp(_target_scale, animation_speed * delta * 1.8)
	
	if enable_outline_pulse and _is_hovered and not disabled:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.001 * outline_pulse_speed) * outline_pulse_strength
		modulate = Color(pulse, pulse, pulse)
	else:
		modulate = Color.WHITE

func _on_hover() -> void:
	if disabled:
		return
	_is_hovered = true
	_target_scale = Vector2.ONE * hover_scale

func _on_unhover() -> void:
	_is_hovered = false
	_target_scale = Vector2.ONE

func _on_pressed() -> void:
	if disabled:
		return
	if use_squish_effect:
		_target_scale = Vector2(press_scale, press_scale * 1.08)
	else:
		_target_scale = Vector2.ONE * press_scale
	
	if enable_click_sound:
		if randomize_pitch:
			_audio_player.pitch_scale = 1.0 + randf_range(-pitch_range, pitch_range)
		else:
			_audio_player.pitch_scale = 1.0
		_audio_player.play()

func _on_released() -> void:
	if disabled:
		return
	if _is_hovered:
		_target_scale = Vector2.ONE * hover_scale
	else:
		_target_scale = Vector2.ONE

func set_visual_state(color: Color) -> void:
	modulate = color
