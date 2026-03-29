# weather_modifier.gd
extends Node2D
class_name WeatherModifier

enum WeatherType {
	NONE,
	RAIN,
	NIGHT,
	SNOW,
	LIGHTNING,
	FOG,
	HAIL,
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

# ── Lightning parameters ───────────────────────────────────────────────────────
var lightning_bolt_color       := Color(0.88, 0.92, 1.00, 1.0)
var lightning_glow_color       := Color(0.70, 0.78, 1.00, 0.35)
var lightning_flash_color      := Color(0.82, 0.88, 1.00, 0.0)
var lightning_min_interval     := 2.5
var lightning_max_interval     := 9.0
var lightning_flash_duration   := 0.12
var lightning_bolt_duration    := 0.22
var lightning_bolt_width       := 2.5
var lightning_glow_width       := 7.0
var lightning_segments         := 10
var lightning_jitter           := 55.0
var lightning_branch_chance    := 0.30
var lightning_rain_density     := 700
var lightning_rain_speed       := 1300.0
var lightning_rain_angle_deg   := 18.0

var lightning_sky_top      := Color(0.08, 0.08, 0.14)
var lightning_sky_horizon  := Color(0.18, 0.18, 0.26)
var lightning_cloud_color  := Color(0.20, 0.20, 0.28, 1.0)
var lightning_cloud_shadow := Color(0.10, 0.10, 0.16)
var lightning_fog_color    := Color(0.16, 0.16, 0.24, 0.32)

# ── Fog parameters ─────────────────────────────────────────────────────────────
var fog_color            := Color(0.78, 0.80, 0.84, 1.0)
var fog_layers           := 6
var fog_scroll_speeds    := [18.0, 28.0, 12.0, 22.0, 9.0, 35.0]
var fog_layer_alphas     := [0.18, 0.13, 0.20, 0.11, 0.16, 0.09]
var fog_layer_heights    := [0.18, 0.24, 0.14, 0.30, 0.10, 0.22]
var fog_ground_alpha     := 0.60
var fog_ground_height    := 120.0
var fog_vignette_alpha   := 0.28
var fog_ambient_darken   := 0.22

var fog_sky_top      := Color(0.62, 0.64, 0.68)
var fog_sky_horizon  := Color(0.74, 0.76, 0.80)
var fog_cloud_color  := Color(0.80, 0.82, 0.86, 1.0)
var fog_cloud_shadow := Color(0.54, 0.56, 0.60)
var fog_fog_color    := Color(0.76, 0.78, 0.82, 0.45)

# ── Hail parameters ───────────────────────────────────────────────────────────
var hail_density         := 500
var hail_speed           := 900.0
var hail_angle_deg       := 8.0
var hail_min_radius      := 2.0
var hail_max_radius      := 5.5
var hail_color           := Color(0.88, 0.94, 1.00, 0.90)
var hail_bounce_chance   := 0.45
var hail_bounce_speed    := 220.0
var hail_bounce_gravity  := 480.0
var hail_bounce_duration := 0.35
var hail_wind            := 60.0
var hail_impact_color    := Color(0.85, 0.92, 1.00, 0.70)

var hail_sky_top      := Color(0.22, 0.24, 0.30)
var hail_sky_horizon  := Color(0.36, 0.38, 0.44)
var hail_cloud_color  := Color(0.38, 0.40, 0.46, 1.0)
var hail_cloud_shadow := Color(0.20, 0.22, 0.28)
var hail_fog_color    := Color(0.30, 0.32, 0.38, 0.30)

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

# ── Lightning internal state ───────────────────────────────────────────────────
var _lightning_timer:        float = 0.0
var _lightning_interval:     float = 0.0
var _lightning_flash_timer:  float = 0.0
var _lightning_bolt_timer:   float = 0.0
var _lightning_bolt_points:  Array[Vector2] = []
var _lightning_branches:     Array[Array]   = []
var _lightning_active:       bool = false
var _lightning_audio:        AudioStreamPlayer = null
const LIGHTNING_SFX_PATH := "res://assets/audio/sfx/thunder_sfx.wav"

# ── Fog internal state ─────────────────────────────────────────────────────────
var _fog_offsets: Array[float] = []

# ── Hail internal state ────────────────────────────────────────────────────────
var _hailstones:   Array[Dictionary] = []
var _hail_bounces: Array[Dictionary] = []

# ── Packed draw arrays — rain (per layer) ────────────────────────────────────
# Each layer stores interleaved [from, to] pairs as a flat PackedVector2Array.
# draw_multiline() issues a single draw call per layer instead of one per drop.
# Initialized at declaration so they exist before _ready() / set_weather fires.
var _rain_lines:  Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
var _rain_colors: Array[Color] = []

# ── Packed draw arrays — snow (per layer) ────────────────────────────────────
var _snow_points: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
var _snow_radii:  Array[PackedFloat32Array] = [
	PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
var _snow_colors: Array[Color] = []

# ── Packed draw arrays — hail (per layer) ────────────────────────────────────
# Each hailstone = filled circle + short streak line.
# Circles: PackedVector2Array of centres, PackedFloat32Array of radii.
# Streaks: PackedVector2Array of interleaved [from, to] pairs.
var _hail_points:  Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
var _hail_radii:   Array[PackedFloat32Array] = [
	PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
var _hail_streaks: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
var _hail_colors:       Array[Color] = []
var _hail_streak_colors: Array[Color] = []

# Precomputed angle components (recalculated only when angle params change)
var _rain_udx: float = 0.0
var _rain_udy: float = 0.0
var _hail_udx: float = 0.0
var _hail_udy: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	z_index = 20
	add_to_group("weather_modifier")
	_wall_ref = get_parent() if get_parent().has_method("get_bounds") else null
	_drop_rng.randomize()
	_setup_audio()
	_setup_lights()
	_setup_lightning_audio()
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

func _setup_lightning_audio() -> void:
	_lightning_audio = AudioStreamPlayer.new()
	_lightning_audio.name = "ThunderSFX"
	add_child(_lightning_audio)
	if not ResourceLoader.exists(LIGHTNING_SFX_PATH):
		push_warning("WeatherModifier: thunder SFX not found at " + LIGHTNING_SFX_PATH)
		return
	_lightning_audio.stream    = load(LIGHTNING_SFX_PATH)
	_lightning_audio.bus       = "Master"
	_lightning_audio.volume_db = -2.0

func _setup_lights() -> void:
	_headlamp = PointLight2D.new()
	_headlamp.name           = "Headlamp"
	_headlamp.texture        = _make_radial_texture(256)
	_headlamp.texture_scale  = _range_to_texture_scale(night_lamp_range, 256)
	_headlamp.color          = night_lamp_color
	_headlamp.energy         = 0.0
	_headlamp.enabled        = false
	_headlamp.shadow_enabled = false
	add_child(_headlamp)

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
	_hailstones.clear()
	_hail_bounces.clear()
	_lightning_active      = false
	_lightning_bolt_points = []
	_lightning_branches    = []
	_fog_offsets           = []

	# Clear all packed arrays
	for i in range(LAYERS):
		_rain_lines[i].clear()
		_snow_points[i].clear()
		_snow_radii[i].clear()
		_hail_points[i].clear()
		_hail_radii[i].clear()
		_hail_streaks[i].clear()

	match weather:
		WeatherType.RAIN:
			_cache_rain_angle()
			_init_rain()
			_set_lights_enabled(false)
			if _audio and _audio.stream and not _audio.playing:
				_audio.volume_db    = -80.0
				_audio.play()
				_audio_fading_in    = true
				_audio_fade_elapsed = 0.0
		WeatherType.NIGHT:
			_set_lights_enabled(true)
			_blend = max(_blend, 0.001)
			_update_night_lamp(0.0)
			_update_night_lights()
			if _audio and _audio.playing:
				_audio.stop()
			_audio_fading_in = false
		WeatherType.SNOW:
			_init_snow()
			_set_lights_enabled(false)
			if _audio and _audio.playing:
				_audio.stop()
			_audio_fading_in = false
		WeatherType.LIGHTNING:
			_cache_rain_angle()
			_init_lightning()
			_set_lights_enabled(false)
			_init_rain()
			if _audio and _audio.stream and not _audio.playing:
				_audio.volume_db    = -80.0
				_audio.play()
				_audio_fading_in    = true
				_audio_fade_elapsed = 0.0
		WeatherType.FOG:
			_init_fog()
			_set_lights_enabled(false)
			if _audio and _audio.playing:
				_audio.stop()
			_audio_fading_in = false
		WeatherType.HAIL:
			_cache_hail_angle()
			_init_hail()
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

# Cache sin/cos of rain angle so _update_rain does no trig per frame
func _cache_rain_angle() -> void:
	var deg := lightning_rain_angle_deg if weather == WeatherType.LIGHTNING else rain_angle_deg
	var rad := deg_to_rad(deg)
	_rain_udx = sin(rad)
	_rain_udy = cos(rad)

func _cache_hail_angle() -> void:
	var rad := deg_to_rad(hail_angle_deg)
	_hail_udx = sin(rad)
	_hail_udy = cos(rad)


# =============================================================================
# RAIN INIT / DROP FACTORY
# =============================================================================

func _init_rain() -> void:
	var density := lightning_rain_density if weather == WeatherType.LIGHTNING else rain_density
	var count   := int(density * clamp(intensity, 0.05, 1.0))
	_drops.resize(count)
	for i in range(count):
		_drops[i] = _make_drop(true)
	_rebuild_rain_packed()

func _make_drop(spread: bool) -> Dictionary:
	var b           := _get_draw_bounds()
	var layer       := _drop_rng.randi() % LAYERS
	var speed_scale  = lerp(0.6, 1.0, float(layer) / float(LAYERS - 1))
	var alpha_scale  = lerp(0.45, 1.0, float(layer) / float(LAYERS - 1))
	var spd         := lightning_rain_speed if weather == WeatherType.LIGHTNING else rain_speed
	var x           := _drop_rng.randf_range(b.x - 200.0, b.x + b.z + 200.0)
	var y           := _drop_rng.randf_range(b.y, b.y + b.w) if spread \
					   else b.y - _drop_rng.randf() * 150.0
	return {
		"x":     x,
		"y":     y,
		"layer": layer,
		"speed": spd * speed_scale * (0.82 + _drop_rng.randf() * 0.36),
		"alpha": (0.55 + _drop_rng.randf() * 0.45) * alpha_scale,
		"len":   rain_streak_len * speed_scale * (0.7 + _drop_rng.randf() * 0.6),
		"width": lerp(1.0, 2.2, float(layer) / float(LAYERS - 1)),
		"wx":    (_drop_rng.randf() - 0.5) * 0.04,
	}

# Rebuild the per-layer line arrays from the current _drops list.
# Called once after init; thereafter _update_rain rebuilds incrementally.
func _rebuild_rain_packed() -> void:
	for i in range(LAYERS):
		_rain_lines[i].clear()
	for d in _drops:
		_append_rain_line(d)

func _append_rain_line(d: Dictionary) -> void:
	var layer: int = d["layer"]
	var px: float  = d["x"]
	var py: float  = d["y"]
	_rain_lines[layer].append(Vector2(px, py))
	_rain_lines[layer].append(Vector2(px - _rain_udx * d["len"], py - _rain_udy * d["len"]))


# =============================================================================
# SNOW INIT / FLAKE FACTORY
# =============================================================================

func _init_snow() -> void:
	var count := int(snow_density * clamp(intensity, 0.05, 1.0))
	_snowflakes.resize(count)
	for i in range(count):
		_snowflakes[i] = _make_flake(true)
	_rebuild_snow_packed()

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

func _rebuild_snow_packed() -> void:
	for i in range(LAYERS):
		_snow_points[i].clear()
		_snow_radii[i].clear()
	for f in _snowflakes:
		var layer: int = f["layer"]
		_snow_points[layer].append(Vector2(f["x"], f["y"]))
		_snow_radii[layer].append(f["radius"])


# =============================================================================
# LIGHTNING INIT
# =============================================================================

func _init_lightning() -> void:
	_lightning_active   = false
	_lightning_timer    = _drop_rng.randf_range(0.5, 2.0)
	_lightning_interval = _lightning_timer

func _trigger_lightning_strike() -> void:
	var b := _get_draw_bounds()
	var bolt_x := _drop_rng.randf_range(b.x + b.z * 0.1, b.x + b.z * 0.9)
	var top_y  := b.y
	var bot_y  := b.y + b.w * _drop_rng.randf_range(0.5, 0.95)

	_lightning_bolt_points = _generate_bolt(
		Vector2(bolt_x, top_y),
		Vector2(bolt_x + _drop_rng.randf_range(-60.0, 60.0), bot_y),
		lightning_segments
	)

	_lightning_branches = []
	for i in range(1, _lightning_bolt_points.size() - 1):
		if _drop_rng.randf() < lightning_branch_chance * intensity:
			var branch_len := int(lightning_segments * _drop_rng.randf_range(0.25, 0.55))
			var branch_dir := Vector2(
				_drop_rng.randf_range(-1.0, 1.0),
				_drop_rng.randf_range(0.4, 1.0)
			).normalized()
			var branch_end := _lightning_bolt_points[i] + branch_dir * (bot_y - top_y) * 0.35
			_lightning_branches.append(
				_generate_bolt(_lightning_bolt_points[i], branch_end, branch_len)
			)

	_lightning_active     = true
	_lightning_bolt_timer  = lightning_bolt_duration
	_lightning_flash_timer = lightning_flash_duration

	if _lightning_audio and _lightning_audio.stream:
		_lightning_audio.pitch_scale = _drop_rng.randf_range(0.85, 1.15)
		_lightning_audio.play()

func _generate_bolt(start: Vector2, end: Vector2, segments: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	pts.append(start)
	var dir    := (end - start).normalized()
	var perp   := Vector2(-dir.y, dir.x)
	for i in range(1, segments):
		var t      := float(i) / float(segments)
		var base   := start.lerp(end, t)
		var jitter := _drop_rng.randf_range(-lightning_jitter, lightning_jitter) * (1.0 - t * 0.5)
		pts.append(base + perp * jitter)
	pts.append(end)
	return pts


# =============================================================================
# FOG INIT
# =============================================================================

func _init_fog() -> void:
	_fog_offsets.resize(fog_layers)
	for i in range(fog_layers):
		_fog_offsets[i] = _drop_rng.randf_range(0.0, 2000.0)


# =============================================================================
# HAIL INIT / STONE FACTORY
# =============================================================================

func _init_hail() -> void:
	var count := int(hail_density * clamp(intensity, 0.05, 1.0))
	_hailstones.resize(count)
	for i in range(count):
		_hailstones[i] = _make_hailstone(true)
	_rebuild_hail_packed()

func _make_hailstone(spread: bool) -> Dictionary:
	var b       := _get_draw_bounds()
	var layer   := _drop_rng.randi() % LAYERS
	var depth_t := float(layer) / float(LAYERS - 1)
	var x       := _drop_rng.randf_range(b.x - 100.0, b.x + b.z + 100.0)
	var y       := _drop_rng.randf_range(b.y, b.y + b.w) if spread \
				   else b.y - _drop_rng.randf() * 120.0
	return {
		"x":      x,
		"y":      y,
		"layer":  layer,
		"radius": lerp(hail_min_radius, hail_max_radius, depth_t)
				  * (0.7 + _drop_rng.randf() * 0.6),
		"speed":  hail_speed * lerp(0.65, 1.0, depth_t)
				  * (0.80 + _drop_rng.randf() * 0.40),
		"alpha":  (0.55 + _drop_rng.randf() * 0.35) * lerp(0.5, 1.0, depth_t),
	}

func _rebuild_hail_packed() -> void:
	for i in range(LAYERS):
		_hail_points[i].clear()
		_hail_radii[i].clear()
		_hail_streaks[i].clear()
	for s in _hailstones:
		_append_hail_stone(s)

func _append_hail_stone(s: Dictionary) -> void:
	var layer: int  = s["layer"]
	var sx: float   = s["x"]
	var sy: float   = s["y"]
	var r: float    = s["radius"]
	_hail_points[layer].append(Vector2(sx, sy))
	_hail_radii[layer].append(r)
	var streak_len := r * 2.5
	_hail_streaks[layer].append(Vector2(sx, sy))
	_hail_streaks[layer].append(Vector2(sx - _hail_udx * streak_len, sy - _hail_udy * streak_len))


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
		WeatherType.LIGHTNING:
			_update_rain(delta)
			_update_rain_audio(delta)
			_update_lightning(delta)
		WeatherType.FOG:
			_update_fog(delta)
		WeatherType.HAIL:
			_update_hail(delta)

	# Advance splashes
	var alive: Array[Dictionary] = []
	alive.resize(_splashes.size())
	var alive_count := 0
	for s in _splashes:
		s["t"] += delta
		if s["t"] < splash_duration:
			alive[alive_count] = s
			alive_count += 1
	alive.resize(alive_count)
	_splashes = alive

	# Advance hail bounces
	var alive_bounces: Array[Dictionary] = []
	alive_bounces.resize(_hail_bounces.size())
	var bounce_count := 0
	for b in _hail_bounces:
		b["t"]  += delta
		b["vy"] += hail_bounce_gravity * delta
		b["x"]  += b["vx"] * delta
		b["y"]  += b["vy"] * delta
		if b["t"] < hail_bounce_duration:
			alive_bounces[bounce_count] = b
			bounce_count += 1
	alive_bounces.resize(bounce_count)
	_hail_bounces = alive_bounces

	queue_redraw()

func _get_ground_y() -> float:
	if _wall_ref and "ground_y" in _wall_ref:
		return _wall_ref.ground_y
	var b := _get_draw_bounds()
	return b.y + b.w

# ── Rain update ───────────────────────────────────────────────────────────────
# Moves every drop, rebuilds packed line arrays in the same pass — no second
# iteration. Replaces the old per-drop draw_line() with draw_multiline().
func _update_rain(delta: float) -> void:
	var dx  := _rain_udx + rain_wind / rain_speed
	var dy  := _rain_udy
	var b   := _get_draw_bounds()
	var ground_y := _get_ground_y()

	for i in range(LAYERS):
		_rain_lines[i].clear()

	for i in range(_drops.size()):
		var d := _drops[i]
		d["x"] += (dx + d["wx"]) * d["speed"] * delta
		d["y"] += dy * d["speed"] * delta

		var out_bottom = d["y"] >= ground_y
		var out_sides  = d["x"] > b.x + b.z + 300.0 or d["x"] < b.x - 300.0

		if out_bottom or out_sides:
			if out_bottom:
				_spawn_splash(d["x"], ground_y, d["alpha"], d["layer"])
			d = _make_drop(false)
			_drops[i] = d

		_append_rain_line(d)

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

func _update_lightning(delta: float) -> void:
	if _lightning_flash_timer > 0.0:
		_lightning_flash_timer -= delta
	if _lightning_bolt_timer > 0.0:
		_lightning_bolt_timer -= delta
		if _lightning_bolt_timer <= 0.0:
			_lightning_active = false

	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_interval = _drop_rng.randf_range(
			lerp(lightning_max_interval, lightning_min_interval, intensity),
			lightning_max_interval
		)
		_lightning_timer = _lightning_interval
		_trigger_lightning_strike()

func _update_fog(delta: float) -> void:
	var n := _fog_offsets.size()
	for i in range(n):
		_fog_offsets[i] += fog_scroll_speeds[i % fog_scroll_speeds.size()] * delta

# ── Snow update ───────────────────────────────────────────────────────────────
# Moves flakes and rebuilds packed circle arrays in one pass.
func _update_snow(delta: float) -> void:
	var b        := _get_draw_bounds()
	var ground_y := _get_ground_y()
	var sway_t   := _time * snow_sway_frequency * TAU   # precomputed once

	for i in range(LAYERS):
		_snow_points[i].clear()
		_snow_radii[i].clear()

	for i in range(_snowflakes.size()):
		var f := _snowflakes[i]
		f["y"] += f["speed"] * delta
		f["x"] += sin(sway_t + f["phase"]) * f["drift"] * delta

		if f["y"] >= ground_y or f["x"] > b.x + b.z + 80.0 or f["x"] < b.x - 80.0:
			f = _make_flake(false)
			_snowflakes[i] = f
		else:
			_snowflakes[i] = f

		var layer: int = f["layer"]
		_snow_points[layer].append(Vector2(f["x"], f["y"]))
		_snow_radii[layer].append(f["radius"])

# ── Hail update ───────────────────────────────────────────────────────────────
# Moves hailstones and rebuilds packed arrays in one pass.
func _update_hail(delta: float) -> void:
	var dx  := _hail_udx + hail_wind / hail_speed
	var dy  := _hail_udy
	var b   := _get_draw_bounds()
	var ground_y := _get_ground_y()

	for i in range(LAYERS):
		_hail_points[i].clear()
		_hail_radii[i].clear()
		_hail_streaks[i].clear()

	for i in range(_hailstones.size()):
		var s := _hailstones[i]
		s["x"] += dx * s["speed"] * delta
		s["y"] += dy * s["speed"] * delta

		var out_bottom = s["y"] >= ground_y
		var out_sides  = s["x"] > b.x + b.z + 200.0 or s["x"] < b.x - 200.0

		if out_bottom or out_sides:
			if out_bottom and _drop_rng.randf() < hail_bounce_chance * intensity:
				_spawn_hail_bounce(s["x"], ground_y, s["alpha"], s["radius"])
			s = _make_hailstone(false)
			_hailstones[i] = s

		_append_hail_stone(s)

func _spawn_splash(sx: float, gy: float, drop_alpha: float, _layer: int) -> void:
	if _drop_rng.randf() > 0.12:
		return
	_splashes.append({
		"x":     sx,
		"gy":    gy,
		"t":     0.0,
		"alpha": drop_alpha * clamp(intensity, 0.3, 0.7),
	})

func _spawn_hail_bounce(sx: float, gy: float, drop_alpha: float, radius: float) -> void:
	var angle := _drop_rng.randf_range(-PI * 0.6, PI * 0.6)
	_hail_bounces.append({
		"x":      sx,
		"y":      gy,
		"vx":     cos(angle) * hail_bounce_speed * _drop_rng.randf_range(0.4, 1.0),
		"vy":     -hail_bounce_speed * _drop_rng.randf_range(0.3, 0.8),
		"t":      0.0,
		"alpha":  drop_alpha * 0.7,
		"radius": radius * 0.6,
	})


# =============================================================================
# NIGHT PROCESS HELPERS
# =============================================================================

func _update_night_lamp(_delta: float) -> void:
	var desired_dir: Vector2
	if _has_player and _lamp_target_world != Vector2.ZERO:
		var to_target := _lamp_target_world - _player_head_world
		desired_dir = to_target.normalized() if to_target.length() > 2.0 else Vector2(0.0, 1.0)
	else:
		desired_dir = Vector2(0.0, 1.0)

	_lamp_dir_smooth = _lamp_dir_smooth.lerp(
		desired_dir, LAMP_DIR_LERP * get_process_delta_time()).normalized()

func _update_night_lights() -> void:
	var target_energy := night_lamp_energy * _blend * intensity
	if _headlamp:
		if _has_player:
			_headlamp.position = to_local(_player_head_world)
		_headlamp.energy   = target_energy
		_headlamp.rotation = _lamp_dir_smooth.angle() + PI * 0.5
	if _ambient_light:
		if _has_player:
			_ambient_light.position = to_local(_player_head_world)
		_ambient_light.energy = night_ambient_energy * _blend * intensity


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
		WeatherType.LIGHTNING:
			_draw_lightning_flash()
			_draw_rain_streaks()
			_draw_splashes()
			_draw_rain_fog()
			_draw_lightning_bolt()
		WeatherType.FOG:
			_draw_fog_ambient()
			_draw_fog_layers()
			_draw_fog_ground()
			_draw_fog_vignette()
		WeatherType.HAIL:
			_draw_hail_fog()
			_draw_hailstones()
			_draw_hail_bounces()
			_draw_splashes()
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
# RAIN DRAW — batched via draw_multiline()
# =============================================================================

func _draw_rain_streaks() -> void:
	# Rebuild per-layer color cache (cheap: 3 Color constructions per frame)
	for layer in range(LAYERS):
		var alpha_scale = lerp(0.45, 1.0, float(layer) / float(LAYERS - 1))
		# Use a representative drop alpha (mid-range) modulated by blend/intensity
		var a = 0.75 * alpha_scale * _blend * intensity
		if a < 0.02:
			continue
		if _rain_lines[layer].size() < 2:
			continue
		var line_w = lerp(1.0, 2.2, float(layer) / float(LAYERS - 1))
		draw_multiline(
			_rain_lines[layer],
			Color(rain_color.r, rain_color.g, rain_color.b, a),
			line_w)

func _draw_splashes() -> void:
	var rc := Color(rain_color.r + 0.10, rain_color.g + 0.05, rain_color.b + 0.03)
	for s in _splashes:
		var t_norm = clamp(s["t"] / splash_duration, 0.0, 1.0)
		var ring_r  = t_norm * splash_radius * 2.2
		var ring_a  = (1.0 - t_norm) * s["alpha"] * _blend * 0.55
		if ring_r > 0.3 and ring_a > 0.01:
			_draw_ellipse_ring(s["x"], s["gy"], ring_r, ring_r * 0.28, ring_a, rc, 1.0)

func _draw_ellipse_ring(cx: float, cy: float, rx: float, ry: float,
						alpha: float, color: Color, line_w: float) -> void:
	if rx < 0.5 or ry < 0.5 or alpha < 0.01:
		return
	const STEPS := 14
	var pts := PackedVector2Array()
	pts.resize(STEPS + 1)
	for i in range(STEPS + 1):
		var angle := (float(i) / float(STEPS)) * TAU
		pts[i] = Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry)
	draw_polyline(pts, Color(color.r, color.g, color.b, alpha), line_w, true)

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
# SNOW DRAW — batched via per-layer circle loop (no layer filter branch)
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
		var pts  := _snow_points[layer]
		var rads := _snow_radii[layer]
		if pts.is_empty():
			continue
		var depth_t := float(layer) / float(LAYERS - 1)
		var a = lerp(0.30, 0.65, depth_t) * _blend * intensity
		if a < 0.02:
			continue
		var color := Color(snow_color.r, snow_color.g, snow_color.b, a)
		var n     := pts.size()
		for j in range(n):
			draw_circle(pts[j], rads[j], color)

func _draw_snow_accumulation() -> void:
	var b        := _get_draw_bounds()
	var ground_y := _get_ground_y()
	var strip_h  = snow_accum_height * clamp(intensity, 0.2, 1.0)
	var a_top    := snow_accum_alpha * _blend * intensity
	_draw_grad_quad(b.x, ground_y - strip_h, b.z, ground_y,
		Color(snow_color.r, snow_color.g, snow_color.b, 0.0),
		Color(snow_color.r, snow_color.g, snow_color.b, a_top))


# =============================================================================
# LIGHTNING DRAW
# =============================================================================

func _draw_lightning_flash() -> void:
	if _lightning_flash_timer <= 0.0:
		return
	var b     := _get_draw_bounds()
	var t     = clamp(_lightning_flash_timer / lightning_flash_duration, 0.0, 1.0)
	var alpha = t * t * 0.55 * _blend * intensity
	draw_rect(
		Rect2(b.x, b.y, b.z, b.w),
		Color(lightning_flash_color.r, lightning_flash_color.g, lightning_flash_color.b, alpha))

func _draw_lightning_bolt() -> void:
	if not _lightning_active or _lightning_bolt_points.size() < 2:
		return
	var t     = clamp(_lightning_bolt_timer / lightning_bolt_duration, 0.0, 1.0)
	var alpha = t * _blend * intensity

	_draw_bolt_path(_lightning_bolt_points,
		Color(lightning_glow_color.r, lightning_glow_color.g, lightning_glow_color.b, alpha * 0.5),
		lightning_glow_width)
	_draw_bolt_path(_lightning_bolt_points,
		Color(lightning_bolt_color.r, lightning_bolt_color.g, lightning_bolt_color.b, alpha),
		lightning_bolt_width)

	for branch in _lightning_branches:
		if branch.size() < 2:
			continue
		_draw_bolt_path(branch,
			Color(lightning_glow_color.r, lightning_glow_color.g, lightning_glow_color.b, alpha * 0.25),
			lightning_glow_width * 0.6)
		_draw_bolt_path(branch,
			Color(lightning_bolt_color.r, lightning_bolt_color.g, lightning_bolt_color.b, alpha * 0.65),
			lightning_bolt_width * 0.55)

func _draw_bolt_path(pts: Array[Vector2], color: Color, width: float) -> void:
	# Convert to PackedVector2Array for draw_polyline — single draw call per bolt segment
	var packed := PackedVector2Array(pts)
	draw_polyline(packed, color, width, true)


# =============================================================================
# FOG DRAW
# =============================================================================

func _draw_fog_ambient() -> void:
	var b := _get_draw_bounds()
	var a := fog_ambient_darken * _blend * intensity
	draw_rect(
		Rect2(b.x, b.y, b.z, b.w),
		Color(fog_color.r * 0.85, fog_color.g * 0.85, fog_color.b * 0.85, a))

func _draw_fog_layers() -> void:
	if _fog_offsets.is_empty():
		return
	var b        := _get_draw_bounds()
	var y_cursor := b.y

	for i in range(fog_layers):
		var layer_h    = b.w * fog_layer_heights[i % fog_layer_heights.size()]
		var base_alpha = fog_layer_alphas[i % fog_layer_alphas.size()] * _blend * intensity
		var offset     := fmod(_fog_offsets[i], b.z + 400.0)

		for tile in range(2):
			var tile_x := b.x - 200.0 + offset + float(tile) * (b.z + 400.0) - (b.z + 400.0)
			var mid_a  = base_alpha * (0.6 + 0.4 * sin(_time * 0.3 + float(i) * 1.7))
			_draw_grad_quad(tile_x, y_cursor, b.z + 400.0, y_cursor + layer_h * 0.5,
				Color(fog_color.r, fog_color.g, fog_color.b, 0.0),
				Color(fog_color.r, fog_color.g, fog_color.b, mid_a))
			_draw_grad_quad(tile_x, y_cursor + layer_h * 0.5, b.z + 400.0, y_cursor + layer_h,
				Color(fog_color.r, fog_color.g, fog_color.b, mid_a),
				Color(fog_color.r, fog_color.g, fog_color.b, 0.0))

		y_cursor += layer_h * 0.55

func _draw_fog_ground() -> void:
	var b        := _get_draw_bounds()
	var ground_y := _get_ground_y()
	var strip_h  = fog_ground_height * clamp(intensity, 0.2, 1.0)
	var a_top    := fog_ground_alpha * _blend * intensity
	_draw_grad_quad(b.x, ground_y - strip_h, b.z, ground_y,
		Color(fog_color.r, fog_color.g, fog_color.b, 0.0),
		Color(fog_color.r, fog_color.g, fog_color.b, a_top))

func _draw_fog_vignette() -> void:
	var b  := _get_draw_bounds()
	var va := fog_vignette_alpha * _blend * intensity
	var vw := b.z * 0.22
	var vc := Color(fog_color.r * 0.6, fog_color.g * 0.6, fog_color.b * 0.6)

	_draw_grad_quad(b.x, b.y, vw, b.y + b.w,
		Color(vc.r, vc.g, vc.b, va),
		Color(vc.r, vc.g, vc.b, 0.0))
	_draw_grad_quad(b.x + b.z - vw, b.y, vw, b.y + b.w,
		Color(vc.r, vc.g, vc.b, 0.0),
		Color(vc.r, vc.g, vc.b, va))


# =============================================================================
# HAIL DRAW — batched circles + draw_multiline() for streaks
# =============================================================================

func _draw_hail_fog() -> void:
	var b    := _get_draw_bounds()
	var haze = lerp(0.0, 0.12, intensity * _blend)
	_draw_grad_quad(b.x, b.y, b.z, b.y + b.w,
		Color(hail_fog_color.r, hail_fog_color.g, hail_fog_color.b, haze * 0.3),
		Color(hail_fog_color.r, hail_fog_color.g, hail_fog_color.b, haze))

func _draw_hailstones() -> void:
	for layer in range(LAYERS):
		var pts     := _hail_points[layer]
		var rads    := _hail_radii[layer]
		var streaks := _hail_streaks[layer]
		if pts.is_empty():
			continue
		var depth_t := float(layer) / float(LAYERS - 1)
		var a       = lerp(0.55, 0.90, depth_t) * _blend * intensity
		if a < 0.02:
			continue
		var color        := Color(hail_color.r, hail_color.g, hail_color.b, a)
		var streak_color := Color(hail_color.r, hail_color.g, hail_color.b, a * 0.45)
		# Draw all circles for this layer
		var n := pts.size()
		for j in range(n):
			draw_circle(pts[j], rads[j], color)
		# Draw all streaks for this layer — one multiline call
		if streaks.size() >= 2:
			draw_multiline(streaks, streak_color, rads[0] * 0.5)

func _draw_hail_bounces() -> void:
	for bc in _hail_bounces:
		var t_norm = clamp(bc["t"] / hail_bounce_duration, 0.0, 1.0)
		var a      = (1.0 - t_norm) * bc["alpha"] * _blend
		if a < 0.02:
			continue
		draw_circle(
			Vector2(bc["x"], bc["y"]),
			bc["radius"],
			Color(hail_impact_color.r, hail_impact_color.g, hail_impact_color.b, a))


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

func get_lightning_sky_override() -> Dictionary:
	return {
		"sky_top":      lightning_sky_top,
		"sky_horizon":  lightning_sky_horizon,
		"cloud_color":  lightning_cloud_color,
		"cloud_shadow": lightning_cloud_shadow,
		"fog_color":    lightning_fog_color,
	}

func get_fog_sky_override() -> Dictionary:
	return {
		"sky_top":      fog_sky_top,
		"sky_horizon":  fog_sky_horizon,
		"cloud_color":  fog_cloud_color,
		"cloud_shadow": fog_cloud_shadow,
		"fog_color":    fog_fog_color,
	}

func get_hail_sky_override() -> Dictionary:
	return {
		"sky_top":      hail_sky_top,
		"sky_horizon":  hail_sky_horizon,
		"cloud_color":  hail_cloud_color,
		"cloud_shadow": hail_cloud_shadow,
		"fog_color":    hail_fog_color,
	}

func get_active_sky_override() -> Dictionary:
	match weather:
		WeatherType.RAIN:      return get_rain_sky_override()
		WeatherType.NIGHT:     return get_night_sky_override()
		WeatherType.SNOW:      return get_snow_sky_override()
		WeatherType.LIGHTNING: return get_lightning_sky_override()
		WeatherType.FOG:       return get_fog_sky_override()
		WeatherType.HAIL:      return get_hail_sky_override()
		_:                     return {}

func get_hold_friction_modifier() -> float:
	match weather:
		WeatherType.RAIN:      return lerp(1.0, 0.60, _blend)
		WeatherType.SNOW:      return lerp(1.0, 0.50, _blend)
		WeatherType.LIGHTNING: return lerp(1.0, 0.58, _blend)
		WeatherType.FOG:       return lerp(1.0, 0.82, _blend)
		WeatherType.HAIL:      return lerp(1.0, 0.45, _blend)
		_:                     return 1.0

func get_stamina_drain_modifier() -> float:
	match weather:
		WeatherType.RAIN:      return lerp(1.0, 1.28, _blend)
		WeatherType.NIGHT:     return lerp(1.0, 1.12, _blend)
		WeatherType.SNOW:      return lerp(1.0, 1.35, _blend)
		WeatherType.LIGHTNING: return lerp(1.0, 1.40, _blend)
		WeatherType.FOG:       return lerp(1.0, 1.15, _blend)
		WeatherType.HAIL:      return lerp(1.0, 1.45, _blend)
		_:                     return 1.0

func get_gravity_modifier() -> float:
	return 1.0

func get_wind_force() -> Vector2:
	match weather:
		WeatherType.RAIN:
			return Vector2(rain_wind * 0.3 * _blend, 0.0)
		WeatherType.SNOW:
			return Vector2(sin(_time * snow_sway_frequency * TAU) * snow_drift_speed * 0.15 * _blend, 0.0)
		WeatherType.LIGHTNING:
			var gust := sin(_time * 1.3) * 0.5 + sin(_time * 3.1) * 0.3 + sin(_time * 7.4) * 0.2
			return Vector2(gust * 80.0 * _blend * intensity, 0.0)
		WeatherType.HAIL:
			return Vector2(hail_wind * 0.25 * _blend, 0.0)
		_:
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
