## random_background.gd
## Attach this script to any Control node to get a randomized animated background.
## The Control node should fill the screen (use a full-rect anchor or CanvasLayer > Control).
##
## Exported settings let you tweak behaviour per-scene in the Inspector.

class_name RandomBackground
extends Control

# ── Inspector knobs ──────────────────────────────────────────────────────────

## Automatically pick a random environment on _ready.
@export var auto_randomize_environment: bool = true

## Parallax strength of the mouse-follow effect (pixels).
@export var parallax_strength: Vector2 = Vector2(30.0, 20.0)

## Lerp speed of the parallax movement.
@export var parallax_speed: float = 3.0

## Whether to allow weather effects (ignored for "Gym" environment).
@export var enable_weather: bool = true

## Fade-in duration when the background becomes ready (0 = instant).
@export var fade_in_duration: float = 0.5

## Wall vertical span as a fraction of viewport height (centre anchor).
@export var wall_span_fraction: Vector2 = Vector2(0.3, 0.7)

## Ground line as a fraction of viewport height.
@export var ground_fraction: float = 0.85

# ── Weather types ────────────────────────────────────────────────────────────

enum WeatherType {
	NONE,
	RAIN,
	NIGHT,
	SNOW,
	LIGHTNING,
	FOG,
	HAIL,
}

# ── Internal state ───────────────────────────────────────────────────────────

var _wall: Node2D        = null
var _wall_ready: bool    = false
var _weather_set: bool   = false

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Hide until the wall finishes its first frame so there's no pop-in.
	modulate = Color(1, 1, 1, 0) if fade_in_duration > 0.0 else Color(1, 1, 1, 1)

	if auto_randomize_environment:
		_randomize_environment()

	_setup_background_wall()


func _process(delta: float) -> void:
	# ── Wait for the wall script to be fully initialised ──────────────────
	if not _wall_ready and _wall != null and _wall.get_script() != null:
		_configure_wall()
		_wall_ready = true
		if fade_in_duration > 0.0:
			_fade_in(fade_in_duration)
		else:
			modulate = Color(1, 1, 1, 1)

	# ── One-shot weather roll after wall is ready ─────────────────────────
	if _wall_ready and not _weather_set:
		_weather_set = true
		if enable_weather:
			_maybe_set_weather()

	# ── Mouse parallax ────────────────────────────────────────────────────
	if _wall_ready:
		var vp    := get_viewport_rect().size
		var mouse := get_viewport().get_mouse_position()
		var norm  := (mouse / vp - Vector2(0.5, 0.5)) * 2.0
		var target := Vector2(-norm.x * parallax_strength.x,
							  -norm.y * parallax_strength.y)
		_wall.position = _wall.position.lerp(target, delta * parallax_speed)

# ── Private helpers ──────────────────────────────────────────────────────────

func _randomize_environment() -> void:
	var env_types: Array = EnvironmentConfig.get_all_environment_types()
	if env_types.is_empty():
		return
	EnvironmentConfig.current_environment = env_types[randi() % env_types.size()]


func _setup_background_wall() -> void:
	_wall = Node2D.new()
	_wall.set_script(load("res://scripts/holds/dynamic_wall.gd"))
	add_child(_wall)
	move_child(_wall, 0)          # always draw behind siblings


func _configure_wall() -> void:
	var vp := get_viewport_rect().size

	# Bounds are centred on screen so sky/ground/clouds all render correctly.
	# wall_min.x == wall_max.x gives the wall rect zero width, so
	# _draw_rectangle_wall draws nothing visible (size.x = 0).
	# All background layers (sky, mountains, ground, clouds) expand outward
	# by BACKGROUND_EXPANSION = 2000 px from these bounds and fill the screen.
	var mid_x := vp.x * 0.5
	_wall.wall_min   = Vector2(mid_x, vp.y * wall_span_fraction.x)
	_wall.wall_max   = Vector2(mid_x, vp.y * wall_span_fraction.y)
	_wall.wall_valid  = true
	_wall.ground_y    = vp.y * ground_fraction
	_wall.ground_enabled  = true
	_wall.show_bolt_holes = false
	_wall.is_granite      = false

	# Rectangle mode with zero-width bounds — wall rect is invisible.
	_wall.use_polygon_mode = false

	# Zero out tonal outlines so no border stripe appears at wall edges
	# or the ground horizon line.
	_wall.wall_outline_width  = 0.0
	_wall.wall_outline_darken = 0.0

	_wall._apply_environment_theme()
	_wall._init_clouds()
	_wall.queue_redraw()


func _maybe_set_weather() -> void:
	# Skip weather in indoor/gym environments.
	if EnvironmentConfig.get_current_environment_name() == "Gym":
		return

	var wm: Node = _wall.get_node_or_null("WeatherModifier")
	if wm == null:
		return

	# Weighted rolls: ~55% chance of no weather, otherwise pick a type.
	# Rare/dramatic effects (lightning, hail) are less likely than common ones.
	var roll := randf()
	if roll < 0.55:
		wm.set_weather(WeatherType.NONE)
	elif roll < 0.70:
		wm.intensity = randf_range(0.3, 1.0)
		wm.set_weather(WeatherType.RAIN)
	elif roll < 0.80:
		wm.intensity = randf_range(0.3, 1.0)
		wm.set_weather(WeatherType.NIGHT)
	elif roll < 0.88:
		wm.intensity = randf_range(0.3, 1.0)
		wm.set_weather(WeatherType.SNOW)
	elif roll < 0.93:
		wm.intensity = randf_range(0.3, 1.0)
		wm.set_weather(WeatherType.FOG)
	elif roll < 0.97:
		wm.intensity = randf_range(0.3, 1.0)
		wm.set_weather(WeatherType.LIGHTNING)
	else:
		wm.intensity = randf_range(0.3, 1.0)
		wm.set_weather(WeatherType.HAIL)


func _fade_in(duration: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), duration)

# ── Public API ───────────────────────────────────────────────────────────────

## Force a new random environment and rebuild the background at runtime.
func rerandomize() -> void:
	_randomize_environment()
	if _wall != null:
		_wall.queue_free()
	_wall        = null
	_wall_ready  = false
	_weather_set = false
	modulate = Color(1, 1, 1, 0) if fade_in_duration > 0.0 else Color(1, 1, 1, 1)
	_setup_background_wall()

## Set a specific environment by name, then rebuild.
func set_environment(env_name: String) -> void:
	var env_types: Array = EnvironmentConfig.get_all_environment_types()
	for env in env_types:
		if str(env) == env_name:
			EnvironmentConfig.current_environment = env
			break
	rerandomize()

## Force a specific weather type directly.
func set_weather(type: WeatherType, intensity: float = 1.0) -> void:
	if _wall == null:
		return
	var wm: Node = _wall.get_node_or_null("WeatherModifier")
	if wm == null:
		return
	wm.intensity = intensity
	wm.set_weather(type)
