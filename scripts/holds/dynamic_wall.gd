extends Node2D
class_name DynamicWall

var wall_texture_enabled := true
var texture_variation := 0.05

var hole_spacing := Vector2(64, 64)
var hole_radius := 2.5
var hole_color := Color(0.15, 0.15, 0.15)
var hole_jitter := 4.0

var edge_color := Color(0.2, 0.2, 0.25)
var edge_thickness := 8.0
var top_edge_color := Color(0.9, 0.4, 0.2)

var wall_min := Vector2.ZERO
var wall_max := Vector2.ZERO
var wall_valid := false

const WALL_PADDING_TOP = 100.0
const WALL_PADDING_BOTTOM = 150.0
const WALL_PADDING_SIDES = 100.0
const BACKGROUND_EXPANSION = 2000.0

@export var use_polygon_mode: bool = false
@export var edit_mode: bool = false
var control_points: Array[Vector2] = []

var ground_y: float = 0.0
var ground_left_index: int = -1
var ground_right_index: int = -1
var top_edge_indices: Array[int] = []

var point_color := Color(0.7, 0.7, 0.7, 0.6)
var point_hover_color := Color(1, 0.7, 0, 1.0)
var point_drag_color := Color(1, 1, 0, 1.0)
var ground_point_color := Color(0.3, 0.8, 0.3, 0.8)
var line_color := Color(0.4, 0.7, 1.0, 0.6)
var edge_hover_color := Color(0.6, 0.9, 1.0, 0.8)

const POINT_RADIUS = 10.0
const POINT_GRAB_RADIUS = 20.0
const EDGE_CLICK_DISTANCE = 15.0

var hovered_point: int = -1
var dragging_point: int = -1
var drag_offset: Vector2 = Vector2.ZERO
var hovered_edge: int = -1

var current_wall_color: Color = Color(0.82, 0.75, 0.62)
var background_color: Color = Color(0.53, 0.81, 0.92)
var show_bolt_holes: bool = true
var is_granite: bool = false
var current_environment: String = "gym"
var is_in_editor: bool = false

var ground_enabled := true
var ground_height := 1000.0
var ground_color := Color(0.298, 0.298, 0.298, 1.0)

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

# ─── Splash particles ─────────────────────────────────────────────────────────
var _splashes: Array[Dictionary] = []
const SPLASH_DURATION := 1.4
const SPLASH_DROPLET_COUNT := 22
# Each droplet: { x, y, vx, vy, life, max_life, size }
# ─────────────────────────────────────────────────────────────────────────────

# ─── Weather ──────────────────────────────────────────────────────────────────
var weather_modifier: Node2D = null
# ─────────────────────────────────────────────────────────────────────────────

func _ready():
	z_index = -10
	add_to_group("environment_walls")
	_scenery_seed = randi()
	_init_clouds()
	_init_weather()
	call_deferred("update_environment_settings")

var _redraw_timer: float = 0.0
const REDRAW_INTERVAL = 0.05

func _process(delta: float):
	_redraw_timer += delta
	if _redraw_timer < REDRAW_INTERVAL:
		return
	_redraw_timer = 0.0

	# Always animate when rain is blending (even if no other animation)
	var rain_blend := _get_weather_blend()
	var has_animation = _env.get("has_stars", false) \
		or (_env.get("cloud_color", Color(1,1,1)).a > 0.02) \
		or _env.get("has_gym_interior", false) \
		or _env.get("has_water", false) \
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

## Returns 0–1 blend from WeatherModifier, or 0 if none loaded.
func _get_weather_blend() -> float:
	if weather_modifier and weather_modifier.has_method("get_blend"):
		return weather_modifier.get_blend()
	return 0.0

## Returns the rain sky override dict, or empty dict if none / not raining.
func _get_rain_override() -> Dictionary:
	if weather_modifier and weather_modifier.has_method("get_rain_sky_override"):
		return weather_modifier.get_rain_sky_override()
	return {}

# ─── Helper: blend a colour toward rain version ───────────────────────────────
func _rain_lerp_color(base: Color, key: String, blend: float) -> Color:
	var ov := _get_rain_override()
	if ov.is_empty() or not key in ov or blend < 0.01:
		return base
	return base.lerp(ov[key], blend)

# ─────────────────────────────────────────────────────────────────────────────

func _init_clouds():
	_clouds.clear()
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(CLOUD_COUNT):
		_clouds.append(_make_cloud(rng, true))

func _make_cloud(rng: RandomNumberGenerator, initial_spread: bool) -> Dictionary:
	var layer = rng.randi() % CLOUD_LAYERS
	var bg_left  = wall_min.x - BACKGROUND_EXPANSION if wall_valid else -3000.0
	var bg_right = wall_max.x + BACKGROUND_EXPANSION if wall_valid else  3000.0
	var sky_top  = (wall_min.y - BACKGROUND_EXPANSION) if wall_valid else -2000.0
	var sky_bottom = ground_y - 120.0 if wall_valid else -400.0

	var sx    = 60.0 + rng.randf() * 220.0 + float(layer) * 50.0
	var sy    = 22.0 + rng.randf() * 38.0  + float(layer) * 8.0
	var speed = (0.18 + rng.randf() * 0.25) * (1.0 + float(layer) * 0.6) * 40.0
	var alpha = 0.4 + rng.randf() * 0.45
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

	var rain_blend := _get_weather_blend()

	for i in range(_clouds.size()):
		var c = _clouds[i]
		var speed_mult := 1.0 + rain_blend * 0.5
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
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world_pos.x * 7.0 + _water_time * 1000.0) ^ 0xBEEF
	var splash_speed = clamp(abs(entry_velocity) * 0.55, 120.0, 600.0)
	var droplets: Array = []
	for i in range(SPLASH_DROPLET_COUNT):
		# Spread outward in a wide cone upward
		var side := 1.0 if (i % 2 == 0) else -1.0
		var spread_frac := float(i) / float(SPLASH_DROPLET_COUNT)
		var angle_deg := 30.0 + spread_frac * 70.0   # 30° to 100° from vertical
		var angle_rad := deg_to_rad(angle_deg) * side
		var speed_frac := 0.5 + rng.randf() * 0.5
		var vx = sin(angle_rad) * splash_speed * speed_frac
		var vy = -cos(angle_rad) * splash_speed * speed_frac * (0.6 + rng.randf() * 0.4)
		# Extra small "crown" droplets
		var drop_size := 2.5 + rng.randf() * 4.5
		if spread_frac < 0.15:
			drop_size *= 1.6   # big central column drops
		var max_life := 0.4 + rng.randf() * 0.6
		droplets.append({
			"x": world_pos.x + rng.randf_range(-8.0, 8.0),
			"y": world_pos.y,
			"vx": vx,
			"vy": vy,
			"life": max_life,
			"max_life": max_life,
			"size": drop_size,
		})
	# Also add a few ring ripple markers
	_splashes.append({
		"pos": world_pos,
		"time": 0.0,
		"droplets": droplets,
		"ring_radius": 0.0,
	})

func _update_splashes(delta: float):
	var gravity := 800.0
	var to_remove: Array = []
	for i in range(_splashes.size()):
		var s = _splashes[i]
		s["time"] += delta
		s["ring_radius"] += delta * 120.0
		var all_dead := true
		for d in s["droplets"]:
			d["life"] -= delta
			if d["life"] > 0.0:
				all_dead = false
				d["x"] += d["vx"] * delta
				d["y"] += d["vy"] * delta
				d["vy"] += gravity * delta
				# Kill droplet if it goes back below water surface
				if d["y"] > s["pos"].y + 10.0:
					d["life"] = 0.0
		if s["time"] > SPLASH_DURATION:
			to_remove.append(i)
		elif all_dead:
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		_splashes.remove_at(to_remove[i])

# ─────────────────────────────────────────────────────────────────────────────

func set_editor_mode(enabled: bool):
	is_in_editor = enabled
	queue_redraw()

func update_environment_settings():
	var env_config := get_node_or_null("/root/EnvironmentConfig")
	if env_config == null:
		call_deferred("update_environment_settings")
		return
	var data = env_config.get_environment_data()
	current_wall_color = data.get("wall_color", Color(0.82, 0.75, 0.62))
	background_color   = data.get("background_color", Color(0.53, 0.81, 0.92))
	show_bolt_holes    = data.get("show_bolt_holes", false)
	is_granite         = data.get("show_granite_texture", false)
	current_environment = env_config.get_current_environment_name().to_lower()
	_apply_environment_theme()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	queue_redraw()

func _apply_environment_theme():
	match current_environment:
		"granite", "sandstone", "night":
			var time_of_day = (abs((_scenery_seed ^ 0x9E3779B9) * 1664525 + 1013904223) >> 7) % 3
			match time_of_day:
				1:  # Sunset / Sunrise
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
				2:  # Night
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
				_:  # Daytime (0)
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
				1:  # Gym — Dusk / Sunset outside the windows
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
				2:  # Gym — Night outside the windows
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
				_:  # Gym — Daytime outside the windows (0)
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

func _draw():
	if not wall_valid: return
	_draw_sky()
	if _env.get("has_stars", false): _draw_stars()
	if _env.get("has_sun", false) and _get_weather_blend() < 0.85: _draw_sun()
	if _env.get("has_moon", false): _draw_moon()
	if _env.get("has_mountains", false): _draw_mountains()
	_draw_clouds()
	_draw_fog()
	if _env.get("has_gym_interior", false): _draw_gym_interior()
	if _env.get("has_scaffold", false): _draw_scaffold()
	if use_polygon_mode and control_points.size() >= 3: _draw_polygon_wall()
	else: _draw_rectangle_wall()
	_draw_wall_base_shadow()
	if _env.get("has_water", false): _draw_underwater_wall_depth()
	if show_bolt_holes:
		if use_polygon_mode and control_points.size() >= 3: draw_bolt_holes_on_polygon()
		else: draw_bolt_holes(wall_min, wall_max)
	if is_granite and not use_polygon_mode: draw_granite_texture()
	if ground_enabled: _draw_ground()
	if _env.get("has_water", false):
		_draw_water_surface()
		_draw_splashes()
	draw_edges()
	if is_in_editor and use_polygon_mode and control_points.size() > 0: _draw_control_points()
	if is_in_editor and edit_mode and use_polygon_mode: _draw_edge_highlights()

func _draw_sky():
	var bl  = wall_min.x - BACKGROUND_EXPANSION
	var br  = wall_max.x + BACKGROUND_EXPANSION
	var st  = wall_min.y - BACKGROUND_EXPANSION
	var sw  = br - bl
	var rb  := _get_weather_blend()

	var col_top   := _rain_lerp_color(_env.get("sky_top",    background_color),              "sky_top",     rb)
	var col_horiz := _rain_lerp_color(_env.get("sky_horizon", background_color.lightened(0.15)), "sky_horizon", rb)

	var bands = 6
	for i in range(bands):
		var t  = float(i) / float(bands)
		var y0 = st + t * (ground_y - st)
		var h  = (ground_y - st) / float(bands) + 1.0
		draw_rect(Rect2(Vector2(bl, y0), Vector2(sw, h)), col_top.lerp(col_horiz, t), true)
	draw_rect(Rect2(Vector2(bl, ground_y), Vector2(sw, 99999.0)), col_horiz, true)

func _draw_stars():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var st = wall_min.y - BACKGROUND_EXPANSION
	var sw = br - bl
	var rb := _get_weather_blend()
	for i in range(80):
		var seed = (_scenery_seed ^ 0xBEEF) + i * 17
		var sx = bl + _hf(seed) * sw
		var sy = st + _hf(seed + 1) * (ground_y - st - 80.0)
		var bright  = (0.5 + _hf(seed + 2) * 0.5) * (1.0 - rb)
		var size    = 1.0 + _hf(seed + 3) * 2.0
		var twinkle = 0.7 + 0.3 * sin(_cloud_time * (1.5 + _hf(seed + 4) * 3.0) + float(i))
		draw_circle(Vector2(sx, sy), size, Color(1.0, 1.0, 1.0, bright * twinkle * 0.9))

func _draw_sun():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var sx = bl + (br - bl) * 0.78
	var sy = wall_min.y - BACKGROUND_EXPANSION * 0.5 + 180.0
	var sc: Color = _env.get("sun_color", Color(1.0, 0.95, 0.70))
	var fade := 1.0 - _get_weather_blend()
	for gi in range(6):
		draw_circle(Vector2(sx, sy), 52.0 + float(gi) * 30.0,
					Color(sc.r, sc.g, sc.b, (0.07 - float(gi) * 0.01) * fade))
	draw_circle(Vector2(sx, sy), 52.0, Color(sc.r, sc.g, sc.b, sc.a * fade))
	draw_circle(Vector2(sx, sy), 38.0, Color(1.0, 1.0, 0.96, fade))

func _draw_moon():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var mx = bl + (br - bl) * 0.72
	var my = wall_min.y - BACKGROUND_EXPANSION * 0.4 + 220.0
	var mr = 36.0
	for gi in range(4):
		draw_circle(Vector2(mx, my), mr + float(gi) * 22.0, Color(0.7, 0.75, 0.9, 0.06))
	draw_circle(Vector2(mx, my), mr, Color(0.88, 0.90, 0.95, 1.0))
	draw_circle(Vector2(mx + mr * 0.35, my - mr * 0.1), mr * 0.82, _env.get("sky_top", Color(0.02, 0.02, 0.08)))
	for ci in range(4):
		var cs = 6000 + ci * 37
		draw_circle(Vector2(mx - mr * 0.3 + _hf(cs) * mr * 0.5, my - mr * 0.2 + _hf(cs + 1) * mr * 0.4),
					2.0 + _hf(cs + 2) * 4.0, Color(0.70, 0.72, 0.78, 0.4))

func _draw_mountains():
	var bl  = wall_min.x - BACKGROUND_EXPANSION
	var br  = wall_max.x + BACKGROUND_EXPANSION
	var rb  := _get_weather_blend()
	var hs: Color = _rain_lerp_color(_env.get("sky_horizon", background_color), "sky_horizon", rb)
	var ht: Color = _rain_lerp_color(_env.get("sky_top",     background_color), "sky_top",     rb)
	_draw_hill_layer(bl, br, ground_y - 60.0, 240.0, 600.0, 90, hs.lerp(ht, 0.6).darkened(0.06), _scenery_seed ^ 0x0A1B2C)
	_draw_hill_layer(bl, br, ground_y - 20.0, 160.0, 420.0, 80, hs.lerp(ht, 0.4).darkened(0.10), _scenery_seed ^ 0x1A2B3C)
	_draw_hill_layer(bl, br, ground_y - 5.0,   90.0, 230.0, 55, hs.darkened(0.25),               _scenery_seed ^ 0x4D5E6F)
	_draw_hill_layer(bl, br, ground_y,          40.0, 110.0, 45, hs.darkened(0.42),               _scenery_seed ^ 0x7F8A9B)

func _draw_hill_layer(left: float, right: float, base_y: float,
					  min_h: float, max_h: float, segs: int, color: Color, seed: int):
	var step = (right - left) / float(segs)
	var pts: PackedVector2Array = []
	pts.append(Vector2(left, base_y + 500.0))
	for i in range(segs + 1):
		var h0 = _hf(seed + (i - 1) * 7) * (max_h - min_h) + min_h
		var h1 = _hf(seed + i * 7) * (max_h - min_h) + min_h
		var h2 = _hf(seed + (i + 1) * 7) * (max_h - min_h) + min_h
		pts.append(Vector2(left + i * step, base_y - (h0 * 0.2 + h1 * 0.6 + h2 * 0.2)))
	pts.append(Vector2(right, base_y + 500.0))
	draw_colored_polygon(pts, color)

func _draw_clouds():
	var rb := _get_weather_blend()
	var base_cc: Color = _env.get("cloud_color", Color(1, 1, 1))
	var base_sc: Color = _env.get("cloud_shadow", Color(0.78, 0.84, 0.92))

	var cc := _rain_lerp_color(base_cc, "cloud_color",  rb)
	var sc := _rain_lerp_color(base_sc, "cloud_shadow", rb)

	if cc.a < 0.02: return

	if rb > 0.15:
		_draw_overcast_layer(rb, cc, sc)

	for layer in range(CLOUD_LAYERS):
		for c in _clouds:
			if c["layer"] != layer: continue
			var alpha_boost := 1.0 + rb * 0.5
			var ba = c["alpha"] * cc.a * alpha_boost
			ba = min(ba, 1.0)
			_draw_cloud_shape(c["x"], c["y"], c["sx"], c["sy"],
				Color(cc.r, cc.g, cc.b, ba),
				Color(sc.r, sc.g, sc.b, ba * 0.55),
				c["seed"], rb)

func _draw_overcast_layer(blend: float, cc: Color, sc: Color):
	var bl   = wall_min.x - BACKGROUND_EXPANSION
	var br   = wall_max.x + BACKGROUND_EXPANSION
	var sw   = br - bl
	var h    = blend * BACKGROUND_EXPANSION * 0.55
	var base = wall_min.y - BACKGROUND_EXPANSION * 0.25

	var steps := 8
	for i in range(steps):
		var t0 := float(i)     / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a0 = lerp(blend * 0.72, 0.0, t0)
		var a1 = lerp(blend * 0.72, 0.0, t1)
		var y0 = base + t0 * h
		var y1 = base + t1 * h
		var tl := Vector2(bl, y0); var tr := Vector2(br, y0)
		var br2 := Vector2(br, y1); var bl2 := Vector2(bl, y1)
		var c0  := Color(cc.r, cc.g, cc.b, a0)
		var c1  := Color(cc.r, cc.g, cc.b, a1)
		draw_polygon(PackedVector2Array([tl, tr, br2]), PackedColorArray([c0, c0, c1]))
		draw_polygon(PackedVector2Array([tl, br2, bl2]), PackedColorArray([c0, c1, c1]))

func _draw_cloud_shape(cx: float, cy: float, sx: float, sy: float,
					   color: Color, shadow: Color, seed: int, rain_blend: float = 0.0):
	var ry_mult := 1.0 + rain_blend * 0.35
	_draw_oval(cx, cy + sy * 0.38, sx * 0.85, sy * 0.52 * ry_mult, shadow)
	_draw_oval(cx, cy, sx, sy * ry_mult, color)
	var offsets = [
		Vector2(-sx * 0.32, -sy * 0.42), Vector2(sx * 0.30, -sy * 0.36),
		Vector2(0.0, -sy * 0.62),        Vector2(-sx * 0.52, -sy * 0.18),
		Vector2(sx * 0.48, -sy * 0.22),
	]
	var sizes = [0.50, 0.44, 0.48, 0.38, 0.36]
	for pi in range(offsets.size()):
		var wobble = Vector2((_hf(seed + pi * 3) - 0.5) * sx * 0.10,
							 (_hf(seed + pi * 3 + 1) - 0.5) * sy * 0.12)
		_draw_oval(cx + offsets[pi].x + wobble.x, cy + offsets[pi].y + wobble.y,
				   sx * sizes[pi], sy * (sizes[pi] + 0.1) * ry_mult, color)

func _draw_oval(cx: float, cy: float, rx: float, ry: float, color: Color):
	var steps = 18
	var pts: PackedVector2Array = []
	for i in range(steps):
		var angle = (float(i) / float(steps)) * TAU
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	draw_colored_polygon(pts, color)

# ─── Fog — gradient polygons, no flat opacity rect ────────────────────────────
func _draw_fog():
	var rb := _get_weather_blend()
	var base_fc: Color = _env.get("fog_color", Color(0, 0, 0, 0))
	var fc := _rain_lerp_color(base_fc, "fog_color", rb)
	if fc.a < 0.01: return
	var bl := wall_min.x - BACKGROUND_EXPANSION
	var br := wall_max.x + BACKGROUND_EXPANSION
	var bt := wall_min.y - BACKGROUND_EXPANSION
	var total_h := (ground_y + 99999.0) - bt

	# Gradient via triangle pairs: full alpha at sky, 35% less near ground.
	var steps := 8
	for i in range(steps):
		var t0 := float(i)     / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a0 := fc.a * (1.0 - t0 * 0.65)
		var a1 := fc.a * (1.0 - t1 * 0.65)
		var y0 := bt + t0 * total_h
		var y1 := bt + t1 * total_h
		var c0 := Color(fc.r, fc.g, fc.b, a0)
		var c1 := Color(fc.r, fc.g, fc.b, a1)
		var tl := Vector2(bl, y0); var tr2 := Vector2(br, y0)
		var br2 := Vector2(br, y1); var bl2 := Vector2(bl, y1)
		draw_polygon(PackedVector2Array([tl, tr2, br2]), PackedColorArray([c0, c0, c1]))
		draw_polygon(PackedVector2Array([tl, br2, bl2]), PackedColorArray([c0, c1, c1]))

func _draw_gym_interior():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var width = br - bl
	var vis_top = wall_min.y
	var vis_bot = ground_y
	var vis_h   = vis_bot - vis_top

	for i in range(8):
		var t = float(i) / 8.0
		draw_rect(Rect2(Vector2(bl, vis_top + t*vis_h), Vector2(width, vis_h/8.0+2.0)),
				  Color(0.93-t*0.03, 0.93-t*0.025, 0.94-t*0.02), true)

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

	var rb      := _get_weather_blend()
	var gym_tod = _env.get("gym_time_of_day", 0)

	var sky_top_c  : Color = _env.get("gym_sky_top",  Color(0.20, 0.44, 0.84))
	var sky_mid_c  : Color = _env.get("gym_sky_mid",  Color(0.44, 0.70, 0.93))
	var sky_haze_c : Color = _env.get("gym_sky_haze", Color(0.70, 0.86, 0.97))

	var rain_sky = Color(0.18, 0.20, 0.26)
	sky_top_c  = sky_top_c.lerp(rain_sky,                       rb)
	sky_mid_c  = sky_mid_c.lerp(rain_sky.lightened(0.06),       rb)
	sky_haze_c = sky_haze_c.lerp(rain_sky.lightened(0.12),      rb)

	var sun_wx = wall_min.x + (wall_max.x - wall_min.x) * 0.68 + cam_x * 0.03
	var gym_sun_color : Color = _env.get("gym_sun_color", Color(1.0, 0.96, 0.78))

	var sun_y_frac := 0.15
	if gym_tod == 1:
		sun_y_frac = 0.72

	var gym_mtn_colors: Array = _env.get("gym_mtn_colors", [
		Color(0.72, 0.82, 0.91), Color(0.54, 0.67, 0.80),
		Color(0.38, 0.52, 0.66), Color(0.24, 0.38, 0.53),
	])
	var gym_grass_color : Color = _env.get("gym_grass_color", Color(0.18, 0.26, 0.19))
	gym_grass_color = gym_grass_color.lerp(Color(0.12, 0.18, 0.14), rb * 0.5)

	for wi in range(win_count):
		var wx  = bl + float(wi) * win_stride + win_gap * 0.5
		var wx2 = wx + win_w

		# ── Sky gradient inside window ────────────────────────────────────────
		for gi in range(10):
			var gt = float(gi) / 10.0
			var sc: Color
			if gt < 0.5:
				sc = sky_top_c.lerp(sky_mid_c, gt * 2.0)
			else:
				sc = sky_mid_c.lerp(sky_haze_c, (gt - 0.5) * 2.0)
			draw_rect(Rect2(Vector2(wx, win_top + gt*win_h), Vector2(win_w, win_h/10.0+1.0)), sc, true)

		# ── Stars (night only) ────────────────────────────────────────────────
		if _env.get("has_gym_stars", false):
			for si in range(30):
				var sseed = (_scenery_seed ^ 0xCAFE) + wi * 97 + si * 13
				var sx2   = wx + _hf(sseed) * win_w
				var sy2   = win_top + _hf(sseed + 1) * win_h * 0.6
				var salp  = 0.4 + _hf(sseed + 2) * 0.55
				var ssize = 1.0 + _hf(sseed + 3) * 1.8
				var twinkle = 0.7 + 0.3 * sin(_cloud_time * (1.5 + _hf(sseed + 4) * 3.0) + float(si))
				draw_circle(Vector2(sx2, sy2), ssize, Color(1.0, 1.0, 1.0, salp * twinkle * (1.0 - rb)))

		# ── Moon (night only) — exactly ONE window chosen by seed ─────────────
		var moon_win_idx = (_scenery_seed ^ 0xF00F) % max(win_count, 1)
		if _env.get("has_gym_moon", false) and wi == moon_win_idx:
			var mseed = _scenery_seed ^ 0xF00F
			var mx2   = wx + win_w * (0.35 + _hf(mseed) * 0.30)
			var my2   = win_top + win_h * (0.12 + _hf(mseed + 1) * 0.22)
			var mr    = 20.0 + _hf(mseed + 2) * 10.0
			for gi in range(3):
				draw_circle(Vector2(mx2, my2), mr + float(gi) * 14.0, Color(0.7, 0.75, 0.9, 0.05))
			draw_circle(Vector2(mx2, my2), mr, Color(0.88, 0.90, 0.95, 0.92 * (1.0 - rb)))
			draw_circle(Vector2(mx2 + mr * 0.35, my2 - mr * 0.1), mr * 0.82, sky_top_c)
		# ── Sun disc (day or dusk, not night) ────────────────────────────────
		var show_sun = gym_tod != 2 and gym_sun_color.r + gym_sun_color.g + gym_sun_color.b > 0.05
		if show_sun and rb < 0.85 and sun_wx >= wx + 20.0 and sun_wx <= wx2 - 20.0:
			var sun_y = win_top + win_h * sun_y_frac
			var sfade := 1.0 - rb
			for ri in range(6):
				draw_circle(Vector2(sun_wx, sun_y), 8.0 + ri * 20.0,
							Color(gym_sun_color.r, gym_sun_color.g, gym_sun_color.b,
								  (0.048 - ri * 0.007) * sfade))
			draw_circle(Vector2(sun_wx, sun_y), 10.0,
						Color(gym_sun_color.r + 0.05, gym_sun_color.g + 0.02, gym_sun_color.b * 0.8,
							  0.72 * sfade))
			if gym_tod == 1:
				var glow_y = sun_y - 4.0
				var glow_steps := 8
				for gsi in range(glow_steps):
					var gt = float(gsi) / float(glow_steps)
					var ga = lerp(0.22, 0.0, gt) * sfade
					draw_rect(Rect2(Vector2(wx, glow_y + gt * 40.0), Vector2(win_w, 40.0 / float(glow_steps) + 1.0)),
							  Color(gym_sun_color.r, gym_sun_color.g * 0.6, 0.05, ga), true)

		if rb > 0.05:
			_draw_window_rain_streaks(wx, wx2, win_top, win_bot, rb)

		# ── Mountain silhouettes ──────────────────────────────────────────────
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
			if mpts.size() >= 4: draw_colored_polygon(mpts, mcol)

		# ── Ground strip at base of window ────────────────────────────────────
		var gnd_h   = win_h * 0.09
		var gsegs   = 40
		var gstep   = win_w / float(gsegs)
		var gpts    = PackedVector2Array()
		gpts.append(Vector2(wx, win_bot + 4.0))
		for gi2 in range(gsegs + 1):
			var gseed = (_scenery_seed ^ 0x9F01) + wi*37 + gi2*5
			var gx2   = clamp(wx + gi2 * gstep, wx, wx2)
			var gh    = gnd_h * (0.6 + _hf(gseed) * 0.4)
			gpts.append(Vector2(gx2, win_bot - gh))
		gpts.append(Vector2(wx2, win_bot + 4.0))
		if gpts.size() >= 4:
			draw_colored_polygon(gpts, gym_grass_color)
		draw_rect(Rect2(Vector2(wx, win_bot - gnd_h * 0.6), Vector2(win_w, gnd_h * 0.6 + 6.0)),
				  gym_grass_color.darkened(0.18), true)

		# ── Window glass glare / reflection ───────────────────────────────────
		draw_rect(Rect2(Vector2(wx, win_top), Vector2(win_w, win_h)), Color(1.0, 1.0, 1.0, 0.10), true)
		draw_rect(Rect2(Vector2(wx, win_top), Vector2(win_w*0.10, win_h)), Color(1.0, 1.0, 1.0, 0.07), true)
		draw_rect(Rect2(Vector2(wx, win_top), Vector2(win_w*0.04, win_h)), Color(1.0, 1.0, 1.0, 0.05), true)

	# ── Interior wall panels between windows ──────────────────────────────────
	for wi in range(win_count + 1):
		var gx = bl + float(wi) * win_stride + win_gap * 0.5 - win_gap
		draw_rect(Rect2(Vector2(gx, vis_top), Vector2(win_gap + 4.0, vis_h)), wall_col, true)
	draw_rect(Rect2(Vector2(bl, vis_top), Vector2(width, win_top - vis_top + 1.0)), wall_col, true)
	draw_rect(Rect2(Vector2(bl, win_bot - 1.0), Vector2(width, vis_bot - win_bot + 2.0)), wall_col, true)

	# ── Window frames ─────────────────────────────────────────────────────────
	for wi in range(win_count):
		var wx  = bl + float(wi) * win_stride + win_gap * 0.5
		var fc  = Color(0.15, 0.16, 0.19)
		var ft  = 10.0
		draw_rect(Rect2(Vector2(wx-ft, win_top-ft), Vector2(win_w+ft*2.0, ft)), fc, true)
		draw_rect(Rect2(Vector2(wx-ft, win_bot),    Vector2(win_w+ft*2.0, ft)), fc, true)
		draw_rect(Rect2(Vector2(wx-ft, win_top-ft), Vector2(ft, win_h+ft*2.0)), fc, true)
		draw_rect(Rect2(Vector2(wx+win_w, win_top-ft), Vector2(ft, win_h+ft*2.0)), fc, true)
		draw_line(Vector2(wx, win_top), Vector2(wx+win_w, win_top), Color(0.55,0.57,0.62), 2.0, true)
		draw_line(Vector2(wx, win_top), Vector2(wx, win_bot),       Color(0.55,0.57,0.62), 2.0, true)
		draw_line(Vector2(wx+12.0, win_top+14.0), Vector2(wx+62.0, win_top+14.0), Color(1.0,1.0,1.0,0.24), 3.0, true)
		draw_line(Vector2(wx+14.0, win_top+25.0), Vector2(wx+40.0, win_top+25.0), Color(1.0,1.0,1.0,0.11), 2.0, true)

	draw_rect(Rect2(Vector2(bl, vis_bot-28.0), Vector2(width, 28.0)), Color(0.22, 0.22, 0.24), true)
	for mi in range(int(ceil(width/900.0))+1):
		draw_line(Vector2(bl+mi*900.0, vis_bot-28.0), Vector2(bl+mi*900.0, vis_bot),
				  Color(0.17, 0.17, 0.19), 2.0, true)

# ─── Window rain — gradient fog + improved streaks, no flat rects ─────────────
func _draw_window_rain_streaks(wx: float, wx2: float, win_top: float, win_bot: float, blend: float):
	var win_h := win_bot - win_top
	var win_w := wx2 - wx

	# ── Gradient atmosphere tint — triangle pairs for correct interpolation ───
	var haze_steps := 8
	var haze_max_a := blend * 0.28
	for i in range(haze_steps):
		var t0 := float(i)     / float(haze_steps)
		var t1 := float(i + 1) / float(haze_steps)
		var a0 := haze_max_a * (t0 * t0)
		var a1 := haze_max_a * (t1 * t1)
		var y0 := win_top + t0 * win_h
		var y1 := win_top + t1 * win_h
		var c0 := Color(0.08, 0.11, 0.18, a0)
		var c1 := Color(0.10, 0.14, 0.22, a1)
		var tl := Vector2(wx, y0);  var tr2 := Vector2(wx2, y0)
		var br2 := Vector2(wx2, y1); var bl2 := Vector2(wx, y1)
		draw_polygon(PackedVector2Array([tl, tr2, br2]), PackedColorArray([c0, c0, c1]))
		draw_polygon(PackedVector2Array([tl, br2, bl2]), PackedColorArray([c0, c1, c1]))

	# ── Ground mist rising from sill ─────────────────────────────────────────
	var mist_col   := Color(0.55, 0.64, 0.78)
	var mist_h     := win_h * 0.16 * blend
	var mist_steps := 6
	for i in range(mist_steps):
		var t0 := float(i)     / float(mist_steps)
		var t1 := float(i + 1) / float(mist_steps)
		var a0 := blend * 0.12 * (1.0 - t0)
		var a1 := blend * 0.12 * (1.0 - t1)
		var y0 := win_bot - t0 * mist_h
		var y1 := win_bot - t1 * mist_h
		var c0 := Color(mist_col.r, mist_col.g, mist_col.b, a0)
		var c1 := Color(mist_col.r, mist_col.g, mist_col.b, a1)
		var tl := Vector2(wx, y0);  var tr2 := Vector2(wx2, y0)
		var br2 := Vector2(wx2, y1); var bl2 := Vector2(wx, y1)
		draw_polygon(PackedVector2Array([tl, tr2, br2]), PackedColorArray([c0, c0, c1]))
		draw_polygon(PackedVector2Array([tl, br2, bl2]), PackedColorArray([c0, c1, c1]))

	# ── Rain streaks on glass ─────────────────────────────────────────────────
	var streak_count := int(14.0 * blend)
	for si in range(streak_count):
		var sseed := (_scenery_seed ^ 0xF00D) + si * 41
		var sx    := wx + _hf(sseed) * win_w
		var slen  := 18.0 + _hf(sseed + 2) * 28.0
		var salp  := (0.07 + _hf(sseed + 3) * 0.13) * blend
		var period   := win_h / (40.0 + _hf(sseed + 4) * 30.0)
		var anim_y   := fmod(_cloud_time / period + _hf(sseed + 1), 1.0) * win_h
		var draw_y   := win_top + anim_y
		if draw_y + slen > win_bot: continue
		draw_line(Vector2(sx, draw_y), Vector2(sx + 1.5, draw_y + slen),
				  Color(0.65, 0.75, 0.92, salp), 1.0, true)
		if salp > 0.08:
			draw_circle(Vector2(sx + 0.75, draw_y + slen), 1.5,
						Color(0.75, 0.88, 1.0, salp * 0.7))

func _draw_scaffold():
	var post_inset = 28.0; var post_w = 18.0
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
	draw_line(Vector2(lx - post_w, top_y - beam_h), Vector2(rx + post_w, top_y - beam_h), post_hi, 2.0, true)
	var mid_y = top_y + (ground_y - top_y) * 0.5
	draw_rect(Rect2(Vector2(lx - post_w * 0.5, mid_y - 7.0), Vector2(rx - lx + post_w, 14.0)), beam_col, true)
	draw_line(Vector2(lx - post_w * 0.5, mid_y - 7.0), Vector2(rx + post_w * 0.5, mid_y - 7.0), post_hi, 1.5, true)
	var brace_col = Color(0.35, 0.26, 0.15, 0.9)
	draw_line(Vector2(lx, top_y + 60.0), Vector2(lx - 70.0, mid_y),    brace_col, 9.0, true)
	draw_line(Vector2(lx, mid_y + 30.0), Vector2(lx - 70.0, ground_y), brace_col, 9.0, true)
	draw_line(Vector2(rx, top_y + 60.0), Vector2(rx + 70.0, mid_y),    brace_col, 9.0, true)
	draw_line(Vector2(rx, mid_y + 30.0), Vector2(rx + 70.0, ground_y), brace_col, 9.0, true)
	for px in [lx, rx]:
		draw_rect(Rect2(Vector2(px - 22.0, ground_y - 8.0), Vector2(44.0, 22.0)), Color(0.50, 0.50, 0.52), true)
		draw_line(Vector2(px - 22.0, ground_y - 8.0), Vector2(px + 22.0, ground_y - 8.0), Color(0.65, 0.65, 0.67), 2.0, true)

func _draw_rectangle_wall():
	var ws = wall_max - wall_min
	if wall_texture_enabled: draw_textured_wall(wall_min, ws)
	else: draw_rect(Rect2(wall_min, ws), current_wall_color, true)

func _draw_polygon_wall():
	var pp = PackedVector2Array(control_points)
	draw_colored_polygon(pp, current_wall_color)
	if wall_texture_enabled:
		var p2: PackedVector2Array = PackedVector2Array()
		var cols: PackedColorArray = PackedColorArray()
		for i in range(pp.size()):
			p2.append(pp[i])
			var t = clamp((pp[i].y - wall_min.y) / max(wall_max.y - wall_min.y, 1.0), 0.0, 1.0)
			cols.append(Color(0.0, 0.0, 0.0, t * 0.09))
		draw_polygon(p2, cols)

func _draw_wall_base_shadow():
	if not wall_valid: return
	for i in range(6):
		draw_line(Vector2(wall_min.x, ground_y + i * 3.0),
				  Vector2(wall_max.x, ground_y + i * 3.0),
				  Color(0.0, 0.0, 0.0, 0.16 * (1.0 - float(i) / 6.0)), 4.0)

func _draw_underwater_wall_depth():
	if not wall_valid: return
	var base_l: Vector2; var base_r: Vector2
	if use_polygon_mode and ground_left_index >= 0 and ground_right_index >= 0:
		base_l = control_points[ground_left_index]; base_r = control_points[ground_right_index]
	else:
		base_l = Vector2(wall_min.x, ground_y); base_r = Vector2(wall_max.x, ground_y)
	var water_y = ground_y; var sub_top = water_y
	var sub_bot = (base_l.y + base_r.y) * 0.5
	if sub_bot > sub_top:
		var sub_h = sub_bot - sub_top; var water_tint = Color(0.04, 0.28, 0.60)
		for li in range(10):
			var t0=float(li)/10.0; var t1=float(li+1)/10.0
			var y0=sub_top+t0*sub_h; var y1=sub_top+t1*sub_h
			var shimmer=sin(_water_time*1.4+t0*8.0)*0.018
			var a0=lerp(0.04,0.48,t0); var a1=lerp(0.04,0.48,t1)
			var tl2=Vector2(base_l.x,y0); var tr2=Vector2(base_r.x,y0)
			var br2=Vector2(base_r.x,y1); var bl2=Vector2(base_l.x,y1)
			var c0=Color(water_tint.r,water_tint.g+shimmer,water_tint.b,a0)
			var c1=Color(water_tint.r,water_tint.g,water_tint.b,a1)
			draw_polygon(PackedVector2Array([tl2,tr2,br2]),PackedColorArray([c0,c0,c1]))
			draw_polygon(PackedVector2Array([tl2,br2,bl2]),PackedColorArray([c0,c1,c1]))
	var depth_amount=600.0; var edge_vec=base_r-base_l; var edge_len=edge_vec.length()
	if edge_len<1.0: return
	var edge_dir=edge_vec/edge_len; var perp=Vector2(-edge_dir.y,edge_dir.x)
	if perp.y<0.0: perp=-perp
	var segs=32; var rock_col_top=Color(0.22,0.28,0.30); var rock_col_deep=Color(0.04,0.06,0.08)
	var bot_pts: Array[Vector2]=[]
	for si in range(segs+1):
		var frac=float(si)/float(segs); var base_pt=base_l.lerp(base_r,frac)
		var rseed=(_scenery_seed^0xB0B0)+si*19
		var depth_var=depth_amount*(0.75+_hf(rseed)*0.50)
		var side_jit=(_hf(rseed+1)-0.5)*18.0
		bot_pts.append(base_pt+perp*depth_var+edge_dir*side_jit)
	var slices=12; var wc=Color(0.03,0.18,0.45)
	for pi in range(segs):
		var frac0=float(pi)/float(segs); var frac1=float(pi+1)/float(segs)
		var top0=base_l.lerp(base_r,frac0); var top1=base_l.lerp(base_r,frac1)
		var bot0=bot_pts[pi]; var bot1=bot_pts[pi+1]
		for si in range(slices):
			var t0=float(si)/float(slices); var t1=float(si+1)/float(slices)
			var c0=rock_col_top.lerp(rock_col_deep,t0); var c1=rock_col_top.lerp(rock_col_deep,t1)
			var tl=top0.lerp(bot0,t0); var tr=top1.lerp(bot1,t0)
			var br=top1.lerp(bot1,t1); var bl2=top0.lerp(bot0,t1)
			draw_polygon(PackedVector2Array([tl,tr,br]),PackedColorArray([c0,c0,c1]))
			draw_polygon(PackedVector2Array([tl,br,bl2]),PackedColorArray([c0,c1,c1]))
			var ha0=lerp(0.08,0.58,t0); var ha1=lerp(0.08,0.58,t1)
			var wc0=Color(wc.r,wc.g,wc.b,ha0); var wc1=Color(wc.r,wc.g,wc.b,ha1)
			draw_polygon(PackedVector2Array([tl,tr,br]),PackedColorArray([wc0,wc0,wc1]))
			draw_polygon(PackedVector2Array([tl,br,bl2]),PackedColorArray([wc0,wc1,wc1]))
	for li in range(5):
		var t=float(li+1)/6.0; var alp=lerp(0.22,0.04,t)
		var p_l=base_l.lerp(bot_pts[0],t); var p_r=base_r.lerp(bot_pts[segs],t)
		draw_line(p_l,p_r,Color(0.0,0.0,0.0,alp),2.0,true)
	draw_line(Vector2(base_l.x,ground_y),Vector2(base_r.x,ground_y),Color(0.55,0.85,1.0,0.40),2.5,true)

func draw_edges():
	if use_polygon_mode and control_points.size() >= 3:
		for i in range(control_points.size()):
			var p1 = control_points[i]; var p2 = control_points[(i + 1) % control_points.size()]
			var color = edge_color; var thickness = edge_thickness
			if is_in_editor and i in top_edge_indices:
				color = top_edge_color; thickness = edge_thickness + 2.0
			draw_line(p1, p2, color, thickness, true)
			draw_circle(p1, thickness * 0.5, color)
		draw_circle(control_points[control_points.size() - 1], edge_thickness * 0.5, edge_color)
	else:
		var tl = wall_min; var tr = Vector2(wall_max.x, wall_min.y)
		var bl = Vector2(wall_min.x, wall_max.y); var br = wall_max
		var sc = edge_color.darkened(0.3); var r = edge_thickness * 0.5
		draw_line(tl, bl, sc, edge_thickness, true); draw_line(tr, br, sc, edge_thickness, true)
		draw_line(tl, tr, edge_color, 4.0, true);    draw_line(bl, br, sc, 6.0, true)
		for pt in [tl, tr, bl, br]: draw_circle(pt, r, sc)

func _draw_ground():
	if not wall_valid: return
	match _env.get("ground_type", "grass"):
		"grass", "grass_dusk", "grass_night": _draw_ground_grass()
		"gym_floor": _draw_ground_gym()
		"water": _draw_ground_water()
		_: _draw_ground_grass()

func _draw_ground_grass():
	var left = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	var rb := _get_weather_blend()
	var cd: Color = _env.get("ground_deep", Color(0.20, 0.14, 0.08))
	var cm: Color = _env.get("ground_mid",  Color(0.32, 0.22, 0.12))
	var ct: Color = _env.get("ground_top",  Color(0.22, 0.52, 0.14))
	ct = ct.lerp(Color(0.14, 0.28, 0.10), rb * 0.55)
	cm = cm.lerp(Color(0.20, 0.16, 0.10), rb * 0.4)
	cd = cd.lerp(Color(0.14, 0.12, 0.08), rb * 0.3)

	draw_rect(Rect2(Vector2(left, ground_y + 32.0), Vector2(width, 99999.0)), cd, true)
	draw_rect(Rect2(Vector2(left, ground_y + 4.0),  Vector2(width, 30.0)), cm, true)
	for si in range(8):
		var seed = (_scenery_seed ^ 0x57AA) + si * 31
		var sy = ground_y + 7.0 + _hf(seed) * 22.0
		var sx_s = left + _hf(seed + 1) * width * 0.4
		var sx_e = sx_s + 80.0 + _hf(seed + 2) * 320.0
		draw_line(Vector2(sx_s, sy), Vector2(min(sx_e, right), sy),
				  Color(cd.r, cd.g, cd.b, 0.25 + _hf(seed + 3) * 0.20), 2.0, true)

	var gc = [ct.darkened(0.28), ct, ct.lightened(0.18)]
	var segs = 80; var step = width / float(segs)
	for pass_i in range(3):
		var seed = (_scenery_seed ^ 0x6A55) + pass_i * 200
		var amp = 10.0 - float(pass_i) * 2.5
		var oy  = float(pass_i) * 2.0
		var pts: PackedVector2Array = []
		pts.append(Vector2(left, ground_y + 26.0))
		for i in range(segs + 1):
			var gx = left + float(i) * step
			var h0 = _hf(seed + (i - 1) * 11) * amp
			var h1 = _hf(seed + i * 11) * amp
			var h2 = _hf(seed + (i + 1) * 11) * amp
			pts.append(Vector2(gx, ground_y - (h0 * 0.2 + h1 * 0.6 + h2 * 0.2) + oy))
		pts.append(Vector2(right, ground_y + 26.0))
		draw_colored_polygon(pts, gc[pass_i])

	draw_line(Vector2(left, ground_y), Vector2(right, ground_y), ct.lightened(0.35), 2.0, true)

	if rb > 0.1:
		_draw_ground_puddles(left, right, rb)

func _draw_ground_puddles(left: float, right: float, blend: float):
	var puddle_count := int(6.0 * blend)
	for pi in range(puddle_count):
		var pseed := (_scenery_seed ^ 0xAB12) + pi * 53
		var px    := left + _hf(pseed) * (right - left)
		var pw    := 60.0 + _hf(pseed + 1) * 140.0 * blend
		var ph    := 6.0 + _hf(pseed + 2) * 10.0
		var palp  := 0.22 * blend
		var shimmer := sin(_cloud_time * 1.8 + float(pi) * 2.1) * 0.06
		var water_col := Color(0.38 + shimmer, 0.48 + shimmer, 0.62, palp)
		var reflect   := Color(0.55, 0.65, 0.80, palp * 0.4)
		var steps := 16
		var pts: PackedVector2Array = []
		for si in range(steps):
			var a := (float(si) / float(steps)) * TAU
			pts.append(Vector2(px + cos(a) * pw, ground_y + 2.0 + sin(a) * ph))
		draw_colored_polygon(pts, water_col)
		draw_line(Vector2(px - pw * 0.3, ground_y + 1.0),
				  Vector2(px + pw * 0.3, ground_y + 1.0), reflect, 1.5, true)

func _draw_ground_gym():
	var left  = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	var ct: Color = _env.get("ground_top",  Color(0.22, 0.22, 0.24))
	var cd: Color = _env.get("ground_deep", Color(0.11, 0.11, 0.12))
	draw_rect(Rect2(Vector2(left, ground_y), Vector2(width, 99999.0)), ct, true)
	var tile_w = 200.0; var tile_count = int(ceil(width / tile_w)) + 1
	for ti in range(tile_count):
		var tx   = left + float(ti) * tile_w
		var seed = (_scenery_seed ^ 0xAABB) + ti * 7
		var v    = (_hf(seed) - 0.5) * 0.018
		draw_rect(Rect2(Vector2(tx+2.0, ground_y+1.0), Vector2(tile_w-4.0, 40.0)),
				  Color(ct.r+v, ct.g+v, ct.b+v+0.01), true)
		draw_line(Vector2(tx, ground_y), Vector2(tx, ground_y+42.0),
				  Color(cd.r, cd.g, cd.b, 0.8), 2.0, true)
	draw_line(Vector2(left, ground_y), Vector2(right, ground_y), Color(0.50, 0.50, 0.52, 0.9), 2.0, true)

func _draw_water_surface():
	if not wall_valid: return
	var bl := wall_min.x - BACKGROUND_EXPANSION
	var br := wall_max.x + BACKGROUND_EXPANSION
	var width := br - bl
	var t := _water_time

	var depth_layers := 8
	for di in range(depth_layers):
		var t0 := float(di) / float(depth_layers)
		var t1 := float(di + 1) / float(depth_layers)
		var y0 := ground_y + t0 * 160.0
		var y1 := ground_y + t1 * 160.0
		var a0 = lerp(0.55, 0.0, t0)
		var a1 = lerp(0.55, 0.0, t1)
		var c0 := Color(0.02, 0.22, 0.50, a0)
		var c1 := Color(0.01, 0.10, 0.28, a1)
		var tl := Vector2(bl, y0); var tr2 := Vector2(br, y0)
		var br2 := Vector2(br, y1); var bl2 := Vector2(bl, y1)
		draw_polygon(PackedVector2Array([tl, tr2, br2]), PackedColorArray([c0, c0, c1]))
		draw_polygon(PackedVector2Array([tl, br2, bl2]), PackedColorArray([c0, c1, c1]))

	var caustic_count := 6
	for ci in range(caustic_count):
		var cseed := (_scenery_seed ^ 0x4C00) + ci * 29
		var cx := bl + _hf(cseed) * width
		var cw := 35.0 + _hf(cseed + 1) * 80.0
		var cy := ground_y + 18.0 + _hf(cseed + 2) * 80.0
		var phase := t * (0.7 + _hf(cseed + 3) * 0.8) + _hf(cseed + 4) * TAU
		var alpha := 0.04 + 0.04 * sin(phase)
		alpha = max(0.0, alpha)
		var drift := sin(t * (0.3 + _hf(cseed + 5) * 0.4) + float(ci)) * 20.0
		_draw_oval(cx + drift, cy, cw, cw * 0.3, Color(0.4, 0.75, 1.0, alpha))

	var segs := 120
	var step := width / float(segs)
	for wi in range(4):
		var freq  := 0.008 + wi * 0.003
		var speed := 0.55 + wi * 0.30
		var amp   := 11.0 - wi * 2.2
		var yoff  := ground_y - 2.0 + wi * 3.0
		var phase := t * speed + wi * 1.3
		var wcol: Color
		match wi:
			0: wcol = Color(0.04, 0.24, 0.52, 0.80)
			1: wcol = Color(0.06, 0.30, 0.60, 0.86)
			2: wcol = Color(0.10, 0.38, 0.68, 0.90)
			_: wcol = Color(0.14, 0.46, 0.72, 0.94)
		var pts := PackedVector2Array()
		pts.append(Vector2(bl, ground_y + 300.0))
		for si in range(segs + 1):
			var x := bl + si * step
			var y := yoff - sin(x * freq + phase) * amp \
					 - sin(x * freq * 1.618 + phase * 0.7) * amp * 0.38 \
					 - sin(x * freq * 3.14 + phase * 1.3) * amp * 0.14
			pts.append(Vector2(x, y))
		pts.append(Vector2(br, ground_y + 300.0))
		draw_colored_polygon(pts, wcol)

	var spec_segs := 80
	var spec_step := width / float(spec_segs)
	for si in range(spec_segs):
		var sx := bl + si * spec_step
		var sy := ground_y - sin(sx * 0.011 + t * 0.9) * 9.0 \
				  - sin(sx * 0.019 + t * 0.55) * 3.5
		var spec_a = max(0.0, sin(sx * 0.011 + t * 0.9)) * 0.55
		if spec_a > 0.06:
			draw_circle(Vector2(sx, sy), 3.5 + sin(float(si) * 2.1) * 1.5,
						Color(0.92, 0.97, 1.0, spec_a))

	var foam_segs := 70
	var fstep := width / float(foam_segs)
	for fi in range(foam_segs):
		var fx := bl + fi * fstep
		var fy := ground_y - sin(fx * 0.011 + t * 0.95) * 8.5 \
				  - sin(fx * 0.018 + t * 0.6) * 3.5 + 5.0
		var sub_alpha = max(0.0, sin(fx * 0.011 + t * 0.95)) * 0.18
		if sub_alpha > 0.03:
			draw_circle(Vector2(fx, fy), 3.0 + sin(float(fi) * 1.9) * 1.2,
						Color(0.7, 0.85, 1.0, sub_alpha))
	for fi in range(foam_segs):
		var fx := bl + fi * fstep
		var fy := ground_y - sin(fx * 0.011 + t * 0.95) * 9.5 \
				  - sin(fx * 0.018 + t * 0.6) * 4.0 - 1.0
		var foam_alpha = max(0.0, sin(fx * 0.011 + t * 0.95)) * 0.42
		if foam_alpha > 0.05:
			draw_circle(Vector2(fx, fy), 4.5 + sin(float(fi) * 2.3) * 2.2,
						Color(1.0, 1.0, 1.0, foam_alpha))

	for gi in range(18):
		var gseed := (_scenery_seed ^ 0x7E00) + gi * 23
		var gx    := bl + _hf(gseed) * width
		var gphase:= t * (0.8 + _hf(gseed + 1) * 0.6) + _hf(gseed + 2) * TAU
		var gy    := ground_y - sin(gx * 0.009 + gphase) * 10.0 - 3.0
		var galp  = max(0.0, sin(gphase * 2.1)) * 0.55
		draw_circle(Vector2(gx, gy), 2.0 + _hf(gseed + 3) * 3.5,
					Color(1.0, 1.0, 1.0, galp * 0.65))

	for si in range(3):
		for side in [-1, 1]:
			var sx = (wall_min.x if side < 0 else wall_max.x) + side * 8.0
			var sy := ground_y - 6.0 + sin(t * 1.2 + si * 0.9) * 3.0
			draw_circle(Vector2(sx, sy), 3.0 + si * 2.0,
						Color(1.0, 1.0, 1.0, 0.18 - si * 0.05))

func _draw_splashes():
	for s in _splashes:
		var age = s["time"]

		var ring_r = s["ring_radius"]
		if ring_r < 250.0:
			var ring_alpha = (1.0 - ring_r / 250.0) * 0.55
			var ring_steps := 24
			var last_pt := Vector2.ZERO
			for ri in range(ring_steps + 1):
				var angle := (float(ri) / float(ring_steps)) * TAU
				var pt := Vector2(
					s["pos"].x + cos(angle) * ring_r,
					s["pos"].y + sin(angle) * ring_r * 0.35
				)
				if ri > 0:
					draw_line(last_pt, pt, Color(0.7, 0.88, 1.0, ring_alpha), 1.5, true)
				last_pt = pt

		var ring2_r = max(0.0, ring_r - 40.0)
		if ring2_r > 0.0 and ring2_r < 180.0:
			var ring2_alpha = (1.0 - ring2_r / 180.0) * 0.35
			var ring_steps := 20
			var last_pt := Vector2.ZERO
			for ri in range(ring_steps + 1):
				var angle := (float(ri) / float(ring_steps)) * TAU
				var pt := Vector2(
					s["pos"].x + cos(angle) * ring2_r,
					s["pos"].y + sin(angle) * ring2_r * 0.3
				)
				if ri > 0:
					draw_line(last_pt, pt, Color(0.85, 0.95, 1.0, ring2_alpha), 1.0, true)
				last_pt = pt

		for d in s["droplets"]:
			if d["life"] <= 0.0:
				continue
			var life_frac = d["life"] / d["max_life"]
			var alpha = life_frac * 0.85
			var drop_pos := Vector2(d["x"], d["y"])
			var spd := Vector2(d["vx"], d["vy"]).length()
			if spd > 80.0:
				var tail_len = min(spd * 0.04, 12.0)
				var vel_dir := Vector2(d["vx"], d["vy"]).normalized()
				draw_line(drop_pos, drop_pos - vel_dir * tail_len,
						  Color(0.7, 0.88, 1.0, alpha * 0.5), 1.2, true)
			draw_circle(drop_pos, d["size"] * life_frac, Color(0.82, 0.94, 1.0, alpha))
			if d["size"] > 3.0:
				draw_circle(drop_pos, d["size"] * life_frac * 0.4,
							Color(1.0, 1.0, 1.0, alpha * 0.7))

func check_water_collision(player_pos: Vector2, player_velocity: Vector2) -> Dictionary:
	if not _env.get("has_water", false) or not wall_valid or ground_y == 0.0:
		return {"in_water": false, "depth": 0.0, "surface_y": 0.0,
				"drag": Vector2(1.0, 1.0), "buoyancy": 0.0}

	var t := _water_time
	var surface_y := ground_y \
		- sin(player_pos.x * 0.011 + t * 0.95) * 9.5 \
		- sin(player_pos.x * 0.018 + t * 0.6) * 4.0
	var in_water := player_pos.y > surface_y
	var depth = max(0.0, player_pos.y - surface_y)

	if in_water:
		var depth_norm = clamp(depth / 280.0, 0.0, 1.0)
		var h_drag = lerp(0.82, 0.62, depth_norm)
		var v_drag = lerp(0.78, 0.55, depth_norm)
		var entry_speed := player_velocity.length()
		var speed_drag = clamp(1.0 - entry_speed * 0.0003, 0.55, 1.0)

		if not _player_in_water:
			_player_in_water = true
			spawn_splash(Vector2(player_pos.x, surface_y), player_velocity.y)
			emit_signal("player_entered_water", depth)

		return {
			"in_water": true,
			"depth": depth,
			"surface_y": surface_y,
			"drag": Vector2(h_drag * speed_drag, v_drag * speed_drag),
			"buoyancy": lerp(0.0, 380.0, depth_norm),
		}
	else:
		if _player_in_water:
			_player_in_water = false
			emit_signal("player_exited_water")
		return {
			"in_water": false,
			"depth": 0.0,
			"surface_y": surface_y,
			"drag": Vector2(1.0, 1.0),
			"buoyancy": 0.0,
		}

func _draw_ground_water():
	var left=wall_min.x-BACKGROUND_EXPANSION; var right=wall_max.x+BACKGROUND_EXPANSION
	var width=right-left
	draw_rect(Rect2(Vector2(left,ground_y),Vector2(width,99999.0)),Color(0.01,0.06,0.16),true)
	var depth_bands=16; var band_h=90.0
	for di in range(depth_bands):
		var t=float(di)/float(depth_bands-1); var dy=ground_y+di*band_h
		var col=Color(lerp(0.06,0.01,t),lerp(0.32,0.04,t),lerp(0.62,0.10,t),1.0)
		draw_rect(Rect2(Vector2(left,dy),Vector2(width,band_h+1.0)),col,true)
	for ci in range(8):
		var cseed=(_scenery_seed^0x3C00)+ci*17; var cx=left+_hf(cseed)*width
		var calp=0.04+_hf(cseed+1)*0.04; var cw=30.0+_hf(cseed+2)*60.0
		var cdep=200.0+_hf(cseed+3)*300.0
		var pts=PackedVector2Array([Vector2(cx-cw*0.5,ground_y),Vector2(cx+cw*0.5,ground_y),
								   Vector2(cx+cw*0.8,ground_y+cdep),Vector2(cx-cw*0.8,ground_y+cdep)])
		draw_colored_polygon(pts,Color(0.30,0.65,0.90,calp))

func draw_textured_wall(start_pos: Vector2, size: Vector2):
	var tile:=128.0; var cols:=int(ceil(size.x/tile))+1; var rows:=int(ceil(size.y/tile))+1
	var gx=floor(start_pos.x/tile)*tile; var gy=floor(start_pos.y/tile)*tile
	for x in cols:
		for y in rows:
			var px=gx+x*tile; var py=gy+y*tile
			var seed:=int(px/tile)+int(py/tile)*1000
			var v:=(_hf(seed)-0.5)*texture_variation
			var tr2=Rect2(Vector2(px,py),Vector2(tile,tile))
			var wr=Rect2(wall_min,wall_max-wall_min)
			var cl=tr2.intersection(wr)
			if cl.has_area():
				draw_rect(cl,Color(current_wall_color.r+v,current_wall_color.g+v,
								   current_wall_color.b+v,current_wall_color.a))

func draw_bolt_holes(start_pos: Vector2, end_pos: Vector2):
	var margin=15.0
	var dmx=start_pos.x+margin; var dMx=end_pos.x-margin
	var dmy=start_pos.y+margin; var dMy=end_pos.y-margin
	var sx=floor(dmx/hole_spacing.x)*hole_spacing.x; var sy=floor(dmy/hole_spacing.y)*hole_spacing.y
	var x=sx
	while x<=ceil(dMx/hole_spacing.x)*hole_spacing.x:
		var y=sy
		while y<=ceil(dMy/hole_spacing.y)*hole_spacing.y:
			var seed:=int(x/hole_spacing.x)+int(y/hole_spacing.y)*1000
			var hp=Vector2(x,y)+Vector2((_hf(seed)-0.5)*hole_jitter,(_hf(seed+1)-0.5)*hole_jitter)
			if hp.x>=dmx and hp.x<=dMx and hp.y>=dmy and hp.y<=dMy:
				draw_circle(hp,hole_radius,hole_color)
			y+=hole_spacing.y
		x+=hole_spacing.x

func draw_bolt_holes_on_polygon():
	if control_points.size()<3: return
	var margin=15.0
	var dmx=wall_min.x+margin; var dMx=wall_max.x-margin
	var dmy=wall_min.y+margin; var dMy=wall_max.y-margin
	var sx=floor(dmx/hole_spacing.x)*hole_spacing.x; var sy=floor(dmy/hole_spacing.y)*hole_spacing.y
	var x=sx
	while x<=ceil(dMx/hole_spacing.x)*hole_spacing.x:
		var y=sy
		while y<=ceil(dMy/hole_spacing.y)*hole_spacing.y:
			var seed:=int(x/hole_spacing.x)+int(y/hole_spacing.y)*1000
			var hp=Vector2(x,y)+Vector2((_hf(seed)-0.5)*hole_jitter,(_hf(seed+1)-0.5)*hole_jitter)
			if _point_in_polygon(hp): draw_circle(hp,hole_radius,hole_color)
			y+=hole_spacing.y
		x+=hole_spacing.x

func _point_in_polygon(point: Vector2) -> bool:
	var inside=false; var j=control_points.size()-1
	for i in range(control_points.size()):
		var pi=control_points[i]; var pj=control_points[j]
		if ((pi.y>point.y)!=(pj.y>point.y)) and \
		   (point.x<(pj.x-pi.x)*(point.y-pi.y)/(pj.y-pi.y)+pi.x):
			inside=not inside
		j=i
	return inside

func draw_granite_texture():
	var ws=wall_max-wall_min; var rs=int(wall_min.x+wall_min.y)
	for i in range(int(ws.x/200.0)+2):
		var xp=wall_min.x+(float(i)/(int(ws.x/200.0)+2))*ws.x+(hash(rs+i)%50-25)
		if xp>=wall_min.x and xp<=wall_max.x:
			draw_line(Vector2(xp,wall_min.y),Vector2(xp,wall_max.y),Color(0.45,0.43,0.4,0.3),2.0)

func _draw_edge_highlights():
	if hovered_edge<0 or control_points.size()<2: return
	if _is_ground_edge(hovered_edge): return
	var p1=control_points[hovered_edge]; var p2=control_points[(hovered_edge+1)%control_points.size()]
	var color=edge_hover_color; var lt="RIGHT-CLICK: Add point | SHIFT+RIGHT-CLICK: Mark as TOP-OUT"
	if hovered_edge in top_edge_indices:
		color=Color(1.0,0.5,0.0,0.9); lt="MARKED AS TOP-OUT | SHIFT+RIGHT-CLICK: Unmark"
	draw_line(p1,p2,color,8.0,true)
	var mp=get_global_mouse_position(); var seg=p2-p1; var slsq=seg.length_squared()
	if slsq>0:
		var np=p1+clamp((mp-p1).dot(seg)/slsq,0.0,1.0)*seg
		draw_circle(np,8.0,color)
		var lp=np+Vector2(0,-30)
		var ls=ThemeDB.fallback_font.get_string_size(lt,HORIZONTAL_ALIGNMENT_CENTER,-1,14)
		draw_rect(Rect2(lp-Vector2(ls.x/2+8,8),ls+Vector2(16,16)),Color(0,0,0,0.9),true)
		draw_string(ThemeDB.fallback_font,lp,lt,HORIZONTAL_ALIGNMENT_CENTER,-1,14,color)

func _draw_control_points():
	for i in range(control_points.size()):
		var pt=control_points[i]; var color=point_color
		if i==ground_left_index or i==ground_right_index: color=ground_point_color
		elif edit_mode:
			if dragging_point==i: color=point_drag_color
			elif hovered_point==i: color=point_hover_color
		draw_circle(pt,POINT_RADIUS+3,Color(0,0,0,0.5))
		draw_circle(pt,POINT_RADIUS,color)
		draw_string(ThemeDB.fallback_font,pt+Vector2(-5,6),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	if edit_mode and control_points.size()>0:
		var mk="" if top_edge_indices.is_empty() else " | MARKED: "+str(top_edge_indices)
		var text="LEFT-DRAG: Move | RIGHT-CLICK: Add | SHIFT+RIGHT-CLICK on EDGE: Mark Top"+mk
		var pos=Vector2(wall_min.x,wall_min.y-40)
		var sz=ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16)
		draw_rect(Rect2(pos-Vector2(8,22),sz+Vector2(16,30)),Color(0,0,0,0.8),true)
		draw_string(ThemeDB.fallback_font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(1,1,0.6))

func calculate_bounds_from_holds(holds_container: Node2D):
	if not holds_container or holds_container.get_child_count()==0:
		wall_valid=false; queue_redraw(); return
	var mn_x=INF; var mx_x=-INF; var mn_y=INF; var mx_y=-INF
	for hold in holds_container.get_children():
		if not hold is Node2D: continue
		var pos=hold.global_position
		mn_x=min(mn_x,pos.x); mx_x=max(mx_x,pos.x)
		mn_y=min(mn_y,pos.y); mx_y=max(mx_y,pos.y)
	wall_min=Vector2(mn_x-WALL_PADDING_SIDES,mn_y-WALL_PADDING_TOP)
	wall_max=Vector2(mx_x+WALL_PADDING_SIDES,mx_y+WALL_PADDING_BOTTOM)
	wall_valid=true; ground_y=wall_max.y
	if control_points.is_empty():
		control_points=[wall_min,Vector2(wall_max.x,wall_min.y),
						Vector2(wall_max.x,wall_max.y),Vector2(wall_min.x,wall_max.y)]
		ground_left_index=3; ground_right_index=2; use_polygon_mode=true
	else:
		if ground_left_index>=0 and ground_left_index<control_points.size():
			control_points[ground_left_index].y=ground_y
		if ground_right_index>=0 and ground_right_index<control_points.size():
			control_points[ground_right_index].y=ground_y
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	if weather_modifier: weather_modifier._wall_ref=self
	_init_clouds()
	queue_redraw()

func _update_bounds_from_polygon():
	if control_points.is_empty(): return
	var mn_x=INF; var mx_x=-INF; var mn_y=INF; var mx_y=-INF
	for p in control_points:
		mn_x=min(mn_x,p.x); mx_x=max(mx_x,p.x)
		mn_y=min(mn_y,p.y); mx_y=max(mx_y,p.y)
	wall_min=Vector2(mn_x,mn_y); wall_max=Vector2(mx_x,mx_y); wall_valid=true

func add_point_between_nearest_edge(pos: Vector2):
	if control_points.size()<2:
		control_points.append(pos); _update_bounds_from_polygon(); queue_redraw(); return
	var nei=-1; var ned=INF
	for i in range(control_points.size()):
		if _is_ground_edge(i): continue
		var d=_point_to_segment_distance(pos,control_points[i],control_points[(i+1)%control_points.size()])
		if d<ned: ned=d; nei=i
	if nei<0: return
	var ni=nei+1; control_points.insert(ni,pos)
	if ground_left_index>=ni: ground_left_index+=1
	if ground_right_index>=ni: ground_right_index+=1
	var ute: Array[int]=[]
	for ei in top_edge_indices: ute.append(ei+1 if ei>=nei else ei)
	top_edge_indices=ute
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	queue_redraw()

func remove_point(index: int):
	if index==ground_left_index or index==ground_right_index:
		push_warning("Cannot remove ground points"); return
	if control_points.size()<=4:
		push_warning("Cannot remove - need at least 4 points"); return
	if index>=0 and index<control_points.size():
		control_points.remove_at(index)
		if ground_left_index>index: ground_left_index-=1
		if ground_right_index>index: ground_right_index-=1
		if dragging_point==index: dragging_point=-1
		elif dragging_point>index: dragging_point-=1
		if hovered_point==index: hovered_point=-1
		elif hovered_point>index: hovered_point-=1
		var ute: Array[int]=[]
		for ei in top_edge_indices:
			if ei==index: continue
			ute.append(ei-1 if ei>index else ei)
		top_edge_indices=ute
		_update_bounds_from_polygon()
		if not top_edge_indices.is_empty(): _create_top_edge_holds()
		queue_redraw()

func enable_polygon_mode(enabled: bool=true):
	use_polygon_mode=enabled
	if enabled and control_points.is_empty() and wall_valid:
		control_points=[wall_min,Vector2(wall_max.x,wall_min.y),
						Vector2(wall_max.x,wall_max.y),Vector2(wall_min.x,wall_max.y)]
		ground_left_index=3; ground_right_index=2; ground_y=wall_max.y
	queue_redraw()

func enable_edit_mode(enabled: bool=true):
	edit_mode=enabled
	if not enabled: dragging_point=-1; hovered_point=-1; hovered_edge=-1
	queue_redraw()

func reset_polygon():
	use_polygon_mode=false; edit_mode=false
	control_points.clear(); top_edge_indices.clear()
	ground_left_index=-1; ground_right_index=-1
	dragging_point=-1; hovered_point=-1; hovered_edge=-1
	for child in get_children():
		if child.has_meta("is_top_edge_hold"): child.queue_free()
	queue_redraw()

func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var seg=seg_end-seg_start; var lsq=seg.length_squared()
	if lsq==0: return point.distance_to(seg_start)
	return point.distance_to(seg_start+clamp((point-seg_start).dot(seg)/lsq,0.0,1.0)*seg)

func _create_top_edge_holds():
	for child in get_children():
		if child.has_meta("is_top_edge_hold"): child.queue_free()
	if not use_polygon_mode or top_edge_indices.is_empty(): return
	for edge_idx in top_edge_indices:
		if edge_idx>=control_points.size(): continue
		var p1=control_points[edge_idx]
		var p2=control_points[(edge_idx+1)%control_points.size()]
		_create_top_hold_at((p1+p2)/2.0,p1.distance_to(p2))

func _create_top_hold_at(position: Vector2, width: float):
	var top_hold=Area2D.new(); top_hold.set_meta("is_top_edge_hold",true)
	top_hold.collision_layer=2; top_hold.collision_mask=0
	top_hold.monitoring=false; top_hold.monitorable=true; top_hold.name="TopEdgeHold"
	var shape=RectangleShape2D.new(); shape.size=Vector2(width,50)
	var collision=CollisionShape2D.new(); collision.shape=shape; top_hold.add_child(collision)
	var hold_point=Marker2D.new(); hold_point.name="HoldPoint"; hold_point.position=Vector2.ZERO
	top_hold.add_child(hold_point)
	top_hold.global_position=position; add_child(top_hold); top_hold.add_to_group("holds")
	call_deferred("_assign_top_hold_script",top_hold)

func _assign_top_hold_script(top_hold):
	var script_code="""
extends Area2D
var claimed_left_hand: Node2D = null
var claimed_right_hand: Node2D = null
var left_hand_x: float = 0.0
var right_hand_x: float = 0.0
func is_start_hold() -> bool: return false
func is_top_out() -> bool: return true
func is_crimp() -> bool: return false
func is_sloper() -> bool: return false
func is_pocket() -> bool: return false
func is_foothold() -> bool: return false
func can_grab(limb: Node2D, is_foot: bool) -> bool:
	if is_foot: return false
	return true
func try_claim(limb: Node2D, is_foot: bool, snap_pos: Vector2) -> bool:
	if not can_grab(limb, is_foot): return false
	if limb.name == 'LeftHand': claimed_left_hand = limb; left_hand_x = snap_pos.x
	elif limb.name == 'RightHand': claimed_right_hand = limb; right_hand_x = snap_pos.x
	return true
func release(limb: Node2D) -> void:
	if limb.name == 'LeftHand' and claimed_left_hand == limb: claimed_left_hand = null; left_hand_x = 0.0
	elif limb.name == 'RightHand' and claimed_right_hand == limb: claimed_right_hand = null; right_hand_x = 0.0
func get_limb_anchor(limb: Node2D) -> Vector2:
	var x_pos = limb.global_position.x
	if limb.name == 'LeftHand' and claimed_left_hand == limb: x_pos = left_hand_x
	elif limb.name == 'RightHand' and claimed_right_hand == limb: x_pos = right_hand_x
	return Vector2(x_pos, global_position.y)
func get_state_pressure(delta: float, body_offset: float, static_time: float, foot_support: float, limb: Node2D) -> float:
	return 0.5 * delta
func get_recovery_rate(delta: float, body_balance: float, foot_support: float) -> float:
	return 3.0 * delta * body_balance
"""
	var hold_script=GDScript.new(); hold_script.source_code=script_code
	hold_script.reload(); top_hold.set_script(hold_script)

func get_bounds() -> Dictionary:
	return {"min": wall_min, "max": wall_max, "valid": wall_valid}

func get_top_edge_y() -> float:
	if use_polygon_mode and not top_edge_indices.is_empty():
		var ty=INF
		for ei in top_edge_indices:
			if ei>=control_points.size(): continue
			var p1=control_points[ei]; var p2=control_points[(ei+1)%control_points.size()]
			ty=min(ty,min(p1.y,p2.y))
		return ty if ty!=INF else wall_min.y
	return wall_min.y

func get_wall_height() -> float: return ground_y-get_top_edge_y()
func get_wall_width() -> float: return wall_max.x-wall_min.x

func _hf(v: int) -> float:
	return float(hash(v)%10000)/10000.0

func hash_to_float(v: int) -> float:
	return _hf(v)

func get_polygon_data() -> Dictionary:
	if not use_polygon_mode or control_points.is_empty(): return {}
	var pts=[]; for p in control_points: pts.append({"x":p.x,"y":p.y})
	return {"enabled":true,"points":pts,"ground_left_index":ground_left_index,
			"ground_right_index":ground_right_index,"top_edge_indices":top_edge_indices.duplicate()}

func set_polygon_data(data: Dictionary):
	if not data or data.is_empty() or not data.get("enabled",false): return
	use_polygon_mode=true; control_points.clear()
	for pd in data.get("points",[]): control_points.append(Vector2(pd.get("x",0),pd.get("y",0)))
	ground_left_index=data.get("ground_left_index",-1)
	ground_right_index=data.get("ground_right_index",-1)
	top_edge_indices.clear()
	for ei in data.get("top_edge_indices",[]):
		if ei is float or ei is int: top_edge_indices.append(int(ei))
	if ground_left_index>=0 and ground_left_index<control_points.size():
		ground_y=control_points[ground_left_index].y
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	if weather_modifier: weather_modifier._wall_ref=self
	_init_clouds()
	queue_redraw()
	print("  Polygon loaded: "+str(control_points.size())+" points, "+str(top_edge_indices.size())+" top edges")
