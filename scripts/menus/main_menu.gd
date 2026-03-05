extends Control

@onready var buttons: VBoxContainer = $CanvasLayer/Buttons
@onready var music_player: AudioStreamPlayer = $MainMenuTheme

# 🎵 Set these to your desired loop timestamps (in seconds)
const MUSIC_LOOP_START := 57.6
const MUSIC_LOOP_END   := 115.2

var _wall: Node2D = null
var _wall_ready := false
var _weather_set := false

func _ready() -> void:
	modulate = Color(1, 1, 1, 0)
	_randomize_environment()
	_setup_background_wall()
	music_player.play()

func _randomize_environment() -> void:
	var env_types = EnvironmentConfig.get_all_environment_types()
	EnvironmentConfig.current_environment = env_types[randi() % env_types.size()]

func _setup_background_wall() -> void:
	_wall = Node2D.new()
	_wall.set_script(load("res://scripts/holds/dynamic_wall.gd"))
	add_child(_wall)
	move_child(_wall, 0)

func _process(delta: float) -> void:
	# --- Music loop check ---
	if music_player.playing and music_player.get_playback_position() >= MUSIC_LOOP_END:
		music_player.seek(MUSIC_LOOP_START)

	if not _wall_ready and _wall != null and _wall.get_script() != null:
		var vp := get_viewport_rect().size
		var center := vp / 2.0
		_wall.wall_min = Vector2(center.x, center.y * 0.3)
		_wall.wall_max = Vector2(center.x, center.y * 0.7)
		_wall.wall_valid = true
		_wall.ground_y = vp.y * 0.85
		_wall.ground_enabled = true
		_wall.show_bolt_holes = false
		_wall.is_granite = false
		_wall.edge_color = Color(0, 0, 0, 0)
		_wall.top_edge_color = Color(0, 0, 0, 0)
		_wall._apply_environment_theme()
		_wall._init_clouds()
		_wall.queue_redraw()
		_wall_ready = true
		_fade_in_menu()

	if _wall_ready and not _weather_set:
		_weather_set = true
		_maybe_set_weather()

	if _wall_ready:
		var vp := get_viewport_rect().size
		var mouse := get_viewport().get_mouse_position()
		var norm := (mouse / vp - Vector2(0.5, 0.5)) * 2.0
		var target := Vector2(-norm.x * 30.0, -norm.y * 20.0)
		_wall.position = _wall.position.lerp(target, delta * 3.0)

func _maybe_set_weather() -> void:
	if EnvironmentConfig.get_current_environment_name() == "Gym":
		return
	var wm: Node = _wall.get_node_or_null("WeatherModifier")
	if wm == null:
		return
	
	var roll := randf()
	
	if roll < 0.1:
		wm.intensity = randf_range(0.3, 1.0)
		wm.set_weather(3)
	elif roll < 0.3:
		wm.intensity = randf_range(0.3, 1.0)
		wm.set_weather(1)

func _fade_in_menu() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.5)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

func _on_play_pressed() -> void:
	Transition.to("res://scenes/menus/collections_select.tscn")

func _on_level_maker_pressed() -> void:
	Transition.to("res://scenes/editor/level_editor.tscn")

func _on_settings_pressed() -> void:
	Transition.to("res://scenes/menus/settings.tscn")

func _on_quit_pressed() -> void:
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
