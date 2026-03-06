# weather_modifier.gd
extends Node2D
class_name WeatherModifier

enum WeatherType {
	NONE,
	RAIN,
	NIGHT,
	SNOW,
}

var weather: int = WeatherType.NONE : set = set_weather
var intensity: float = 1.0

# ── Rain parameters ────────────────────────────────────────────────────────────
var rain_color       := Color(0.72, 0.82, 0.95, 0.72)
var rain_streak_len  := 80.0
var rain_angle_deg   := 12.0
var rain_speed       := 1100.0
var rain_density     := 600
var rain_wind        := 0.0

var splash_duration  := 0.30
var splash_radius    := 6.0

var rain_sky_top      := Color(0.14, 0.16, 0.22)
var rain_sky_horizon  := Color(0.28, 0.30, 0.36)
var rain_cloud_color  := Color(0.30, 0.32, 0.38, 1.0)
var rain_cloud_shadow := Color(0.18, 0.20, 0.26)
var rain_fog_color    := Color(0.22, 0.24, 0.30, 0.28)

# ── Night parameters ───────────────────────────────────────────────────────────
var night_darkness_alpha := 0.94
var night_dark_color     := Color(0.02, 0.02, 0.06)

var night_lamp_energy    := 2.2
var night_lamp_range     := 300.0
var night_lamp_color     := Color(1.00, 0.95, 0.78)
var night_ambient_energy := 0.18
var night_ambient_range  := 80.0
var night_ambient_color  := Color(0.55, 0.65, 1.00)

var night_sky_top      := Color(0.02, 0.02, 0.06)
var night_sky_horizon  := Color(0.06, 0.06, 0.12)
var night_cloud_color  := Color(0.08, 0.08, 0.14, 1.0)
var night_cloud_shadow := Color(0.02, 0.02, 0.05)
var night_fog_color    := Color(0.04, 0.04, 0.08, 0.12)

# ── Snow parameters ────────────────────────────────────────────────────────────
var snow_density        := 800
var snow_speed          := 160.0
var snow_drift_speed    := 40.0
var snow_sway_frequency := 0.6
var snow_min_radius     := 1.5
var snow_max_radius     := 4.5
var snow_color          := Color(0.92, 0.95, 1.00, 0.88)
var snow_accum_height   := 18.0
var snow_accum_alpha    := 0.55
var snow_fog_color_top  := Color(0.80, 0.85, 0.95, 0.0)
var snow_fog_color_mid  := Color(0.82, 0.87, 0.96, 0.07)

var snow_sky_top      := Color(0.62, 0.68, 0.78)
var snow_sky_horizon  := Color(0.80, 0.84, 0.90)
var snow_cloud_color  := Color(0.88, 0.90, 0.94, 1.0)
var snow_cloud_shadow := Color(0.55, 0.60, 0.68)
var snow_fog_color    := Color(0.78, 0.82, 0.90, 0.22)

# ── Player tracking ────────────────────────────────────────────────────────────
var _player_head_world: Vector2 = Vector2.ZERO
var _lamp_target_world: Vector2 = Vector2.ZERO
var _has_player: bool = false

var _lamp_dir_smooth: Vector2 = Vector2(0.0, 1.0)
const LAMP_DIR_LERP := 10.0

# ── PointLight2D nodes ────────────────────────────────────────────────────────
var _headlamp:      PointLight2D = null
var _ambient_light: PointLight2D = null

# ── Shared internal state ─────────────────────────────────────────────────────
var _time:       float = 0.0
var _drops:      Array[Dictionary] = []
var _splashes:   Array[Dictionary] = []
var _snowflakes: Array[Dictionary] = []
var _wall_ref:   Node2D = null

var _blend: float = 0.0
const BLEND_SPEED := 1.2
const LAYERS      := 3

var _audio:              AudioStreamPlayer = null
var _audio_fading_in:    bool  = false
var _audio_fade_elapsed: float = 0.0
const RAIN_SFX_PATH    := "res://assets/audio/sfx/rain_sfx.wav"
const RAIN_VOLUME_DB   := -4.0
const RAIN_VOLUME_MIN  := -18.0
const FADE_IN_DURATION := 2.5

var _drop_rng := RandomNumberGenerator.new()


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	z_index = 20
	add_to_group("weather_modifier")  # allows character.gd to find this node
	_wall_ref = get_parent() if get_parent().has_method("get_bounds") else null
	_drop_rng.randomize()
	_setup_audio()
	_setup_lights()
	set_weather(weather)

func _setup_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "RainSFX"
	add_child(_audio)
	if not ResourceLoader.exists(RAIN_SFX_PATH):
		push_warning("WeatherModifier: rain SFX not found at " + RAIN_SFX_PATH)
		return
	_audio.stream    = load(RAIN_SFX_PATH)
	_audio.bus       = "Master"
	_audio.volume_db = -80.0
	_audio.autoplay  = false

func _setup_lights() -> void:
	# ── Main headlamp ─────────────────────────────────────────────────────────
	_headlamp = PointLight2D.new()
	_headlamp.name           = "Headlamp"
	_headlamp.texture        = _make_radial_texture(256)
	_headlamp.texture_scale  = _range_to_texture_scale(night_lamp_range, 256)
	_headlamp.color          = night_lamp_color
	_headlamp.energy         = 0.0
	_headlamp.enabled        = false
	_headlamp.shadow_enabled = false
	add_child(_headlamp)

	# ── Ambient body glow ─────────────────────────────────────────────────────
	_ambient_light = PointLight2D.new()
	_ambient_light.name          = "AmbientGlow"
	_ambient_light.texture       = _make_radial_texture(128)
	_ambient_light.texture_scale = _range_to_texture_scale(night_ambient_range, 128)
	_ambient_light.color         = night_ambient_color
	_ambient_light.energy        = 0.0
	_ambient_light.enabled       = false
	add_child(_ambient_light)

func _make_radial_texture(size: int) -> ImageTexture:
	var img    := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(centre) / radius
			var a  = clamp(1.0 - smoothstep(0.0, 1.0, d), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

func _range_to_texture_scale(world_radius: float, tex_size: int) -> float:
	return (world_radius * 2.0) / float(tex_size)


# =============================================================================
# PLAYER DATA FEED
# =============================================================================

func update_player_data(head_world_pos: Vector2, limb_world_pos: Vector2) -> void:
	_player_head_world = head_world_pos
	_lamp_target_world = limb_world_pos
	_has_player        = true


# =============================================================================
# WEATHER SWITCHING
# =============================================================================

func set_weather(new_weather: int) -> void:
	weather = new_weather
	_drops.clear()
	_splashes.clear()
	_snowflakes.clear()

	match weather:
		WeatherType.RAIN:
			_init_rain()
			_set_lights_enabled(false)
			if _audio and _audio.stream and not _audio.playing:
				_audio.volume_db    = -80.0
				_audio.play()
				_audio_fading_in    = true
				_audio_fade_elapsed = 0.0
		WeatherType.NIGHT:
			_set_lights_enabled(true)
			_blend = max(_blend, 0.001)  # kick-start blend so energy guard passes
			_update_night_lamp(0.0)
			_update_night_lights()       # apply energy immediately, don't wait for _process
			if _audio and _audio.playing:
				_audio.stop()
			_audio_fading_in = false
		WeatherType.SNOW:
			_init_snow()
			_set_lights_enabled(false)
			if _audio and _audio.playing:
				_audio.stop()
			_audio_fading_in = false
		_:  # NONE
			_set_lights_enabled(false)
			if _audio and _audio.playing:
				_audio.stop()
			_audio_fading_in = false

	queue_redraw()

func _set_lights_enabled(on: bool) -> void:
	if _headlamp:
		_headlamp.enabled = on
		if not on:
			_headlamp.energy = 0.0
	if _ambient_light:
		_ambient_light.enabled = on
		if not on:
			_ambient_light.energy = 0.0


# =============================================================================
# RAIN INIT / DROP FACTORY
# =============================================================================

func _init_rain() -> void:
	var count := int(rain_density * clamp(intensity, 0.05, 1.0))
	for i in range(count):
		_drops.append(_make_drop(true))

func _make_drop(spread: bool) -> Dictionary:
	var b           := _get_draw_bounds()
	var layer       := _drop_rng.randi() % LAYERS
	var speed_scale  = lerp(0.6, 1.0, float(layer) / float(LAYERS - 1))
	var alpha_scale  = lerp(0.45, 1.0, float(layer) / float(LAYERS - 1))
	var x           := _drop_rng.randf_range(b.x - 200.0, b.x + b.z + 200.0)
	var y           := _drop_rng.randf_range(b.y, b.y + b.w) if spread \
					   else b.y - _drop_rng.randf() * 150.0
	return {
		"x":     x,
		"y":     y,
		"layer": layer,
		"speed": rain_speed * speed_scale * (0.82 + _drop_rng.randf() * 0.36),
		"alpha": (0.55 + _drop_rng.randf() * 0.45) * alpha_scale,
		"len":   rain_streak_len * speed_scale * (0.7 + _drop_rng.randf() * 0.6),
		"width": lerp(1.0, 2.2, float(layer) / float(LAYERS - 1)),
		"wx":    (_drop_rng.randf() - 0.5) * 0.04,
	}


# =============================================================================
# SNOW INIT / FLAKE FACTORY
# =============================================================================

func _init_snow() -> void:
	var count := int(snow_density * clamp(intensity, 0.05, 1.0))
	for i in range(count):
		_snowflakes.append(_make_flake(true))

func _make_flake(spread: bool) -> Dictionary:
	var b       := _get_draw_bounds()
	var layer   := _drop_rng.randi() % LAYERS
	var depth_t := float(layer) / float(LAYERS - 1)
	var x       := _drop_rng.randf_range(b.x - 50.0, b.x + b.z + 50.0)
	var y       := _drop_rng.randf_range(b.y, b.y + b.w) if spread \
				   else b.y - _drop_rng.randf() * 80.0
	return {
		"x":      x,
		"y":      y,
		"layer":  layer,
		"radius": lerp(snow_min_radius * 0.6, snow_max_radius, depth_t)
				  * (0.7 + _drop_rng.randf() * 0.6),
		"speed":  snow_speed * lerp(0.5, 1.0, depth_t)
				  * (0.75 + _drop_rng.randf() * 0.5),
		"phase":  _drop_rng.randf() * TAU,
		"drift":  snow_drift_speed * (0.3 + _drop_rng.randf() * 0.7),
		"alpha": (0.30 + _drop_rng.randf() * 0.35) * lerp(0.45, 1.0, depth_t),
	}


# =============================================================================
# PROCESS
# =============================================================================

func _process(delta: float) -> void:
	if weather == WeatherType.NONE and _blend <= 0.0:
		return

	_time += delta

	var target_blend := intensity if weather != WeatherType.NONE else 0.0
	_blend = move_toward(_blend, target_blend, BLEND_SPEED * delta)

	match weather:
		WeatherType.RAIN:
			_update_rain(delta)
			_update_rain_audio(delta)
		WeatherType.NIGHT:
			_update_night_lamp(delta)
			_update_night_lights()
		WeatherType.SNOW:
			_update_snow(delta)

	# Advance splashes
	var alive: Array[Dictionary] = []
	for s in _splashes:
		s["t"] += delta
		if s["t"] < splash_duration:
			alive.append(s)
	_splashes = alive

	queue_redraw()

func _get_ground_y() -> float:
	if _wall_ref and "ground_y" in _wall_ref:
		return _wall_ref.ground_y
	var b := _get_draw_bounds()
	return b.y + b.w

func _update_rain(delta: float) -> void:
	var angle_rad := deg_to_rad(rain_angle_deg)
	var dx        := sin(angle_rad) + rain_wind / rain_speed
	var dy        := cos(angle_rad)
	var b         := _get_draw_bounds()
	var ground_y  := _get_ground_y()

	for i in range(_drops.size()):
		var d := _drops[i]
		d["x"] += (dx + d["wx"]) * d["speed"] * delta
		d["y"] += dy * d["speed"] * delta

		var out_bottom = d["y"] >= ground_y
		var out_sides  = d["x"] > b.x + b.z + 300.0 or d["x"] < b.x - 300.0

		if out_bottom or out_sides:
			if out_bottom:
				_spawn_splash(d["x"], ground_y, d["alpha"], d["layer"])
			_drops[i] = _make_drop(false)
		else:
			_drops[i] = d

func _update_rain_audio(delta: float) -> void:
	var target_db = lerp(RAIN_VOLUME_MIN, RAIN_VOLUME_DB, intensity)
	if _audio_fading_in:
		_audio_fade_elapsed += delta
		var t     = clamp(_audio_fade_elapsed / FADE_IN_DURATION, 0.0, 1.0)
		var eased = 1.0 - (1.0 - t) * (1.0 - t)
		_audio.volume_db = lerp(-80.0, target_db, eased)
		if t >= 1.0:
			_audio.volume_db = target_db
			_audio_fading_in = false
	else:
		_audio.volume_db = move_toward(_audio.volume_db, target_db, 6.0 * delta)

## _delta is intentionally unused — smoothing uses get_process_delta_time() internally.
func _update_night_lamp(_delta: float) -> void:
	var desired_dir: Vector2
	if _has_player and _lamp_target_world != Vector2.ZERO:
		var to_target := _lamp_target_world - _player_head_world
		if to_target.length() > 2.0:
			desired_dir = to_target.normalized()
		else:
			desired_dir = Vector2(0.0, 1.0)
	else:
		desired_dir = Vector2(0.0, 1.0)

	_lamp_dir_smooth = _lamp_dir_smooth.lerp(
		desired_dir, LAMP_DIR_LERP * get_process_delta_time()).normalized()

func _update_night_lights() -> void:
	var target_energy := night_lamp_energy * _blend * intensity

	if _headlamp:
		if _has_player:
			# Convert world position → local space of this Node2D,
			# so the light sits correctly regardless of WeatherModifier's own position/parent.
			_headlamp.position = to_local(_player_head_world)
		_headlamp.energy   = target_energy
		_headlamp.rotation = _lamp_dir_smooth.angle() + PI * 0.5

	if _ambient_light:
		if _has_player:
			_ambient_light.position = to_local(_player_head_world)
		_ambient_light.energy = night_ambient_energy * _blend * intensity

func _update_snow(delta: float) -> void:
	var b        := _get_draw_bounds()
	var ground_y := _get_ground_y()

	for i in range(_snowflakes.size()):
		var f := _snowflakes[i]
		f["y"] += f["speed"] * delta
		f["x"] += sin(_time * snow_sway_frequency * TAU + f["phase"]) * f["drift"] * delta

		var out_bottom = f["y"] >= ground_y
		var out_sides  = f["x"] > b.x + b.z + 80.0 or f["x"] < b.x - 80.0

		if out_bottom or out_sides:
			_snowflakes[i] = _make_flake(false)
		else:
			_snowflakes[i] = f

func _spawn_splash(sx: float, gy: float, drop_alpha: float, _layer: int) -> void:
	if _drop_rng.randf() > 0.12:
		return
	_splashes.append({
		"x":     sx,
		"gy":    gy,
		"t":     0.0,
		"alpha": drop_alpha * clamp(intensity, 0.3, 0.7),
	})


# =============================================================================
# DRAW DISPATCH
# =============================================================================

func _draw() -> void:
	if _blend < 0.01:
		return
	match weather:
		WeatherType.RAIN:
			_draw_rain_streaks()
			_draw_splashes()
			_draw_rain_fog()
		WeatherType.NIGHT:
			_draw_night_darkness()
		WeatherType.SNOW:
			_draw_snow_fog()
			_draw_snowflakes()
			_draw_snow_accumulation()
		WeatherType.NONE:
			pass


# =============================================================================
# NIGHT DRAW
# =============================================================================

func _draw_night_darkness() -> void:
	var b := _get_draw_bounds()
	var a := night_darkness_alpha * _blend * intensity
	draw_rect(
		Rect2(b.x, b.y, b.z, b.w),
		Color(night_dark_color.r, night_dark_color.g, night_dark_color.b, a))


# =============================================================================
# RAIN DRAW
# =============================================================================

func _draw_rain_streaks() -> void:
	var angle_rad := deg_to_rad(rain_angle_deg)
	var udx       := sin(angle_rad)
	var udy       := cos(angle_rad)
	for layer in range(LAYERS):
		for d in _drops:
			if d["layer"] != layer:
				continue
			var a = d["alpha"] * _blend * intensity
			if a < 0.02:
				continue
			var px: float = d["x"]
			var py: float = d["y"]
			draw_line(
				Vector2(px, py),
				Vector2(px - udx * d["len"], py - udy * d["len"]),
				Color(rain_color.r, rain_color.g, rain_color.b, a),
				d["width"], true)

func _draw_splashes() -> void:
	var rc := Color(rain_color.r + 0.10, rain_color.g + 0.05, rain_color.b + 0.03)
	for s in _splashes:
		var t_norm = clamp(s["t"] / splash_duration, 0.0, 1.0)
		var ring_r = t_norm * splash_radius * 2.2
		var ring_a = (1.0 - t_norm) * s["alpha"] * _blend * 0.55
		if ring_r > 0.3 and ring_a > 0.01:
			_draw_ellipse_ring(s["x"], s["gy"], ring_r, ring_r * 0.28, ring_a, rc, 1.0)

func _draw_ellipse_ring(cx: float, cy: float, rx: float, ry: float,
						alpha: float, color: Color, line_w: float) -> void:
	if rx < 0.5 or ry < 0.5 or alpha < 0.01:
		return
	const STEPS := 14
	var prev := Vector2.ZERO
	for i in range(STEPS + 1):
		var angle := (float(i) / float(STEPS)) * TAU
		var pt    := Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry)
		if i > 0:
			draw_line(prev, pt, Color(color.r, color.g, color.b, alpha), line_w, true)
		prev = pt

## Renamed local vars from tl/tr/br/bl to top_left/top_right/bot_right/bot_left
## to avoid shadowing the built-in Object.tr() method (fixes warning line 437).
func _draw_grad_quad(x: float, y0: float, w: float, y1: float,
					 c_top: Color, c_bot: Color) -> void:
	var top_left  := Vector2(x,     y0)
	var top_right := Vector2(x + w, y0)
	var bot_right := Vector2(x + w, y1)
	var bot_left  := Vector2(x,     y1)
	draw_polygon(PackedVector2Array([top_left, top_right, bot_right]),
				 PackedColorArray([c_top, c_top, c_bot]))
	draw_polygon(PackedVector2Array([top_left, bot_right, bot_left]),
				 PackedColorArray([c_top, c_bot, c_bot]))

func _draw_rain_fog() -> void:
	var b        := _get_draw_bounds()
	var ground_y := _get_ground_y()
	var total_h  := ground_y - b.y + 300.0
	var w        := b.z

	var haze_max_a = lerp(0.0, 0.35, intensity * _blend)
	for i in range(8):
		var t0 := float(i)     / 8.0
		var t1 := float(i + 1) / 8.0
		_draw_grad_quad(b.x, b.y + t0 * total_h, w, b.y + t1 * total_h,
			Color(0.08, 0.11, 0.18, haze_max_a * (t0 * t0)),
			Color(0.10, 0.14, 0.22, haze_max_a * (t1 * t1)))

	var mist_max_a = lerp(0.0, 0.20, intensity * _blend)
	var mist_h     = lerp(30.0, 110.0, intensity)
	var mist_col   := Color(0.55, 0.64, 0.78)
	for i in range(6):
		var t0 := float(i)     / 6.0
		var t1 := float(i + 1) / 6.0
		_draw_grad_quad(b.x, ground_y - t0 * mist_h, w, ground_y - t1 * mist_h,
			Color(mist_col.r, mist_col.g, mist_col.b, mist_max_a * (1.0 - t0)),
			Color(mist_col.r, mist_col.g, mist_col.b, mist_max_a * (1.0 - t1)))


# =============================================================================
# SNOW DRAW
# =============================================================================

func _draw_snow_fog() -> void:
	var b      := _get_draw_bounds()
	var w      := b.z
	var h      := b.w
	var haze_a = lerp(0.0, 0.08, intensity * _blend)
	_draw_grad_quad(b.x, b.y,           w, b.y + h * 0.5,
		Color(snow_fog_color_top.r, snow_fog_color_top.g, snow_fog_color_top.b, 0.0),
		Color(snow_fog_color_mid.r, snow_fog_color_mid.g, snow_fog_color_mid.b, haze_a))
	_draw_grad_quad(b.x, b.y + h * 0.5, w, b.y + h,
		Color(snow_fog_color_mid.r, snow_fog_color_mid.g, snow_fog_color_mid.b, haze_a),
		Color(snow_fog_color_mid.r, snow_fog_color_mid.g, snow_fog_color_mid.b, haze_a * 1.4))

func _draw_snowflakes() -> void:
	for layer in range(LAYERS):
		for f in _snowflakes:
			if f["layer"] != layer:
				continue
			var a = f["alpha"] * _blend * intensity
			if a < 0.02:
				continue
			draw_circle(
				Vector2(f["x"], f["y"]),
				f["radius"],
				Color(snow_color.r, snow_color.g, snow_color.b, a))

func _draw_snow_accumulation() -> void:
	var b        := _get_draw_bounds()
	var ground_y := _get_ground_y()
	var strip_h  = snow_accum_height * clamp(intensity, 0.2, 1.0)
	var a_top    := snow_accum_alpha * _blend * intensity
	_draw_grad_quad(b.x, ground_y - strip_h, b.z, ground_y,
		Color(snow_color.r, snow_color.g, snow_color.b, 0.0),
		Color(snow_color.r, snow_color.g, snow_color.b, a_top))


# =============================================================================
# PUBLIC API
# =============================================================================

func get_blend() -> float:
	return _blend

func get_rain_sky_override() -> Dictionary:
	return {
		"sky_top":      rain_sky_top,
		"sky_horizon":  rain_sky_horizon,
		"cloud_color":  rain_cloud_color,
		"cloud_shadow": rain_cloud_shadow,
		"fog_color":    rain_fog_color,
	}

func get_night_sky_override() -> Dictionary:
	return {
		"sky_top":      night_sky_top,
		"sky_horizon":  night_sky_horizon,
		"cloud_color":  night_cloud_color,
		"cloud_shadow": night_cloud_shadow,
		"fog_color":    night_fog_color,
	}

func get_snow_sky_override() -> Dictionary:
	return {
		"sky_top":      snow_sky_top,
		"sky_horizon":  snow_sky_horizon,
		"cloud_color":  snow_cloud_color,
		"cloud_shadow": snow_cloud_shadow,
		"fog_color":    snow_fog_color,
	}

func get_active_sky_override() -> Dictionary:
	match weather:
		WeatherType.RAIN:  return get_rain_sky_override()
		WeatherType.NIGHT: return get_night_sky_override()
		WeatherType.SNOW:  return get_snow_sky_override()
		_:                 return {}

func get_hold_friction_modifier() -> float:
	if weather == WeatherType.RAIN:
		return lerp(1.0, 0.60, _blend)
	if weather == WeatherType.SNOW:
		return lerp(1.0, 0.50, _blend)
	return 1.0

func get_stamina_drain_modifier() -> float:
	if weather == WeatherType.RAIN:
		return lerp(1.0, 1.28, _blend)
	if weather == WeatherType.NIGHT:
		return lerp(1.0, 1.12, _blend)
	if weather == WeatherType.SNOW:
		return lerp(1.0, 1.35, _blend)
	return 1.0

func get_gravity_modifier() -> float:
	return 1.0

func get_wind_force() -> Vector2:
	if weather == WeatherType.RAIN:
		return Vector2(rain_wind * 0.3 * _blend, 0.0)
	if weather == WeatherType.SNOW:
		return Vector2(sin(_time * snow_sway_frequency * TAU) * snow_drift_speed * 0.15 * _blend, 0.0)
	return Vector2.ZERO

func _get_draw_bounds() -> Vector4:
	if _wall_ref and _wall_ref.has_method("get_bounds"):
		var b: Dictionary = _wall_ref.get_bounds()
		if b.get("valid", false):
			const EXP := 700.0
			return Vector4(b["min"].x - EXP, b["min"].y - EXP,
						   (b["max"].x - b["min"].x) + EXP * 2.0,
						   (b["max"].y - b["min"].y) + EXP * 2.0)
	var vs := get_viewport_rect().size
	return Vector4(-vs.x * 0.5, -vs.y * 0.5, vs.x * 2.0, vs.y * 2.0)
