## random_background.gd
## Attach to a Control node that fills the screen.
## When  is_menu_background = true  it creates a  MenuBackground  node
## and hands control entirely to it.  For gameplay levels it creates
## the usual DynamicWall as before, but with cleaner initialisation.
class_name RandomBackground
extends Control

# ─────────────────────────────────────────────────────────────────────────────
# EXPORTS
# ─────────────────────────────────────────────────────────────────────────────

@export var auto_randomize_environment: bool = true
@export var is_menu_background:         bool = false
@export var parallax_strength:          Vector2 = Vector2(30.0, 20.0)
@export var parallax_speed:             float   = 3.0
@export var enable_weather:             bool    = true
@export var fade_in_duration:           float   = 0.5
@export var wall_span_fraction:         Vector2 = Vector2(0.3, 0.7)
@export var ground_fraction:            float   = 0.85

# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE STATE
# ─────────────────────────────────────────────────────────────────────────────

var _menu_bg:      Node2D         = null   # used when is_menu_background
var _wall:         Node2D         = null   # used for gameplay backgrounds
var _wall_ready:   bool           = false
var _weather_set:  bool           = false

# ─────────────────────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	modulate = Color(1, 1, 1, 0) if fade_in_duration > 0.0 else Color(1, 1, 1, 1)

	if is_menu_background:
		_setup_menu_background()
	else:
		if auto_randomize_environment:
			_randomize_environment()
		_setup_wall()

func _process(delta: float) -> void:
	if is_menu_background:
		# MenuBackground handles everything internally; just fade in once.
		if _menu_bg != null and not _wall_ready:
			_wall_ready = true
			_do_fade_in()
		return

	# ── Gameplay wall ─────────────────────────────────────────────────────
	if not is_instance_valid(_wall): return

	if not _wall_ready:
		if not _wall.get("_is_ready"): return
		_configure_wall()
		_wall_ready = true
		_do_fade_in()

	if _wall_ready and not _weather_set:
		_weather_set = true
		if enable_weather:
			_maybe_set_weather()

	# Mouse parallax for gameplay wall
	if _wall_ready:
		var vp   := get_viewport_rect().size
		var mp   := get_viewport().get_mouse_position()
		var norm := (mp / vp - Vector2(0.5, 0.5)) * 2.0
		var tgt  := Vector2(-norm.x * parallax_strength.x, -norm.y * parallax_strength.y)
		_wall.position = _wall.position.lerp(tgt, delta * parallax_speed)

# ─────────────────────────────────────────────────────────────────────────────
# MENU BACKGROUND SETUP
# ─────────────────────────────────────────────────────────────────────────────

func _setup_menu_background() -> void:
	_menu_bg                  = MenuBackground.new()
	_menu_bg.parallax_strength = parallax_strength
	_menu_bg.parallax_speed    = parallax_speed
	# Start the cycle near sunset (0.48)
	_menu_bg.set_time_of_day(0.48)
	add_child(_menu_bg)
	move_child(_menu_bg, 0)

# ─────────────────────────────────────────────────────────────────────────────
# GAMEPLAY WALL SETUP
# ─────────────────────────────────────────────────────────────────────────────

func _setup_wall() -> void:
	_wall_ready  = false
	_weather_set = false
	_wall        = Node2D.new()
	_wall.set_script(load("res://scripts/holds/dynamic_wall.gd"))
	add_child(_wall)
	move_child(_wall, 0)

func _configure_wall() -> void:
	var vp    := get_viewport_rect().size
	var mid_x := vp.x * 0.5

	_wall.wall_min         = Vector2(mid_x, vp.y * wall_span_fraction.x)
	_wall.wall_max         = Vector2(mid_x, vp.y * wall_span_fraction.y)
	_wall.wall_valid       = true
	_wall.ground_y         = vp.y * ground_fraction
	_wall.ground_enabled   = true
	_wall.show_bolt_holes  = false
	_wall.is_granite       = false
	_wall.use_polygon_mode = false
	_wall.wall_outline_width  = 0.0
	_wall.wall_outline_darken = 0.0
	_wall.z_index = -1
	_wall.set_meta("is_background_wall", true)

	_wall._apply_environment_theme()
	_wall._init_clouds()
	_wall.queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _randomize_environment() -> void:
	var all := EnvironmentConfig.get_all_environment_types()
	if all.is_empty(): return
	const EXCLUDED := ["Building", "Urban", "City", "Dark", "Menu"]
	var filtered := all.filter(func(e): 
		var n := str(e)
		for kw in EXCLUDED:
			if n.containsn(kw): return false
		return true)
	if filtered.is_empty(): return
	EnvironmentConfig.current_environment = filtered[randi() % filtered.size()]

func _maybe_set_weather() -> void:
	if EnvironmentConfig.get_current_environment_name() == "Gym": return
	var wm : Node = _wall.get_node_or_null("WeatherModifier")
	if wm == null: return
	var roll := randf()
	if    roll < 0.90: wm.set_weather(0)
	elif  roll < 0.95: wm.intensity = randf_range(0.3, 1.0); wm.set_weather(1)   # rain
	elif  roll < 0.97: wm.intensity = randf_range(0.3, 1.0); wm.set_weather(3)   # snow
	elif  roll < 0.98: wm.intensity = randf_range(0.3, 1.0); wm.set_weather(5)   # fog
	elif  roll < 0.99: wm.intensity = randf_range(0.3, 1.0); wm.set_weather(4)   # lightning
	else:              wm.intensity = randf_range(0.3, 1.0); wm.set_weather(6)   # hail

func _do_fade_in() -> void:
	if fade_in_duration <= 0.0:
		modulate = Color(1, 1, 1, 1)
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), fade_in_duration)

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

## Rebuild with a new random environment.
func rerandomize() -> void:
	_wall_ready  = false
	_weather_set = false
	if is_menu_background:
		if is_instance_valid(_menu_bg): _menu_bg.queue_free()
		_menu_bg = null
		_setup_menu_background()
	else:
		if is_instance_valid(_wall): _wall.queue_free()
		_wall = null
		modulate = Color(1, 1, 1, 0) if fade_in_duration > 0.0 else Color(1, 1, 1, 1)
		_setup_wall()

## Weather is not available on the menu background (removed for cinematic quality).
func set_weather(_kind: int, _intensity: float = 1.0) -> void:
	pass  # weather removed from MenuBackground
