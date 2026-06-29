extends Button
class_name UniversalButton

## ── Exports ──────────────────────────────────────────────────────────────────
@export_group("Visual")
@export var hover_scale: float = 1.05
@export var press_scale: float = 0.94
## lerp factor per second for scale animation (applied via _process when hovered).
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

## ── Constants ────────────────────────────────────────────────────────────────
const CLICK_SOUND := preload("res://assets/audio/sfx/button-clicked.wav")

## ── State ────────────────────────────────────────────────────────────────────
var _is_hovered := false
var _audio_player: AudioStreamPlayer
var _pulse_time: float = 0.0
var _target_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_update_pivot()
	_setup_audio()
	_connect_signals()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_pivot()


# ── Per-frame animation (only active when hovered or animating) ─────────────
func _process(delta: float) -> void:
	# ── Smooth lerp scale animation (runs while scale != target) ──
	if scale != _target_scale:
		scale = scale.lerp(_target_scale, animation_speed * delta)
		# Snap when close enough to avoid micro-drift
		if scale.distance_to(_target_scale) < 0.001:
			scale = _target_scale

	# ── Outline pulse ──
	if _is_hovered and enable_outline_pulse:
		_pulse_time += delta
		var pulse := 1.0 + sin(_pulse_time * outline_pulse_speed) * outline_pulse_strength
		modulate = Color(pulse, pulse, pulse)

	# ── Stop _process only when BOTH idle AND fully settled ──
	if not _is_hovered \
	and not enable_outline_pulse \
	and scale == _target_scale:
		set_process(false)


# ── Setup ────────────────────────────────────────────────────────────────────
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


# ── Interactivity ────────────────────────────────────────────────────────────
func _on_hover() -> void:
	if not _can_interact():
		return
	_is_hovered = true
	_target_scale = Vector2.ONE * hover_scale
	set_process(true)

func _on_unhover() -> void:
	_is_hovered = false
	_target_scale = Vector2.ONE
	modulate = Color.WHITE

func _on_pressed() -> void:
	if not _can_interact():
		return
	if use_squish_effect:
		_target_scale = Vector2(press_scale, hover_scale)
		scale = _target_scale
	_play_click_sound()

func _on_released() -> void:
	if not _can_interact():
		return
	if _is_hovered:
		_target_scale = Vector2.ONE * hover_scale
	else:
		_target_scale = Vector2.ONE


# ── Audio ────────────────────────────────────────────────────────────────────
func _play_click_sound() -> void:
	if not enable_click_sound:
		return
	if randomize_pitch:
		_audio_player.pitch_scale = 1.0 + randf_range(-pitch_range, pitch_range)
	else:
		_audio_player.pitch_scale = 1.0
	_audio_player.play()

func _can_interact() -> bool:
	return not disabled

func set_visual_state(color: Color) -> void:
	modulate = color
