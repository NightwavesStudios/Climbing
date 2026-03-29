extends Node2D
class_name DynamicWall

var _is_ready: bool = false

var wall_texture_enabled = true
var texture_variation = 0.03

var hole_spacing = Vector2(64, 64)
var hole_radius = 2.5
var hole_color = Color(0.15, 0.15, 0.15)
var hole_jitter = 4.0

var wall_min = Vector2.ZERO
var wall_max = Vector2.ZERO
var wall_valid = false

const WALL_PADDING_TOP = 100.0
const WALL_PADDING_BOTTOM = 150.0
const WALL_PADDING_SIDES = 100.0
const BACKGROUND_EXPANSION = 2000.0

@export var use_polygon_mode: bool = false
@export var edit_mode: bool = false

# =============================================================================
#  OUTLINE EXPORTS  (wall + ground tonal outlines)
# =============================================================================
@export_group("Outline")
## Width of the tonal outline stroke on the wall edges and ground horizon lines (px).
@export var wall_outline_width: float = 5.5
## How much darker the outline is versus the surface color it borders.
@export_range(0.0, 1.0, 0.01) var wall_outline_darken: float = 0.25
@export_group("")

var control_points: Array[Vector2] = []

var ground_y: float = 0.0
var ground_left_index: int = -1
var ground_right_index: int = -1
var top_edge_indices: Array[int] = []

var point_color = Color(0.7, 0.7, 0.7, 0.6)
var point_hover_color = Color(1, 0.7, 0, 1.0)
var point_drag_color = Color(1, 1, 0, 1.0)
var ground_point_color = Color(0.3, 0.8, 0.3, 0.8)
var line_color = Color(0.4, 0.7, 1.0, 0.6)
var edge_hover_color = Color(0.6, 0.9, 1.0, 0.8)
var top_edge_color = Color(0.9, 0.4, 0.2)

const POINT_RADIUS = 10.0
const POINT_GRAB_RADIUS = 20.0
const EDGE_CLICK_DISTANCE = 15.0

var hovered_point: int = -1
var dragging_point: int = -1
var drag_offset: Vector2 = Vector2.ZERO
var hovered_edge: int = -1

var current_wall_color: Color = Color(0.82, 0.75, 0.62)
var background_color: Color = Color(0.53, 0.81, 0.92)
var show_bolt_holes: bool = false
var is_granite: bool = false
var current_environment: String = "gym"
var is_in_editor: bool = false

var ground_enabled = true
var ground_height = 1000.0
var ground_color = Color(0.298, 0.298, 0.298, 1.0)

var _clouds: Array[Dictionary] = []
var _cloud_time: float = 0.0
const CLOUD_COUNT = 22
const CLOUD_LAYERS = 3

var _env: Dictionary = {}
var _scenery_seed: int = 0

var _water_time: float = 0.0
var _player_in_water: bool = false
signal player_entered_water(depth: float)
signal player_exited_water

var _splashes: Array[Dictionary] = []
const SPLASH_DURATION = 1.4
const SPLASH_DROPLET_COUNT = 22

var weather_modifier: Node2D = null

func _ready() -> void:
	print("DynamicWall _ready START")
	z_index = -10
	add_to_group("environment_walls")
	_scenery_seed = randi()
	_init_clouds()
	_init_weather()
	_is_ready = true  # ← SET THIS BEFORE the await
	await _wait_for_env_config()
	update_environment_settings()
	print("DynamicWall _ready COMPLETE — wall_valid: ", wall_valid)

var _redraw_timer: float = 0.0
const REDRAW_INTERVAL = 0.05

func _process(delta: float):
	_redraw_timer += delta
	if _redraw_timer < REDRAW_INTERVAL:
		return
	_redraw_timer = 0.0

	var rain_blend = _get_weather_blend()
	var has_animation = _env.get("has_stars", false) \
		or (_env.get("cloud_color", Color(1,1,1)).a > 0.02) \
		or _env.get("has_gym_interior", false) \
		or _env.get("has_water", false) \
		or _env.get("has_city", false) \
		or rain_blend > 0.01 \
		or _splashes.size() > 0
	if has_animation:
		_cloud_time += REDRAW_INTERVAL
		_water_time += REDRAW_INTERVAL
		_update_clouds(REDRAW_INTERVAL)
		_update_splashes(REDRAW_INTERVAL)
		queue_redraw()

# ─── Weather public API ───────────────────────────────────────────────────────

func _init_weather() -> void:
	weather_modifier = get_node_or_null("WeatherModifier")
	if weather_modifier == null:
		var script = load("res://scripts/levels/weather_modifier.gd")
		if script:
			weather_modifier = script.new()
			weather_modifier.name = "WeatherModifier"
			add_child(weather_modifier)
		else:
			push_warning("DynamicWall: could not load res://scripts/levels/weather_modifier.gd — weather disabled")

func set_weather(weather_type: int, intensity: float = 1.0) -> void:
	if weather_modifier:
		weather_modifier.intensity = clamp(intensity, 0.0, 1.0)
		weather_modifier.weather   = weather_type

func get_weather() -> int:
	return weather_modifier.weather if weather_modifier else 0

func get_weather_modifier() -> Node2D:
	return weather_modifier

func _get_weather_blend() -> float:
	if weather_modifier and weather_modifier.has_method("get_blend"):
		return weather_modifier.get_blend()
	return 0.0

func _get_rain_override() -> Dictionary:
	if weather_modifier and weather_modifier.has_method("get_rain_sky_override"):
		return weather_modifier.get_rain_sky_override()
	return {}

func _rain_lerp_color(base: Color, key: String, blend: float) -> Color:
	var ov = _get_rain_override()
	if ov.is_empty() or not key in ov or blend < 0.01:
		return base
	return base.lerp(ov[key], blend)

# ─── Cloud system ─────────────────────────────────────────────────────────────

func _init_clouds():
	_clouds.clear()
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(CLOUD_COUNT):
		_clouds.append(_make_cloud(rng, true))

func _make_cloud(rng: RandomNumberGenerator, initial_spread: bool) -> Dictionary:
	var layer = rng.randi() % CLOUD_LAYERS
	var bg_left  = wall_min.x - BACKGROUND_EXPANSION if wall_valid else -3000.0
	var _bg_right = wall_max.x + BACKGROUND_EXPANSION if wall_valid else  3000.0
	var bg_right  = _bg_right
	var sky_top  = (wall_min.y - BACKGROUND_EXPANSION) if wall_valid else -2000.0
	var sky_bottom = ground_y - 120.0 if wall_valid else -400.0

	var sx    = 60.0 + rng.randf() * 220.0 + float(layer) * 50.0
	var sy    = 22.0 + rng.randf() * 38.0  + float(layer) * 8.0
	var speed = (0.18 + rng.randf() * 0.25) * (1.0 + float(layer) * 0.6) * 40.0
	var alpha = 0.35 + rng.randf() * 0.35
	var y     = sky_top + 40.0 + rng.randf() * max(sky_bottom - sky_top - 100.0, 100.0)
	var x: float
	if initial_spread:
		x = bg_left + rng.randf() * (bg_right - bg_left)
	else:
		x = bg_right + sx + rng.randf() * 200.0

	return { "x": x, "y": y, "sx": sx, "sy": sy, "speed": speed,
			 "alpha": alpha, "layer": layer, "seed": rng.randi() }

func _update_clouds(delta: float):
	var bg_left  = wall_min.x - BACKGROUND_EXPANSION if wall_valid else -3000.0
	var bg_right = wall_max.x + BACKGROUND_EXPANSION if wall_valid else  3000.0
	var rng = RandomNumberGenerator.new()
	rng.seed = int(_cloud_time * 100.0) ^ 0xDEADBEEF

	var rain_blend = _get_weather_blend()

	for i in range(_clouds.size()):
		var c = _clouds[i]
		var speed_mult = 1.0 + rain_blend * 0.5
		c["x"] -= c["speed"] * delta * speed_mult
		if c["x"] + c["sx"] < bg_left - 100.0:
			_clouds[i] = _make_cloud(rng, false)
			if rain_blend > 0.3:
				_clouds[i]["sy"] *= (1.0 + rain_blend * 0.6)
				_clouds[i]["alpha"] = min(_clouds[i]["alpha"] * (1.0 + rain_blend * 0.4), 1.0)
		else:
			_clouds[i] = c

# ─── Splash system ────────────────────────────────────────────────────────────

func spawn_splash(world_pos: Vector2, entry_velocity: float):
	var rng = RandomNumberGenerator.new()
	rng.seed = int(world_pos.x * 7.0 + _water_time * 1000.0) ^ 0xBEEF
	var splash_speed = clamp(abs(entry_velocity) * 0.55, 120.0, 600.0)
	var droplets: Array = []
	for i in range(SPLASH_DROPLET_COUNT):
		var side = 1.0 if (i % 2 == 0) else -1.0
		var spread_frac = float(i) / float(SPLASH_DROPLET_COUNT)
		var angle_deg = 30.0 + spread_frac * 70.0
		var angle_rad = deg_to_rad(angle_deg) * side
		var speed_frac = 0.5 + rng.randf() * 0.5
		var vx = sin(angle_rad) * splash_speed * speed_frac
		var vy = -cos(angle_rad) * splash_speed * speed_frac * (0.6 + rng.randf() * 0.4)
		var drop_size = 2.5 + rng.randf() * 4.5
		if spread_frac < 0.15:
			drop_size *= 1.6
		var max_life = 0.4 + rng.randf() * 0.6
		droplets.append({
			"x": world_pos.x + rng.randf_range(-8.0, 8.0),
			"y": world_pos.y,
			"vx": vx,
			"vy": vy,
			"life": max_life,
			"max_life": max_life,
			"size": drop_size,
		})
	_splashes.append({
		"pos": world_pos,
		"time": 0.0,
		"droplets": droplets,
		"ring_radius": 0.0,
	})

func _update_splashes(delta: float):
	var gravity = 800.0
	var to_remove: Array = []
	for i in range(_splashes.size()):
		var s = _splashes[i]
		s["time"] += delta
		s["ring_radius"] += delta * 120.0
		var all_dead = true
		for d in s["droplets"]:
			d["life"] -= delta
			if d["life"] > 0.0:
				all_dead = false
				d["x"] += d["vx"] * delta
				d["y"] += d["vy"] * delta
				d["vy"] += gravity * delta
				if d["y"] > s["pos"].y + 10.0:
					d["life"] = 0.0
		if s["time"] > SPLASH_DURATION:
			to_remove.append(i)
		elif all_dead:
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		_splashes.remove_at(to_remove[i])

# ─── Editor ───────────────────────────────────────────────────────────────────

func set_editor_mode(enabled: bool):
	is_in_editor = enabled
	queue_redraw()

func _wait_for_env_config() -> void:
	var timeout := 0
	while get_node_or_null("/root/EnvironmentConfig") == null and timeout < 120:
		await get_tree().process_frame
		timeout += 1

func update_environment_settings():
	# Background decorative walls manage their own environment — skip broadcast
	if get_meta("is_background_wall", false):
		return
	print("update_environment_settings called")
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if env_config == null:
		print("ERROR: EnvironmentConfig is NULL in update_environment_settings")
		return
	print("EnvironmentConfig found OK")
	var data = env_config.get_environment_data()
	current_wall_color  = data.get("wall_color",           Color(0.82, 0.75, 0.62))
	background_color    = data.get("background_color",     Color(0.53, 0.81, 0.92))
	show_bolt_holes     = data.get("show_bolt_holes",      false)
	is_granite          = data.get("show_granite_texture", false)
	current_environment = env_config.get_current_environment_name().to_lower()
	print("current_environment set to: ", current_environment)
	_apply_environment_theme()
	if not top_edge_indices.is_empty():
		_create_top_edge_holds()
	queue_redraw()

func _apply_environment_theme():
	match current_environment:
		"granite", "sandstone", "night":
			var time_of_day = (abs((_scenery_seed ^ 0x9E3779B9) * 1664525 + 1013904223) >> 7) % 3
			match time_of_day:
				1:
					_env = {
						"sky_top": Color(0.12, 0.10, 0.32),
						"sky_horizon": Color(0.98, 0.52, 0.18),
						"cloud_color": Color(1.0, 0.65, 0.40, 1.0),
						"cloud_shadow": Color(0.65, 0.25, 0.12),
						"has_sun": true, "sun_color": Color(1.0, 0.65, 0.15),
						"has_mountains": true,
						"ground_type": "grass_dusk",
						"ground_top": Color(0.14, 0.22, 0.10),
						"ground_mid": Color(0.24, 0.16, 0.08),
						"ground_deep": Color(0.16, 0.10, 0.06),
						"ground_detail": "rocks",
						"fog_color": Color(0.90, 0.45, 0.15, 0.10),
					}
				2:
					_env = {
						"sky_top": Color(0.02, 0.02, 0.08),
						"sky_horizon": Color(0.06, 0.08, 0.18),
						"cloud_color": Color(0.22, 0.25, 0.38, 0.7),
						"cloud_shadow": Color(0.10, 0.12, 0.20),
						"has_sun": false, "has_moon": true, "has_stars": true,
						"has_mountains": true,
						"ground_type": "grass_night",
						"ground_top": Color(0.08, 0.14, 0.07),
						"ground_mid": Color(0.12, 0.10, 0.08),
						"ground_deep": Color(0.07, 0.06, 0.05),
						"ground_detail": "rocks",
						"fog_color": Color(0.05, 0.06, 0.15, 0.12),
					}
				_:
					_env = {
						"sky_top": Color(0.20, 0.45, 0.78),
						"sky_horizon": Color(0.72, 0.85, 0.95),
						"cloud_color": Color(1.0, 1.0, 1.0, 1.0),
						"cloud_shadow": Color(0.75, 0.82, 0.90),
						"has_sun": true, "sun_color": Color(1.0, 0.96, 0.78),
						"has_mountains": true,
						"ground_type": "grass",
						"ground_top": Color(0.22, 0.52, 0.14),
						"ground_mid": Color(0.38, 0.28, 0.16),
						"ground_deep": Color(0.28, 0.20, 0.10),
						"ground_detail": "rocks",
						"fog_color": Color(0.65, 0.80, 0.95, 0.0),
					}
		"gym":
			var gym_tod = (abs((_scenery_seed ^ 0x6B43FA1D) * 22695477 + 1) >> 9) % 3
			match gym_tod:
				1:
					_env = {
						"sky_top": Color(0.96, 0.96, 0.97),
						"sky_horizon": Color(0.92, 0.92, 0.93),
						"cloud_color": Color(1.0, 1.0, 1.0, 0.0),
						"has_sun": false, "has_mountains": false,
						"has_gym_interior": true,
						"gym_time_of_day": 1,
						"gym_sky_top":   Color(0.12, 0.10, 0.32),
						"gym_sky_mid":   Color(0.72, 0.28, 0.12),
						"gym_sky_haze":  Color(0.98, 0.52, 0.18),
						"gym_sun_color": Color(1.0, 0.55, 0.10),
						"gym_mtn_colors": [
							Color(0.58, 0.35, 0.28),
							Color(0.42, 0.22, 0.18),
							Color(0.28, 0.14, 0.12),
							Color(0.16, 0.08, 0.08),
						],
						"gym_grass_color": Color(0.14, 0.22, 0.10),
						"ground_type": "gym_floor",
						"ground_top": Color(0.22, 0.22, 0.24),
						"ground_mid": Color(0.16, 0.16, 0.18),
						"ground_deep": Color(0.11, 0.11, 0.12),
					}
				2:
					_env = {
						"sky_top": Color(0.96, 0.96, 0.97),
						"sky_horizon": Color(0.92, 0.92, 0.93),
						"cloud_color": Color(1.0, 1.0, 1.0, 0.0),
						"has_sun": false, "has_mountains": false,
						"has_gym_interior": true,
						"gym_time_of_day": 2,
						"gym_sky_top":   Color(0.02, 0.02, 0.08),
						"gym_sky_mid":   Color(0.04, 0.06, 0.14),
						"gym_sky_haze":  Color(0.06, 0.08, 0.20),
						"gym_sun_color": Color(0.0, 0.0, 0.0),
						"gym_mtn_colors": [
							Color(0.14, 0.16, 0.22),
							Color(0.10, 0.12, 0.18),
							Color(0.06, 0.08, 0.13),
							Color(0.03, 0.04, 0.08),
						],
						"gym_grass_color": Color(0.08, 0.14, 0.07),
						"has_gym_stars": true,
						"has_gym_moon":  true,
						"ground_type": "gym_floor",
						"ground_top": Color(0.22, 0.22, 0.24),
						"ground_mid": Color(0.16, 0.16, 0.18),
						"ground_deep": Color(0.11, 0.11, 0.12),
					}
				_:
					_env = {
						"sky_top": Color(0.96, 0.96, 0.97),
						"sky_horizon": Color(0.92, 0.92, 0.93),
						"cloud_color": Color(1.0, 1.0, 1.0, 0.0),
						"has_sun": false, "has_mountains": false,
						"has_gym_interior": true,
						"gym_time_of_day": 0,
						"gym_sky_top":   Color(0.20, 0.45, 0.78),
						"gym_sky_mid":   Color(0.44, 0.70, 0.93),
						"gym_sky_haze":  Color(0.70, 0.86, 0.97),
						"gym_sun_color": Color(1.0, 0.96, 0.78),
						"gym_mtn_colors": [
							Color(0.72, 0.82, 0.91),
							Color(0.54, 0.67, 0.80),
							Color(0.38, 0.52, 0.66),
							Color(0.24, 0.38, 0.53),
						],
						"gym_grass_color": Color(0.18, 0.26, 0.19),
						"ground_type": "gym_floor",
						"ground_top": Color(0.22, 0.22, 0.24),
						"ground_mid": Color(0.16, 0.16, 0.18),
						"ground_deep": Color(0.11, 0.11, 0.12),
					}
		"deep_water_solo":
			_env = {
				"sky_top": Color(0.18, 0.42, 0.72),
				"sky_horizon": Color(0.60, 0.82, 0.94),
				"cloud_color": Color(1.0, 1.0, 1.0, 0.85),
				"cloud_shadow": Color(0.72, 0.84, 0.92),
				"has_sun": true, "sun_color": Color(1.0, 0.95, 0.75),
				"has_mountains": false,
				"has_water": true,
				"ground_type": "water",
				"ground_top":  Color(0.04, 0.22, 0.44),
				"ground_mid":  Color(0.02, 0.14, 0.30),
				"ground_deep": Color(0.01, 0.08, 0.18),
				"fog_color": Color(0.50, 0.75, 0.90, 0.06),
				"has_sea_cliffs": true,
			}
		"building":
			var bld_tod = (abs((_scenery_seed ^ 0x3F7A2B1C) * 1664525 + 1013904223) >> 7) % 3
			match bld_tod:
				1:
					_env = {
						"sky_top":      Color(0.06, 0.05, 0.14),
						"sky_horizon":  Color(0.72, 0.28, 0.10),
						"cloud_color":  Color(1.0,  0.55, 0.25, 0.70),
						"cloud_shadow": Color(0.55, 0.20, 0.10),
						"has_sun":      false,
						"has_moon":     false,
						"has_mountains":false,
						"has_city":     true,
						"city_time":    1,
						"ground_type":  "city_street",
						"ground_top":   Color(0.22, 0.18, 0.14),
						"ground_mid":   Color(0.16, 0.13, 0.10),
						"ground_deep":  Color(0.11, 0.09, 0.07),
						"fog_color":    Color(0.60, 0.25, 0.08, 0.08),
					}
				2:
					_env = {
						"sky_top":      Color(0.02, 0.02, 0.07),
						"sky_horizon":  Color(0.05, 0.06, 0.14),
						"cloud_color":  Color(0.20, 0.22, 0.35, 0.60),
						"cloud_shadow": Color(0.08, 0.10, 0.20),
						"has_sun":      false,
						"has_moon":     true,
						"has_stars":    true,
						"has_mountains":false,
						"has_city":     true,
						"city_time":    2,
						"ground_type":  "city_street",
						"ground_top":   Color(0.14, 0.14, 0.16),
						"ground_mid":   Color(0.10, 0.10, 0.12),
						"ground_deep":  Color(0.06, 0.06, 0.08),
						"fog_color":    Color(0.04, 0.05, 0.12, 0.10),
					}
				_:
					_env = {
						"sky_top":      Color(0.16, 0.38, 0.70),
						"sky_horizon":  Color(0.62, 0.78, 0.94),
						"cloud_color":  Color(1.0,  1.0,  1.0,  0.90),
						"cloud_shadow": Color(0.76, 0.84, 0.92),
						"has_sun":      true,
						"sun_color":    Color(1.0, 0.96, 0.78),
						"has_mountains":false,
						"has_city":     true,
						"city_time":    0,
						"ground_type":  "city_street",
						"ground_top":   Color(0.28, 0.28, 0.30),
						"ground_mid":   Color(0.20, 0.20, 0.22),
						"ground_deep":  Color(0.13, 0.13, 0.14),
						"fog_color":    Color(0.60, 0.76, 0.94, 0.04),
					}
		_:
			_env = {
				"sky_top": background_color.darkened(0.25),
				"sky_horizon": background_color.lightened(0.15),
				"cloud_color": Color(1.0, 1.0, 1.0, 1.0),
				"cloud_shadow": Color(0.78, 0.84, 0.92),
				"has_sun": true, "sun_color": Color(1.0, 0.95, 0.70),
				"has_mountains": true,
				"ground_type": "grass",
				"ground_top": Color(0.22, 0.52, 0.14),
				"ground_mid": Color(0.38, 0.28, 0.16),
				"ground_deep": Color(0.28, 0.20, 0.10),
				"ground_detail": "rocks",
				"fog_color": Color(0.0, 0.0, 0.0, 0.0),
			}

# ─── Input (editor) ───────────────────────────────────────────────────────────

func _input(event: InputEvent):
	if not is_in_editor or not edit_mode: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _try_start_drag()
			else: _end_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var mp = get_global_mouse_position()
			for i in range(control_points.size()):
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
		else: _update_hover()

func toggle_top_edge(edge_index: int):
	if _is_ground_edge(edge_index): return
	if edge_index in top_edge_indices: top_edge_indices.erase(edge_index)
	else: top_edge_indices.append(edge_index)
	_create_top_edge_holds(); queue_redraw()

func _try_start_drag():
	var mp = get_global_mouse_position()
	for i in range(control_points.size()):
		if mp.distance_to(control_points[i]) < POINT_GRAB_RADIUS:
			dragging_point = i; drag_offset = control_points[i] - mp; queue_redraw(); return

func _update_drag():
	if dragging_point < 0 or dragging_point >= control_points.size(): return
	var mp = get_global_mouse_position()
	var np = mp + drag_offset
	if dragging_point == ground_left_index or dragging_point == ground_right_index:
		var new_y = np.y
		control_points[ground_left_index].y  = new_y
		control_points[ground_right_index].y = new_y
		ground_y = new_y
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

func _end_drag():
	dragging_point = -1; queue_redraw()

func _update_hover():
	var mp = get_global_mouse_position()
	var ohp = hovered_point; var ohe = hovered_edge
	hovered_point = -1; hovered_edge = -1
	for i in range(control_points.size()):
		if mp.distance_to(control_points[i]) < POINT_GRAB_RADIUS:
			hovered_point = i
			if ohp != hovered_point or ohe != hovered_edge: queue_redraw()
			return
	for i in range(control_points.size()):
		if _is_ground_edge(i): continue
		if _point_to_segment_distance(mp, control_points[i],
				control_points[(i + 1) % control_points.size()]) < EDGE_CLICK_DISTANCE:
			hovered_edge = i; break
	if ohp != hovered_point or ohe != hovered_edge: queue_redraw()

func _is_ground_edge(edge_index: int) -> bool:
	if ground_left_index < 0 or ground_right_index < 0: return false
	var ni = (edge_index + 1) % control_points.size()
	return (edge_index == ground_left_index and ni == ground_right_index) or \
		   (edge_index == ground_right_index and ni == ground_left_index)

# =============================================================================
# MAIN DRAW DISPATCH
# =============================================================================

func _draw():
	if not wall_valid: return
	_draw_sky()
	if _env.get("has_stars", false): _draw_stars()
	if _env.get("has_sun", false) and _get_weather_blend() < 0.85: _draw_sun()
	if _env.get("has_moon", false): _draw_moon()
	if _env.get("has_mountains", false): _draw_mountains()
	if _env.get("has_city", false): _draw_city_silhouette()
	_draw_clouds()
	_draw_fog()
	if _env.get("has_gym_interior", false): _draw_gym_interior()
	if _env.get("has_scaffold", false): _draw_scaffold()
	if use_polygon_mode and control_points.size() >= 3: _draw_polygon_wall()
	else: _draw_rectangle_wall()
	_draw_wall_depth_shading()
	_draw_wall_tonal_outline()
	if _env.get("has_water", false): _draw_underwater_wall_depth()
	if show_bolt_holes:
		if use_polygon_mode and control_points.size() >= 3: draw_bolt_holes_on_polygon()
		else: draw_bolt_holes(wall_min, wall_max)
	if is_granite and not use_polygon_mode: draw_granite_texture()
	if ground_enabled: _draw_ground()
	if _env.get("has_water", false):
		_draw_water_surface()
		_draw_splashes()
	if is_in_editor and use_polygon_mode and control_points.size() > 0: _draw_control_points()
	if is_in_editor and edit_mode and use_polygon_mode: _draw_edge_highlights()

# =============================================================================
# SKY — smooth multi-stop gradient, 20 bands to eliminate banding
# =============================================================================

func _draw_sky() -> void:
	var bl  = wall_min.x - BACKGROUND_EXPANSION
	var br  = wall_max.x + BACKGROUND_EXPANSION
	var st  = wall_min.y - BACKGROUND_EXPANSION
	var sw  = br - bl
	var rb  = _get_weather_blend()

	var col_top   = _rain_lerp_color(_env.get("sky_top",    background_color),               "sky_top",     rb)
	var col_horiz = _rain_lerp_color(_env.get("sky_horizon", background_color.lightened(0.15)), "sky_horizon", rb)

	# 20 gradient bands — more than 16 further eliminates any visible banding
	var bands = 20
	var total_h = ground_y - st
	for i in range(bands):
		var t0 = float(i)     / float(bands)
		var t1 = float(i + 1) / float(bands)
		# Squared easing: sky color changes faster at top, slower near horizon
		var c0 = col_top.lerp(col_horiz, t0 * t0)
		var c1 = col_top.lerp(col_horiz, t1 * t1)
		var y0 = st + t0 * total_h
		var y1 = st + t1 * total_h
		_draw_grad_quad(bl, y0, sw, y1, c0, c1)

	# Fill below horizon with horizon color
	draw_rect(Rect2(Vector2(bl, ground_y), Vector2(sw, 99999.0)), col_horiz, true)

# =============================================================================
# CELESTIAL — stars, sun, moon
# =============================================================================

func _draw_stars() -> void:
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var st = wall_min.y - BACKGROUND_EXPANSION
	var sw = br - bl
	var rb = _get_weather_blend()
	for i in range(80):
		var star_seed = (_scenery_seed ^ 0xBEEF) + i * 17
		var sx = bl + _hf(star_seed) * sw
		var sy = st + _hf(star_seed + 1) * (ground_y - st - 80.0)
		var bright  = (0.5 + _hf(star_seed + 2) * 0.5) * (1.0 - rb)
		var sz      = 1.0 + _hf(star_seed + 3) * 1.8
		var twinkle = 0.7 + 0.3 * sin(_cloud_time * (1.5 + _hf(star_seed + 4) * 3.0) + float(i))
		draw_circle(Vector2(sx, sy), sz, Color(1.0, 1.0, 1.0, bright * twinkle * 0.85))

func _draw_sun() -> void:
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var sx = bl + (br - bl) * 0.78
	var sy = wall_min.y - BACKGROUND_EXPANSION * 0.5 + 180.0
	var sc: Color = _env.get("sun_color", Color(1.0, 0.95, 0.70))
	var fade = 1.0 - _get_weather_blend()
	for gi in range(8):
		draw_circle(Vector2(sx, sy), 45.0 + float(gi) * 28.0,
					Color(sc.r, sc.g, sc.b, (0.05 - float(gi) * 0.005) * fade))
	draw_circle(Vector2(sx, sy), 45.0, Color(sc.r, sc.g, sc.b, sc.a * fade))
	draw_circle(Vector2(sx, sy), 32.0, Color(1.0, 1.0, 0.97, fade * 0.9))

func _draw_moon() -> void:
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var mx = bl + (br - bl) * 0.72
	var my = wall_min.y - BACKGROUND_EXPANSION * 0.4 + 220.0
	var mr = 36.0
	for gi in range(5):
		draw_circle(Vector2(mx, my), mr + float(gi) * 20.0, Color(0.7, 0.75, 0.9, 0.04))
	draw_circle(Vector2(mx, my), mr, Color(0.88, 0.90, 0.95, 1.0))
	draw_circle(Vector2(mx + mr * 0.35, my - mr * 0.1), mr * 0.82, _env.get("sky_top", Color(0.02, 0.02, 0.08)))
	for ci in range(4):
		var cs = 6000 + ci * 37
		draw_circle(Vector2(mx - mr * 0.3 + _hf(cs) * mr * 0.5, my - mr * 0.2 + _hf(cs + 1) * mr * 0.4),
					2.0 + _hf(cs + 2) * 4.0, Color(0.70, 0.72, 0.78, 0.35))

# =============================================================================
# MOUNTAINS — layered silhouettes with atmospheric haze between layers
# =============================================================================

func _draw_mountains() -> void:
	var bl  = wall_min.x - BACKGROUND_EXPANSION
	var br  = wall_max.x + BACKGROUND_EXPANSION
	var rb  = _get_weather_blend()
	var hs: Color = _rain_lerp_color(_env.get("sky_horizon", background_color), "sky_horizon", rb)
	var ht: Color = _rain_lerp_color(_env.get("sky_top",     background_color), "sky_top",     rb)

	# Far mountain layers
	_draw_hill_layer(bl, br, ground_y - 60.0, 240.0, 600.0, 90, hs.lerp(ht, 0.6).darkened(0.05), _scenery_seed ^ 0x0A1B2C)
	_draw_hill_layer(bl, br, ground_y - 20.0, 160.0, 420.0, 80, hs.lerp(ht, 0.4).darkened(0.09), _scenery_seed ^ 0x1A2B3C)

	# Atmospheric haze band — separates distant mountains from near ground, key for depth
	var haze_color = hs.lightened(0.08)
	var haze_color_rb = _rain_lerp_color(haze_color, "sky_horizon", rb * 0.5)
	var haze_y     = ground_y - 55.0
	var sw         = br - bl
	_draw_grad_quad(bl, haze_y - 20.0, sw, haze_y + 8.0,
		Color(haze_color_rb.r, haze_color_rb.g, haze_color_rb.b, 0.0),
		Color(haze_color_rb.r, haze_color_rb.g, haze_color_rb.b, 0.50 * (1.0 - rb * 0.4)))
	_draw_grad_quad(bl, haze_y + 8.0, sw, haze_y + 36.0,
		Color(haze_color_rb.r, haze_color_rb.g, haze_color_rb.b, 0.50 * (1.0 - rb * 0.4)),
		Color(haze_color_rb.r, haze_color_rb.g, haze_color_rb.b, 0.0))

	# Near mountain layers (drawn after haze so they appear in front)
	_draw_hill_layer(bl, br, ground_y - 5.0,   90.0, 230.0, 55, hs.darkened(0.22), _scenery_seed ^ 0x4D5E6F)
	_draw_hill_layer(bl, br, ground_y,          40.0, 110.0, 45, hs.darkened(0.38), _scenery_seed ^ 0x7F8A9B)

func _draw_hill_layer(left: float, right: float, base_y: float,
					  min_h: float, max_h: float, segs: int, color: Color, hill_seed: int) -> void:
	if segs < 1 or right <= left:
		return
	var step = (right - left) / float(segs)
	var pts: PackedVector2Array = []
	pts.append(Vector2(left, base_y + 500.0))
	for i in range(segs + 1):
		var h0 = _hf(hill_seed + (i - 1) * 7) * (max_h - min_h) + min_h
		var h1 = _hf(hill_seed + i * 7) * (max_h - min_h) + min_h
		var h2 = _hf(hill_seed + (i + 1) * 7) * (max_h - min_h) + min_h
		pts.append(Vector2(left + i * step, base_y - (h0 * 0.2 + h1 * 0.6 + h2 * 0.2)))
	pts.append(Vector2(right, base_y + 500.0))
	if _polygon_valid(pts):
		draw_colored_polygon(pts, color)

# =============================================================================
# CITY SILHOUETTE
# =============================================================================

func _draw_city_silhouette() -> void:
	var bl  = wall_min.x - BACKGROUND_EXPANSION
	var br  = wall_max.x + BACKGROUND_EXPANSION
	var rb  = _get_weather_blend()
	var tod : int = _env.get("city_time", 0)

	var sil_colors: Array = []
	match tod:
		1:
			sil_colors = [Color(0.10, 0.08, 0.16), Color(0.16, 0.12, 0.22),
						   Color(0.24, 0.16, 0.24), Color(0.34, 0.20, 0.22)]
		2:
			sil_colors = [Color(0.04, 0.04, 0.09), Color(0.06, 0.06, 0.13),
						   Color(0.09, 0.09, 0.17), Color(0.13, 0.13, 0.20)]
		_:
			sil_colors = [Color(0.50, 0.54, 0.60), Color(0.40, 0.44, 0.52),
						   Color(0.30, 0.34, 0.42), Color(0.20, 0.24, 0.32)]

	for i in range(sil_colors.size()):
		sil_colors[i] = (sil_colors[i] as Color).lerp(Color(0.18, 0.20, 0.24), rb * 0.4)

	var layer_configs: Array = [
		[0.72, 100.0, 280.0,  55.0,  95.0, 0xA1B2C3],
		[0.62, 150.0, 360.0,  65.0, 120.0, 0xD4E5F6],
		[0.50, 200.0, 460.0,  85.0, 160.0, 0x3C4D5E],
		[0.36, 250.0, 580.0, 100.0, 200.0, 0x7F8A9B],
	]

	for li in range(layer_configs.size()):
		var lc        = layer_configs[li]
		var h_min     = float(lc[1]); var h_max = float(lc[2])
		var w_min     = float(lc[3]); var w_max = float(lc[4])
		var seed_base = int(lc[5]) ^ _scenery_seed
		var col       : Color = sil_colors[li]
		var x = bl; var bldg_idx = 0
		while x < br + w_max:
			var bldg_seed = seed_base + bldg_idx * 31
			var bw   = w_min + _hf(bldg_seed)     * (w_max - w_min)
			var bh   = h_min + _hf(bldg_seed + 1) * (h_max - h_min)
			var bx   = x + (_hf(bldg_seed + 2) - 0.5) * 20.0
			draw_rect(Rect2(bx, ground_y - bh, bw, bh), col, true)
			if _hf(bldg_seed + 5) > 0.72:
				var ah = 10.0 + _hf(bldg_seed + 6) * 18.0
				var ax = bx + bw * (0.4 + _hf(bldg_seed + 7) * 0.2)
				draw_line(Vector2(ax, ground_y - bh), Vector2(ax, ground_y - bh - ah),
						  col.darkened(0.12), 1.2)
			x = bx + bw + _hf(bldg_seed + 8) * 25.0
			bldg_idx += 1

	if tod == 2:
		var sw = br - bl
		for gi in range(3):
			draw_rect(Rect2(bl, ground_y - float(gi) * 12.0 - 6.0, sw, 14.0),
					  Color(0.55, 0.60, 0.90, 0.020 * (1.0 - float(gi) / 3.0)), true)

# =============================================================================
# CLOUDS
# =============================================================================

func _draw_clouds() -> void:
	var rb = _get_weather_blend()
	var base_cc: Color = _env.get("cloud_color", Color(1, 1, 1))
	var base_sc: Color = _env.get("cloud_shadow", Color(0.78, 0.84, 0.92))

	var cc = _rain_lerp_color(base_cc, "cloud_color",  rb)
	var sc = _rain_lerp_color(base_sc, "cloud_shadow", rb)

	if cc.a < 0.02: return

	if rb > 0.15:
		_draw_overcast_layer(rb, cc, sc)

	for layer in range(CLOUD_LAYERS):
		for c in _clouds:
			if c["layer"] != layer: continue
			var alpha_boost = 1.0 + rb * 0.4
			var ba = c["alpha"] * cc.a * alpha_boost
			ba = min(ba, 0.92)
			_draw_cloud_shape(c["x"], c["y"], c["sx"], c["sy"],
				Color(cc.r, cc.g, cc.b, ba),
				Color(sc.r, sc.g, sc.b, ba * 0.45),
				c["seed"], rb)

func _draw_overcast_layer(blend: float, cc: Color, _sc: Color) -> void:
	var bl   = wall_min.x - BACKGROUND_EXPANSION
	var br   = wall_max.x + BACKGROUND_EXPANSION
	var _sw  = br - bl
	var h    = blend * BACKGROUND_EXPANSION * 0.55
	var base = wall_min.y - BACKGROUND_EXPANSION * 0.25
	var steps = 10
	for i in range(steps):
		var t0 = float(i)     / float(steps)
		var t1 = float(i + 1) / float(steps)
		var a0 = lerp(blend * 0.65, 0.0, t0 * t0)
		var a1 = lerp(blend * 0.65, 0.0, t1 * t1)
		_draw_grad_quad(bl, base + t0 * h, _sw, base + t1 * h,
			Color(cc.r, cc.g, cc.b, a0),
			Color(cc.r, cc.g, cc.b, a1))

func _draw_cloud_shape(cx: float, cy: float, sx: float, sy: float,
					   color: Color, shadow: Color, cloud_seed: int, rain_blend: float = 0.0) -> void:
	var ry_mult = 1.0 + rain_blend * 0.30
	_draw_oval(cx, cy + sy * 0.38, sx * 0.85, sy * 0.52 * ry_mult, shadow)
	_draw_oval(cx, cy, sx, sy * ry_mult, color)
	var offsets = [
		Vector2(-sx * 0.32, -sy * 0.42), Vector2(sx * 0.30, -sy * 0.36),
		Vector2(0.0, -sy * 0.62),        Vector2(-sx * 0.52, -sy * 0.18),
		Vector2(sx * 0.48, -sy * 0.22),
	]
	var sizes = [0.50, 0.44, 0.48, 0.38, 0.36]
	for pi in range(offsets.size()):
		var wobble = Vector2((_hf(cloud_seed + pi * 3) - 0.5) * sx * 0.08,
							  (_hf(cloud_seed + pi * 3 + 1) - 0.5) * sy * 0.10)
		_draw_oval(cx + offsets[pi].x + wobble.x, cy + offsets[pi].y + wobble.y,
				   sx * sizes[pi], sy * (sizes[pi] + 0.1) * ry_mult, color)

func _draw_oval(cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	if rx < 0.5 or ry < 0.5: return
	var steps = 20
	var pts: PackedVector2Array = []
	for i in range(steps):
		var angle = (float(i) / float(steps)) * TAU
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	if _polygon_valid(pts):
		draw_colored_polygon(pts, color)

# =============================================================================
# FOG LAYER
# =============================================================================

func _draw_fog() -> void:
	var rb = _get_weather_blend()
	var base_fc: Color = _env.get("fog_color", Color(0, 0, 0, 0))
	var fc = _rain_lerp_color(base_fc, "fog_color", rb)
	if fc.a < 0.01: return
	var bl     = wall_min.x - BACKGROUND_EXPANSION
	var br     = wall_max.x + BACKGROUND_EXPANSION
	var bt     = wall_min.y - BACKGROUND_EXPANSION
	var total_h = (ground_y + 99999.0) - bt
	var steps = 10
	for i in range(steps):
		var t0 = float(i)     / float(steps)
		var t1 = float(i + 1) / float(steps)
		var a0 = fc.a * (1.0 - t0 * 0.65)
		var a1 = fc.a * (1.0 - t1 * 0.65)
		_draw_grad_quad(bl, bt + t0 * total_h, br - bl, bt + t1 * total_h,
			Color(fc.r, fc.g, fc.b, a0),
			Color(fc.r, fc.g, fc.b, a1))

# =============================================================================
# GYM INTERIOR
# =============================================================================

func _draw_gym_interior() -> void:
	var bl      = wall_min.x - BACKGROUND_EXPANSION
	var br      = wall_max.x + BACKGROUND_EXPANSION
	var width   = br - bl
	var vis_top = wall_min.y
	var vis_bot = ground_y if ground_y > vis_top + 10.0 else vis_top + (wall_max.y - wall_min.y)
	var vis_h   = vis_bot - vis_top
	if width < 1.0 or vis_h < 10.0: return

	var steps = 12
	for i in range(steps):
		var t = float(i) / float(steps)
		draw_rect(Rect2(Vector2(bl, vis_top + t * vis_h), Vector2(width, vis_h / float(steps) + 2.0)),
				  Color(0.93 - t * 0.025, 0.93 - t * 0.022, 0.94 - t * 0.018), true)

	var win_top    = vis_top + vis_h * 0.10
	var win_h      = vis_h * 0.78
	var win_bot    = win_top + win_h
	var win_w      = 400.0
	var win_gap    = 150.0
	var win_stride = win_w + win_gap
	var win_count  = int(ceil(width / win_stride)) + 2
	var wall_col   = Color(0.93, 0.93, 0.94)

	var ct    = get_viewport().get_canvas_transform()
	var zoom  = ct.x.x
	var cam_x = -ct.origin.x / zoom

	var rb      = _get_weather_blend()
	var gym_tod = _env.get("gym_time_of_day", 0)

	var sky_top_c  : Color = _env.get("gym_sky_top",  Color(0.20, 0.44, 0.84))
	var sky_mid_c  : Color = _env.get("gym_sky_mid",  Color(0.44, 0.70, 0.93))
	var sky_haze_c : Color = _env.get("gym_sky_haze", Color(0.70, 0.86, 0.97))

	var rain_sky = Color(0.18, 0.20, 0.26)
	sky_top_c  = sky_top_c.lerp(rain_sky,                  rb)
	sky_mid_c  = sky_mid_c.lerp(rain_sky.lightened(0.06),  rb)
	sky_haze_c = sky_haze_c.lerp(rain_sky.lightened(0.12), rb)

	var sun_wx        = wall_min.x + (wall_max.x - wall_min.x) * 0.68 + cam_x * 0.03
	var gym_sun_color : Color = _env.get("gym_sun_color", Color(1.0, 0.96, 0.78))
	var sun_y_frac    = 0.15
	if gym_tod == 1: sun_y_frac = 0.72

	var gym_mtn_colors: Array = _env.get("gym_mtn_colors", [
		Color(0.72, 0.82, 0.91), Color(0.54, 0.67, 0.80),
		Color(0.38, 0.52, 0.66), Color(0.24, 0.38, 0.53),
	])
	var gym_grass_color : Color = _env.get("gym_grass_color", Color(0.18, 0.26, 0.19))
	gym_grass_color = gym_grass_color.lerp(Color(0.12, 0.18, 0.14), rb * 0.5)

	for wi in range(win_count):
		var wx  = bl + float(wi) * win_stride + win_gap * 0.5
		var wx2 = wx + win_w

		for gi in range(12):
			var gt = float(gi) / 12.0
			var sky_c: Color
			if gt < 0.5:
				sky_c = sky_top_c.lerp(sky_mid_c, gt * 2.0)
			else:
				sky_c = sky_mid_c.lerp(sky_haze_c, (gt - 0.5) * 2.0)
			draw_rect(Rect2(Vector2(wx, win_top + gt * win_h), Vector2(win_w, win_h / 12.0 + 1.0)), sky_c, true)

		if _env.get("has_gym_stars", false):
			for si in range(30):
				var sseed = (_scenery_seed ^ 0xCAFE) + wi * 97 + si * 13
				var sx2   = wx + _hf(sseed) * win_w
				var sy2   = win_top + _hf(sseed + 1) * win_h * 0.6
				var salp  = 0.35 + _hf(sseed + 2) * 0.50
				var ssize = 1.0 + _hf(sseed + 3) * 1.6
				var twinkle = 0.7 + 0.3 * sin(_cloud_time * (1.5 + _hf(sseed + 4) * 3.0) + float(si))
				draw_circle(Vector2(sx2, sy2), ssize, Color(1.0, 1.0, 1.0, salp * twinkle * (1.0 - rb)))

		var moon_win_idx = (_scenery_seed ^ 0xF00F) % max(win_count, 1)
		if _env.get("has_gym_moon", false) and wi == moon_win_idx:
			var mseed = _scenery_seed ^ 0xF00F
			var mx2   = wx + win_w * (0.35 + _hf(mseed) * 0.30)
			var my2   = win_top + win_h * (0.12 + _hf(mseed + 1) * 0.22)
			var mr    = 20.0 + _hf(mseed + 2) * 10.0
			for gi in range(3):
				draw_circle(Vector2(mx2, my2), mr + float(gi) * 14.0, Color(0.7, 0.75, 0.9, 0.04))
			draw_circle(Vector2(mx2, my2), mr, Color(0.88, 0.90, 0.95, 0.92 * (1.0 - rb)))
			draw_circle(Vector2(mx2 + mr * 0.35, my2 - mr * 0.1), mr * 0.82, sky_top_c)

		var show_sun: bool = (gym_tod != 2) and (gym_sun_color.r + gym_sun_color.g + gym_sun_color.b > 0.05)
		if show_sun and rb < 0.85 and sun_wx >= wx + 20.0 and sun_wx <= wx2 - 20.0:
			var sun_y = win_top + win_h * sun_y_frac
			var sfade = 1.0 - rb
			for ri in range(7):
				draw_circle(Vector2(sun_wx, sun_y), 7.0 + ri * 18.0,
							Color(gym_sun_color.r, gym_sun_color.g, gym_sun_color.b,
								  (0.042 - ri * 0.005) * sfade))
			draw_circle(Vector2(sun_wx, sun_y), 10.0,
						Color(gym_sun_color.r + 0.05, gym_sun_color.g + 0.02, gym_sun_color.b * 0.8,
							  0.70 * sfade))
			if gym_tod == 1:
				var glow_y   = sun_y - 4.0
				var glow_steps = 8
				for gsi in range(glow_steps):
					var gt = float(gsi) / float(glow_steps)
					var ga = lerp(0.18, 0.0, gt) * sfade
					draw_rect(Rect2(Vector2(wx, glow_y + gt * 40.0), Vector2(win_w, 40.0 / float(glow_steps) + 1.0)),
							  Color(gym_sun_color.r, gym_sun_color.g * 0.6, 0.05, ga), true)

		if rb > 0.05:
			_draw_window_rain_streaks(wx, wx2, win_top, win_bot, rb)

		var mtn_span = win_w * 8.0
		var msegs    = 80
		for mi in range(4):
			var mseed  = (_scenery_seed ^ (0xC001 + mi * 0x999)) + wi * 61
			var mpar   = cam_x * (0.04 + mi * 0.055)
			var mhmin  = win_h * (0.06 + mi * 0.09)
			var mhmax  = win_h * (0.20 + mi * 0.11)
			var mleft  = wx + win_w * 0.5 - mtn_span * 0.5 + mpar
			var mstep  = mtn_span / float(msegs)
			var mbase  = win_bot + 6.0
			var mcol: Color = gym_mtn_colors[mi] if mi < gym_mtn_colors.size() else Color(0.24, 0.38, 0.53)
			mcol = mcol.lerp(Color(0.22, 0.24, 0.30), rb * 0.6)

			var ridge: Array = []
			for si in range(msegs + 1):
				var px = mleft + si * mstep
				if px < wx - mstep or px > wx2 + mstep: continue
				var mh0 = _hf(mseed+(si-1)*7)*(mhmax-mhmin)+mhmin
				var mh1 = _hf(mseed+si*7)*(mhmax-mhmin)+mhmin
				var mh2 = _hf(mseed+(si+1)*7)*(mhmax-mhmin)+mhmin
				var py  = mbase - (mh0*0.2+mh1*0.6+mh2*0.2)
				ridge.append(Vector2(clamp(px, wx, wx2), py))

			if ridge.size() < 2: continue
			var mpts = PackedVector2Array()
			mpts.append(Vector2(wx, mbase))
			for rp in ridge: mpts.append(rp)
			mpts.append(Vector2(wx2, mbase))
			if _polygon_valid(mpts):
				draw_colored_polygon(mpts, mcol)

		var gnd_h  = win_h * 0.09
		var gsegs  = 40
		var gstep  = win_w / float(gsegs)
		var gpts   = PackedVector2Array()
		gpts.append(Vector2(wx, win_bot + 4.0))
		for gi2 in range(gsegs + 1):
			var gseed = (_scenery_seed ^ 0x9F01) + wi*37 + gi2*5
			var gx2   = clamp(wx + gi2 * gstep, wx, wx2)
			var gh    = gnd_h * (0.6 + _hf(gseed) * 0.4)
			gpts.append(Vector2(gx2, win_bot - gh))
		gpts.append(Vector2(wx2, win_bot + 4.0))
		if _polygon_valid(gpts):
			draw_colored_polygon(gpts, gym_grass_color)
		draw_rect(Rect2(Vector2(wx, win_bot - gnd_h * 0.6), Vector2(win_w, gnd_h * 0.6 + 6.0)),
				  gym_grass_color.darkened(0.16), true)

		draw_rect(Rect2(Vector2(wx, win_top), Vector2(win_w, win_h)), Color(1.0, 1.0, 1.0, 0.06), true)
		draw_rect(Rect2(Vector2(wx, win_top), Vector2(win_w * 0.08, win_h)), Color(1.0, 1.0, 1.0, 0.05), true)

	for wi in range(win_count + 1):
		var gx = bl + float(wi) * win_stride + win_gap * 0.5 - win_gap
		draw_rect(Rect2(Vector2(gx, vis_top), Vector2(win_gap + 4.0, vis_h)), wall_col, true)
	draw_rect(Rect2(Vector2(bl, vis_top), Vector2(width, win_top - vis_top + 1.0)), wall_col, true)
	draw_rect(Rect2(Vector2(bl, win_bot - 1.0), Vector2(width, vis_bot - win_bot + 2.0)), wall_col, true)

	for wi in range(win_count):
		var wx  = bl + float(wi) * win_stride + win_gap * 0.5
		draw_line(Vector2(wx, win_top), Vector2(wx + win_w, win_top), Color(0.55, 0.57, 0.62, 0.35), 1.5, true)
		draw_line(Vector2(wx, win_top), Vector2(wx, win_bot),         Color(0.55, 0.57, 0.62, 0.35), 1.5, true)

	draw_rect(Rect2(Vector2(bl, vis_bot - 28.0), Vector2(width, 28.0)), Color(0.22, 0.22, 0.24), true)

func _draw_window_rain_streaks(wx: float, wx2: float, win_top: float, win_bot: float, blend: float) -> void:
	var win_h = win_bot - win_top
	var win_w = wx2 - wx

	var haze_steps = 8
	var haze_max_a = blend * 0.24
	for i in range(haze_steps):
		var t0 = float(i)     / float(haze_steps)
		var t1 = float(i + 1) / float(haze_steps)
		_draw_grad_quad(wx, win_top + t0 * win_h, win_w, win_top + t1 * win_h,
			Color(0.08, 0.11, 0.18, haze_max_a * (t0 * t0)),
			Color(0.10, 0.14, 0.22, haze_max_a * (t1 * t1)))

	var mist_col   = Color(0.55, 0.64, 0.78)
	var mist_h     = win_h * 0.14 * blend
	var mist_steps = 6
	for i in range(mist_steps):
		var t0 = float(i)     / float(mist_steps)
		var t1 = float(i + 1) / float(mist_steps)
		var a0 = blend * 0.10 * (1.0 - t0)
		var a1 = blend * 0.10 * (1.0 - t1)
		_draw_grad_quad(wx, win_bot - t0 * mist_h, win_w, win_bot - t1 * mist_h,
			Color(mist_col.r, mist_col.g, mist_col.b, a0),
			Color(mist_col.r, mist_col.g, mist_col.b, a1))

	var streak_count = int(12.0 * blend)
	for si in range(streak_count):
		var sseed  = (_scenery_seed ^ 0xF00D) + si * 41
		var sx    = wx + _hf(sseed) * win_w
		var slen  = 16.0 + _hf(sseed + 2) * 26.0
		var salp  = (0.06 + _hf(sseed + 3) * 0.11) * blend
		var period   = win_h / (40.0 + _hf(sseed + 4) * 30.0)
		var anim_y   = fmod(_cloud_time / period + _hf(sseed + 1), 1.0) * win_h
		var draw_y   = win_top + anim_y
		if draw_y + slen > win_bot: continue
		draw_line(Vector2(sx, draw_y), Vector2(sx + 1.2, draw_y + slen),
				  Color(0.65, 0.75, 0.92, salp), 1.0, true)

# =============================================================================
# SCAFFOLD
# =============================================================================

func _draw_scaffold() -> void:
	var post_inset  = 28.0; var post_w = 18.0
	var post_col    = Color(0.42, 0.32, 0.20)
	var post_hi     = Color(0.55, 0.44, 0.28)
	var post_shadow = Color(0.28, 0.20, 0.12)
	var beam_col    = Color(0.38, 0.28, 0.17)
	var lx = wall_min.x - post_inset; var rx = wall_max.x + post_inset
	var top_y = wall_min.y - 36.0;   var bot_y = ground_y + 14.0
	for px in [lx, rx]:
		draw_rect(Rect2(Vector2(px - post_w * 0.5, top_y), Vector2(post_w, bot_y - top_y)), post_col, true)
		draw_rect(Rect2(Vector2(px - post_w * 0.5, top_y), Vector2(5, bot_y - top_y)),      post_shadow, true)
		draw_rect(Rect2(Vector2(px + post_w * 0.5 - 4, top_y), Vector2(4, bot_y - top_y)), post_hi, true)
	var beam_h = 14.0
	draw_rect(Rect2(Vector2(lx - post_w, top_y - beam_h), Vector2(rx - lx + post_w * 2.0, beam_h)), beam_col, true)
	draw_line(Vector2(lx - post_w, top_y - beam_h), Vector2(rx + post_w, top_y - beam_h), post_hi, 1.5, true)
	var mid_y = top_y + (ground_y - top_y) * 0.5
	draw_rect(Rect2(Vector2(lx - post_w * 0.5, mid_y - 7.0), Vector2(rx - lx + post_w, 14.0)), beam_col, true)
	draw_line(Vector2(lx - post_w * 0.5, mid_y - 7.0), Vector2(rx + post_w * 0.5, mid_y - 7.0), post_hi, 1.0, true)
	var brace_col = Color(0.35, 0.26, 0.15, 0.9)
	draw_line(Vector2(lx, top_y + 60.0), Vector2(lx - 70.0, mid_y),    brace_col, 9.0, true)
	draw_line(Vector2(lx, mid_y + 30.0), Vector2(lx - 70.0, ground_y), brace_col, 9.0, true)
	draw_line(Vector2(rx, top_y + 60.0), Vector2(rx + 70.0, mid_y),    brace_col, 9.0, true)
	draw_line(Vector2(rx, mid_y + 30.0), Vector2(rx + 70.0, ground_y), brace_col, 9.0, true)
	for px in [lx, rx]:
		draw_rect(Rect2(Vector2(px - 22.0, ground_y - 8.0), Vector2(44.0, 22.0)), Color(0.50, 0.50, 0.52), true)

# =============================================================================
# WALL RENDERING
# =============================================================================

func _draw_rectangle_wall() -> void:
	if current_environment == "building":
		_draw_building_facade_wall()
		return

	var ws = wall_max - wall_min

	draw_rect(Rect2(wall_min, ws), current_wall_color, true)

	var sheen_h   = ws.y * 0.15
	var sheen_top = current_wall_color.lightened(0.09)
	_draw_grad_quad(wall_min.x, wall_min.y, ws.x, wall_min.y + sheen_h,
		sheen_top, Color(sheen_top.r, sheen_top.g, sheen_top.b, 0.0))

	var depth_h = ws.y * 0.30
	_draw_grad_quad(wall_min.x, wall_max.y - depth_h, ws.x, wall_max.y,
		Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.06))

	var ao_w = minf(ws.x * 0.035, 16.0)
	_draw_grad_quad_h(wall_min.x, wall_min.y, wall_min.x + ao_w, wall_max.y,
		Color(0.0, 0.0, 0.0, 0.09), Color(0.0, 0.0, 0.0, 0.0))

	if wall_texture_enabled:
		draw_textured_wall(wall_min, ws)

func _draw_polygon_wall() -> void:
	var pp = PackedVector2Array(control_points)
	if not _polygon_valid(pp): return

	draw_colored_polygon(pp, current_wall_color)

	if wall_texture_enabled:
		var p2:   PackedVector2Array = PackedVector2Array()
		var cols: PackedColorArray   = PackedColorArray()
		for i in range(pp.size()):
			p2.append(pp[i])
			var t = clamp((pp[i].y - wall_min.y) / max(wall_max.y - wall_min.y, 1.0), 0.0, 1.0)
			cols.append(Color(0.0, 0.0, 0.0, t * t * 0.06))
		if _polygon_valid(p2):
			draw_polygon(p2, cols)

# =============================================================================
# WALL DEPTH SHADING — improved contact shadow
# =============================================================================

func _draw_wall_depth_shading() -> void:
	if not wall_valid: return

	# Wide soft contact shadow — extends slightly past wall edges to ground the wall
	var w          = wall_max.x - wall_min.x
	var shadow_w   = w + 80.0
	var shadow_x   = wall_min.x - 40.0
	_draw_grad_quad(shadow_x, ground_y, shadow_w, ground_y + 32.0,
		Color(0.0, 0.0, 0.0, 0.24),
		Color(0.0, 0.0, 0.0, 0.0))

	# Tight AO strip right at the wall base — crisp seam between wall and ground
	_draw_grad_quad(wall_min.x, ground_y - 8.0, w, ground_y + 6.0,
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.14))

	# Faint top edge brightening
	if not use_polygon_mode:
		_draw_grad_quad(wall_min.x, wall_min.y - 3.0, w, wall_min.y + 6.0,
			Color(1.0, 1.0, 1.0, 0.08),
			Color(1.0, 1.0, 1.0, 0.0))

# ─── Tonal outlines ───────────────────────────────────────────────────────────

func _draw_wall_tonal_outline() -> void:
	if not wall_valid: return

	var wc = current_wall_color.darkened(wall_outline_darken)
	wc.a    = wall_outline_darken * 2.8

	if use_polygon_mode and control_points.size() >= 3:
		for i in range(control_points.size()):
			if _is_ground_edge(i): continue
			var p1 = control_points[i]
			var p2 = control_points[(i + 1) % control_points.size()]
			draw_line(p1, p2, wc, wall_outline_width, true)
	else:
		var tl  = wall_min
		var tr2 = Vector2(wall_max.x, wall_min.y)
		var bl  = Vector2(wall_min.x, wall_max.y)
		var br  = wall_max
		draw_line(tl,  tr2, wc, wall_outline_width, true)
		draw_line(tl,  bl,  wc, wall_outline_width, true)
		draw_line(tr2, br,  wc, wall_outline_width, true)
		var gc = (_env.get("ground_top", Color(0.22, 0.52, 0.14)) as Color).darkened(wall_outline_darken)
		gc.a    = wc.a * 0.80
		draw_line(bl, br, gc, wall_outline_width, true)

# =============================================================================
# BUILDING FACADE
# =============================================================================

func _draw_building_facade_wall() -> void:
	var tod : int   = _env.get("city_time", 0)
	var rb  : float = _get_weather_blend()

	var base_col : Color; var dark_col : Color; var lite_col : Color
	match tod:
		1:
			base_col = Color(0.42, 0.36, 0.30)
			dark_col = Color(0.28, 0.23, 0.18)
			lite_col = Color(0.54, 0.46, 0.36)
		2:
			base_col = Color(0.22, 0.22, 0.26)
			dark_col = Color(0.14, 0.14, 0.18)
			lite_col = Color(0.28, 0.28, 0.34)
		_:
			base_col = Color(0.52, 0.52, 0.54)
			dark_col = Color(0.38, 0.38, 0.40)
			lite_col = Color(0.64, 0.64, 0.66)

	base_col = base_col.lerp(Color(0.34, 0.36, 0.40), rb * 0.4)
	lite_col = lite_col.lerp(Color(0.40, 0.42, 0.46), rb * 0.3)

	var w = wall_max.x - wall_min.x
	var h = wall_max.y - wall_min.y

	var v_bands = 10
	for vi in range(v_bands):
		var t0 = float(vi)     / float(v_bands)
		var t1 = float(vi + 1) / float(v_bands)
		var y0 = wall_min.y + t0 * h
		var y1 = wall_min.y + t1 * h
		var c0 = lite_col.lerp(dark_col, t0 * 0.5)
		var c1 = lite_col.lerp(dark_col, t1 * 0.5)
		_draw_grad_quad(wall_min.x, y0, w, y1, c0, c1)

	var panel_w = 220.0
	var panel_h = 160.0
	var groove   = Color(dark_col.r, dark_col.g, dark_col.b, 0.30)

	var vg_x = floor(wall_min.x / panel_w) * panel_w
	while vg_x <= wall_max.x:
		if vg_x >= wall_min.x:
			draw_line(Vector2(vg_x, wall_min.y), Vector2(vg_x, wall_max.y), groove, 1.5, true)
		vg_x += panel_w

	var hg_y = floor(wall_min.y / panel_h) * panel_h
	while hg_y <= wall_max.y:
		if hg_y >= wall_min.y:
			draw_line(Vector2(wall_min.x, hg_y), Vector2(wall_max.x, hg_y), groove, 1.5, true)
		hg_y += panel_h

	var win_w  = panel_w * 0.42
	var win_h2 = panel_h * 0.50
	var wmx    = (panel_w - win_w) * 0.5
	var wmy    = (panel_h - win_h2) * 0.5

	var lit_prob  : float
	var win_glass : Color
	var win_frame : Color
	match tod:
		1:
			lit_prob  = 0.40
			win_glass = Color(0.88, 0.64, 0.28, 0.60)
			win_frame = Color(0.22, 0.18, 0.14)
		2:
			lit_prob  = 0.70
			win_glass = Color(0.86, 0.82, 0.50, 0.75)
			win_frame = Color(0.10, 0.10, 0.14)
		_:
			lit_prob  = 0.08
			win_glass = Color(0.48, 0.66, 0.82, 0.42)
			win_frame = Color(0.28, 0.28, 0.30)

	win_glass = win_glass.lerp(Color(0.38, 0.44, 0.52, win_glass.a), rb * 0.4)

	var col_i = 0
	var cpx   = floor(wall_min.x / panel_w) * panel_w
	while cpx < wall_max.x:
		var row_i = 0
		var cpy   = floor(wall_min.y / panel_h) * panel_h
		while cpy < wall_max.y:
			var wr2 = Rect2(cpx + wmx, cpy + wmy, win_w, win_h2)
			var cl  = wr2.intersection(Rect2(wall_min, wall_max - wall_min))
			if cl.has_area():
				var wseed = (col_i * 1117 + row_i * 337) ^ _scenery_seed
				var lit   = _hf(wseed) < lit_prob
				_draw_grad_quad(cl.position.x - 2.0, cl.position.y - 2.0,
					cl.size.x + 4.0, cl.position.y + 2.0,
					Color(win_frame.r, win_frame.g, win_frame.b, 0.5),
					Color(win_frame.r, win_frame.g, win_frame.b, 0.0))
				if lit:
					draw_rect(cl, win_glass, true)
				else:
					draw_rect(cl, Color(dark_col.r, dark_col.g, dark_col.b, 0.50), true)
				if tod == 0 and rb < 0.5:
					draw_rect(Rect2(cl.position, Vector2(cl.size.x * 0.25, cl.size.y * 0.18)),
							  Color(0.75, 0.86, 0.96, 0.12 * (1.0 - rb * 2.0)), true)
			row_i += 1
			cpy   += panel_h
		col_i += 1
		cpx   += panel_w

	var rib_w = 10.0
	draw_rect(Rect2(wall_min.x,         wall_min.y, rib_w, h), dark_col, true)
	draw_rect(Rect2(wall_max.x - rib_w, wall_min.y, rib_w, h), dark_col, true)

	if rb > 0.2:
		for si in range(int(10.0 * rb)):
			var sseed  = (_scenery_seed ^ 0xC0DE) + si * 43
			var sx     = wall_min.x + _hf(sseed) * w
			var slen   = 18.0 + _hf(sseed + 1) * 30.0
			var salp   = (0.04 + _hf(sseed + 2) * 0.07) * rb
			var period = h / (35.0 + _hf(sseed + 3) * 25.0)
			var anim_y = fmod(_cloud_time / period + _hf(sseed + 4), 1.0) * h
			var draw_y = wall_min.y + anim_y
			if draw_y + slen > wall_max.y: continue
			draw_line(Vector2(sx, draw_y), Vector2(sx + 1.0, draw_y + slen),
					  Color(0.60, 0.70, 0.88, salp), 1.0, true)

# =============================================================================
# GROUND DISPATCH
# =============================================================================

func _draw_ground() -> void:
	if not wall_valid: return
	match _env.get("ground_type", "grass"):
		"grass", "grass_dusk", "grass_night": _draw_ground_grass()
		"gym_floor":  _draw_ground_gym()
		"water":      _draw_ground_water()
		"city_street": _draw_ground_city()
		_:            _draw_ground_grass()

# =============================================================================
# GROUND — GRASS (full 3D recession)
# =============================================================================

func _draw_ground_grass() -> void:
	var left  = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	var rb    = _get_weather_blend()

	var ct: Color = _env.get("ground_top",  Color(0.22, 0.52, 0.14))
	var cm: Color = _env.get("ground_mid",  Color(0.32, 0.22, 0.12))
	var cd: Color = _env.get("ground_deep", Color(0.20, 0.14, 0.08))
	ct = ct.lerp(Color(0.14, 0.28, 0.10), rb * 0.55)
	cm = cm.lerp(Color(0.20, 0.16, 0.10), rb * 0.40)
	cd = cd.lerp(Color(0.14, 0.12, 0.08), rb * 0.30)

	# ── Deep base fill ────────────────────────────────────────────────────────
	draw_rect(Rect2(Vector2(left, ground_y), Vector2(width, 99999.0)), cd, true)

	# ── Ground plane: 3 recession bands ──────────────────────────────────────
	var close_h = 38.0
	var mid_h   = 90.0
	var near_h  = 240.0

	_draw_grad_quad(left, ground_y,                    width, ground_y + close_h,
		ct.lightened(0.06), ct)
	_draw_grad_quad(left, ground_y + close_h,          width, ground_y + close_h + mid_h,
		ct, cm)
	_draw_grad_quad(left, ground_y + close_h + mid_h,  width, ground_y + close_h + mid_h + near_h,
		cm, cd)

	# ── Hill silhouette (micro undulation at horizon line) ────────────────────
	var segs      = 80
	var step      = width / float(segs)
	var hill_seed = _scenery_seed ^ 0x6A55
	var pts       = PackedVector2Array()
	pts.append(Vector2(left, ground_y + close_h + 6.0))
	for i in range(segs + 1):
		var gx = left + float(i) * step
		var h0 = _hf(hill_seed + (i - 1) * 11) * 7.0
		var h1 = _hf(hill_seed + i       * 11) * 7.0
		var h2 = _hf(hill_seed + (i + 1) * 11) * 7.0
		pts.append(Vector2(gx, ground_y - (h0 * 0.2 + h1 * 0.6 + h2 * 0.2)))
	pts.append(Vector2(right, ground_y + close_h + 6.0))
	if _polygon_valid(pts):
		draw_colored_polygon(pts, ct)

	# ── Atmospheric haze on horizon ground strip (aerial perspective) ─────────
	var sky_h: Color = _env.get("sky_horizon", background_color.lightened(0.15))
	sky_h = _rain_lerp_color(sky_h, "sky_horizon", rb)
	_draw_grad_quad(left, ground_y - 2.0, width, ground_y + 30.0,
		Color(sky_h.r, sky_h.g, sky_h.b, 0.40 * (1.0 - rb * 0.5)),
		Color(sky_h.r, sky_h.g, sky_h.b, 0.0))

	# ── Tonal horizon line ────────────────────────────────────────────────────
	var hc = ct.darkened(wall_outline_darken)
	hc.a = minf(wall_outline_darken * 2.6, 1.0)
	draw_line(Vector2(left, ground_y), Vector2(right, ground_y), hc, wall_outline_width, true)

	if rb > 0.1:
		_draw_ground_puddles(left, right, rb)

func _draw_ground_puddles(left: float, right: float, blend: float) -> void:
	var puddle_count = int(6.0 * blend)
	for pi in range(puddle_count):
		var pseed   = (_scenery_seed ^ 0xAB12) + pi * 53
		var px      = left + _hf(pseed) * (right - left)
		var pw      = 60.0 + _hf(pseed + 1) * 140.0 * blend
		var ph      = 6.0 + _hf(pseed + 2) * 10.0
		var palp    = 0.20 * blend
		var shimmer = sin(_cloud_time * 1.8 + float(pi) * 2.1) * 0.05
		var water_col = Color(0.38 + shimmer, 0.48 + shimmer, 0.62, palp)
		var reflect   = Color(0.55, 0.65, 0.80, palp * 0.35)
		var steps = 16
		var ovals = PackedVector2Array()
		for si in range(steps):
			var a = (float(si) / float(steps)) * TAU
			ovals.append(Vector2(px + cos(a) * pw, ground_y + 2.0 + sin(a) * ph))
		if _polygon_valid(ovals):
			draw_colored_polygon(ovals, water_col)
		draw_line(Vector2(px - pw * 0.3, ground_y + 1.0),
				  Vector2(px + pw * 0.3, ground_y + 1.0), reflect, 1.2, true)

# =============================================================================
# GROUND — GYM FLOOR (polished with perspective tiles)
# =============================================================================

func _draw_ground_gym() -> void:
	var left  = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	var ct: Color = _env.get("ground_top",  Color(0.22, 0.22, 0.24))
	var cd: Color = _env.get("ground_deep", Color(0.11, 0.11, 0.12))

	# Base fill
	draw_rect(Rect2(Vector2(left, ground_y), Vector2(width, 99999.0)), ct, true)

	# Recession gradient — floor gets darker away from wall
	_draw_grad_quad(left, ground_y, width, ground_y + 280.0, ct.lightened(0.05), cd)

	# Specular sheen right at horizon — polished floor catching ceiling light
	_draw_grad_quad(left, ground_y, width, ground_y + 20.0,
		Color(1.0, 1.0, 1.0, 0.10),
		Color(1.0, 1.0, 1.0, 0.0))

	# Vertical tile seams (uniform spacing — don't foreshorten laterally)
	var tile_w     = 200.0
	var tile_count = int(ceil(width / tile_w)) + 1
	for ti in range(tile_count):
		var tx = left + float(ti) * tile_w
		draw_line(Vector2(tx, ground_y), Vector2(tx, ground_y + 38.0),
				  Color(cd.r, cd.g, cd.b, 0.20), 0.8, true)

	# Tonal floor edge
	var fc = ct.darkened(wall_outline_darken)
	fc.a = minf(wall_outline_darken * 2.4, 1.0)
	draw_line(Vector2(left, ground_y), Vector2(right, ground_y), fc, wall_outline_width, true)

# =============================================================================
# GROUND — CITY STREET (asphalt with perspective and wet reflections)
# =============================================================================

func _draw_ground_city() -> void:
	var left  = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	var rb    = _get_weather_blend()
	var tod   : int = _env.get("city_time", 0)

	var ct: Color; var cd: Color
	match tod:
		1:  ct = Color(0.20, 0.17, 0.13); cd = Color(0.10, 0.08, 0.06)
		2:  ct = Color(0.12, 0.12, 0.14); cd = Color(0.06, 0.06, 0.08)
		_:  ct = Color(0.26, 0.26, 0.28); cd = Color(0.13, 0.13, 0.14)
	ct = ct.lerp(Color(0.16, 0.18, 0.20), rb * 0.45)

	draw_rect(Rect2(Vector2(left, ground_y), Vector2(width, 99999.0)), cd, true)

	# Recession gradient
	_draw_grad_quad(left, ground_y, width, ground_y + 220.0, ct.lightened(0.04), cd)

	# Atmospheric haze at street horizon
	var sky_h: Color = _env.get("sky_horizon", background_color)
	sky_h = _rain_lerp_color(sky_h, "sky_horizon", rb)
	_draw_grad_quad(left, ground_y, width, ground_y + 22.0,
		Color(sky_h.r, sky_h.g, sky_h.b, 0.25 * (1.0 - rb * 0.4)),
		Color(sky_h.r, sky_h.g, sky_h.b, 0.0))

	# Tonal curb line
	var cc = ct.darkened(wall_outline_darken)
	cc.a = minf(wall_outline_darken * 2.4, 1.0)
	draw_line(Vector2(left, ground_y), Vector2(right, ground_y), cc, wall_outline_width, true)

	# Road lane dashes (wet = brighter reflection)
	var stripe_alpha = 0.15 if tod == 0 else 0.24
	stripe_alpha = lerp(stripe_alpha, stripe_alpha * 1.6, rb * 0.5)
	var ssx = floor(left / 150.0) * 150.0
	while ssx < right:
		draw_rect(Rect2(ssx, ground_y + 14.0, 22.0, 2.0),
				  Color(0.55, 0.52, 0.22, stripe_alpha), true)
		# Wet puddle reflection of dash
		if rb > 0.2:
			draw_rect(Rect2(ssx, ground_y + 8.0, 22.0, 5.0),
					  Color(0.65, 0.68, 0.75, rb * 0.20), true)
		ssx += 150.0

	if rb > 0.1:
		_draw_ground_puddles(left, right, rb)

# =============================================================================
# GROUND — WATER
# =============================================================================

func _draw_ground_water() -> void:
	var left  = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	draw_rect(Rect2(Vector2(left, ground_y), Vector2(width, 99999.0)), Color(0.01, 0.06, 0.16), true)
	var depth_bands = 16; var band_h = 90.0
	for di in range(depth_bands):
		var t   = float(di) / float(depth_bands - 1)
		var dy  = ground_y + di * band_h
		var col = Color(lerp(0.06, 0.01, t), lerp(0.32, 0.04, t), lerp(0.62, 0.10, t), 1.0)
		draw_rect(Rect2(Vector2(left, dy), Vector2(width, band_h + 1.0)), col, true)
	for ci in range(8):
		var cseed = (_scenery_seed ^ 0x3C00) + ci * 17
		var cx    = left + _hf(cseed) * width
		var calp  = 0.04 + _hf(cseed + 1) * 0.04
		var cw    = 30.0 + _hf(cseed + 2) * 60.0
		var cdep  = 200.0 + _hf(cseed + 3) * 300.0
		var pts   = PackedVector2Array([
			Vector2(cx - cw * 0.5, ground_y), Vector2(cx + cw * 0.5, ground_y),
			Vector2(cx + cw * 0.8, ground_y + cdep), Vector2(cx - cw * 0.8, ground_y + cdep)])
		if _polygon_valid(pts):
			draw_colored_polygon(pts, Color(0.30, 0.65, 0.90, calp))

# =============================================================================
# WATER SURFACE
# =============================================================================

func _draw_water_surface() -> void:
	if not wall_valid: return
	var bl    = wall_min.x - BACKGROUND_EXPANSION
	var br    = wall_max.x + BACKGROUND_EXPANSION
	var width = br - bl
	var t     = _water_time

	var depth_layers = 8
	for di in range(depth_layers):
		var t0 = float(di)     / float(depth_layers)
		var t1 = float(di + 1) / float(depth_layers)
		_draw_grad_quad(bl, ground_y + t0 * 160.0, width, ground_y + t1 * 160.0,
			Color(0.02, 0.22, 0.50, lerp(0.55, 0.0, t0)),
			Color(0.01, 0.10, 0.28, lerp(0.55, 0.0, t1)))

	for ci in range(6):
		var cseed = (_scenery_seed ^ 0x4C00) + ci * 29
		var cx    = bl + _hf(cseed) * width
		var cw2   = 35.0 + _hf(cseed + 1) * 80.0
		var cy    = ground_y + 18.0 + _hf(cseed + 2) * 80.0
		var phase = t * (0.7 + _hf(cseed + 3) * 0.8) + _hf(cseed + 4) * TAU
		var alpha = maxf(0.0, 0.04 + 0.04 * sin(phase))
		var drift = sin(t * (0.3 + _hf(cseed + 5) * 0.4) + float(ci)) * 20.0
		_draw_oval(cx + drift, cy, cw2, cw2 * 0.3, Color(0.4, 0.75, 1.0, alpha))

	var segs = 120
	var step = width / float(segs)
	for wi in range(4):
		var freq  = 0.008 + wi * 0.003
		var speed = 0.55  + wi * 0.30
		var amp   = 11.0  - wi * 2.2
		var yoff  = ground_y - 2.0 + wi * 3.0
		var phase = t * speed + wi * 1.3
		var wcol: Color
		match wi:
			0: wcol = Color(0.04, 0.24, 0.52, 0.80)
			1: wcol = Color(0.06, 0.30, 0.60, 0.86)
			2: wcol = Color(0.10, 0.38, 0.68, 0.90)
			_: wcol = Color(0.14, 0.46, 0.72, 0.94)
		var pts = PackedVector2Array()
		pts.append(Vector2(bl, ground_y + 300.0))
		for si in range(segs + 1):
			var x = bl + si * step
			var y = yoff - sin(x * freq + phase) * amp \
					 - sin(x * freq * 1.618 + phase * 0.7) * amp * 0.38 \
					 - sin(x * freq * 3.14  + phase * 1.3) * amp * 0.14
			pts.append(Vector2(x, y))
		pts.append(Vector2(br, ground_y + 300.0))
		if _polygon_valid(pts):
			draw_colored_polygon(pts, wcol)

	var spec_segs = 80
	var spec_step = width / float(spec_segs)
	for si in range(spec_segs):
		var sx = bl + si * spec_step
		var sy = ground_y - sin(sx * 0.011 + t * 0.9) * 9.0 \
				  - sin(sx * 0.019 + t * 0.55) * 3.5
		var spec_a = maxf(0.0, sin(sx * 0.011 + t * 0.9)) * 0.50
		if spec_a > 0.06:
			draw_circle(Vector2(sx, sy), 3.0 + sin(float(si) * 2.1) * 1.4,
						Color(0.92, 0.97, 1.0, spec_a))

	var foam_segs = 70
	var fstep     = width / float(foam_segs)
	for fi in range(foam_segs):
		var fx   = bl + fi * fstep
		var fy_s = ground_y - sin(fx * 0.011 + t * 0.95) * 9.5 \
					- sin(fx * 0.018 + t * 0.6) * 4.0 - 1.0
		var fa   = maxf(0.0, sin(fx * 0.011 + t * 0.95)) * 0.38
		if fa > 0.05:
			draw_circle(Vector2(fx, fy_s), 4.0 + sin(float(fi) * 2.3) * 2.0,
						Color(1.0, 1.0, 1.0, fa))

func _draw_splashes() -> void:
	for s in _splashes:
		var ring_r = s["ring_radius"]
		if ring_r < 250.0:
			var ring_alpha = (1.0 - ring_r / 250.0) * 0.50
			var ring_steps = 24
			var last_pt    = Vector2.ZERO
			for ri in range(ring_steps + 1):
				var angle = (float(ri) / float(ring_steps)) * TAU
				var pt    = Vector2(s["pos"].x + cos(angle) * ring_r,
									 s["pos"].y + sin(angle) * ring_r * 0.35)
				if ri > 0:
					draw_line(last_pt, pt, Color(0.7, 0.88, 1.0, ring_alpha), 1.2, true)
				last_pt = pt
		for d in s["droplets"]:
			if d["life"] <= 0.0: continue
			var life_frac = d["life"] / d["max_life"]
			var alpha     = life_frac * 0.80
			var drop_pos  = Vector2(d["x"], d["y"])
			var spd       = Vector2(d["vx"], d["vy"]).length()
			if spd > 80.0:
				var tail_len = min(spd * 0.04, 12.0)
				var vel_dir  = Vector2(d["vx"], d["vy"]).normalized()
				draw_line(drop_pos, drop_pos - vel_dir * tail_len,
						  Color(0.7, 0.88, 1.0, alpha * 0.45), 1.1, true)
			draw_circle(drop_pos, d["size"] * life_frac, Color(0.82, 0.94, 1.0, alpha))
			if d["size"] > 3.0:
				draw_circle(drop_pos, d["size"] * life_frac * 0.4,
							Color(1.0, 1.0, 1.0, alpha * 0.65))

func check_water_collision(player_pos: Vector2, player_velocity: Vector2) -> Dictionary:
	if not _env.get("has_water", false) or not wall_valid or ground_y == 0.0:
		return {"in_water": false, "depth": 0.0, "surface_y": 0.0,
				"drag": Vector2(1.0, 1.0), "buoyancy": 0.0}
	var t         = _water_time
	var surface_y = ground_y \
		- sin(player_pos.x * 0.011 + t * 0.95) * 9.5 \
		- sin(player_pos.x * 0.018 + t * 0.6)  * 4.0
	var in_water = player_pos.y > surface_y
	var depth    = maxf(0.0, player_pos.y - surface_y)
	if in_water:
		var depth_norm = clamp(depth / 280.0, 0.0, 1.0)
		var h_drag     = lerp(0.82, 0.62, depth_norm)
		var v_drag     = lerp(0.78, 0.55, depth_norm)
		var entry_speed = player_velocity.length()
		var speed_drag   = clamp(1.0 - entry_speed * 0.0003, 0.55, 1.0)
		if not _player_in_water:
			_player_in_water = true
			spawn_splash(Vector2(player_pos.x, surface_y), player_velocity.y)
			emit_signal("player_entered_water", depth)
		return {
			"in_water": true, "depth": depth, "surface_y": surface_y,
			"drag": Vector2(h_drag * speed_drag, v_drag * speed_drag),
			"buoyancy": lerp(0.0, 380.0, depth_norm),
		}
	else:
		if _player_in_water:
			_player_in_water = false
			emit_signal("player_exited_water")
		return {
			"in_water": false, "depth": 0.0, "surface_y": surface_y,
			"drag": Vector2(1.0, 1.0), "buoyancy": 0.0,
		}

func _draw_underwater_wall_depth() -> void:
	if not wall_valid: return
	var base_l: Vector2; var base_r: Vector2
	if use_polygon_mode and ground_left_index >= 0 and ground_right_index >= 0:
		base_l = control_points[ground_left_index]; base_r = control_points[ground_right_index]
	else:
		base_l = Vector2(wall_min.x, ground_y); base_r = Vector2(wall_max.x, ground_y)
	var water_y = ground_y
	var sub_top = water_y
	var sub_bot = (base_l.y + base_r.y) * 0.5
	if sub_bot > sub_top:
		var sub_h      = sub_bot - sub_top
		var water_tint = Color(0.04, 0.28, 0.60)
		for li in range(10):
			var t0      = float(li) / 10.0; var t1 = float(li + 1) / 10.0
			var shimmer = sin(_water_time * 1.4 + t0 * 8.0) * 0.016
			_draw_grad_quad(base_l.x, sub_top + t0 * sub_h, base_r.x - base_l.x, sub_top + t1 * sub_h,
				Color(water_tint.r, water_tint.g + shimmer, water_tint.b, lerp(0.04, 0.48, t0)),
				Color(water_tint.r, water_tint.g,           water_tint.b, lerp(0.04, 0.48, t1)))
	var depth_amount = 600.0
	var edge_vec     = base_r - base_l
	var edge_len     = edge_vec.length()
	if edge_len < 1.0: return
	var edge_dir = edge_vec / edge_len
	var perp     = Vector2(-edge_dir.y, edge_dir.x)
	if perp.y < 0.0: perp = -perp
	var segs          = 32
	var rock_col_top  = Color(0.22, 0.28, 0.30)
	var rock_col_deep = Color(0.04, 0.06, 0.08)
	var bot_pts: Array[Vector2] = []
	for si in range(segs + 1):
		var frac      = float(si) / float(segs)
		var base_pt   = base_l.lerp(base_r, frac)
		var rseed     = (_scenery_seed ^ 0xB0B0) + si * 19
		var depth_var = depth_amount * (0.75 + _hf(rseed) * 0.50)
		var side_jit  = (_hf(rseed + 1) - 0.5) * 18.0
		bot_pts.append(base_pt + perp * depth_var + edge_dir * side_jit)
	var slices = 12
	var wc     = Color(0.03, 0.18, 0.45)
	for pi in range(segs):
		var frac0 = float(pi)     / float(segs)
		var frac1 = float(pi + 1) / float(segs)
		var top0  = base_l.lerp(base_r, frac0); var top1 = base_l.lerp(base_r, frac1)
		var bot0  = bot_pts[pi];                var bot1  = bot_pts[pi + 1]
		for si in range(slices):
			var t0 = float(si)     / float(slices)
			var t1 = float(si + 1) / float(slices)
			var c0 = rock_col_top.lerp(rock_col_deep, t0)
			var c1 = rock_col_top.lerp(rock_col_deep, t1)
			var tl2 = top0.lerp(bot0, t0); var tr2 = top1.lerp(bot1, t0)
			var br2 = top1.lerp(bot1, t1); var bl2  = top0.lerp(bot0, t1)
			draw_polygon(PackedVector2Array([tl2, tr2, br2]), PackedColorArray([c0, c0, c1]))
			draw_polygon(PackedVector2Array([tl2, br2, bl2]), PackedColorArray([c0, c1, c1]))
			var ha0 = lerp(0.08, 0.55, t0); var ha1 = lerp(0.08, 0.55, t1)
			draw_polygon(PackedVector2Array([tl2, tr2, br2]), PackedColorArray([Color(wc,ha0), Color(wc,ha0), Color(wc,ha1)]))
			draw_polygon(PackedVector2Array([tl2, br2, bl2]), PackedColorArray([Color(wc,ha0), Color(wc,ha1), Color(wc,ha1)]))

# =============================================================================
# WALL TEXTURE & GRANITE
# =============================================================================

func draw_textured_wall(start_pos: Vector2, size: Vector2) -> void:
	var tile  = 128.0
	var cols  = int(ceil(size.x / tile)) + 1
	var rows  = int(ceil(size.y / tile)) + 1
	var gx    = floor(start_pos.x / tile) * tile
	var gy    = floor(start_pos.y / tile) * tile
	for x in cols:
		for y in rows:
			var px        = gx + x * tile
			var py        = gy + y * tile
			var tile_seed = int(px / tile) + int(py / tile) * 1000
			var v         = (_hf(tile_seed) - 0.5) * texture_variation
			var tr2       = Rect2(Vector2(px, py), Vector2(tile, tile))
			var wr        = Rect2(wall_min, wall_max - wall_min)
			var cl        = tr2.intersection(wr)
			if cl.has_area():
				draw_rect(cl, Color(
					current_wall_color.r + v,
					current_wall_color.g + v,
					current_wall_color.b + v,
					current_wall_color.a))

func draw_bolt_holes(_start_pos: Vector2, _end_pos: Vector2) -> void:
	return

func draw_bolt_holes_on_polygon() -> void:
	return

func _point_in_polygon(point: Vector2) -> bool:
	var inside = false; var j = control_points.size() - 1
	for i in range(control_points.size()):
		var pi = control_points[i]; var pj = control_points[j]
		if ((pi.y > point.y) != (pj.y > point.y)) and \
		   (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = not inside
		j = i
	return inside

func draw_granite_texture() -> void:
	var ws  = wall_max - wall_min
	var rs  = int(wall_min.x + wall_min.y)
	for i in range(int(ws.x / 200.0) + 2):
		var xp = wall_min.x + (float(i) / (int(ws.x / 200.0) + 2)) * ws.x + (hash(rs + i) % 50 - 25)
		if xp >= wall_min.x and xp <= wall_max.x:
			draw_line(Vector2(xp, wall_min.y), Vector2(xp, wall_max.y),
					  Color(0.45, 0.43, 0.4, 0.22), 1.5)

# =============================================================================
# EDITOR OVERLAYS
# =============================================================================

func _draw_edge_highlights() -> void:
	if hovered_edge < 0 or control_points.size() < 2: return
	if _is_ground_edge(hovered_edge): return
	var p1    = control_points[hovered_edge]
	var p2    = control_points[(hovered_edge + 1) % control_points.size()]
	var color = edge_hover_color
	var lt    = "RIGHT-CLICK: Add point | SHIFT+RIGHT-CLICK: Mark as TOP-OUT"
	if hovered_edge in top_edge_indices:
		color = Color(1.0, 0.5, 0.0, 0.9)
		lt    = "MARKED AS TOP-OUT | SHIFT+RIGHT-CLICK: Unmark"
	draw_line(p1, p2, color, 6.0, true)
	var mp   = get_global_mouse_position()
	var seg  = p2 - p1
	var slsq = seg.length_squared()
	if slsq > 0:
		var np = p1 + clamp((mp - p1).dot(seg) / slsq, 0.0, 1.0) * seg
		draw_circle(np, 6.0, color)
		var lp = np + Vector2(0, -30)
		var ls = ThemeDB.fallback_font.get_string_size(lt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_rect(Rect2(lp - Vector2(ls.x / 2 + 8, 8), ls + Vector2(16, 16)), Color(0, 0, 0, 0.85), true)
		draw_string(ThemeDB.fallback_font, lp, lt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, color)

func _draw_control_points() -> void:
	for i in range(control_points.size()):
		var pt    = control_points[i]
		var color = point_color
		if i == ground_left_index or i == ground_right_index: color = ground_point_color
		elif edit_mode:
			if dragging_point == i:  color = point_drag_color
			elif hovered_point == i: color = point_hover_color
		draw_circle(pt, POINT_RADIUS + 3, Color(0, 0, 0, 0.4))
		draw_circle(pt, POINT_RADIUS, color)
		draw_string(ThemeDB.fallback_font, pt + Vector2(-5, 6), str(i + 1),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	if edit_mode and control_points.size() > 0:
		var mk   = "" if top_edge_indices.is_empty() else " | MARKED: " + str(top_edge_indices)
		var text = "LEFT-DRAG: Move | RIGHT-CLICK: Add | SHIFT+RIGHT-CLICK on EDGE: Mark Top" + mk
		var pos  = Vector2(wall_min.x, wall_min.y - 40)
		var sz   = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_rect(Rect2(pos - Vector2(8, 22), sz + Vector2(16, 30)), Color(0, 0, 0, 0.8), true)
		draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.6))

# =============================================================================
# BOUNDS & POLYGON MANAGEMENT
# =============================================================================

func calculate_bounds_from_holds(holds_container: Node2D) -> void:
	print("calculate_bounds_from_holds called — holds: ", holds_container.get_child_count() if holds_container else "NULL CONTAINER")
	if not holds_container or holds_container.get_child_count() == 0:
		print("WARNING: no holds in container, wall_valid stays false")
		wall_valid = false
		queue_redraw()
		return
	var mn_x = INF; var mx_x = -INF; var mn_y = INF; var mx_y = -INF
	for hold in holds_container.get_children():
		if not hold is Node2D:
			continue
		var pos = hold.global_position
		mn_x = min(mn_x, pos.x); mx_x = max(mx_x, pos.x)
		mn_y = min(mn_y, pos.y); mx_y = max(mx_y, pos.y)
	wall_min  = Vector2(mn_x - WALL_PADDING_SIDES, mn_y - WALL_PADDING_TOP)
	wall_max  = Vector2(mx_x + WALL_PADDING_SIDES, mx_y + WALL_PADDING_BOTTOM)
	wall_valid = true
	ground_y   = wall_max.y
	print("calculate_bounds_from_holds DONE — wall_min: ", wall_min, " wall_max: ", wall_max, " ground_y: ", ground_y)
	if control_points.is_empty():
		control_points = [wall_min, Vector2(wall_max.x, wall_min.y),
						  Vector2(wall_max.x, wall_max.y), Vector2(wall_min.x, wall_max.y)]
		ground_left_index = 3; ground_right_index = 2; use_polygon_mode = true
	else:
		if ground_left_index  >= 0 and ground_left_index  < control_points.size():
			control_points[ground_left_index].y  = ground_y
		if ground_right_index >= 0 and ground_right_index < control_points.size():
			control_points[ground_right_index].y = ground_y
	if not top_edge_indices.is_empty():
		_create_top_edge_holds()
	if weather_modifier:
		weather_modifier._wall_ref = self
	_init_clouds()
	queue_redraw()

func _update_bounds_from_polygon() -> void:
	if control_points.is_empty(): return
	var mn_x = INF; var mx_x = -INF; var mn_y = INF; var mx_y = -INF
	for p in control_points:
		mn_x = min(mn_x, p.x); mx_x = max(mx_x, p.x)
		mn_y = min(mn_y, p.y); mx_y = max(mx_y, p.y)
	wall_min = Vector2(mn_x, mn_y); wall_max = Vector2(mx_x, mx_y); wall_valid = true

func add_point_between_nearest_edge(pos: Vector2) -> void:
	if control_points.size() < 2:
		control_points.append(pos); _update_bounds_from_polygon(); queue_redraw(); return
	var nei = -1; var ned = INF
	for i in range(control_points.size()):
		if _is_ground_edge(i): continue
		var d = _point_to_segment_distance(pos, control_points[i],
				control_points[(i + 1) % control_points.size()])
		if d < ned: ned = d; nei = i
	if nei < 0: return
	var ni = nei + 1; control_points.insert(ni, pos)
	if ground_left_index  >= ni: ground_left_index  += 1
	if ground_right_index >= ni: ground_right_index += 1
	var ute: Array[int] = []
	for ei in top_edge_indices: ute.append(ei + 1 if ei >= nei else ei)
	top_edge_indices = ute
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	queue_redraw()

func remove_point(index: int) -> void:
	if index == ground_left_index or index == ground_right_index:
		push_warning("Cannot remove ground points"); return
	if control_points.size() <= 4:
		push_warning("Cannot remove - need at least 4 points"); return
	if index >= 0 and index < control_points.size():
		control_points.remove_at(index)
		if ground_left_index  > index: ground_left_index  -= 1
		if ground_right_index > index: ground_right_index -= 1
		if dragging_point == index:    dragging_point = -1
		elif dragging_point > index:   dragging_point -= 1
		if hovered_point == index:     hovered_point = -1
		elif hovered_point > index:    hovered_point -= 1
		var ute: Array[int] = []
		for ei in top_edge_indices:
			if ei == index: continue
			ute.append(ei - 1 if ei > index else ei)
		top_edge_indices = ute
		_update_bounds_from_polygon()
		if not top_edge_indices.is_empty(): _create_top_edge_holds()
		queue_redraw()

func enable_polygon_mode(enabled: bool = true) -> void:
	use_polygon_mode = enabled
	if enabled and control_points.is_empty() and wall_valid:
		control_points = [wall_min, Vector2(wall_max.x, wall_min.y),
						  Vector2(wall_max.x, wall_max.y), Vector2(wall_min.x, wall_max.y)]
		ground_left_index = 3; ground_right_index = 2; ground_y = wall_max.y
	queue_redraw()

func enable_edit_mode(enabled: bool = true) -> void:
	edit_mode = enabled
	if not enabled: dragging_point = -1; hovered_point = -1; hovered_edge = -1
	queue_redraw()

func reset_polygon() -> void:
	use_polygon_mode = false; edit_mode = false
	control_points.clear(); top_edge_indices.clear()
	ground_left_index = -1; ground_right_index = -1
	dragging_point = -1; hovered_point = -1; hovered_edge = -1
	for child in get_children():
		if child.has_meta("is_top_edge_hold"): child.queue_free()
	queue_redraw()

func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var seg  = seg_end - seg_start
	var lsq  = seg.length_squared()
	if lsq == 0: return point.distance_to(seg_start)
	return point.distance_to(seg_start + clamp((point - seg_start).dot(seg) / lsq, 0.0, 1.0) * seg)

# =============================================================================
# TOP EDGE HOLD
# =============================================================================

func _create_top_edge_holds() -> void:
	for child in get_children():
		if child.has_meta("is_top_edge_hold"):
			child.set_script(null)
			child.free()
	if not use_polygon_mode or top_edge_indices.is_empty():
		return
	for edge_idx in top_edge_indices:
		if edge_idx >= control_points.size(): continue
		var p1 = control_points[edge_idx]
		var p2 = control_points[(edge_idx + 1) % control_points.size()]
		_create_top_hold_at((p1 + p2) / 2.0, p1.distance_to(p2))

func _create_top_hold_at(hold_position: Vector2, width: float) -> void:
	var top_hold            = _TopEdgeHold.new()
	top_hold.set_meta("is_top_edge_hold", true)
	top_hold.collision_layer = 2
	top_hold.collision_mask  = 0
	top_hold.monitoring      = false
	top_hold.monitorable     = true
	top_hold.name            = "TopEdgeHold"
	var shape       = RectangleShape2D.new()
	shape.size       = Vector2(width, 50)
	var collision   = CollisionShape2D.new()
	collision.shape  = shape
	top_hold.add_child(collision)
	var hold_point      = Marker2D.new()
	hold_point.name      = "HoldPoint"
	hold_point.position  = Vector2.ZERO
	top_hold.add_child(hold_point)
	top_hold.global_position = hold_position
	add_child(top_hold)
	top_hold.add_to_group("holds")


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

	func can_grab(_limb: Node2D, is_foot: bool) -> bool:
		return not is_foot

	func try_claim(limb: Node2D, is_foot: bool, snap_pos: Vector2) -> bool:
		if not can_grab(limb, is_foot): return false
		if limb.name == "LeftHand":
			claimed_left_hand = limb; left_hand_x = snap_pos.x
		elif limb.name == "RightHand":
			claimed_right_hand = limb; right_hand_x = snap_pos.x
		return true

	func release(limb: Node2D) -> void:
		if limb.name == "LeftHand"  and claimed_left_hand  == limb: claimed_left_hand  = null; left_hand_x  = 0.0
		elif limb.name == "RightHand" and claimed_right_hand == limb: claimed_right_hand = null; right_hand_x = 0.0

	func get_limb_anchor(limb: Node2D) -> Vector2:
		var x = left_hand_x  if (limb.name == "LeftHand"  and claimed_left_hand  == limb) \
				 else right_hand_x if (limb.name == "RightHand" and claimed_right_hand == limb) \
				 else limb.global_position.x
		return Vector2(x, global_position.y)

	func get_state_pressure(delta: float, _bo: float, _st: float, _fs: float, _limb: Node2D) -> float:
		return 0.5 * delta

	func get_recovery_rate(delta: float, body_balance: float, _fs: float) -> float:
		return 3.0 * delta * body_balance

# =============================================================================
# PUBLIC API
# =============================================================================

func get_bounds() -> Dictionary:
	return {"min": wall_min, "max": wall_max, "valid": wall_valid}

func get_top_edge_y() -> float:
	if use_polygon_mode and not top_edge_indices.is_empty():
		var ty = INF
		for ei in top_edge_indices:
			if ei >= control_points.size(): continue
			var p1 = control_points[ei]
			var p2 = control_points[(ei + 1) % control_points.size()]
			ty = min(ty, min(p1.y, p2.y))
		return ty if ty != INF else wall_min.y
	return wall_min.y

func get_wall_height() -> float: return ground_y - get_top_edge_y()
func get_wall_width()  -> float: return wall_max.x - wall_min.x

func get_anchor_position_for_x(world_x: float) -> Vector2:
	if use_polygon_mode and control_points.size() >= 3:
		var edges_to_check: Array[int] = []
		if not top_edge_indices.is_empty():
			edges_to_check = top_edge_indices.duplicate()
		else:
			for i in range(control_points.size()):
				if not _is_ground_edge(i): edges_to_check.append(i)
		var best_pos   = Vector2.ZERO
		var best_score = INF
		for ei in edges_to_check:
			if ei >= control_points.size(): continue
			var p1 = control_points[ei]
			var p2 = control_points[(ei + 1) % control_points.size()]
			var x_min = minf(p1.x, p2.x); var x_max = maxf(p1.x, p2.x)
			if x_max - x_min < 1.0: continue
			var clamped_x = clampf(world_x, x_min, x_max)
			var t         = clampf((clamped_x - p1.x) / (p2.x - p1.x), 0.0, 1.0)
			var on_edge   = p1.lerp(p2, t)
			var score     = on_edge.y + absf(world_x - clamped_x) * 0.5
			if score < best_score:
				best_score = score; best_pos = on_edge
		if best_score < INF: return best_pos
	return Vector2(clampf(world_x, wall_min.x, wall_max.x), wall_min.y)

func get_polygon_data() -> Dictionary:
	if not use_polygon_mode or control_points.is_empty(): return {}
	var pts = []
	for p in control_points: pts.append({"x": p.x, "y": p.y})
	return {"enabled": true, "points": pts,
			"ground_left_index": ground_left_index,
			"ground_right_index": ground_right_index,
			"top_edge_indices": top_edge_indices.duplicate()}

func set_polygon_data(data: Dictionary) -> void:
	if not data or data.is_empty() or not data.get("enabled", false): return
	use_polygon_mode = true
	control_points.clear()
	for pd in data.get("points", []):
		control_points.append(Vector2(pd.get("x", 0), pd.get("y", 0)))
	if control_points.size() < 3:
		push_warning("DynamicWall.set_polygon_data: fewer than 3 points, ignoring polygon")
		control_points.clear(); use_polygon_mode = false; return
	ground_left_index  = data.get("ground_left_index",  -1)
	ground_right_index = data.get("ground_right_index", -1)
	top_edge_indices.clear()
	for ei in data.get("top_edge_indices", []):
		if ei is float or ei is int: top_edge_indices.append(int(ei))
	if ground_left_index >= 0 and ground_left_index < control_points.size():
		ground_y = control_points[ground_left_index].y
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	if weather_modifier: weather_modifier._wall_ref = self
	_init_clouds()
	queue_redraw()
	print("  Polygon loaded: " + str(control_points.size()) + " points, " + str(top_edge_indices.size()) + " top edges")

# =============================================================================
# HELPERS
# =============================================================================

## Vertical gradient quad — top color fades to bottom color
func _draw_grad_quad(x: float, y0: float, w: float, y1: float,
					 c_top: Color, c_bot: Color) -> void:
	if w < 0.5 or absf(y1 - y0) < 0.5: return
	var tl = Vector2(x,     y0); var tr2 = Vector2(x + w, y0)
	var br2 = Vector2(x + w, y1); var bl  = Vector2(x,     y1)
	draw_polygon(PackedVector2Array([tl, tr2, br2]), PackedColorArray([c_top, c_top, c_bot]))
	draw_polygon(PackedVector2Array([tl, br2, bl]),  PackedColorArray([c_top, c_bot, c_bot]))

## Horizontal gradient quad — left color to right color
func _draw_grad_quad_h(x0: float, y0: float, x1: float, y1: float,
					   c_left: Color, c_right: Color) -> void:
	if absf(x1 - x0) < 0.5 or absf(y1 - y0) < 0.5: return
	var tl  = Vector2(x0, y0); var tr2 = Vector2(x1, y0)
	var br2 = Vector2(x1, y1); var bl   = Vector2(x0, y1)
	draw_polygon(PackedVector2Array([tl, tr2, br2]), PackedColorArray([c_left, c_right, c_right]))
	draw_polygon(PackedVector2Array([tl, br2, bl]),  PackedColorArray([c_left, c_right, c_left]))

## Polygon validity guard
func _polygon_valid(pts: PackedVector2Array) -> bool:
	if pts.size() < 3: return false
	for i in range(pts.size()):
		var a = pts[i]
		var b = pts[(i + 1) % pts.size()]
		var c = pts[(i + 2) % pts.size()]
		if abs((b - a).cross(c - a)) > 0.01: return true
	return false

func _hf(v: int) -> float:
	return float(hash(v) % 10000) / 10000.0

func hash_to_float(v: int) -> float:
	return _hf(v)
