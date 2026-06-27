## dynamic_wall.gd NEW AND BROKEN ONE
## Procedural climbing-wall renderer.  Handles sky, mountains, clouds,
## ground, weather, the wall surface itself, and the polygon editor overlay.
##
## All drawing is done in _draw().  No Sprite or Texture nodes are used.
## The wall is rebuilt by calling  calculate_bounds_from_holds()  or
## set_polygon_data().  update_environment_settings()  re-reads EnvironmentConfig
## and triggers a redraw.
extends Node2D
class_name DynamicWall

# ─────────────────────────────────────────────────────────────────────────────
# EXPORTS
# ─────────────────────────────────────────────────────────────────────────────

@export var use_polygon_mode:   bool  = false
@export var edit_mode:          bool  = false

@export_group("Wall surface")
@export var wall_texture_enabled: bool  = true
@export var texture_variation:    float = 0.03

@export_group("Outline")
@export var wall_outline_width:                   float = 5.5
@export_range(0.0, 1.0, 0.01) var wall_outline_darken: float = 0.25

@export_group("")

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

const WALL_PADDING_TOP    = 100.0
const WALL_PADDING_BOTTOM = 150.0
const WALL_PADDING_SIDES  = 100.0
const BACKGROUND_EXPANSION = 2000.0

const POINT_RADIUS    = 10.0
const POINT_GRAB_RADIUS = 20.0
const EDGE_CLICK_DISTANCE = 15.0

const CLOUD_COUNT  = 14
const CLOUD_LAYERS = 3

const SPLASH_DURATION      = 1.4
const SPLASH_DROPLET_COUNT = 22

const REDRAW_INTERVAL = 1.0 / 12.0   # 12 fps — background doesn't need 60 fps
const REDRAW_INTERVAL_FAST = 1.0 / 30.0  # 30 fps when weather is active (smoother sync with weather_modifier)

# ─────────────────────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────────────────────

var _is_ready: bool = false

# Wall geometry
var wall_min:   Vector2 = Vector2.ZERO
var wall_max:   Vector2 = Vector2.ZERO
var wall_valid: bool    = false

# Polygon editor
var control_points:     Array[Vector2] = []
var ground_y:           float  = 0.0
var ground_left_index:  int    = -1
var ground_right_index: int    = -1
var top_edge_indices:   Array[int] = []

# Editor interaction
var hovered_point: int    = -1
var dragging_point: int   = -1
var drag_offset:   Vector2 = Vector2.ZERO
var hovered_edge:  int    = -1

# Appearance — set by update_environment_settings()
var current_wall_color:  Color  = Color(0.82, 0.75, 0.62)
var background_color:    Color  = Color(0.53, 0.81, 0.92)
var show_bolt_holes:     bool   = false
var is_granite:          bool   = false
var current_environment: String = "gym"
var is_in_editor:        bool   = false

# Ground
var ground_enabled: bool  = true
var ground_color:   Color = Color(0.298, 0.298, 0.298, 1.0)

# Environment theme (populated by _apply_environment_theme)
var _env:          Dictionary = {}
var _scenery_seed: int        = 0

# Clouds
var _clouds:       Array[Dictionary] = []
var _cloud_time:   float             = 0.0

# Water
var _water_time:      float = 0.0
var _player_in_water: bool  = false
var _splashes:        Array[Dictionary] = []

signal player_entered_water(depth: float)
signal player_exited_water

# Weather
var weather_modifier: WeatherModifier = null

# Redraw throttle
var _redraw_timer: float = 0.0

# Per-frame weather blend — refreshed each _process call.
var _weather_blend_current: float = 0.0

# ── Granite noise cache — pre-rendered Image to avoid per-frame line drawing ─
var _granite_cache:     ImageTexture = null
var _granite_cache_dirty: bool       = true

# ── Background frame-skip counter (only redraw static elements every N frames)
# Editor overlay colours
var point_color        = Color(0.7, 0.7, 0.7, 0.6)
var point_hover_color  = Color(1, 0.7, 0, 1.0)
var point_drag_color   = Color(1, 1, 0, 1.0)
var ground_point_color = Color(0.3, 0.8, 0.3, 0.8)
var top_edge_color     = Color(0.9, 0.4, 0.2)

# ─────────────────────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	z_index = -10
	add_to_group("environment_walls")
	_scenery_seed = randi()
	_init_clouds()
	_init_weather()
	_is_ready = true
	await _wait_for_env_config()
	update_environment_settings()

func _process(delta: float) -> void:
	# Update weather blend every frame so draw methods always have current value
	_weather_blend_current = _get_weather_blend()

	# Use faster redraw when weather is active (rain, snow, etc. need smoother animation)
	var weather_type: int = 0
	if weather_modifier != null and is_instance_valid(weather_modifier):
		weather_type = weather_modifier.get_weather()
	var has_weather: bool = weather_type > 0
	var interval: float = REDRAW_INTERVAL_FAST if has_weather else REDRAW_INTERVAL

	_redraw_timer += delta
	if _redraw_timer < interval:
		return
	_redraw_timer -= interval  # subtract, don't reset — smooth timing

	# Always advance animated state so clouds, water, etc. keep moving.
	_cloud_time += interval
	_water_time += interval
	_update_clouds(interval)
	_update_splashes(interval)

	# Redraw every tick so background (sky, mountains, clouds, wall) stays
	# in sync with the camera.  The old has_animation gate meant the wall
	# would freeze at the initial camera position in static environments.
	queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
# BACKGROUND EXTENT HELPER  (replaces _get_view_rect — fixed expansion)
# ─────────────────────────────────────────────────────────────────────────────

func _bg_left()  -> float: return wall_min.x - BACKGROUND_EXPANSION if wall_valid else -3000.0
func _bg_right() -> float: return wall_max.x + BACKGROUND_EXPANSION if wall_valid else  3000.0
func _bg_top()   -> float: return wall_min.y - BACKGROUND_EXPANSION if wall_valid else -2000.0

# ─────────────────────────────────────────────────────────────────────────────
# WEATHER — PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

func _init_weather() -> void:
	weather_modifier = get_node_or_null("WeatherModifier")
	if weather_modifier == null:
		var script = load("res://scripts/levels/weather_modifier.gd")
		if script:
			weather_modifier = script.new()
			weather_modifier.name = "WeatherModifier"
			add_child(weather_modifier)
		else:
			push_warning("DynamicWall: could not load weather_modifier.gd — weather disabled")

func set_weather(weather_type: int, intensity: float = 1.0) -> void:
	if weather_modifier:
		weather_modifier.intensity = clampf(intensity, 0.0, 1.0)
		weather_modifier.weather   = weather_type

func get_weather()          -> int:    return weather_modifier.weather if weather_modifier else 0
func get_weather_modifier() -> Node2D: return weather_modifier

func _get_weather_blend() -> float:
	if weather_modifier:
		return weather_modifier.get_blend()
	return 0.0

func _get_rain_override() -> Dictionary:
	if weather_modifier and weather_modifier.has_method("get_active_sky_override"):
		return weather_modifier.get_active_sky_override()
	return {}

func _rain_lerp_color(base: Color, key: String, blend: float) -> Color:
	if blend < 0.01: return base
	var ov := _get_rain_override()
	if ov.is_empty() or not key in ov: return base
	return base.lerp(ov[key], blend)

# ─────────────────────────────────────────────────────────────────────────────
# CLOUD SYSTEM
# ─────────────────────────────────────────────────────────────────────────────

func _init_clouds() -> void:
	_clouds.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in CLOUD_COUNT:
		_clouds.append(_make_cloud(rng, true))

func _make_cloud(rng: RandomNumberGenerator, initial_spread: bool) -> Dictionary:
	var layer   := rng.randi() % CLOUD_LAYERS
	var bl      := _bg_left()
	var br      := _bg_right()
	var sky_top := _bg_top()
	var sky_bot := ground_y - 120.0 if wall_valid else -400.0

	var sx    := 70.0 + rng.randf() * 140.0 + float(layer) * 90.0 / float(CLOUD_LAYERS - 1)
	var sy    := 22.0 + rng.randf() * 26.0  + float(layer) * 20.0 / float(CLOUD_LAYERS - 1)
	var speed := (0.08 + rng.randf() * 0.16) * (1.0 + float(layer) * 0.8 / float(CLOUD_LAYERS - 1)) * 10.0
	var alpha = lerp(0.20, 0.45, float(layer) / float(CLOUD_LAYERS - 1)) + rng.randf() * 0.28

	var y_range = max(sky_bot - sky_top - 100.0, 100.0)
	var x: float
	if initial_spread:
		x = bl + rng.randf() * (br - bl)
	else:
		x = br + sx + rng.randf() * 200.0

	return {
		"x": x,
		"y": sky_top + 40.0 + rng.randf() * y_range,
		"sx": sx, "sy": sy, "speed": speed, "alpha": alpha,
		"layer": layer, "seed": rng.randi(),
		"phase": rng.randf() * TAU,
	}

func _update_clouds(delta: float) -> void:
	var bl         := _bg_left()
	var speed_mult := 1.0 + _get_weather_blend() * 0.5
	var rng        := RandomNumberGenerator.new()
	rng.seed        = int(_cloud_time * 100.0) ^ 0xDEADBEEF
	for i in _clouds.size():
		var c = _clouds[i]
		c["x"] -= c["speed"] * delta * speed_mult
		c["y"] += sin(_cloud_time * (0.6 + float(c["layer"]) * 0.3) + c["phase"]) * delta * 0.8 * (1.0 + float(c["layer"]) * 0.35)
		if c["x"] + c["sx"] < bl - 100.0:
			_clouds[i] = _make_cloud(rng, false)
		else:
			_clouds[i] = c

# ─────────────────────────────────────────────────────────────────────────────
# SPLASH SYSTEM
# ─────────────────────────────────────────────────────────────────────────────

func spawn_splash(world_pos: Vector2, entry_velocity: float) -> void:
	var rng        := RandomNumberGenerator.new()
	rng.seed        = int(world_pos.x * 7.0 + _water_time * 1000.0) ^ 0xBEEF
	var splash_spd := clampf(abs(entry_velocity) * 0.55, 120.0, 600.0)
	var droplets:  Array = []
	for i in SPLASH_DROPLET_COUNT:
		var side       := 1.0 if (i % 2 == 0) else -1.0
		var frac       := float(i) / float(SPLASH_DROPLET_COUNT)
		var angle_rad  := deg_to_rad(30.0 + frac * 70.0) * side
		var spd_frac   := 0.5 + rng.randf() * 0.5
		var drop_size  := (2.5 + rng.randf() * 4.5) * (1.6 if frac < 0.15 else 1.0)
		var max_life   := 0.4 + rng.randf() * 0.6
		droplets.append({
			"x": world_pos.x + rng.randf_range(-8.0, 8.0), "y": world_pos.y,
			"vx": sin(angle_rad) * splash_spd * spd_frac,
			"vy": -cos(angle_rad) * splash_spd * spd_frac * (0.6 + rng.randf() * 0.4),
			"life": max_life, "max_life": max_life, "size": drop_size,
		})
	_splashes.append({ "pos": world_pos, "time": 0.0, "droplets": droplets, "ring_radius": 0.0 })

func _update_splashes(delta: float) -> void:
	var gravity    := 800.0
	var to_remove: Array = []
	for i in _splashes.size():
		var s := _splashes[i]
		s["time"]        += delta
		s["ring_radius"] += delta * 120.0
		var all_dead := true
		for d in s["droplets"]:
			d["life"] -= delta
			if d["life"] > 0.0:
				all_dead = false
				d["x"] += d["vx"] * delta
				d["y"] += d["vy"] * delta
				d["vy"] += gravity * delta
				if d["y"] > s["pos"].y + 10.0: d["life"] = 0.0
		if s["time"] > SPLASH_DURATION or all_dead:
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		_splashes.remove_at(to_remove[i])

# ─────────────────────────────────────────────────────────────────────────────
# EDITOR API
# ─────────────────────────────────────────────────────────────────────────────

func set_editor_mode(enabled: bool) -> void:
	is_in_editor = enabled
	queue_redraw()

func _wait_for_env_config() -> void:
	var t := 0
	while get_node_or_null("/root/EnvironmentConfig") == null and t < 120:
		await get_tree().process_frame
		t += 1

func update_environment_settings() -> void:
	if get_meta("is_background_wall", false): return
	var ec := get_node_or_null("/root/EnvironmentConfig")
	if ec == null: return
	var data: Dictionary = ec.get_environment_data()
	current_wall_color      = data.get("wall_color",           Color(0.82, 0.75, 0.62))
	background_color        = data.get("background_color",     Color(0.53, 0.81, 0.92))
	show_bolt_holes         = data.get("show_bolt_holes",      false)
	is_granite              = data.get("show_granite_texture", false)
	current_environment     = ec.get_current_environment_name().to_lower()
	_apply_environment_theme()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	_granite_cache_dirty = true
	queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT THEME DATA
# ─────────────────────────────────────────────────────────────────────────────

func _apply_environment_theme() -> void:
	_env.clear()  # ensure no stale keys from previous environment
	match current_environment:
		"granite", "night": _apply_granite_theme()
		"sandstone":        _apply_sandstone_theme()
		"ice":              _apply_ice_theme()
		"menu_sunset":      _apply_menu_sunset_theme()
		"gym":              _apply_gym_theme()
		"deep water solo":  _apply_deep_water_theme()
		"building":         _apply_building_theme()
		_:                  _apply_default_theme()

func _tod(seed_xor: int) -> int:
	return (abs((_scenery_seed ^ seed_xor) * 1664525 + 1013904223) >> 7) % 3

func _apply_granite_theme() -> void:
	match _tod(0x9E3779B9):
		1: _env = {
				"sky_top": Color(0.12,0.10,0.32), "sky_horizon": Color(0.98,0.52,0.18),
				"cloud_color": Color(1.0,0.65,0.40,1.0), "cloud_shadow": Color(0.65,0.25,0.12),
				"has_sun": true, "sun_color": Color(1.0,0.65,0.15), "has_mountains": true,
				"ground_type": "grass_dusk",
				"ground_top": Color(0.14,0.22,0.10), "ground_mid": Color(0.24,0.16,0.08), "ground_deep": Color(0.16,0.10,0.06),
				"ground_detail": "rocks", "fog_color": Color(0.90,0.45,0.15,0.10),
			}
		2: _env = {
				"sky_top": Color(0.02,0.02,0.08), "sky_horizon": Color(0.06,0.08,0.18),
				"cloud_color": Color(0.22,0.25,0.38,0.7), "cloud_shadow": Color(0.10,0.12,0.20),
				"has_sun": false, "has_moon": true, "has_stars": true, "has_mountains": true,
				"ground_type": "grass_night",
				"ground_top": Color(0.08,0.14,0.07), "ground_mid": Color(0.12,0.10,0.08), "ground_deep": Color(0.07,0.06,0.05),
				"ground_detail": "rocks", "fog_color": Color(0.05,0.06,0.15,0.12),
			}
		_: _env = {
				"sky_top": Color(0.20,0.45,0.78), "sky_horizon": Color(0.72,0.85,0.95),
				"cloud_color": Color(1.0,1.0,1.0,1.0), "cloud_shadow": Color(0.75,0.82,0.90),
				"has_sun": true, "sun_color": Color(1.0,0.96,0.78), "has_mountains": true,
				"ground_type": "grass",
				"ground_top": Color(0.22,0.52,0.14), "ground_mid": Color(0.38,0.28,0.16), "ground_deep": Color(0.28,0.20,0.10),
				"ground_detail": "rocks", "fog_color": Color(0.65,0.80,0.95,0.0),
			}

func _apply_sandstone_theme() -> void:
	match _tod(0x4E2A9F3B):
		1: _env = {
				"sky_top": Color(0.14,0.09,0.22), "sky_horizon": Color(0.96,0.46,0.12),
				"cloud_color": Color(1.0,0.60,0.28,0.9), "cloud_shadow": Color(0.68,0.28,0.10),
				"has_sun": false, "has_mountains": true, "ground_type": "sand_dusk",
				"ground_top": Color(0.72,0.44,0.18), "ground_mid": Color(0.54,0.30,0.10), "ground_deep": Color(0.36,0.18,0.06),
				"fog_color": Color(0.88,0.42,0.12,0.10), "has_sand_wind": true,
			}
		2: _env = {
				"sky_top": Color(0.03,0.03,0.10), "sky_horizon": Color(0.10,0.10,0.22),
				"cloud_color": Color(0.18,0.20,0.32,0.55), "cloud_shadow": Color(0.08,0.08,0.18),
				"has_sun": false, "has_moon": true, "has_stars": true, "has_mountains": true,
				"ground_type": "sand_night",
				"ground_top": Color(0.44,0.28,0.10), "ground_mid": Color(0.28,0.16,0.06), "ground_deep": Color(0.16,0.09,0.03),
				"fog_color": Color(0.06,0.06,0.16,0.10), "has_sand_wind": false,
			}
		_: _env = {
				"sky_top": Color(0.48,0.32,0.14), "sky_horizon": Color(0.88,0.70,0.40),
				"cloud_color": Color(1.0,0.92,0.78,0.70), "cloud_shadow": Color(0.80,0.64,0.40),
				"has_sun": true, "sun_color": Color(1.0,0.88,0.54), "has_mountains": true,
				"ground_type": "sand",
				"ground_top": Color(0.82,0.62,0.32), "ground_mid": Color(0.62,0.40,0.16), "ground_deep": Color(0.42,0.24,0.08),
				"fog_color": Color(0.90,0.72,0.40,0.07), "has_sand_wind": true,
			}

func _apply_ice_theme() -> void:
	match (abs((_scenery_seed ^ 0xC7D3E1F2) * 22695477 + 1) >> 9) % 3:
		1: _env = {
				"sky_top": Color(0.18,0.10,0.30), "sky_horizon": Color(0.94,0.44,0.52),
				"cloud_color": Color(1.0,0.62,0.70,0.85), "cloud_shadow": Color(0.60,0.22,0.38),
				"has_sun": false, "has_mountains": true, "ground_type": "ice_snow",
				"ground_top": Color(0.78,0.84,0.90), "ground_mid": Color(0.60,0.70,0.80), "ground_deep": Color(0.38,0.48,0.62),
				"ground_detail": "snow", "fog_color": Color(0.80,0.60,0.70,0.08),
				"has_ice_sheen": true, "ice_sheen_color": Color(0.94,0.72,0.82),
			}
		2: _env = {
				"sky_top": Color(0.02,0.03,0.10), "sky_horizon": Color(0.06,0.10,0.24),
				"cloud_color": Color(0.12,0.16,0.30,0.65), "cloud_shadow": Color(0.04,0.06,0.14),
				"has_sun": false, "has_moon": true, "has_stars": true, "has_mountains": true,
				"ground_type": "ice_snow",
				"ground_top": Color(0.56,0.66,0.80), "ground_mid": Color(0.34,0.44,0.60), "ground_deep": Color(0.16,0.22,0.38),
				"ground_detail": "snow", "fog_color": Color(0.04,0.06,0.18,0.14),
				"has_ice_sheen": true, "ice_sheen_color": Color(0.40,0.58,0.90),
			}
		_: _env = {
				"sky_top": Color(0.12,0.36,0.72), "sky_horizon": Color(0.70,0.88,0.98),
				"cloud_color": Color(1.0,1.0,1.0,0.92), "cloud_shadow": Color(0.76,0.84,0.94),
				"has_sun": true, "sun_color": Color(1.0,0.98,0.90), "has_mountains": true,
				"ground_type": "ice_snow",
				"ground_top": Color(0.90,0.94,0.98), "ground_mid": Color(0.70,0.80,0.92), "ground_deep": Color(0.46,0.60,0.78),
				"ground_detail": "snow", "fog_color": Color(0.72,0.88,0.98,0.05),
				"has_ice_sheen": true, "ice_sheen_color": Color(0.82,0.94,1.00),
			}

func _apply_menu_sunset_theme() -> void:
	_env = {
		"sky_top": Color(0.88,0.55,0.75), "sky_horizon": Color(0.98,0.72,0.48),
		"cloud_color": Color(1.0,0.85,0.92,0.8), "cloud_shadow": Color(0.6,0.38,0.65,0.5),
		"has_sun": true, "sun_color": Color(1.0,0.82,0.55), "has_mountains": true,
		"fog_color": Color(0.95,0.68,0.82,0.18),
		"ground_type": "grass_dusk",
		"ground_top": Color(0.45,0.38,0.42), "ground_mid": Color(0.38,0.32,0.35), "ground_deep": Color(0.28,0.24,0.30),
		"ground_detail": "rocks",
	}

func _apply_gym_theme() -> void:
	var tod: int = (abs((_scenery_seed ^ 0x6B43FA1D) * 22695477 + 1) >> 9) % 3
	var base := {
		"sky_top": Color(0.96,0.96,0.97), "sky_horizon": Color(0.92,0.92,0.93),
		"cloud_color": Color(1.0,1.0,1.0,0.0), "has_sun": false, "has_mountains": false,
		"has_gym_interior": true, "gym_time_of_day": tod,
		"ground_type": "gym_floor",
		"ground_top": Color(0.22,0.22,0.24), "ground_mid": Color(0.16,0.16,0.18), "ground_deep": Color(0.11,0.11,0.12),
	}
	match tod:
		1: base.merge({
				"gym_sky_top": Color(0.12,0.10,0.32), "gym_sky_mid": Color(0.72,0.28,0.12), "gym_sky_haze": Color(0.98,0.52,0.18),
				"gym_sun_color": Color(1.0,0.55,0.10),
				"gym_mtn_colors": [Color(0.58,0.35,0.28),Color(0.42,0.22,0.18),Color(0.28,0.14,0.12),Color(0.16,0.08,0.08)],
				"gym_grass_color": Color(0.14,0.22,0.10),
			})
		2: base.merge({
				"gym_sky_top": Color(0.02,0.02,0.08), "gym_sky_mid": Color(0.04,0.06,0.14), "gym_sky_haze": Color(0.06,0.08,0.20),
				"gym_sun_color": Color.TRANSPARENT,
				"gym_mtn_colors": [Color(0.14,0.16,0.22),Color(0.10,0.12,0.18),Color(0.06,0.08,0.13),Color(0.03,0.04,0.08)],
				"gym_grass_color": Color(0.08,0.14,0.07), "has_gym_stars": true, "has_gym_moon": true,
			})
		_: base.merge({
				"gym_sky_top": Color(0.20,0.45,0.78), "gym_sky_mid": Color(0.44,0.70,0.93), "gym_sky_haze": Color(0.70,0.86,0.97),
				"gym_sun_color": Color(1.0,0.96,0.78),
				"gym_mtn_colors": [Color(0.72,0.82,0.91),Color(0.54,0.67,0.80),Color(0.38,0.52,0.66),Color(0.24,0.38,0.53)],
				"gym_grass_color": Color(0.18,0.26,0.19),
			})
	_env = base

func _apply_deep_water_theme() -> void:
	_env = {
		"sky_top": Color(0.18,0.42,0.72), "sky_horizon": Color(0.60,0.82,0.94),
		"cloud_color": Color(1.0,1.0,1.0,0.85), "cloud_shadow": Color(0.72,0.84,0.92),
		"has_sun": true, "sun_color": Color(1.0,0.95,0.75), "has_mountains": false,
		"has_water": true, "ground_type": "water",
		"ground_top": Color(0.04,0.22,0.44), "ground_mid": Color(0.02,0.14,0.30), "ground_deep": Color(0.01,0.08,0.18),
		"fog_color": Color(0.50,0.75,0.90,0.06), "has_sea_cliffs": true,
	}

func _apply_building_theme() -> void:
	match _tod(0x3F7A2B1C):
		1: _env = {
				"sky_top": Color(0.06,0.05,0.14), "sky_horizon": Color(0.72,0.28,0.10),
				"cloud_color": Color(1.0,0.55,0.25,0.70), "cloud_shadow": Color(0.55,0.20,0.10),
				"has_sun": false, "has_moon": false, "has_mountains": false, "has_city": true, "city_time": 1,
				"ground_type": "city_street",
				"ground_top": Color(0.22,0.18,0.14), "ground_mid": Color(0.16,0.13,0.10), "ground_deep": Color(0.11,0.09,0.07),
				"fog_color": Color(0.60,0.25,0.08,0.08),
			}
		2: _env = {
				"sky_top": Color(0.02,0.02,0.07), "sky_horizon": Color(0.05,0.06,0.14),
				"cloud_color": Color(0.20,0.22,0.35,0.60), "cloud_shadow": Color(0.08,0.10,0.20),
				"has_sun": false, "has_moon": true, "has_stars": true, "has_mountains": false, "has_city": true, "city_time": 2,
				"ground_type": "city_street",
				"ground_top": Color(0.14,0.14,0.16), "ground_mid": Color(0.10,0.10,0.12), "ground_deep": Color(0.06,0.06,0.08),
				"fog_color": Color(0.04,0.05,0.12,0.10),
			}
		_: _env = {
				"sky_top": Color(0.16,0.38,0.70), "sky_horizon": Color(0.62,0.78,0.94),
				"cloud_color": Color(1.0,1.0,1.0,0.90), "cloud_shadow": Color(0.76,0.84,0.92),
				"has_sun": true, "sun_color": Color(1.0,0.96,0.78), "has_mountains": false, "has_city": true, "city_time": 0,
				"ground_type": "city_street",
				"ground_top": Color(0.28,0.28,0.30), "ground_mid": Color(0.20,0.20,0.22), "ground_deep": Color(0.13,0.13,0.14),
				"fog_color": Color(0.60,0.76,0.94,0.04),
			}

func _apply_default_theme() -> void:
	_env = {
		"sky_top": background_color.darkened(0.25), "sky_horizon": background_color.lightened(0.15),
		"cloud_color": Color(1.0,1.0,1.0,1.0), "cloud_shadow": Color(0.78,0.84,0.92),
		"has_sun": true, "sun_color": Color(1.0,0.95,0.70), "has_mountains": true,
		"ground_type": "grass",
		"ground_top": Color(0.22,0.52,0.14), "ground_mid": Color(0.38,0.28,0.16), "ground_deep": Color(0.28,0.20,0.10),
		"ground_detail": "rocks", "fog_color": Color(0.0,0.0,0.0,0.0),
	}

# ─────────────────────────────────────────────────────────────────────────────
# INPUT (editor only)
# ─────────────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not is_in_editor or not edit_mode: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _try_start_drag()
			else:             _end_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var mp := get_global_mouse_position()
			for i in control_points.size():
				if i == ground_left_index or i == ground_right_index: continue
				if mp.distance_to(control_points[i]) < POINT_GRAB_RADIUS:
					remove_point(i); return
			if hovered_edge >= 0:
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_SHIFT):
					toggle_top_edge(hovered_edge)
				else:
					add_point_between_nearest_edge(mp)
	elif event is InputEventMouseMotion:
		if dragging_point >= 0: _update_drag()
		else:                   _update_hover()

func toggle_top_edge(edge_index: int) -> void:
	if _is_ground_edge(edge_index): return
	if edge_index in top_edge_indices: top_edge_indices.erase(edge_index)
	else:                              top_edge_indices.append(edge_index)
	_create_top_edge_holds()
	queue_redraw()

func _try_start_drag() -> void:
	var mp := get_global_mouse_position()
	for i in control_points.size():
		if mp.distance_to(control_points[i]) < POINT_GRAB_RADIUS:
			dragging_point = i; drag_offset = control_points[i] - mp; queue_redraw(); return

func _update_drag() -> void:
	if dragging_point < 0 or dragging_point >= control_points.size(): return
	var np := get_global_mouse_position() + drag_offset
	if dragging_point == ground_left_index or dragging_point == ground_right_index:
		control_points[ground_left_index].y  = np.y
		control_points[ground_right_index].y = np.y
		ground_y = np.y
		if dragging_point == ground_left_index:
			np.x = min(np.x, control_points[ground_right_index].x - 50.0)
		else:
			np.x = max(np.x, control_points[ground_left_index].x + 50.0)
		control_points[dragging_point].x = np.x
	else:
		control_points[dragging_point] = np
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	queue_redraw()

func _end_drag() -> void:
	dragging_point = -1; queue_redraw()

func _update_hover() -> void:
	var mp  := get_global_mouse_position()
	var ohp := hovered_point; var ohe := hovered_edge
	hovered_point = -1; hovered_edge = -1
	for i in control_points.size():
		if mp.distance_to(control_points[i]) < POINT_GRAB_RADIUS:
			hovered_point = i
			if ohp != hovered_point or ohe != hovered_edge: queue_redraw()
			return
	for i in control_points.size():
		if _is_ground_edge(i): continue
		if _point_to_segment_distance(mp, control_points[i],
				control_points[(i + 1) % control_points.size()]) < EDGE_CLICK_DISTANCE:
			hovered_edge = i; break
	if ohp != hovered_point or ohe != hovered_edge: queue_redraw()

func _is_ground_edge(ei: int) -> bool:
	if ground_left_index < 0 or ground_right_index < 0: return false
	var ni := (ei + 1) % control_points.size()
	return (ei == ground_left_index and ni == ground_right_index) or \
		   (ei == ground_right_index and ni == ground_left_index)

# ─────────────────────────────────────────────────────────────────────────────
# MAIN DRAW DISPATCH
# ─────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not wall_valid: return
	var rb := _weather_blend_current

	_draw_sky()
	_draw_atmospheric_haze()
	if _env.get("has_stars", false) and rb < 0.85: _draw_stars()
	if _env.get("has_sun", false) and rb < 0.85: _draw_sun()
	if _env.get("has_moon", false) and rb < 0.85: _draw_moon()
	if _env.get("has_mountains", false): _draw_mountains()
	if _env.get("has_city", false): _draw_city_silhouette()
	_draw_fog()
	if _env.get("has_gym_interior", false): _draw_gym_interior()
	if _env.get("has_scaffold", false): _draw_scaffold()
	_draw_clouds()
	if use_polygon_mode and control_points.size() >= 3: _draw_polygon_wall()
	else:                                               _draw_rectangle_wall()
	_draw_wall_depth_shading()
	_draw_wall_tonal_outline()
	if rb < 0.80:  # skip material texture when weather nearly opaque
		_draw_wall_material_texture()
	if current_environment == "ice" and _env.get("has_ice_sheen", false) and rb < 0.85:
		_draw_ice_wall_sheen()
	if _env.get("has_water", false): _draw_underwater_wall_depth()
	if show_bolt_holes:
		if use_polygon_mode and control_points.size() >= 3: draw_bolt_holes_on_polygon()
		else:                                               draw_bolt_holes(wall_min, wall_max)
	if is_granite and not use_polygon_mode and rb < 0.80: draw_granite_texture()
	if ground_enabled: _draw_ground()
	if _env.get("has_water", false):
		_draw_water_surface()
		_draw_splashes()
	if is_in_editor and use_polygon_mode and control_points.size() > 0: _draw_control_points()
	if is_in_editor and edit_mode and use_polygon_mode:                  _draw_edge_highlights()

# ─────────────────────────────────────────────────────────────────────────────
# SKY
# ─────────────────────────────────────────────────────────────────────────────

func _draw_sky() -> void:
	var bl    := _bg_left()
	var br    := _bg_right()
	var st    := _bg_top()
	var sw    := br - bl
	var rb    := _get_weather_blend()
	var ctop  := _rain_lerp_color(_env.get("sky_top",    background_color),                "sky_top",    rb)
	var choriz := _rain_lerp_color(_env.get("sky_horizon", background_color.lightened(0.15)),"sky_horizon",rb)
	var total_h := ground_y - st

	# ── Upper atmosphere (darken zenith for natural depth) ──────────────────
	# Rayleigh scattering makes the sky darker at the zenith and brighter
	# near the horizon during the day; at night the gradient inverts slightly.
	var dayness := clampf((ctop.r + ctop.g + ctop.b) * 0.6, 0.0, 1.0)
	for i in 12:
		var t0 := float(i)     / 12.0
		var t1 := float(i + 1) / 12.0
		var f0 := t0 * t0 * (1.0 - t0 * 0.15)
		var f1 := t1 * t1 * (1.0 - t1 * 0.15)
		_draw_grad_quad(bl, st + t0 * total_h, sw, st + t1 * total_h,
			ctop.lerp(choriz, f0), ctop.lerp(choriz, f1))

	# ── Subtle zenith darkening band (daytime only) ─────────────────────────
	if dayness > 0.15:
		var zenith_strength := dayness * 0.06
		for i in 3:
			var t0 := float(i) / 3.0
			var t1 := float(i + 1) / 3.0
			var fade0 := (1.0 - t0) * zenith_strength
			var fade1 := (1.0 - t1) * zenith_strength
			_draw_grad_quad(bl, st + t0 * total_h * 0.18, sw, st + t1 * total_h * 0.18,
				Color(ctop.r - fade0, ctop.g - fade0 * 0.6, ctop.b, ctop.a),
				Color(ctop.r - fade1, ctop.g - fade1 * 0.6, ctop.b, ctop.a))

	draw_rect(Rect2(Vector2(bl, ground_y), Vector2(sw, 99999.0)), choriz, true)

# ─────────────────────────────────────────────────────────────────────────────
# ATMOSPHERIC HAZE
# ─────────────────────────────────────────────────────────────────────────────

func _draw_atmospheric_haze() -> void:
	## Soft atmospheric haze layer — mimics suspended particles scattering
	## light near the horizon.  Gives depth and a "breathing" atmosphere to
	## every environment, just like the painterly clouds.
	var bl  := _bg_left()
	var br  := _bg_right()
	var sw  := br - bl
	var rb  := _get_weather_blend()
	var choriz := _rain_lerp_color(_env.get("sky_horizon", background_color.lightened(0.15)), "sky_horizon", rb)

	# ── Warm haze band (sunlight scattering off particles) ──────────────────
	# A soft golden/pink horizon glow that fades upward.
	var haze_warmth := 0.08 * (1.0 - rb * 0.3)
	if _env.get("has_sun", false):
		var sc: Color = _env.get("sun_color", Color(1.0, 0.95, 0.70))
		var warm := Color(
			choriz.r * 0.5 + sc.r * 0.5,
			choriz.g * 0.5 + sc.g * 0.3,
			choriz.b * 0.5,
			haze_warmth)
		for i in 5:
			var t0 := float(i) / 5.0
			var t1 := float(i + 1) / 5.0
			var a0 := haze_warmth * (1.0 - t0 * t0 * 0.85)
			var a1 := haze_warmth * (1.0 - t1 * t1 * 0.85)
			_draw_grad_quad(bl, ground_y - (1.0 - t0) * 220.0, sw, ground_y - (1.0 - t1) * 220.0,
				Color(warm.r, warm.g, warm.b, a0), Color(warm.r, warm.g, warm.b, a1))
	else:
		# Moonlight/night — cooler, subtler haze
		var cool := Color(
			choriz.r * 0.6, choriz.g * 0.6, choriz.b * 0.8,
			haze_warmth * 0.6)
		for i in 4:
			var t0 := float(i) / 4.0
			var t1 := float(i + 1) / 4.0
			_draw_grad_quad(bl, ground_y - (1.0 - t0) * 160.0, sw, ground_y - (1.0 - t1) * 160.0,
				Color(cool.r, cool.g, cool.b, cool.a * (1.0 - t0 * t0 * 0.7)),
				Color(cool.r, cool.g, cool.b, cool.a * (1.0 - t1 * t1 * 0.7)))

	# ── Distant blue-light scattering layer ─────────────────────────────────
	# A very faint blue-ish veil over the far distance (like Rayleigh scatter)
	var scatter_strength := 0.04 * (1.0 - rb * 0.5)
	if dayness_internal() > 0.3:
		var scatter := Color(0.55, 0.70, 0.95, scatter_strength)
		for i in 6:
			var t0 := float(i) / 6.0
			var t1 := float(i + 1) / 6.0
			_draw_grad_quad(bl, ground_y - (1.0 - t0) * 320.0, sw, ground_y - (1.0 - t1) * 320.0,
				Color(scatter.r, scatter.g, scatter.b, scatter.a * (1.0 - t0 * 0.5)),
				Color(scatter.r, scatter.g, scatter.b, scatter.a * (1.0 - t1 * 0.5)))

func dayness_internal() -> float:
	var ctop: Color = _env.get("sky_top", Color(0.2, 0.4, 0.7))
	return clampf((ctop.r + ctop.g + ctop.b) * 0.6, 0.0, 1.0)

# ─────────────────────────────────────────────────────────────────────────────
# CELESTIAL
# ─────────────────────────────────────────────────────────────────────────────

func _draw_stars() -> void:
	var bl := _bg_left(); var br := _bg_right(); var st := _bg_top()
	var sw := br - bl
	var rb := _get_weather_blend()
	for i in 80:
		var ss     := (_scenery_seed ^ 0xBEEF) + i * 17
		var bright := (0.5 + _hf(ss + 2) * 0.5) * (1.0 - rb)
		var tw     := 0.7 + 0.3 * sin(_cloud_time * (1.5 + _hf(ss + 4) * 3.0) + float(i))
		draw_circle(Vector2(bl + _hf(ss) * sw, st + _hf(ss+1) * (ground_y - st - 80.0)),
					1.0 + _hf(ss + 3) * 1.8, Color(1.0, 1.0, 1.0, bright * tw * 0.85))

func _draw_sun() -> void:
	var bl := _bg_left(); var br := _bg_right(); var st := _bg_top()
	var sx := bl + (br - bl) * 0.78
	var sy := st + 180.0
	var sc : Color = _env.get("sun_color", Color(1.0,0.95,0.70))
	var fade := 1.0 - _get_weather_blend()
	for gi in 8:
		draw_circle(Vector2(sx, sy), 45.0 + float(gi) * 28.0,
					Color(sc.r, sc.g, sc.b, (0.05 - float(gi) * 0.005) * fade))
	draw_circle(Vector2(sx, sy), 45.0, Color(sc.r, sc.g, sc.b, sc.a * fade))
	draw_circle(Vector2(sx, sy), 32.0, Color(1.0, 1.0, 0.97, fade * 0.9))

func _draw_moon() -> void:
	var bl := _bg_left(); var br := _bg_right(); var st := _bg_top()
	var mx := bl + (br - bl) * 0.72
	var my := st + 220.0
	var mr := 36.0
	for gi in 5:
		draw_circle(Vector2(mx, my), mr + float(gi) * 20.0, Color(0.7,0.75,0.9, 0.04))
	draw_circle(Vector2(mx, my), mr, Color(0.88, 0.90, 0.95, 1.0))
	draw_circle(Vector2(mx + mr*0.35, my - mr*0.1), mr * 0.82, _env.get("sky_top", Color(0.02,0.02,0.08)))
	for ci in 4:
		var cs := 6000 + ci * 37
		draw_circle(Vector2(mx - mr*0.3 + _hf(cs)*mr*0.5, my - mr*0.2 + _hf(cs+1)*mr*0.4),
					2.0 + _hf(cs+2)*4.0, Color(0.70,0.72,0.78,0.35))

# ─────────────────────────────────────────────────────────────────────────────
# MOUNTAINS  —  painterly, with atmospheric perspective, snow caps & ridge detail
# ─────────────────────────────────────────────────────────────────────────────

func _draw_mountains() -> void:
	var bl := _bg_left(); var br := _bg_right()
	var rb  := _get_weather_blend()
	var hs : Color = _rain_lerp_color(_env.get("sky_horizon", background_color), "sky_horizon", rb)
	var ht : Color = _rain_lerp_color(_env.get("sky_top",     background_color), "sky_top",     rb)
	var choriz := hs

	# ── Atmospheric perspective: further layers (higher index) get MORE sky
	# colour blended in, mimicking how air scatters light over distance.
	var layer_configs := [
		# [base_y_offset, min_h, max_h, segs, atmos_persp_strength, seed]
		{ "by": -60.0, "min": 240.0, "max": 600.0, "segs": 50, "atmos": 0.55, "seed": 0x0A1B2C },
		{ "by": -20.0, "min": 160.0, "max": 420.0, "segs": 45, "atmos": 0.40, "seed": 0x1A2B3C },
	]

	# Extra layers for menu_sunset
	if current_environment == "menu_sunset":
		layer_configs.append_array([
			{ "by": -120.0, "min": 280.0, "max": 680.0, "segs": 110, "atmos": 0.65, "seed": 0x111222 },
			{ "by": -70.0,  "min": 200.0, "max": 520.0, "segs": 95,  "atmos": 0.50, "seed": 0x333444 },
		])

	var crest_data: Array[Dictionary] = []
	for lc in layer_configs:
		var base_col := hs.lerp(ht, lc["atmos"]).darkened(lerpf(0.05, 0.20, lc["atmos"] * 0.5))
		var count   := int(lc["segs"])
		var step    := (br - bl) / float(count)
		var pts     := PackedVector2Array()
		var crests  := PackedVector2Array()  # crest-point positions for snow caps

		pts.append(Vector2(bl, ground_y + lc["by"] + 500.0))
		for i in count + 1:
			var h0: float = _hf(int(lc["seed"])+(i-1)*7) * (lc["max"] - lc["min"]) + lc["min"]
			var h1: float = _hf(int(lc["seed"])+i*7)     * (lc["max"] - lc["min"]) + lc["min"]
			var h2: float = _hf(int(lc["seed"])+(i+1)*7) * (lc["max"] - lc["min"]) + lc["min"]
			var y: float  = ground_y + lc["by"] - (h0*0.2 + h1*0.6 + h2*0.2)
			var x: float  = bl + i * step
			pts.append(Vector2(x, y))
			crests.append(Vector2(x, y))
		pts.append(Vector2(br, ground_y + lc["by"] + 500.0))

		_safe_draw_polygon(pts, base_col)

		# ── Snow caps on high peaks (only for non-city, non-ice already has sheen)
		if current_environment != "building" and current_environment != "desert":
			_draw_mountain_snow_caps(crests, base_col, choriz, rb)

		# ── Subtle ridge shadow for depth ──────────────────────────────────
		_draw_mountain_ridge_shadows(crests, base_col, choriz, rb)

		# Store for the foreground haze step below
		crest_data.append({ "crests": crests, "color": base_col, "atmos": lc["atmos"] })

	# ── Foreground atmospheric haze over mountain base ──────────────────────
	var sw := br - bl
	_draw_grad_quad(bl, ground_y - 40.0, sw, ground_y - 10.0,
		Color(choriz.r, choriz.g, choriz.b, 0.14 * (1.0 - rb * 0.4)),
		Color(choriz.r, choriz.g, choriz.b, 0.40 * (1.0 - rb * 0.4)))

	# ── Closest two hill layers (no snow, more silhouette) ──────────────────
	var front_configs := [
		{ "by": -5.0, "min": 90.0, "max": 230.0, "segs": 30, "seed": 0x4D5E6F, "dark": 0.22 },
		{ "by":  0.0, "min": 40.0, "max": 110.0, "segs": 25, "seed": 0x7F8A9B, "dark": 0.38 },
	]
	for lc in front_configs:
		var front_col := choriz.darkened(lc["dark"])
		var count   := int(lc["segs"])
		var step    := (br - bl) / float(count)
		var pts     := PackedVector2Array()
		pts.append(Vector2(bl, ground_y + lc["by"] + 500.0))
		for i in count + 1:
			var h0: float = _hf(int(lc["seed"])+(i-1)*7) * (lc["max"] - lc["min"]) + lc["min"]
			var h1: float = _hf(int(lc["seed"])+i*7)     * (lc["max"] - lc["min"]) + lc["min"]
			var h2: float = _hf(int(lc["seed"])+(i+1)*7) * (lc["max"] - lc["min"]) + lc["min"]
			pts.append(Vector2(bl + i * step, ground_y + lc["by"] - (h0*0.2 + h1*0.6 + h2*0.2)))
		pts.append(Vector2(br, ground_y + lc["by"] + 500.0))
		_safe_draw_polygon(pts, front_col)

func _draw_mountain_snow_caps(crests: PackedVector2Array, base_col: Color,
							   sky_horiz: Color, weather_blend: float) -> void:
	## Paints small snow/ice highlights on the highest peaks of a mountain layer.
	if weather_blend > 0.7: return  # too stormy to see snow
	var snow_col := Color(0.92, 0.94, 0.98, 0.55 * (1.0 - weather_blend * 0.5))
	snow_col = snow_col.lerp(sky_horiz.lightened(0.3), 0.15)  # tint with sky
	snow_col = snow_col.lerp(base_col, 0.30)  # ground-tint for integration

	for i in range(1, crests.size() - 1):
		var p  := crests[i]
		var pp := crests[i - 1]
		var pn := crests[i + 1]

		# Only snow on actual peaks (higher than both neighbours)
		if p.y >= pp.y or p.y >= pn.y: continue

		var prominence: float = (min(pp.y, pn.y) - p.y) / 200.0  # how much this peak juts out
		if prominence < 0.08: continue  # too gentle

		var cap_w: float = 12.0 + prominence * 40.0
		var cap_h: float = 6.0  + prominence * 18.0
		var spread := clampf(prominence * 1.5, 0.3, 1.0)

		# Snow cap: a small semi-transparent triangle/oval on the peak
		_draw_soft_puff(p.x, p.y - cap_h * 0.2, cap_w * spread, cap_h,
			Color(snow_col.r, snow_col.g, snow_col.b, snow_col.a * minf(prominence * 2.0, 0.7)), 0.5)

		# Right-side accumulation (wind-blown look)
		_draw_soft_puff(p.x + cap_w * 0.15, p.y - cap_h * 0.1, cap_w * 0.4, cap_h * 0.5,
			Color(snow_col.r, snow_col.g, snow_col.b, snow_col.a * 0.35), 0.4)

func _draw_mountain_ridge_shadows(crests: PackedVector2Array, base_col: Color,
								   _sky_horiz: Color, weather_blend: float) -> void:
	## Subtle shadow lines on right-facing slopes — suggests 3D ridge structure
	## with minimal draw overhead.  Left-facing slopes catch the (implied) light.
	if weather_blend > 0.6: return
	var shadow_col := base_col.darkened(0.12)
	shadow_col.a = 0.20

	for i in range(1, crests.size()):
		var p0 := crests[i - 1]
		var p1 := crests[i]
		var dx := p1.x - p0.x
		var dy := p1.y - p0.y

		# Right-facing slope = shadow (light comes from upper-left)
		if dy > 2.0 and dx > 0:
			var steepness := clampf(dy / (absf(dx) + 1.0), 0.0, 3.0)
			var alpha := minf(steepness * 0.07, 0.22)
			draw_line(p0, p1, Color(shadow_col.r, shadow_col.g, shadow_col.b, alpha), 1.8, true)

# ─────────────────────────────────────────────────────────────────────────────
# CITY SILHOUETTE
# ─────────────────────────────────────────────────────────────────────────────

func _draw_city_silhouette() -> void:
	var bl  := _bg_left(); var br := _bg_right()
	var rb  := _get_weather_blend()
	var tod : int = _env.get("city_time", 0)

	var sil_colors: Array
	match tod:
		1: sil_colors = [Color(0.10,0.08,0.16),Color(0.16,0.12,0.22),
						  Color(0.24,0.16,0.24),Color(0.34,0.20,0.22)]
		2: sil_colors = [Color(0.04,0.04,0.09),Color(0.06,0.06,0.13),
						  Color(0.09,0.09,0.17),Color(0.13,0.13,0.20)]
		_: sil_colors = [Color(0.50,0.54,0.60),Color(0.40,0.44,0.52),
						  Color(0.30,0.34,0.42),Color(0.20,0.24,0.32)]
	for i in sil_colors.size():
		sil_colors[i] = (sil_colors[i] as Color).lerp(Color(0.18,0.20,0.24), rb * 0.4)

	var layer_configs := [
		[0.72,100.0,280.0, 55.0, 95.0,0xA1B2C3],
		[0.62,150.0,360.0, 65.0,120.0,0xD4E5F6],
		[0.50,200.0,460.0, 85.0,160.0,0x3C4D5E],
		[0.36,250.0,580.0,100.0,200.0,0x7F8A9B],
	]
	var win_warm := Color(1.00,0.86,0.48,0.55)
	var win_cool := Color(0.82,0.90,1.00,0.50)
	var lit_prob: float = [0.0, 0.38, 0.68][tod]

	for li in layer_configs.size():
		var lc: Array = layer_configs[li]
		var h_min     := float(lc[1]); var h_max := float(lc[2])
		var w_min     := float(lc[3]); var w_max := float(lc[4])
		var seed_base := int(lc[5]) ^ _scenery_seed
		var col       : Color = sil_colors[li]
		var x := bl; var bldg_idx := 0

		while x < br + w_max:
			var bs  := seed_base + bldg_idx * 31
			var bw  := w_min + _hf(bs)     * (w_max - w_min)
			var bh  := h_min + _hf(bs + 1) * (h_max - h_min)
			var bx  := x + (_hf(bs + 2) - 0.5) * 20.0
			draw_rect(Rect2(bx, ground_y - bh, bw, bh), col, true)
			draw_rect(Rect2(bx, ground_y - bh, 2.5, bh), Color(col.r+0.07,col.g+0.07,col.b+0.08,col.a*0.55), true)

			if _hf(bs+9) > 0.58:
				var sbw := bw*(0.52+_hf(bs+10)*0.32); var sbh := bh*(0.07+_hf(bs+11)*0.13)
				draw_rect(Rect2(bx+(bw-sbw)*0.5, ground_y-bh-sbh, sbw, sbh), col.darkened(0.06), true)
				draw_rect(Rect2(bx+(bw-sbw)*0.5, ground_y-bh-sbh, sbw, 1.5), Color(col.r+0.10,col.g+0.10,col.b+0.12,0.40), true)

			if _hf(bs+5) > 0.72:
				var ah := 10.0+_hf(bs+6)*22.0
				var ax := bx+bw*(0.38+_hf(bs+7)*0.24)
				draw_line(Vector2(ax,ground_y-bh), Vector2(ax,ground_y-bh-ah), col.darkened(0.10), 1.2)
				if tod == 2 and ah > 28.0:
					var blink := sin(_cloud_time*1.2+float(bldg_idx)*2.3)
					draw_circle(Vector2(ax,ground_y-bh-ah), 2.8, Color(1.0,0.18,0.10, clampf((blink+1.0)*0.5*0.85,0.0,0.85)))

			if li >= 2 and lit_prob > 0.0:
				var win_rows := int(bh/20.0); var win_cols := int(bw/16.0)
				for wr in win_rows:
					for wc in win_cols:
						var ws  := bs+wr*97+wc*31
						if _hf(ws) > lit_prob: continue
						var wlit := (win_warm if _hf(ws+5)>0.42 else win_cool)
						var hv   := (_hf(ws+6)-0.5)*0.10
						wlit = Color(clampf(wlit.r+hv,0,1),clampf(wlit.g-hv*0.3,0,1),clampf(wlit.b-hv*0.5,0,1),wlit.a*(0.75+_hf(ws+7)*0.30))
						draw_rect(Rect2(bx+4.0+wc*16.0, ground_y-bh+7.0+wr*20.0, 7.0, 9.0), wlit, true)
						if tod == 2:
							draw_rect(Rect2(bx+5.0+wc*16.0, ground_y-bh+8.0+wr*20.0, 5.0, 7.0), Color(wlit.r,wlit.g,wlit.b,wlit.a*0.40), true)

			x = bx + bw + _hf(bs+8)*25.0
			bldg_idx += 1

	if tod == 2:
		var sw := br - bl
		for gi in 3:
			draw_rect(Rect2(bl, ground_y-float(gi)*12.0-6.0, sw, 14.0), Color(0.55,0.60,0.90,0.018*(1.0-float(gi)/3.0)), true)

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDS
# ─────────────────────────────────────────────────────────────────────────────

func _draw_clouds() -> void:
	var rb := _get_weather_blend()
	var cc : Color = _rain_lerp_color(_env.get("cloud_color", Color(1,1,1)), "cloud_color",  rb)
	var sc : Color = _rain_lerp_color(_env.get("cloud_shadow",Color(0.78,0.84,0.92)), "cloud_shadow", rb)
	if cc.a < 0.02: return
	if rb > 0.15: _draw_overcast_layer(rb, cc)
	for layer in CLOUD_LAYERS:
		for c in _clouds:
			if c["layer"] != layer: continue
			var ba := minf(c["alpha"] * cc.a * (1.0 + rb * 0.4), 0.92)

			var warmth := 1.0 + float(layer) * 0.05 + rb * 0.08
			var top_col := Color(
				minf(cc.r * warmth, 1.0), minf(cc.g * warmth, 1.0), cc.b, ba * 0.92)
			var bot_col := Color(
				cc.r * 0.82, cc.g * 0.80, minf(cc.b * 1.15, 1.0), ba * 0.78)
			var shadow_col := Color(sc.r, sc.g, sc.b, ba * 0.38)

			_draw_painterly_cloud(c["x"], c["y"], c["sx"], c["sy"],
				top_col, bot_col, shadow_col, c["seed"], layer, rb)

func _draw_overcast_layer(blend: float, cc: Color) -> void:
	var bl   := _bg_left(); var br := _bg_right(); var st := _bg_top()
	var sw   := br - bl
	var h    := blend * BACKGROUND_EXPANSION * 0.55
	var base := st
	for i in 10:
		var t0 := float(i)/10.0; var t1 := float(i+1)/10.0
		_draw_grad_quad(bl, base+t0*h, sw, base+t1*h,
			Color(cc.r,cc.g,cc.b, lerp(blend*0.65,0.0,t0*t0)),
			Color(cc.r,cc.g,cc.b, lerp(blend*0.65,0.0,t1*t1)))

func _draw_painterly_cloud(cx: float, cy: float, sx: float, sy: float,
						   top_col: Color, bot_col: Color, shadow: Color,
						   cseed: int, _layer: int, rb: float = 0.0) -> void:
	var rym := 1.0 + rb * 0.30

	_draw_soft_puff(cx - sx * 0.04, cy + sy * 0.32 * rym, sx * 0.90, sy * 0.50 * rym, shadow, 0.55)
	_draw_soft_puff(cx, cy, sx * 0.92, sy * 0.78 * rym, top_col, 0.65)
	_draw_soft_puff(cx, cy + sy * 0.08 * rym, sx * 0.86, sy * 0.52 * rym, bot_col, 0.50)

	var offsets := [
		Vector2(0.0,     -0.50), Vector2(-0.18,  -0.38), Vector2(0.18,  -0.38),
		Vector2(-0.28,   -0.22), Vector2(0.28,   -0.22),
		Vector2(-0.40,   -0.06), Vector2(0.40,   -0.06),
		Vector2(-0.22,    0.22), Vector2(0.22,    0.22),
	]
	var sizes := [
		0.42, 0.34, 0.34, 0.36, 0.36,
		0.32, 0.32, 0.26, 0.26,
	]
	var is_top := [
		true,  true,  true,  true,  true,
		false, false, false, false,
	]

	for pi in offsets.size():
		var wob: Vector2 = Vector2(
			(_hf(cseed + pi * 7) - 0.50) * sx * 0.14,
			(_hf(cseed + pi * 7 + 3) - 0.50) * sy * 0.16 * rym)
		var px: float = cx + offsets[pi].x * sx + wob.x
		var py: float = cy + offsets[pi].y * sy * rym + wob.y
		var psx: float = sx * sizes[pi]
		var psy: float = sy * (sizes[pi] + 0.18) * rym

		var puff_col: Color = top_col if is_top[pi] else bot_col
		var alpha_mod: float = 0.70 if is_top[pi] else 0.60

		_draw_soft_puff(px, py, psx, psy, puff_col, alpha_mod)

func _draw_soft_puff(cx: float, cy: float, rx: float, ry: float,
					 color: Color, density: float) -> void:
	if rx < 1.5 or ry < 1.5 or color.a < 0.005: return
	var a: float = color.a * density
	_draw_oval(cx, cy, rx * 1.15, ry * 1.15, Color(color.r, color.g, color.b, a * 0.08))
	_draw_oval(cx, cy, rx * 0.95, ry * 0.95, Color(color.r, color.g, color.b, a * 0.30))
	_draw_oval(cx, cy, rx * 0.70, ry * 0.70, Color(color.r, color.g, color.b, a * 0.55))
	_draw_oval(cx, cy, rx * 0.35, ry * 0.35, Color(color.r, color.g, color.b, a * 1.00))

func _draw_oval(cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	if rx < 0.5 or ry < 0.5: return
	var pts := PackedVector2Array()
	for i in 8:
		var a := (float(i)/8.0)*TAU
		pts.append(Vector2(cx+cos(a)*rx, cy+sin(a)*ry))
	_safe_draw_polygon(pts, color)

# ─────────────────────────────────────────────────────────────────────────────
# FOG
# ─────────────────────────────────────────────────────────────────────────────

func _draw_fog() -> void:
	var rb := _get_weather_blend()
	var fc : Color = _rain_lerp_color(_env.get("fog_color",Color(0,0,0,0)),"fog_color",rb)
	if fc.a < 0.01: return
	var bl := _bg_left(); var br := _bg_right(); var st := _bg_top()
	var sw := br - bl
	var total_h := (ground_y + 99999.0) - st
	for i in 5:
		var t0 := float(i)/5.0; var t1 := float(i+1)/5.0
		_draw_grad_quad(bl, st+t0*total_h, sw, st+t1*total_h,
			Color(fc.r,fc.g,fc.b, fc.a*(1.0-t0*0.65)),
			Color(fc.r,fc.g,fc.b, fc.a*(1.0-t1*0.65)))

# ─────────────────────────────────────────────────────────────────────────────
# GYM INTERIOR
# ─────────────────────────────────────────────────────────────────────────────

func _draw_gym_interior() -> void:
	var bl      := _bg_left(); var br := _bg_right()
	var width   := br - bl
	var vis_top := wall_min.y
	var vis_bot := ground_y if ground_y > vis_top + 10.0 else vis_top + (wall_max.y - wall_min.y)
	var vis_h   := vis_bot - vis_top
	if width < 1.0 or vis_h < 10.0: return

	for i in 12:
		var t := float(i) / 12.0
		draw_rect(Rect2(Vector2(bl, vis_top+t*vis_h), Vector2(width, vis_h/12.0+2.0)),
				  Color(0.93-t*0.025, 0.93-t*0.022, 0.94-t*0.018), true)

	var win_top := vis_top + vis_h * 0.10
	var win_h   := vis_h * 0.78
	var win_bot := win_top + win_h
	var win_w   := 400.0; var win_gap := 150.0
	var win_stride := win_w + win_gap
	var win_count  := int(ceil(width / win_stride)) + 2
	var wall_col   := Color(0.93, 0.93, 0.94)

	var ct   := get_viewport().get_canvas_transform()
	var zoom := ct.x.x; var cam_x := -ct.origin.x / zoom
	var rb   := _get_weather_blend()
	var tod  : int = _env.get("gym_time_of_day", 0)

	var stc : Color = _env.get("gym_sky_top",   Color(0.20,0.45,0.78))
	var smc : Color = _env.get("gym_sky_mid",   Color(0.44,0.70,0.93))
	var shc : Color = _env.get("gym_sky_haze",  Color(0.70,0.86,0.97))
	var rain_sky := Color(0.18,0.20,0.26)
	stc = stc.lerp(rain_sky, rb); smc = smc.lerp(rain_sky.lightened(0.06), rb); shc = shc.lerp(rain_sky.lightened(0.12), rb)

	var sun_wx     := wall_min.x + (wall_max.x-wall_min.x)*0.68 + cam_x*0.03
	var gsc        : Color = _env.get("gym_sun_color", Color(1.0,0.96,0.78))
	var sun_y_frac := 0.72 if tod == 1 else 0.15
	var mtns       : Array = _env.get("gym_mtn_colors", [Color(0.72,0.82,0.91),Color(0.54,0.67,0.80),Color(0.38,0.52,0.66),Color(0.24,0.38,0.53)])
	var grass_c    : Color = (_env.get("gym_grass_color", Color(0.18,0.26,0.19)) as Color).lerp(Color(0.12,0.18,0.14), rb*0.5)

	for wi in win_count:
		var wx  := bl + float(wi)*win_stride + win_gap*0.5
		var wx2 := wx + win_w
		for gi in 12:
			var gt := float(gi)/12.0
			var sky_c := stc.lerp(smc, gt*2.0) if gt < 0.5 else smc.lerp(shc,(gt-0.5)*2.0)
			draw_rect(Rect2(Vector2(wx, win_top+gt*win_h), Vector2(win_w, win_h/12.0+1.0)), sky_c, true)
		if _env.get("has_gym_stars", false):
			for si in 30:
				var ss := (_scenery_seed^0xCAFE)+wi*97+si*13
				var tw := 0.7+0.3*sin(_cloud_time*(1.5+_hf(ss+4)*3.0)+float(si))
				draw_circle(Vector2(wx+_hf(ss)*win_w, win_top+_hf(ss+1)*win_h*0.6),
							1.0+_hf(ss+3)*1.6, Color(1.0,1.0,1.0,(0.35+_hf(ss+2)*0.50)*tw*(1.0-rb)))
		var moon_idx: int = (_scenery_seed^0xF00F)%max(win_count,1)
		if _env.get("has_gym_moon",false) and wi == moon_idx:
			var ms := _scenery_seed^0xF00F
			var mx2 := wx+win_w*(0.35+_hf(ms)*0.30); var my2 := win_top+win_h*(0.12+_hf(ms+1)*0.22)
			var mr := 20.0+_hf(ms+2)*10.0
			for gi in 3: draw_circle(Vector2(mx2,my2), mr+float(gi)*14.0, Color(0.7,0.75,0.9,0.04))
			draw_circle(Vector2(mx2,my2), mr, Color(0.88,0.90,0.95,0.92*(1.0-rb)))
			draw_circle(Vector2(mx2+mr*0.35,my2-mr*0.1), mr*0.82, stc)
		if tod != 2 and gsc.r+gsc.g+gsc.b > 0.05 and rb < 0.85 and sun_wx >= wx+20.0 and sun_wx <= wx2-20.0:
			var sun_y := win_top+win_h*sun_y_frac; var sf := 1.0-rb
			for ri in 7:
				draw_circle(Vector2(sun_wx,sun_y), 7.0+ri*18.0,
							Color(gsc.r,gsc.g,gsc.b,(0.042-ri*0.005)*sf))
			draw_circle(Vector2(sun_wx,sun_y), 10.0,
						Color(gsc.r+0.05,gsc.g+0.02,gsc.b*0.8,0.70*sf))
			if tod == 1:
				for gsi in 8:
					var gt := float(gsi)/8.0
					_draw_grad_quad(wx, sun_y-4.0+gt*40.0, win_w, sun_y-4.0+(gt+1.0/8.0)*40.0,
						Color(gsc.r,gsc.g*0.6,0.05,lerp(0.18,0.0,gt)*sf),
						Color(gsc.r,gsc.g*0.6,0.05,lerp(0.18,0.0,(gt+1.0/8.0))*sf))
		if rb > 0.05: _draw_window_rain_streaks(wx, wx2, win_top, win_bot, rb)
		var mtn_span := win_w*8.0; var msegs := 80
		for mi in 4:
			var ms   := (_scenery_seed^(0xC001+mi*0x999))+wi*61
			var mpar := cam_x*(0.04+mi*0.055)
			var mhmin := win_h*(0.06+mi*0.09); var mhmax := win_h*(0.20+mi*0.11)
			var mleft := wx+win_w*0.5-mtn_span*0.5+mpar
			var mbase := win_bot+6.0; var mstep := mtn_span/float(msegs)
			var mcol  : Color = (mtns[mi] if mi < mtns.size() else Color(0.24,0.38,0.53))
			mcol = mcol.lerp(Color(0.22,0.24,0.30), rb*0.6)
			var ridge: Array = []
			for si in msegs+1:
				var px := mleft+si*mstep
				if px < wx-mstep or px > wx2+mstep: continue
				var mh0 := _hf(ms+(si-1)*7)*(mhmax-mhmin)+mhmin
				var mh1 := _hf(ms+si*7)*(mhmax-mhmin)+mhmin
				var mh2 := _hf(ms+(si+1)*7)*(mhmax-mhmin)+mhmin
				ridge.append(Vector2(clampf(px,wx,wx2), mbase-(mh0*0.2+mh1*0.6+mh2*0.2)))
			if ridge.size() < 2: continue
			var mpts := PackedVector2Array(); mpts.append(Vector2(wx,mbase))
			for rp in ridge: mpts.append(rp)
			mpts.append(Vector2(wx2,mbase))
			_safe_draw_polygon(mpts, mcol)
		var gnd_h := win_h*0.09; var gsegs := 40; var gstep := win_w/float(gsegs)
		var gpts  := PackedVector2Array(); gpts.append(Vector2(wx, win_bot+4.0))
		for gi2 in gsegs+1:
			var gs := (_scenery_seed^0x9F01)+wi*37+gi2*5
			gpts.append(Vector2(clampf(wx+gi2*gstep,wx,wx2), win_bot-gnd_h*(0.6+_hf(gs)*0.4)))
		gpts.append(Vector2(wx2,win_bot+4.0))
		_safe_draw_polygon(gpts, grass_c)
		draw_rect(Rect2(Vector2(wx,win_bot-gnd_h*0.6), Vector2(win_w,gnd_h*0.6+6.0)), grass_c.darkened(0.16), true)
		draw_rect(Rect2(Vector2(wx,win_top), Vector2(win_w,win_h)), Color(1.0,1.0,1.0,0.06), true)
		draw_rect(Rect2(Vector2(wx,win_top), Vector2(win_w*0.08,win_h)), Color(1.0,1.0,1.0,0.05), true)

	for wi in win_count+1:
		var gx := bl+float(wi)*win_stride+win_gap*0.5-win_gap
		draw_rect(Rect2(Vector2(gx,vis_top), Vector2(win_gap+4.0,vis_h)), wall_col, true)
	draw_rect(Rect2(Vector2(bl,vis_top), Vector2(width,win_top-vis_top+1.0)), wall_col, true)
	draw_rect(Rect2(Vector2(bl,win_bot-1.0), Vector2(width,vis_bot-win_bot+2.0)), wall_col, true)
	for wi in win_count:
		var wx := bl+float(wi)*win_stride+win_gap*0.5
		draw_line(Vector2(wx,win_top), Vector2(wx+win_w,win_top), Color(0.55,0.57,0.62,0.35), 1.5, true)
		draw_line(Vector2(wx,win_top), Vector2(wx,win_bot),       Color(0.55,0.57,0.62,0.35), 1.5, true)
	draw_rect(Rect2(Vector2(bl,vis_bot-28.0), Vector2(width,28.0)), Color(0.22,0.22,0.24), true)

func _draw_window_rain_streaks(wx: float, wx2: float, win_top: float, win_bot: float, blend: float) -> void:
	var win_h := win_bot-win_top; var win_w := wx2-wx
	for i in 5:
		var t0 := float(i)/5.0; var t1 := float(i+1)/5.0
		_draw_grad_quad(wx, win_top+t0*win_h, win_w, win_top+t1*win_h,
			Color(0.08,0.11,0.18, blend*0.24*t0*t0), Color(0.10,0.14,0.22, blend*0.24*t1*t1))
	var mist_h := win_h*0.14*blend
	for i in 4:
		var t0 := float(i)/4.0; var t1 := float(i+1)/4.0
		_draw_grad_quad(wx, win_bot-t0*mist_h, win_w, win_bot-t1*mist_h,
			Color(0.55,0.64,0.78, blend*0.10*(1.0-t0)),
			Color(0.55,0.64,0.78, blend*0.10*(1.0-t1)))
	for si in int(6.0*blend):
		var ss := (_scenery_seed^0xF00D)+si*41
		var sx := wx+_hf(ss)*win_w; var slen := 16.0+_hf(ss+2)*26.0
		var per := win_h/(40.0+_hf(ss+4)*30.0)
		var ay  := fmod(_cloud_time/per+_hf(ss+1),1.0)*win_h
		if ay+slen>win_bot-win_top: continue
		draw_line(Vector2(sx,win_top+ay), Vector2(sx+1.2,win_top+ay+slen),
				  Color(0.65,0.75,0.92,(0.06+_hf(ss+3)*0.11)*blend), 1.0, true)

# ─────────────────────────────────────────────────────────────────────────────
# SCAFFOLD
# ─────────────────────────────────────────────────────────────────────────────

func _draw_scaffold() -> void:
	var pc := Color(0.42,0.32,0.20); var ph := Color(0.55,0.44,0.28)
	var ps := Color(0.28,0.20,0.12); var bc := Color(0.38,0.28,0.17)
	var lx := wall_min.x-28.0; var rx := wall_max.x+28.0
	var ty := wall_min.y-36.0; var by := ground_y+14.0
	for px in [lx,rx]:
		draw_rect(Rect2(Vector2(px-9.0,ty), Vector2(18.0,by-ty)), pc, true)
		draw_rect(Rect2(Vector2(px-9.0,ty), Vector2(5.0,by-ty)),  ps, true)
		draw_rect(Rect2(Vector2(px+5.0, ty), Vector2(4.0,by-ty)), ph, true)
	draw_rect(Rect2(Vector2(lx-18.0,ty-14.0), Vector2(rx-lx+36.0,14.0)), bc, true)
	draw_line(Vector2(lx-18.0,ty-14.0), Vector2(rx+18.0,ty-14.0), ph, 1.5, true)
	var my := ty+(ground_y-ty)*0.5
	draw_rect(Rect2(Vector2(lx-9.0,my-7.0), Vector2(rx-lx+18.0,14.0)), bc, true)
	draw_line(Vector2(lx-9.0,my-7.0), Vector2(rx+9.0,my-7.0), ph, 1.0, true)
	var brc := Color(0.35,0.26,0.15,0.9)
	for sx in [lx,rx]:
		var dir := -1.0 if sx == lx else 1.0
		draw_line(Vector2(sx,ty+60.0), Vector2(sx+dir*70.0,my),    brc, 9.0, true)
		draw_line(Vector2(sx,my+30.0), Vector2(sx+dir*70.0,ground_y), brc, 9.0, true)
	for px in [lx,rx]:
		draw_rect(Rect2(Vector2(px-22.0,ground_y-8.0), Vector2(44.0,22.0)), Color(0.50,0.50,0.52), true)

# ─────────────────────────────────────────────────────────────────────────────
# WALL SURFACE
# ─────────────────────────────────────────────────────────────────────────────

func _draw_rectangle_wall() -> void:
	if current_environment == "building": _draw_building_facade_wall(); return
	var ws := wall_max - wall_min
	draw_rect(Rect2(wall_min, ws), current_wall_color, true)
	var st := current_wall_color.lightened(0.09)
	_draw_grad_quad(wall_min.x, wall_min.y, ws.x, wall_min.y+ws.y*0.15,
		st, Color(st.r,st.g,st.b,0.0))
	_draw_grad_quad(wall_min.x, wall_max.y-ws.y*0.30, ws.x, wall_max.y,
		Color(0,0,0,0.0), Color(0,0,0,0.06))
	var ao_w := minf(ws.x*0.035, 16.0)
	_draw_grad_quad_h(wall_min.x, wall_min.y, wall_min.x+ao_w, wall_max.y,
		Color(0,0,0,0.09), Color(0,0,0,0.0))
	if wall_texture_enabled: draw_textured_wall(wall_min, ws)

func _draw_polygon_wall() -> void:
	var pp := PackedVector2Array(control_points)
	_safe_draw_polygon(pp, current_wall_color)
	if wall_texture_enabled:
		var p2   := PackedVector2Array(); var cols := PackedColorArray()
		for i in pp.size():
			p2.append(pp[i])
			var t := clampf((pp[i].y - wall_min.y) / max(wall_max.y - wall_min.y, 1.0), 0.0, 1.0)
			cols.append(Color(0,0,0, t*t*0.06))
		_safe_draw_vertex_polygon(p2, cols)

# ─────────────────────────────────────────────────────────────────────────────
# WALL MATERIAL TEXTURE  —  environment-specific surface grain
# ─────────────────────────────────────────────────────────────────────────────

func _draw_wall_material_texture() -> void:
	## Adds a subtle material-specific surface texture to the wall so it
	## doesn't look like a flat colour fill.  Each environment gets its own
	## visual grain: wood for gym, crack lines for granite, bedding for
	## sandstone, frost for ice, concrete for building.
	if not wall_valid: return
	if use_polygon_mode: return  # polygon walls use the existing shader path
	var rb := _get_weather_blend()

	match current_environment:
		"gym":
			# ── Vertical wood-grain streaks ────────────────────────────────
			var wood := current_wall_color.darkened(0.04)
			for si in int((wall_max.x - wall_min.x) / 80.0) + 1:
				var ss := (_scenery_seed ^ 0xA1B2) + si * 17
				var sx := wall_min.x + _hf(ss) * (wall_max.x - wall_min.x)
				var sw := 1.0 + _hf(ss + 1) * 2.5
				var sv := 0.01 + _hf(ss + 2) * 0.03
				draw_line(Vector2(sx, wall_min.y), Vector2(sx, wall_max.y),
					Color(wood.r + sv, wood.g + sv, wood.b + sv, 0.06), sw, true)
			# Subtle panel joint seam spaced every ~240 pixels
			var jx: float = floor(wall_min.x / 240.0) * 240.0
			while jx <= wall_max.x:
				if jx >= wall_min.x:
					draw_line(Vector2(jx, wall_min.y), Vector2(jx, wall_max.y),
						Color(0, 0, 0, 0.04), 0.8, true)
				jx += 240.0

		"granite", "deep water solo":
			# ── Fine crack/fissure lines ───────────────────────────────────
			for ci in int((wall_max.x - wall_min.x) / 150.0) + 1:
				var cs := (_scenery_seed ^ 0xB3C4) + ci * 23
				var cx := wall_min.x + _hf(cs) * (wall_max.x - wall_min.x)
				var cy := wall_min.y + _hf(cs + 1) * (wall_max.y - wall_min.y)
				var clen := 20.0 + _hf(cs + 2) * 60.0
				var crank := (_hf(cs + 3) - 0.5) * 0.8
				var cend := Vector2(cx + sin(crank) * clen, cy + cos(crank) * clen)
				var crack_col := Color(0.38, 0.36, 0.34, 0.07 + _hf(cs + 4) * 0.06)
				draw_line(Vector2(cx, cy), cend, crack_col, 0.8 + _hf(cs + 5) * 1.2, true)
				# Forked branch
				if _hf(cs + 6) > 0.6:
					var fork_end := Vector2(
						cend.x + (_hf(cs + 7) - 0.5) * clen * 0.5,
						cend.y + (_hf(cs + 8) - 0.5) * clen * 0.5)
					draw_line(cend, fork_end, crack_col, 0.6, true)

		"sandstone":
			# ── Horizontal sedimentary bedding lines ───────────────────────
			var bedding_col := current_wall_color.darkened(0.06)
			var by: float = floor(wall_min.y / 60.0) * 60.0
			while by <= wall_max.y:
				if by >= wall_min.y:
					var bv := (_hf(_scenery_seed ^ int(by * 0.1)) - 0.5) * 0.03
					draw_line(Vector2(wall_min.x, by), Vector2(wall_max.x, by),
						Color(bedding_col.r + bv, bedding_col.g + bv, bedding_col.b + bv, 0.05 + absf(bv) * 0.5),
						1.0 + _hf(_scenery_seed ^ (int(by * 0.1) + 5)) * 2.0, true)
				by += 45.0 + _hf(_scenery_seed ^ int(by * 0.01)) * 30.0
			# Subtle undulating layer between beddings
			var uy: float = floor(wall_min.y / 120.0) * 120.0
			while uy <= wall_max.y:
				if uy >= wall_min.y:
					var ux := wall_min.x
					while ux <= wall_max.x:
						var uv := sin(ux * 0.015 + uy * 0.01) * 3.0
						draw_line(Vector2(ux, uy + uv), Vector2(ux + 30.0, uy + sin((ux + 30.0) * 0.015 + uy * 0.01) * 3.0),
							Color(0, 0, 0, 0.02), 0.6, true)
						ux += 30.0
				uy += 120.0

		"ice":
			# ── Frost hex crystal sparkles ─────────────────────────────────
			var frost_col := Color(0.82, 0.94, 1.0, 0.08 * (1.0 - rb * 0.5))
			for fi in int((wall_max.x - wall_min.x) / 200.0) + 1:
				var fs := (_scenery_seed ^ 0xC5D6) + fi * 29
				var fx := wall_min.x + _hf(fs) * (wall_max.x - wall_min.x)
				var fy := wall_min.y + _hf(fs + 1) * (wall_max.y - wall_min.y)
				var fr := 3.0 + _hf(fs + 2) * 8.0
				# Small hexagonal crystal indication
				var twinkle := sin(_cloud_time * (1.1 + _hf(fs + 3) * 2.3) + float(fi)) * 0.5 + 0.5
				draw_line(Vector2(fx - fr, fy), Vector2(fx + fr, fy), Color(frost_col.r, frost_col.g, frost_col.b, frost_col.a * twinkle), 0.8, true)
				draw_line(Vector2(fx - fr * 0.5, fy - fr * 0.87), Vector2(fx + fr * 0.5, fy + fr * 0.87), Color(frost_col.r, frost_col.g, frost_col.b, frost_col.a * twinkle * 0.6), 0.6, true)
				draw_line(Vector2(fx - fr * 0.5, fy + fr * 0.87), Vector2(fx + fr * 0.5, fy - fr * 0.87), Color(frost_col.r, frost_col.g, frost_col.b, frost_col.a * twinkle * 0.6), 0.6, true)

		"building":
			# ── Concrete pour joint detail ─────────────────────────────────
			var bjoint := current_wall_color.darkened(0.05)
			for hi in int((wall_max.y - wall_min.y) / 300.0) + 1:
				var hy2 := wall_min.y + float(hi) * 300.0 + _hf(_scenery_seed ^ (hi * 13)) * 30.0
				if hy2 > wall_max.y: break
				if hy2 >= wall_min.y:
					draw_line(Vector2(wall_min.x, hy2), Vector2(wall_max.x, hy2),
						Color(bjoint.r, bjoint.g, bjoint.b, 0.06), 1.2, true)

# ─────────────────────────────────────────────────────────────────────────────
# ICE SHEEN
# ─────────────────────────────────────────────────────────────────────────────

func _draw_ice_wall_sheen() -> void:
	if not wall_valid: return
	var sc : Color = _env.get("ice_sheen_color", Color(0.88,0.96,1.00))
	var ws := wall_max - wall_min
	for bi in 5:
		var bs := (_scenery_seed^0xACE0)+bi*37
		var bx := wall_min.x+_hf(bs)*ws.x; var bw := 14.0+_hf(bs+1)*38.0; var ba := 0.04+_hf(bs+2)*0.07
		_draw_grad_quad_h(bx, wall_min.y, bx+bw, wall_max.y, Color(sc.r,sc.g,sc.b,0.0), Color(sc.r,sc.g,sc.b,ba))
		_draw_grad_quad_h(bx+bw, wall_min.y, bx+bw*2.0, wall_max.y, Color(sc.r,sc.g,sc.b,ba), Color(sc.r,sc.g,sc.b,0.0))
	_draw_grad_quad(wall_min.x, wall_min.y, ws.x, wall_min.y+ws.y*0.08,
		Color(sc.r,sc.g,sc.b,0.14), Color(sc.r,sc.g,sc.b,0.0))
	draw_rect(Rect2(wall_min, ws), Color(sc.r,sc.g,sc.b,0.06), true)

# ─────────────────────────────────────────────────────────────────────────────
# WALL DEPTH & OUTLINE
# ─────────────────────────────────────────────────────────────────────────────

func _draw_wall_depth_shading() -> void:
	if not wall_valid: return
	var w := wall_max.x - wall_min.x
	_draw_grad_quad(wall_min.x-40.0, ground_y, w+80.0, ground_y+32.0, Color(0,0,0,0.24), Color(0,0,0,0.0))
	_draw_grad_quad(wall_min.x, ground_y-8.0, w, ground_y+6.0,        Color(0,0,0,0.0),  Color(0,0,0,0.14))
	if not use_polygon_mode:
		_draw_grad_quad(wall_min.x, wall_min.y-3.0, w, wall_min.y+6.0, Color(1,1,1,0.08), Color(1,1,1,0.0))

func _draw_wall_tonal_outline() -> void:
	if not wall_valid: return
	var wc := current_wall_color.darkened(wall_outline_darken)
	wc.a    = wall_outline_darken * 2.8
	if use_polygon_mode and control_points.size() >= 3:
		for i in control_points.size():
			if _is_ground_edge(i): continue
			draw_line(control_points[i], control_points[(i+1)%control_points.size()], wc, wall_outline_width, true)
	else:
		var tl  := wall_min; var tr2 := Vector2(wall_max.x,wall_min.y)
		var bl  := Vector2(wall_min.x,wall_max.y); var br := wall_max
		draw_line(tl,tr2,wc,wall_outline_width,true); draw_line(tl,bl,wc,wall_outline_width,true)
		draw_line(tr2,br,wc,wall_outline_width,true)
		var gc := (_env.get("ground_top",Color(0.22,0.52,0.14)) as Color).darkened(wall_outline_darken)
		gc.a = wc.a * 0.80
		draw_line(bl, br, gc, wall_outline_width, true)

# ─────────────────────────────────────────────────────────────────────────────
# BUILDING FACADE WALL
# ─────────────────────────────────────────────────────────────────────────────

func _draw_building_facade_wall() -> void:
	var tod : int = _env.get("city_time", 0)
	var rb  := _get_weather_blend()
	var base_col: Color; var dark_col: Color; var lite_col: Color
	match tod:
		1: base_col=Color(0.42,0.36,0.30); dark_col=Color(0.28,0.23,0.18); lite_col=Color(0.54,0.46,0.36)
		2: base_col=Color(0.22,0.22,0.26); dark_col=Color(0.14,0.14,0.18); lite_col=Color(0.28,0.28,0.34)
		_: base_col=Color(0.52,0.52,0.54); dark_col=Color(0.38,0.38,0.40); lite_col=Color(0.64,0.64,0.66)
	base_col=base_col.lerp(Color(0.34,0.36,0.40),rb*0.4); lite_col=lite_col.lerp(Color(0.40,0.42,0.46),rb*0.3)
	var w := wall_max.x-wall_min.x; var h := wall_max.y-wall_min.y
	for vi in 14:
		var t0 := float(vi)/14.0; var t1 := float(vi+1)/14.0
		_draw_grad_quad(wall_min.x, wall_min.y+t0*h, w, wall_min.y+t1*h,
			lite_col.lerp(dark_col, t0*t0*0.72+t0*0.28), lite_col.lerp(dark_col, t1*t1*0.72+t1*0.28))
	_draw_grad_quad_h(wall_max.x-minf(w*0.04,18.0), wall_min.y, wall_max.x, wall_max.y,
		Color(0,0,0,0.0), Color(0,0,0,0.10))
	var panel_w := 220.0; var panel_h := 160.0
	var vgx: float = floor(wall_min.x/panel_w)*panel_w
	while vgx <= wall_max.x:
		if vgx >= wall_min.x: draw_line(Vector2(vgx,wall_min.y),Vector2(vgx,wall_max.y),Color(dark_col.r,dark_col.g,dark_col.b,0.28),1.5,true)
		vgx += panel_w
	var hgy: float = floor(wall_min.y/panel_h)*panel_h
	while hgy <= wall_max.y:
		if hgy >= wall_min.y:
			var dt := clampf((hgy-wall_min.y)/h,0.0,1.0)
			draw_line(Vector2(wall_min.x,hgy),Vector2(wall_max.x,hgy),Color(dark_col.r,dark_col.g,dark_col.b,lerp(0.18,0.40,dt)),1.5,true)
		hgy += panel_h
	var win_w2 := panel_w*0.42; var win_h2 := panel_h*0.50
	var wmx := (panel_w-win_w2)*0.5; var wmy := (panel_h-win_h2)*0.5
	var lit_prob: float; var wg: Color; var wf: Color
	match tod:
		1: lit_prob=0.40; wg=Color(0.88,0.64,0.28,0.62); wf=Color(0.22,0.18,0.14)
		2: lit_prob=0.70; wg=Color(0.86,0.82,0.50,0.78); wf=Color(0.10,0.10,0.14)
		_: lit_prob=0.08; wg=Color(0.48,0.66,0.82,0.42); wf=Color(0.28,0.28,0.30)
	wg = wg.lerp(Color(0.38,0.44,0.52,wg.a), rb*0.4)
	var coli := 0; var cpx: float = floor(wall_min.x/panel_w)*panel_w
	while cpx < wall_max.x:
		var rowi := 0; var cpy: float = floor(wall_min.y/panel_h)*panel_h
		while cpy < wall_max.y:
			var wr := Rect2(cpx+wmx,cpy+wmy,win_w2,win_h2)
			var cl := wr.intersection(Rect2(wall_min,wall_max-wall_min))
			if cl.has_area():
				var ws2 := (coli*1117+rowi*337)^_scenery_seed
				_draw_grad_quad(cl.position.x-2.0,cl.position.y-2.0,cl.size.x+4.0,cl.position.y+2.0,
					Color(wf.r,wf.g,wf.b,0.5),Color(wf.r,wf.g,wf.b,0.0))
				if _hf(ws2) < lit_prob:
					var hv := (_hf(ws2+7)-0.5)*0.10
					var wv := Color(clampf(wg.r+hv*0.6,0,1),clampf(wg.g-hv*0.2,0,1),clampf(wg.b-hv*0.4,0,1),wg.a*(0.78+_hf(ws2+8)*0.26))
					draw_rect(cl, wv, true)
					if tod>=1: draw_rect(Rect2(cl.position+Vector2(1.5,1.5),cl.size-Vector2(3.0,3.0)),Color(wv.r,wv.g,wv.b,wv.a*0.38),true)
					if tod==0 and rb<0.5: draw_rect(Rect2(cl.position,Vector2(cl.size.x*0.22,cl.size.y*0.16)),Color(0.78,0.88,0.98,0.14*(1.0-rb*2.0)),true)
				else:
					draw_rect(cl, Color(dark_col.r,dark_col.g,dark_col.b,0.50), true)
			rowi+=1; cpy+=panel_h
		coli+=1; cpx+=panel_w
	draw_rect(Rect2(wall_min.x,wall_min.y,10.0,h),dark_col,true)
	draw_rect(Rect2(wall_max.x-10.0,wall_min.y,10.0,h),dark_col,true)
	var crh := 9.0
	draw_rect(Rect2(wall_min.x-4.0,wall_min.y-crh,w+8.0,crh),lite_col.lightened(0.07),true)
	draw_rect(Rect2(wall_min.x-4.0,wall_min.y,w+8.0,3.0),dark_col.darkened(0.12),true)
	if rb > 0.2:
		for si in int(10.0*rb):
			var ss := (_scenery_seed^0xC0DE)+si*43
			var per := h/(35.0+_hf(ss+3)*25.0)
			var ay  := fmod(_cloud_time/per+_hf(ss+4),1.0)*h
			if ay+18.0+_hf(ss+1)*30.0>h: continue
			draw_line(Vector2(wall_min.x+_hf(ss)*w,wall_min.y+ay),
					  Vector2(wall_min.x+_hf(ss)*w+1.0,wall_min.y+ay+18.0+_hf(ss+1)*30.0),
					  Color(0.60,0.70,0.88,(0.04+_hf(ss+2)*0.07)*rb),1.0,true)

# ─────────────────────────────────────────────────────────────────────────────
# GROUND DISPATCH
# ─────────────────────────────────────────────────────────────────────────────

func _draw_ground() -> void:
	if not wall_valid: return
	match _env.get("ground_type","grass"):
		"grass","grass_dusk","grass_night": _draw_ground_grass()
		"gym_floor":                        _draw_ground_gym()
		"water":                            _draw_ground_water()
		"city_street":                      _draw_ground_city()
		"sand","sand_dusk","sand_night":    _draw_ground_sand()
		"ice_snow":                         _draw_ground_ice_snow()
		_:                                  _draw_ground_grass()

func _draw_ground_grass() -> void:
	var left  := _bg_left(); var right := _bg_right(); var width := right - left
	var rb    := _weather_blend_current
	var ct: Color = (_env.get("ground_top",  Color(0.22,0.52,0.14)) as Color).lerp(Color(0.14,0.28,0.10),rb*0.55)
	var cm: Color = (_env.get("ground_mid",  Color(0.32,0.22,0.12)) as Color).lerp(Color(0.20,0.16,0.10),rb*0.40)
	var cd: Color = (_env.get("ground_deep", Color(0.20,0.14,0.08)) as Color).lerp(Color(0.14,0.12,0.08),rb*0.30)
	draw_rect(Rect2(Vector2(left,ground_y), Vector2(width,99999.0)), cd, true)
	_draw_grad_quad(left,ground_y,        width,ground_y+38.0,    ct.lightened(0.06),ct)
	_draw_grad_quad(left,ground_y+38.0,   width,ground_y+128.0,   ct,cm)
	_draw_grad_quad(left,ground_y+128.0,  width,ground_y+368.0,   cm,cd)
	var pts := PackedVector2Array(); var hs := _scenery_seed^0x6A55
	pts.append(Vector2(left,ground_y+44.0))
	for i in 81:
		var h0:=_hf(hs+(i-1)*11)*7.0; var h1:=_hf(hs+i*11)*7.0; var h2:=_hf(hs+(i+1)*11)*7.0
		pts.append(Vector2(left+float(i)*(width/80.0), ground_y-(h0*0.2+h1*0.6+h2*0.2)))
	pts.append(Vector2(right,ground_y+44.0))
	_safe_draw_polygon(pts, ct)
	var sh : Color = _rain_lerp_color(_env.get("sky_horizon",background_color.lightened(0.15)),"sky_horizon",rb)
	_draw_grad_quad(left,ground_y-1.0,width,ground_y+18.0,Color(sh.r,sh.g,sh.b,0.18*(1.0-rb*0.5)),Color(sh.r,sh.g,sh.b,0.0))
	var hc := ct.darkened(wall_outline_darken); hc.a=minf(wall_outline_darken*2.6,1.0)
	draw_line(Vector2(left,ground_y),Vector2(right,ground_y),hc,wall_outline_width,true)
	if rb > 0.1: _draw_ground_puddles(left,right,rb)
	# ── Grass blade detail ──────────────────────────────────────────────────
	# Grass blade detail — halve density when weather is light, skip when heavy
	if rb < 0.4:
		var density_mult := 3.0 if rb < 0.15 else 5.0  # fewer blades when weather
		for bi in int(width / (120.0 * density_mult)) + 1:
			var bs := _scenery_seed ^ (0xB1E2 + bi * 13)
			var bx := left + _hf(bs) * width
			for ti in 3:
				var tx := bx + (_hf(bs + ti * 7 + 1) - 0.5) * 12.0
				var tlen := 4.0 + _hf(bs + ti * 7 + 2) * 10.0
				var tangle := -1.2 + _hf(bs + ti * 7 + 3) * 1.0
				var gc := ct.lightened(0.08 + _hf(bs + ti * 7 + 4) * 0.18)
				draw_line(Vector2(tx, ground_y + 1.0),
					Vector2(tx + sin(tangle) * tlen, ground_y - 1.0 - cos(tangle) * tlen * 0.6),
					Color(gc.r, gc.g, gc.b, 0.30 + _hf(bs + ti * 7 + 5) * 0.25), 0.8)
		if rb < 0.2:
			for fi in int(width / 400.0) + 1:  # fewer flowers
				var fs := _scenery_seed ^ (0xC3D4 + fi * 27)
				var fx := left + _hf(fs) * width
				var fy := ground_y + 2.0 + _hf(fs + 1) * 16.0
				var fd := 2.0 + _hf(fs + 2) * 3.0
				var flower := Color(0.92 + _hf(fs + 3) * 0.07, 0.65 + _hf(fs + 4) * 0.20, 0.30 + _hf(fs + 5) * 0.30, 0.35)
				draw_circle(Vector2(fx, fy), fd, flower)

func _draw_ground_puddles(left: float, right: float, blend: float) -> void:
	for pi in int(6.0*blend):
		var ps := (_scenery_seed^0xAB12)+pi*53
		var px := left+_hf(ps)*(right-left); var pw := 60.0+_hf(ps+1)*140.0*blend; var ph := 6.0+_hf(ps+2)*10.0
		var shimmer := sin(_cloud_time*1.8+float(pi)*2.1)*0.05
		var ov := PackedVector2Array()
		for si in 12: ov.append(Vector2(px+cos(float(si)/12.0*TAU)*pw, ground_y+2.0+sin(float(si)/12.0*TAU)*ph))
		_safe_draw_polygon(ov, Color(0.38+shimmer,0.48+shimmer,0.62,0.20*blend))
		draw_line(Vector2(px-pw*0.3,ground_y+1.0),Vector2(px+pw*0.3,ground_y+1.0),Color(0.55,0.65,0.80,0.20*blend*0.35),1.2,true)

func _draw_ground_gym() -> void:
	var left  := _bg_left(); var right := _bg_right(); var width := right - left
	var ct : Color = _env.get("ground_top",  Color(0.22,0.22,0.24))
	var cd : Color = _env.get("ground_deep", Color(0.11,0.11,0.12))
	draw_rect(Rect2(Vector2(left,ground_y), Vector2(width,99999.0)), ct, true)
	_draw_grad_quad(left,ground_y,     width,ground_y+120.0,ct.lightened(0.03),ct.lerp(cd,0.5))
	_draw_grad_quad(left,ground_y+120.0,width,ground_y+420.0,ct.lerp(cd,0.5),cd)
	_draw_grad_quad(left,ground_y,width,ground_y+7.0,Color(1,1,1,0.045),Color(1,1,1,0.0))
	# ── Floor joint pattern (concrete slab seams) ──────────────────────────
	var tc := int(ceil(width/200.0))+1
	for ti in tc: draw_line(Vector2(left+float(ti)*200.0,ground_y),Vector2(left+float(ti)*200.0,ground_y+85.0),Color(cd.r,cd.g,cd.b,0.11),0.7,true)
	for hy in [18.0,42.0,80.0,145.0,245.0]: draw_line(Vector2(left,ground_y+hy),Vector2(left+width,ground_y+hy),Color(cd.r,cd.g,cd.b,0.07),0.6,true)
	# ── Subtle floor wear/sheen near the wall base ─────────────────────────
	for wi in int(width / 300.0) + 1:
		var ws2 := _scenery_seed ^ (0x9A1B + wi * 21)
		var wx := left + _hf(ws2) * width
		var wear := Color(1, 1, 1, 0.02 + _hf(ws2 + 1) * 0.02)
		draw_rect(Rect2(Vector2(wx, ground_y + 1.0), Vector2(12.0 + _hf(ws2 + 2) * 20.0, 4.0)), wear, true)
	var fc := ct.darkened(wall_outline_darken); fc.a=minf(wall_outline_darken*2.4,1.0)
	draw_line(Vector2(left,ground_y),Vector2(right,ground_y),fc,wall_outline_width,true)

func _draw_ground_city() -> void:
	var left  := _bg_left(); var right := _bg_right(); var width := right - left
	var rb := _weather_blend_current; var tod : int = _env.get("city_time",0)
	var ct: Color; var cd: Color
	match tod:
		1: ct=Color(0.20,0.17,0.13); cd=Color(0.10,0.08,0.06)
		2: ct=Color(0.12,0.12,0.14); cd=Color(0.06,0.06,0.08)
		_: ct=Color(0.26,0.26,0.28); cd=Color(0.13,0.13,0.14)
	ct=ct.lerp(Color(0.16,0.18,0.20),rb*0.45)
	draw_rect(Rect2(Vector2(left,ground_y),Vector2(width,99999.0)),cd,true)
	_draw_grad_quad(left,ground_y,width,ground_y+220.0,ct.lightened(0.04),cd)
	var sh : Color = _rain_lerp_color(_env.get("sky_horizon",background_color),"sky_horizon",rb)
	_draw_grad_quad(left,ground_y,width,ground_y+22.0,Color(sh.r,sh.g,sh.b,0.25*(1.0-rb*0.4)),Color(sh.r,sh.g,sh.b,0.0))
	var cc := ct.darkened(wall_outline_darken); cc.a=minf(wall_outline_darken*2.4,1.0)
	draw_line(Vector2(left,ground_y),Vector2(right,ground_y),cc,wall_outline_width,true)
	# ── Street markings (center lines, crosswalks) ─────────────────────────
	var sa: float = lerp(0.15 if tod==0 else 0.24, (0.15 if tod==0 else 0.24)*1.6, rb*0.5)
	var ssx: float = floor(left/150.0)*150.0
	while ssx < right:
		draw_rect(Rect2(ssx,ground_y+14.0,22.0,2.0),Color(0.55,0.52,0.22,sa),true)
		if rb>0.2: draw_rect(Rect2(ssx,ground_y+9.0,18.0,3.0),Color(0.50,0.52,0.56,rb*0.12),true)
		# Crosswalk stripe
		if int(ssx / 150.0) % 6 == 0:
			draw_rect(Rect2(ssx - 10.0, ground_y + 4.0, 6.0, 12.0), Color(0.55, 0.51, 0.28, sa * 0.5), true)
			draw_rect(Rect2(ssx + 6.0, ground_y + 4.0, 6.0, 12.0), Color(0.55, 0.51, 0.28, sa * 0.5), true)
		ssx+=150.0
	if rb>0.1: _draw_ground_puddles(left,right,rb)

func _draw_ground_sand() -> void:
	var left  := _bg_left(); var right := _bg_right(); var width := right - left
	var rb    := _weather_blend_current
	var ct := (_env.get("ground_top",  Color(0.82,0.62,0.32)) as Color).lerp(Color(0.58,0.44,0.20),rb*0.40)
	var cm := (_env.get("ground_mid",  Color(0.62,0.40,0.16)) as Color).lerp(Color(0.44,0.28,0.10),rb*0.30)
	var cd : Color = _env.get("ground_deep",Color(0.42,0.24,0.08))
	draw_rect(Rect2(Vector2(left,ground_y),Vector2(width,99999.0)),cd,true)
	_draw_grad_quad(left,ground_y,    width,ground_y+28.0, ct.lightened(0.08),ct)
	_draw_grad_quad(left,ground_y+28.0,width,ground_y+98.0, ct,cm)
	_draw_grad_quad(left,ground_y+98.0,width,ground_y+298.0,cm,cd)
	var pts:=PackedVector2Array(); var ds:=_scenery_seed^0xD4A7
	pts.append(Vector2(left,ground_y+38.0))
	for i in 91:
		var h0:=_hf(ds+(i-1)*13)*10.0; var h1:=_hf(ds+i*13)*10.0; var h2:=_hf(ds+(i+1)*13)*10.0
		pts.append(Vector2(left+float(i)*(width/90.0),ground_y-(h0*0.15+h1*0.70+h2*0.15)))
	pts.append(Vector2(right,ground_y+38.0))
	_safe_draw_polygon(pts,ct)
	# ── Sand dune ripple detail ────────────────────────────────────────────
	var sand_detail: bool = _env.get("has_sand_wind", true)
	if sand_detail and rb < 0.35:
		for ri in int(width / 200.0) + 1:
			var rs := _scenery_seed ^ (0xD4A8 + ri * 23)
			var rx := left + _hf(rs) * width
			var rw := 60.0 + _hf(rs + 1) * 120.0
			var rd := 1.5 + _hf(rs + 2) * 4.0
			var ripple_col := ct.darkened(0.06 + _hf(rs + 3) * 0.10)
			draw_line(Vector2(rx, ground_y + 6.0 + _hf(rs + 4) * 25.0),
				Vector2(rx + rw, ground_y + 6.0 + _hf(rs + 5) * 25.0),
				Color(ripple_col.r, ripple_col.g, ripple_col.b, 0.12 + _hf(rs + 6) * 0.15), rd)
	# ── Small pebble/clast detail ───────────────────────────────────────────
	for pi in int(width / 400.0) + 1:
		var ps := _scenery_seed ^ (0xE5B6 + pi * 31)
		var px := left + _hf(ps) * width
		var py := ground_y + 4.0 + _hf(ps + 1) * 12.0
		var pr := 1.0 + _hf(ps + 2) * 2.5
		draw_circle(Vector2(px, py), pr, ct.darkened(0.12 + _hf(ps + 3) * 0.15))
	var sh:Color=_rain_lerp_color(_env.get("sky_horizon",Color(0.88,0.70,0.40)),"sky_horizon",rb)
	_draw_grad_quad(left,ground_y-1.0,width,ground_y+22.0,Color(sh.r,sh.g,sh.b,0.22*(1.0-rb*0.4)),Color(sh.r,sh.g,sh.b,0.0))
	var hc:=ct.darkened(wall_outline_darken); hc.a=minf(wall_outline_darken*2.6,1.0)
	draw_line(Vector2(left,ground_y),Vector2(right,ground_y),hc,wall_outline_width,true)

func _draw_ground_ice_snow() -> void:
	var left  := _bg_left(); var right := _bg_right(); var width := right - left
	var rb    := _weather_blend_current
	var ct:=(_env.get("ground_top", Color(0.90,0.94,0.98)) as Color).lerp(Color(0.80,0.86,0.94),rb*0.35)
	var cm:Color=_env.get("ground_mid", Color(0.70,0.80,0.92))
	var cd:Color=_env.get("ground_deep",Color(0.46,0.60,0.78))
	draw_rect(Rect2(Vector2(left,ground_y),Vector2(width,99999.0)),cd,true)
	_draw_grad_quad(left,ground_y,    width,ground_y+40.0, ct.lightened(0.06),ct)
	_draw_grad_quad(left,ground_y+40.0,width,ground_y+110.0,ct,cm)
	_draw_grad_quad(left,ground_y+110.0,width,ground_y+300.0,cm,cd)
	var pts:=PackedVector2Array(); var ss2:=_scenery_seed^0xF1E2
	pts.append(Vector2(left,ground_y+50.0))
	for i in 101:
		var h0:=_hf(ss2+(i-1)*9)*14.0; var h1:=_hf(ss2+i*9)*14.0; var h2:=_hf(ss2+(i+1)*9)*14.0
		pts.append(Vector2(left+float(i)*(width/100.0),ground_y-(h0*0.2+h1*0.6+h2*0.2)))
	pts.append(Vector2(right,ground_y+50.0))
	_safe_draw_polygon(pts,ct)
	# ── Ice crack/fracture detail ──────────────────────────────────────────
	for ci in 12:
		var cs:=(_scenery_seed^0x2F3A)+ci*53
		draw_line(Vector2(left+_hf(cs)*width,ground_y+3.0+_hf(cs+3)*20.0),
				  Vector2(left+_hf(cs)*width+(_hf(cs+2)-0.5)*(40.0+_hf(cs+1)*120.0)*2.0, ground_y+3.0+_hf(cs+3)*20.0+(_hf(cs+4)-0.5)*14.0),
				  Color(0.48,0.62,0.82,0.28+_hf(cs+5)*0.18),0.8,true)
	# ── Frost crystal sparkle dots ─────────────────────────────────────────
	if rb < 0.4:
		for si in int(width / 300.0) + 1:
			var ss3 := _scenery_seed ^ (0x4F5A + si * 17)
			var sx := left + _hf(ss3) * width
			var sy := ground_y + 2.0 + _hf(ss3 + 1) * 40.0
			var sparkle := sin(_cloud_time * (1.2 + _hf(ss3 + 2) * 2.5) + float(si)) * 0.5 + 0.5
			var sr := 1.0 + _hf(ss3 + 3) * 3.0
			var sc3 := Color(0.92, 0.96, 1.0, sparkle * (0.15 + _hf(ss3 + 4) * 0.25))
			draw_circle(Vector2(sx, sy), sr, sc3)
			# Tiny cross sparkle
			if sr > 2.5:
				draw_line(Vector2(sx - sr * 1.5, sy), Vector2(sx + sr * 1.5, sy), Color(sc3.r, sc3.g, sc3.b, sc3.a * 0.3), 0.6)
				draw_line(Vector2(sx, sy - sr * 1.5), Vector2(sx, sy + sr * 1.5), Color(sc3.r, sc3.g, sc3.b, sc3.a * 0.3), 0.6)
	# ── Snow drift lines ───────────────────────────────────────────────────
	for di in int(width / 250.0) + 1:
		var ds3 := _scenery_seed ^ (0x8B9C + di * 29)
		var dx := left + _hf(ds3) * width
		var dw := 40.0 + _hf(ds3 + 1) * 100.0
		var drift_ct := ct.lightened(0.08 + _hf(ds3 + 2) * 0.14)
		draw_line(Vector2(dx, ground_y + 2.0 + _hf(ds3 + 3) * 10.0),
			Vector2(dx + dw, ground_y + 2.0 + _hf(ds3 + 4) * 8.0),
			Color(drift_ct.r, drift_ct.g, drift_ct.b, 0.18 + _hf(ds3 + 5) * 0.20), 1.5 + _hf(ds3 + 6) * 2.0)
	var sc2:Color=_env.get("ice_sheen_color",Color(0.88,0.96,1.00))
	_draw_grad_quad(left,ground_y-2.0,width,ground_y+8.0,Color(sc2.r,sc2.g,sc2.b,0.22),Color(sc2.r,sc2.g,sc2.b,0.0))
	var sh:Color=_rain_lerp_color(_env.get("sky_horizon",Color(0.70,0.88,0.98)),"sky_horizon",rb)
	_draw_grad_quad(left,ground_y-1.0,width,ground_y+18.0,Color(sh.r,sh.g,sh.b,0.20*(1.0-rb*0.4)),Color(sh.r,sh.g,sh.b,0.0))
	var hc:=ct.darkened(wall_outline_darken+0.05); hc.a=minf(wall_outline_darken*2.4,1.0)
	draw_line(Vector2(left,ground_y),Vector2(right,ground_y),hc,wall_outline_width,true)

func _draw_ground_water() -> void:
	var left  := _bg_left(); var right := _bg_right(); var width := right - left
	draw_rect(Rect2(Vector2(left,ground_y),Vector2(width,99999.0)),Color(0.01,0.06,0.16),true)
	for di in 10:
		var t:=float(di)/9.0
		draw_rect(Rect2(Vector2(left,ground_y+di*144.0),Vector2(width,145.0)),
				  Color(lerp(0.06,0.01,t),lerp(0.32,0.04,t),lerp(0.62,0.10,t)),true)
	for ci in 5:
		var cs:=(_scenery_seed^0x3C00)+ci*17
		var cx:=left+_hf(cs)*width; var cw:=30.0+_hf(cs+2)*60.0; var cdep:=200.0+_hf(cs+3)*300.0
		var pts:=PackedVector2Array([Vector2(cx-cw*0.5,ground_y),Vector2(cx+cw*0.5,ground_y),Vector2(cx+cw*0.8,ground_y+cdep),Vector2(cx-cw*0.8,ground_y+cdep)])
		_safe_draw_polygon(pts,Color(0.30,0.65,0.90,0.04+_hf(cs+1)*0.04))

# ─────────────────────────────────────────────────────────────────────────────
# WATER SURFACE + SPLASHES
# ─────────────────────────────────────────────────────────────────────────────

func _draw_water_surface() -> void:
	if not wall_valid: return
	var bl:=_bg_left(); var br:=_bg_right(); var width:=br-bl
	var t:=_water_time
	for di in 5:
		var t0:=float(di)/5.0; var t1:=float(di+1)/5.0
		_draw_grad_quad(bl,ground_y+t0*160.0,width,ground_y+t1*160.0,Color(0.02,0.22,0.50,lerp(0.55,0.0,t0)),Color(0.01,0.10,0.28,lerp(0.55,0.0,t1)))
	for ci in 6:
		var cs:=(_scenery_seed^0x4C00)+ci*29
		var phase:=t*(0.7+_hf(cs+3)*0.8)+_hf(cs+4)*TAU
		_draw_oval(bl+_hf(cs)*width+sin(t*(0.3+_hf(cs+5)*0.4)+float(ci))*20.0,
				   ground_y+18.0+_hf(cs+2)*80.0,35.0+_hf(cs+1)*80.0,
				   (35.0+_hf(cs+1)*80.0)*0.3,Color(0.4,0.75,1.0,maxf(0.0,0.04+0.04*sin(phase))))
	var segs:=35; var step:=width/float(segs)  # reduced for performance
	for wi in 4:
		var freq:=0.008+wi*0.003; var speed:=0.55+wi*0.30; var amp:=11.0-wi*2.2
		var ph:=t*speed+wi*1.3
		var wcol: Color = [Color(0.04,0.24,0.52,0.80),Color(0.06,0.30,0.60,0.86),Color(0.10,0.38,0.68,0.90),Color(0.14,0.46,0.72,0.94)][wi]
		var pts:=PackedVector2Array(); pts.append(Vector2(bl,ground_y+300.0))
		for si in segs+1:
			var x:=bl+si*step
			pts.append(Vector2(x,ground_y-2.0+wi*3.0-sin(x*freq+ph)*amp-sin(x*freq*1.618+ph*0.7)*amp*0.38-sin(x*freq*3.14+ph*1.3)*amp*0.14))
		pts.append(Vector2(br,ground_y+300.0))
		_safe_draw_polygon(pts,wcol)
	for si in 80:
		var sx:=bl+si*(width/80.0); var sy:=ground_y-sin(sx*0.011+t*0.9)*9.0-sin(sx*0.019+t*0.55)*3.5
		var sa:=maxf(0.0,sin(sx*0.011+t*0.9))*0.50
		if sa>0.06: draw_circle(Vector2(sx,sy),3.0+sin(float(si)*2.1)*1.4,Color(0.92,0.97,1.0,sa))
	for fi in 70:
		var fx:=bl+fi*(width/70.0); var fy:=ground_y-sin(fx*0.011+t*0.95)*9.5-sin(fx*0.018+t*0.6)*4.0-1.0
		var fa:=maxf(0.0,sin(fx*0.011+t*0.95))*0.38
		if fa>0.05: draw_circle(Vector2(fx,fy),4.0+sin(float(fi)*2.3)*2.0,Color(1.0,1.0,1.0,fa))

func _draw_splashes() -> void:
	for s in _splashes:
		var ring_r: float = s["ring_radius"]
		if ring_r < 250.0:
			var last_pt:=Vector2.ZERO
			for ri in 25:
				var angle:=(float(ri)/25.0)*TAU
				var pt:=Vector2(s["pos"].x+cos(angle)*ring_r, s["pos"].y+sin(angle)*ring_r*0.35)
				if ri>0: draw_line(last_pt,pt,Color(0.7,0.88,1.0,(1.0-ring_r/250.0)*0.50),1.2,true)
				last_pt=pt
		for d in s["droplets"]:
			if d["life"]<=0.0: continue
			var lf: float = d["life"]/d["max_life"]; var alpha: float = lf*0.80; var dp:=Vector2(d["x"],d["y"])
			var spd:=Vector2(d["vx"],d["vy"]).length()
			if spd>80.0:
				draw_line(dp, dp-Vector2(d["vx"],d["vy"]).normalized()*min(spd*0.04,12.0), Color(0.7,0.88,1.0,alpha*0.45),1.1,true)
			draw_circle(dp, d["size"]*lf, Color(0.82,0.94,1.0,alpha))
			if d["size"]>3.0: draw_circle(dp, d["size"]*lf*0.4, Color(1.0,1.0,1.0,alpha*0.65))

func check_water_collision(player_pos: Vector2, player_velocity: Vector2) -> Dictionary:
	if not _env.get("has_water",false) or not wall_valid or ground_y == 0.0:
		return {"in_water":false,"depth":0.0,"surface_y":0.0,"drag":Vector2(1,1),"buoyancy":0.0}
	var t:=_water_time
	var sy:=ground_y-sin(player_pos.x*0.011+t*0.95)*9.5-sin(player_pos.x*0.018+t*0.6)*4.0
	var depth:=maxf(0.0,player_pos.y-sy)
	if player_pos.y > sy:
		var dn:=clampf(depth/280.0,0.0,1.0)
		var sd:=clampf(1.0-player_velocity.length()*0.0003,0.55,1.0)
		if not _player_in_water:
			_player_in_water=true; spawn_splash(Vector2(player_pos.x,sy),player_velocity.y)
			emit_signal("player_entered_water",depth)
		return {"in_water":true,"depth":depth,"surface_y":sy,"drag":Vector2(lerp(0.82,0.62,dn)*sd,lerp(0.78,0.55,dn)*sd),"buoyancy":lerp(0.0,380.0,dn)}
	else:
		if _player_in_water: _player_in_water=false; emit_signal("player_exited_water")
		return {"in_water":false,"depth":0.0,"surface_y":sy,"drag":Vector2(1,1),"buoyancy":0.0}

func _draw_underwater_wall_depth() -> void:
	if not wall_valid: return
	var base_l:=Vector2(wall_min.x,ground_y); var base_r:=Vector2(wall_max.x,ground_y)
	if use_polygon_mode and ground_left_index>=0 and ground_right_index>=0:
		base_l=control_points[ground_left_index]; base_r=control_points[ground_right_index]
	var sub_top:=ground_y; var sub_bot:=(base_l.y+base_r.y)*0.5
	if sub_bot>sub_top:
		var wt:=Color(0.04,0.28,0.60); var sh:=sub_bot-sub_top
		for li in 10:
			var t0:=float(li)/10.0; var t1:=float(li+1)/10.0; var shim:=sin(_water_time*1.4+t0*8.0)*0.016
			_draw_grad_quad(base_l.x,sub_top+t0*sh,base_r.x-base_l.x,sub_top+t1*sh,
				Color(wt.r,wt.g+shim,wt.b,lerp(0.04,0.48,t0)),Color(wt.r,wt.g,wt.b,lerp(0.04,0.48,t1)))
	var ev:=base_r-base_l; var el:=ev.length()
	if el<1.0: return
	var ed:=ev/el; var perp:=Vector2(-ed.y,ed.x)
	if perp.y<0.0: perp=-perp
	var segs:=32; var bot_pts:Array[Vector2]=[]
	for si in segs+1:
		var rs:=(_scenery_seed^0xB0B0)+si*19
		bot_pts.append(base_l.lerp(base_r,float(si)/float(segs))+perp*(_env.get("has_water",false)*600.0*(0.75+_hf(rs)*0.50))+ed*(_hf(rs+1)-0.5)*18.0)
	var rtop:=Color(0.22,0.28,0.30); var rdeep:=Color(0.04,0.06,0.08); var wc:=Color(0.03,0.18,0.45)
	for pi in segs:
		var f0:=float(pi)/float(segs); var f1:=float(pi+1)/float(segs)
		var top0:=base_l.lerp(base_r,f0); var top1:=base_l.lerp(base_r,f1)
		var bot0:=bot_pts[pi]; var bot1:=bot_pts[pi+1]
		for si in 12:
			var t0:=float(si)/12.0; var t1:=float(si+1)/12.0
			var c0:=rtop.lerp(rdeep,t0); var c1:=rtop.lerp(rdeep,t1)
			var tl2:=top0.lerp(bot0,t0); var tr2:=top1.lerp(bot1,t0)
			var br2:=top1.lerp(bot1,t1); var bl2:=top0.lerp(bot0,t1)
			draw_polygon(PackedVector2Array([tl2,tr2,br2]),PackedColorArray([c0,c0,c1]))
			draw_polygon(PackedVector2Array([tl2,br2,bl2]),PackedColorArray([c0,c1,c1]))
			draw_polygon(PackedVector2Array([tl2,tr2,br2]),PackedColorArray([Color(wc,lerp(0.08,0.55,t0)),Color(wc,lerp(0.08,0.55,t0)),Color(wc,lerp(0.08,0.55,t1))]))
			draw_polygon(PackedVector2Array([tl2,br2,bl2]),PackedColorArray([Color(wc,lerp(0.08,0.55,t0)),Color(wc,lerp(0.08,0.55,t1)),Color(wc,lerp(0.08,0.55,t1))]))

# ─────────────────────────────────────────────────────────────────────────────
# WALL TEXTURE & GRANITE
# ─────────────────────────────────────────────────────────────────────────────

func draw_textured_wall(start_pos: Vector2, size: Vector2) -> void:
	var tile:=128.0; var cols:=int(ceil(size.x/tile))+1; var rows:=int(ceil(size.y/tile))+1
	var gx: float = floor(start_pos.x/tile)*tile; var gy: float = floor(start_pos.y/tile)*tile
	for x in cols:
		for y in rows:
			var ts:=int(gx/tile+x)+int(gy/tile+y)*1000
			var v:=(_hf(ts)-0.5)*texture_variation
			var cl:=Rect2(Vector2(gx+x*tile,gy+y*tile),Vector2(tile,tile)).intersection(Rect2(wall_min,wall_max-wall_min))
			if cl.has_area():
				draw_rect(cl,Color(current_wall_color.r+v,current_wall_color.g+v,current_wall_color.b+v,current_wall_color.a))

func draw_bolt_holes(_start_pos: Vector2, _end_pos: Vector2) -> void: pass
func draw_bolt_holes_on_polygon() -> void: pass

func draw_granite_texture() -> void:
	## Draws granite wall texture. Uses a cached ImageTexture so the noise
	## pattern is rendered once and blitted each frame instead of drawing
	## dozens of individual lines.
	if not wall_valid: return
	var ws := wall_max - wall_min
	var tw := int(ceil(ws.x))
	var th := int(ceil(ws.y))
	if tw < 4 or th < 4: return

	# Rebuild cache if size changed or flagged dirty
	if _granite_cache == null or _granite_cache.get_width() != tw or \
	   _granite_cache.get_height() != th or _granite_cache_dirty:
		_build_granite_cache(tw, th)

	if _granite_cache:
		draw_texture_rect(_granite_cache, Rect2(wall_min, ws), false)

func _build_granite_cache(tw: int, th: int) -> void:
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	var rs := int(wall_min.x + wall_min.y)
	var base := current_wall_color
	var line_count := maxi(tw / 200 + 2, 3)

	for i in line_count:
		var frac := float(i) / float(line_count - 1)
		var xp := wall_min.x + frac * (wall_max.x - wall_min.x) + (hash(rs + i) % 50 - 25)
		var lx := int(round(xp - wall_min.x))
		if lx < 0 or lx >= tw:
			continue
		# Draw a subtle vertical crack line across the full height
		for py in th:
			var bright := 0.45 + (hash(rs + i + py) % 50) / 200.0 * 0.3
			# Get existing pixel or base color
			var existing := img.get_pixel(lx, py) if img.get_pixel(lx, py).a > 0 else base
			var line_col := Color(bright - 0.1, bright - 0.12, bright - 0.15, 0.22)
			# Blend line with existing
			var blended := existing.lerp(line_col, line_col.a)
			img.set_pixel(lx, py, Color(blended.r, blended.g, blended.b, 1.0))

	# Also add subtle noise across the whole texture
	for px in tw:
		for py in range(0, th, 3):
			var noise_val := (hash(rs + px * 31 + py * 7) % 40) / 200.0 - 0.1
			if abs(noise_val) > 0.04:
				var existing := img.get_pixel(px, py) if img.get_pixel(px, py).a > 0 else base
				var noise_col := Color(
					clampf(existing.r + noise_val, 0.0, 1.0),
					clampf(existing.g + noise_val, 0.0, 1.0),
					clampf(existing.b + noise_val, 0.0, 1.0),
					1.0)
				img.set_pixel(px, py, noise_col)

	_granite_cache = ImageTexture.create_from_image(img)
	_granite_cache_dirty = false

func _point_in_polygon(point: Vector2) -> bool:
	var inside:=false; var j:=control_points.size()-1
	for i in control_points.size():
		var pi:=control_points[i]; var pj:=control_points[j]
		if ((pi.y>point.y)!=(pj.y>point.y)) and (point.x<(pj.x-pi.x)*(point.y-pi.y)/(pj.y-pi.y)+pi.x):
			inside=not inside
		j=i
	return inside

# ─────────────────────────────────────────────────────────────────────────────
# EDITOR OVERLAYS
# ─────────────────────────────────────────────────────────────────────────────

func _draw_edge_highlights() -> void:
	if hovered_edge<0 or control_points.size()<2: return
	if _is_ground_edge(hovered_edge): return
	var p1:=control_points[hovered_edge]; var p2:=control_points[(hovered_edge+1)%control_points.size()]
	var color:=Color(0.6,0.9,1.0,0.8)
	var lt:="RIGHT-CLICK: Add point | SHIFT+RIGHT-CLICK: Mark as TOP-OUT"
	if hovered_edge in top_edge_indices: color=Color(1.0,0.5,0.0,0.9); lt="MARKED AS TOP-OUT | SHIFT+RIGHT-CLICK: Unmark"
	draw_line(p1,p2,color,6.0,true)
	var mp:=get_global_mouse_position(); var seg:=p2-p1; var slsq:=seg.length_squared()
	if slsq>0:
		var np:=p1+clampf((mp-p1).dot(seg)/slsq,0.0,1.0)*seg; draw_circle(np,6.0,color)
		var lp:=np+Vector2(0,-30); var ls:=ThemeDB.fallback_font.get_string_size(lt,HORIZONTAL_ALIGNMENT_CENTER,-1,14)
		draw_rect(Rect2(lp-Vector2(ls.x/2+8,8),ls+Vector2(16,16)),Color(0,0,0,0.85),true)
		draw_string(ThemeDB.fallback_font,lp,lt,HORIZONTAL_ALIGNMENT_CENTER,-1,14,color)

func _draw_control_points() -> void:
	for i in control_points.size():
		var pt:=control_points[i]; var color: Color = point_color
		if i==ground_left_index or i==ground_right_index: color=ground_point_color
		elif edit_mode:
			if dragging_point==i: color=point_drag_color
			elif hovered_point==i: color=point_hover_color
		draw_circle(pt,POINT_RADIUS+3,Color(0,0,0,0.4)); draw_circle(pt,POINT_RADIUS,color)
		draw_string(ThemeDB.fallback_font,pt+Vector2(-5,6),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	if edit_mode and control_points.size()>0:
		var mk:="" if top_edge_indices.is_empty() else " | MARKED: "+str(top_edge_indices)
		var text:="LEFT-DRAG: Move | RIGHT-CLICK: Add | SHIFT+RIGHT-CLICK on EDGE: Mark Top"+mk
		var pos:=Vector2(wall_min.x,wall_min.y-40)
		var sz:=ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16)
		draw_rect(Rect2(pos-Vector2(8,22),sz+Vector2(16,30)),Color(0,0,0,0.8),true)
		draw_string(ThemeDB.fallback_font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(1,1,0.6))

# ─────────────────────────────────────────────────────────────────────────────
# BOUNDS & POLYGON MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

func calculate_bounds_from_holds(holds_container: Node2D) -> void:
	if not holds_container or holds_container.get_child_count()==0:
		wall_valid=false; _granite_cache_dirty=true; queue_redraw(); return
	var mn_x:=INF; var mx_x:=-INF; var mn_y:=INF; var mx_y:=-INF
	for hold in holds_container.get_children():
		if not hold is Node2D: continue
		mn_x=min(mn_x,hold.global_position.x); mx_x=max(mx_x,hold.global_position.x)
		mn_y=min(mn_y,hold.global_position.y); mx_y=max(mx_y,hold.global_position.y)
	wall_min=Vector2(mn_x-WALL_PADDING_SIDES, mn_y-WALL_PADDING_TOP)
	wall_max=Vector2(mx_x+WALL_PADDING_SIDES, mx_y+WALL_PADDING_BOTTOM)
	wall_valid=true; ground_y=wall_max.y; _granite_cache_dirty=true
	if control_points.is_empty():
		control_points=[wall_min,Vector2(wall_max.x,wall_min.y),wall_max,Vector2(wall_min.x,wall_max.y)]
		ground_left_index=3; ground_right_index=2; use_polygon_mode=true
	else:
		if ground_left_index>=0  and ground_left_index<control_points.size():  control_points[ground_left_index].y=ground_y
		if ground_right_index>=0 and ground_right_index<control_points.size(): control_points[ground_right_index].y=ground_y
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	if weather_modifier: weather_modifier._wall_ref=self
	_init_clouds(); queue_redraw()

func _update_bounds_from_polygon() -> void:
	if control_points.is_empty(): return
	var mn_x:=INF; var mx_x:=-INF; var mn_y:=INF; var mx_y:=-INF
	for p in control_points:
		mn_x=min(mn_x,p.x); mx_x=max(mx_x,p.x); mn_y=min(mn_y,p.y); mx_y=max(mx_y,p.y)
	wall_min=Vector2(mn_x,mn_y); wall_max=Vector2(mx_x,mx_y); wall_valid=true; _granite_cache_dirty=true

func add_point_between_nearest_edge(pos: Vector2) -> void:
	if control_points.size()<2: control_points.append(pos); _update_bounds_from_polygon(); queue_redraw(); return
	var nei:=-1; var ned:=INF
	for i in control_points.size():
		if _is_ground_edge(i): continue
		var d: float = _point_to_segment_distance(pos,control_points[i],control_points[(i+1)%control_points.size()])
		if d<ned: ned=d; nei=i
	if nei<0: return
	control_points.insert(nei+1, pos)
	if ground_left_index>=nei+1:  ground_left_index+=1
	if ground_right_index>=nei+1: ground_right_index+=1
	var ute:Array[int]=[]
	for ei in top_edge_indices: ute.append(ei+1 if ei>=nei else ei)
	top_edge_indices=ute
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	queue_redraw()

func remove_point(index: int) -> void:
	if index==ground_left_index or index==ground_right_index: push_warning("Cannot remove ground points"); return
	if control_points.size()<=4: push_warning("Need at least 4 points"); return
	if index<0 or index>=control_points.size(): return
	control_points.remove_at(index)
	if ground_left_index>index:  ground_left_index-=1
	if ground_right_index>index: ground_right_index-=1
	if dragging_point==index:    dragging_point=-1
	elif dragging_point>index:   dragging_point-=1
	if hovered_point==index:     hovered_point=-1
	elif hovered_point>index:    hovered_point-=1
	var ute:Array[int]=[]
	for ei in top_edge_indices:
		if ei==index: continue
		ute.append(ei-1 if ei>index else ei)
	top_edge_indices=ute
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	queue_redraw()

func enable_polygon_mode(enabled: bool=true) -> void:
	use_polygon_mode=enabled
	if enabled and control_points.is_empty() and wall_valid:
		control_points=[wall_min,Vector2(wall_max.x,wall_min.y),wall_max,Vector2(wall_min.x,wall_max.y)]
		ground_left_index=3; ground_right_index=2; ground_y=wall_max.y
	queue_redraw()

func enable_edit_mode(enabled: bool=true) -> void:
	edit_mode=enabled
	if not enabled: dragging_point=-1; hovered_point=-1; hovered_edge=-1
	queue_redraw()

func reset_polygon() -> void:
	use_polygon_mode=false; edit_mode=false; control_points.clear(); top_edge_indices.clear()
	ground_left_index=-1; ground_right_index=-1; dragging_point=-1; hovered_point=-1; hovered_edge=-1
	for child in get_children():
		if child.has_meta("is_top_edge_hold"): child.queue_free()
	queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
# TOP EDGE HOLDS
# ─────────────────────────────────────────────────────────────────────────────

func _create_top_edge_holds() -> void:
	for child in get_children():
		if child.has_meta("is_top_edge_hold"): child.set_script(null); child.free()
	if not use_polygon_mode or top_edge_indices.is_empty(): return
	for edge_idx in top_edge_indices:
		if edge_idx>=control_points.size(): continue
		var p1:=control_points[edge_idx]; var p2:=control_points[(edge_idx+1)%control_points.size()]
		_create_top_hold_at((p1+p2)/2.0, p1.distance_to(p2))

func _create_top_hold_at(hold_position: Vector2, width: float) -> void:
	var top_hold:=_TopEdgeHold.new()
	top_hold.set_meta("is_top_edge_hold",true)
	top_hold.collision_layer=2; top_hold.collision_mask=0
	top_hold.monitoring=false; top_hold.monitorable=true; top_hold.name="TopEdgeHold"
	var shape:=RectangleShape2D.new(); shape.size=Vector2(width,50)
	var col:=CollisionShape2D.new(); col.shape=shape; top_hold.add_child(col)
	var hp:=Marker2D.new(); hp.name="HoldPoint"; hp.position=Vector2.ZERO; top_hold.add_child(hp)
	top_hold.global_position=hold_position; add_child(top_hold); top_hold.add_to_group("holds")

class _TopEdgeHold extends Area2D:
	var claimed_left_hand:  Node2D = null
	var claimed_right_hand: Node2D = null
	var left_hand_x:  float = 0.0
	var right_hand_x: float = 0.0
	func is_start_hold() -> bool: return false
	func is_top_out()    -> bool: return true
	func is_crimp()      -> bool: return false
	func is_sloper()     -> bool: return false
	func is_pocket()     -> bool: return false
	func is_foothold()   -> bool: return false
	func can_grab(_limb: Node2D, is_foot: bool) -> bool: return not is_foot
	func try_claim(limb: Node2D, is_foot: bool, snap_pos: Vector2) -> bool:
		if not can_grab(limb,is_foot): return false
		if limb.name=="LeftHand":  claimed_left_hand=limb;  left_hand_x=snap_pos.x
		elif limb.name=="RightHand": claimed_right_hand=limb; right_hand_x=snap_pos.x
		return true
	func release(limb: Node2D) -> void:
		if limb.name=="LeftHand"   and claimed_left_hand==limb:   claimed_left_hand=null;  left_hand_x=0.0
		elif limb.name=="RightHand" and claimed_right_hand==limb: claimed_right_hand=null; right_hand_x=0.0
	func get_limb_anchor(limb: Node2D) -> Vector2:
		var x:=left_hand_x if (limb.name=="LeftHand" and claimed_left_hand==limb) else right_hand_x if (limb.name=="RightHand" and claimed_right_hand==limb) else limb.global_position.x
		return Vector2(x, global_position.y)
	func get_state_pressure(delta: float, _bo: float, _st: float, _fs: float, _limb: Node2D) -> float: return 0.5*delta
	func get_recovery_rate(delta: float, body_balance: float, _fs: float) -> float: return 3.0*delta*body_balance

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

func get_bounds() -> Dictionary:
	return {"min":wall_min,"max":wall_max,"valid":wall_valid}

func get_top_edge_y() -> float:
	if use_polygon_mode and not top_edge_indices.is_empty():
		var ty:=INF
		for ei in top_edge_indices:
			if ei>=control_points.size(): continue
			ty=min(ty,min(control_points[ei].y,control_points[(ei+1)%control_points.size()].y))
		return ty if ty!=INF else wall_min.y
	return wall_min.y

func get_wall_height() -> float: return ground_y-get_top_edge_y()
func get_wall_width()  -> float: return wall_max.x-wall_min.x

func get_anchor_position_for_x(world_x: float) -> Vector2:
	if use_polygon_mode and control_points.size()>=3:
		var edges = top_edge_indices.duplicate() if not top_edge_indices.is_empty() else []
		if edges.is_empty():
			for i in control_points.size():
				if not _is_ground_edge(i): edges.append(i)
		var best:=Vector2.ZERO; var best_s:=INF
		for ei in edges:
			if ei>=control_points.size(): continue
			var p1:=control_points[ei]; var p2:=control_points[(ei+1)%control_points.size()]
			if absf(p2.x-p1.x)<1.0: continue
			var t:=clampf((world_x-p1.x)/(p2.x-p1.x),0.0,1.0)
			var on:=p1.lerp(p2,t); var score:=on.y+absf(world_x-clampf(world_x,min(p1.x,p2.x),max(p1.x,p2.x)))*0.5
			if score<best_s: best_s=score; best=on
		if best_s<INF: return best
	return Vector2(clampf(world_x,wall_min.x,wall_max.x),wall_min.y)

func get_polygon_data() -> Dictionary:
	if not use_polygon_mode or control_points.is_empty(): return {}
	return {"enabled":true,"points":control_points.map(func(p): return {"x":p.x,"y":p.y}),
			"ground_left_index":ground_left_index,"ground_right_index":ground_right_index,
			"top_edge_indices":top_edge_indices.duplicate()}

func set_polygon_data(data: Dictionary) -> void:
	if not data or data.is_empty() or not data.get("enabled",false): return
	use_polygon_mode=true; control_points.clear()
	for pd in data.get("points",[]): control_points.append(Vector2(pd.get("x",0),pd.get("y",0)))
	if control_points.size()<3: push_warning("DynamicWall.set_polygon_data: fewer than 3 points"); control_points.clear(); use_polygon_mode=false; return
	ground_left_index=data.get("ground_left_index",-1); ground_right_index=data.get("ground_right_index",-1)
	top_edge_indices.clear()
	for ei in data.get("top_edge_indices",[]): if ei is float or ei is int: top_edge_indices.append(int(ei))
	if ground_left_index>=0 and ground_left_index<control_points.size(): ground_y=control_points[ground_left_index].y
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	if weather_modifier: weather_modifier._wall_ref=self
	_granite_cache_dirty=true; _init_clouds(); queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
# DRAW PRIMITIVES
# ─────────────────────────────────────────────────────────────────────────────

func _draw_grad_quad(x: float, y0: float, w: float, y1: float, c_top: Color, c_bot: Color) -> void:
	if w<0.5 or absf(y1-y0)<0.5: return
	var tl:=Vector2(x,y0); var tr_:=Vector2(x+w,y0); var br:=Vector2(x+w,y1); var bl:=Vector2(x,y1)
	draw_polygon(PackedVector2Array([tl,tr_,br]),PackedColorArray([c_top,c_top,c_bot]))
	draw_polygon(PackedVector2Array([tl,br,bl]),PackedColorArray([c_top,c_bot,c_bot]))

func _draw_grad_quad_h(x0: float, y0: float, x1: float, y1: float, c_left: Color, c_right: Color) -> void:
	if absf(x1-x0)<0.5 or absf(y1-y0)<0.5: return
	var tl:=Vector2(x0,y0); var tr_:=Vector2(x1,y0); var br:=Vector2(x1,y1); var bl:=Vector2(x0,y1)
	draw_polygon(PackedVector2Array([tl,tr_,br]),PackedColorArray([c_left,c_right,c_right]))
	draw_polygon(PackedVector2Array([tl,br,bl]),PackedColorArray([c_left,c_right,c_left]))

func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t: float = clampf(ap.dot(ab) / max(ab.length_squared(), 1e-10), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _polygon_valid(pts: PackedVector2Array) -> bool:
	## Robust polygon validation — checks size, collinearity, duplicate points,
	## and self-intersection so Godot's triangulator never receives bad data.
	if pts.size() < 3: return false

	# Remove consecutive duplicates (they confuse triangulation)
	var cleaned := PackedVector2Array()
	cleaned.append(pts[0])
	for i in range(1, pts.size()):
		if pts[i].distance_squared_to(pts[i-1]) > 0.01:
			cleaned.append(pts[i])
	if cleaned.size() < 3: return false

	# Check all points are not collinear (need at least one non-zero cross)
	var found_area := false
	for i in cleaned.size():
		if abs((cleaned[(i+1)%cleaned.size()]-cleaned[i]).cross(
			   cleaned[(i+2)%cleaned.size()]-cleaned[i])) > 0.01:
			found_area = true
			break
	if not found_area: return false

	# Quick exclusion test: reject extreme aspect-ratio slivers (width/height > 50)
	var min_x := INF; var max_x := -INF
	var min_y := INF; var max_y := -INF
	for p in cleaned:
		if p.x < min_x: min_x = p.x
		if p.x > max_x: max_x = p.x
		if p.y < min_y: min_y = p.y
		if p.y > max_y: max_y = p.y
	var span_x := max_x - min_x; var span_y := max_y - min_y
	if min(span_x, span_y) < 0.5: return false  # zero-width
	if max(span_x, span_y) / max(min(span_x, span_y), 0.5) > 50.0: return false  # sliver

	# Quick self-intersection test (O(n²) but n is small — typically < 100 pts)
	for i in cleaned.size():
		var a1 := cleaned[i]
		var b1 := cleaned[(i + 1) % cleaned.size()]
		for j in range(i + 2, cleaned.size()):
			if j == 0 or (j + 1) % cleaned.size() == i: continue
			var a2 := cleaned[j]
			var b2 := cleaned[(j + 1) % cleaned.size()]
			if _segments_intersect(a1, b1, a2, b2):
				return false
	return true

func _safe_draw_polygon(pts: PackedVector2Array, color: Color) -> void:
	## Safely draws a colored polygon — validates first so Godot's
	## triangulator never receives degenerate data.
	if not _polygon_valid(pts): return
	draw_colored_polygon(pts, color)

func _safe_draw_vertex_polygon(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	## Safely draws a vertex-colored polygon.
	if not _polygon_valid(pts): return
	draw_polygon(pts, cols)

func _segments_intersect(a1: Vector2, b1: Vector2, a2: Vector2, b2: Vector2) -> bool:
	## Returns true if two 2D line segments intersect (excluding shared endpoints).
	var d1 := b1 - a1; var d2 := b2 - a2
	var rxs := d1.cross(d2)
	if abs(rxs) < 1e-8: return false  # parallel
	var t := (a2 - a1).cross(d2) / rxs
	var u := (a2 - a1).cross(d1) / rxs
	return t >= 1e-6 and t <= 1.0 - 1e-6 and u >= 1e-6 and u <= 1.0 - 1e-6

func _hf(v: int) -> float:
	return float(hash(v)%10000)/10000.0
