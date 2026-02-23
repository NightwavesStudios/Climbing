extends Node2D
class_name WeatherModifier

enum WeatherType {
	NONE,
	RAIN,
}

var weather: int = WeatherType.NONE : set = set_weather
var intensity: float = 1.0

var rain_color       := Color(0.72, 0.82, 0.95, 0.72)
var rain_streak_len  := 80.0
var rain_angle_deg   := 12.0
var rain_speed       := 1100.0
var rain_density     := 600
var rain_wind        := 0.0

var splash_duration  := 0.22
var splash_radius    := 8.0

var rain_sky_top      := Color(0.14, 0.16, 0.22)
var rain_sky_horizon  := Color(0.28, 0.30, 0.36)
var rain_cloud_color  := Color(0.30, 0.32, 0.38, 1.0)
var rain_cloud_shadow := Color(0.18, 0.20, 0.26)
var rain_fog_color    := Color(0.22, 0.24, 0.30, 0.28)

var _time: float = 0.0
var _drops: Array[Dictionary] = []
var _splashes: Array[Dictionary] = []
var _wall_ref: Node2D = null

var _blend: float = 0.0
const BLEND_SPEED := 1.2
const LAYERS := 3

var _audio: AudioStreamPlayer = null
var _audio_fading_in: bool = false
var _audio_fade_elapsed: float = 0.0
const RAIN_SFX_PATH    := "res://assets/audio/sfx/rain_sfx.wav"
const RAIN_VOLUME_DB   := -4.0
const RAIN_VOLUME_MIN  := -18.0
const FADE_IN_DURATION := 2.5

func _ready() -> void:
	z_index = 20
	_wall_ref = get_parent() if get_parent().has_method("get_bounds") else null
	_setup_audio()
	set_weather(weather)

func _setup_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "RainSFX"
	add_child(_audio)
	if not ResourceLoader.exists(RAIN_SFX_PATH):
		push_warning("WeatherModifier: rain SFX not found at " + RAIN_SFX_PATH)
		return
	_audio.stream = load(RAIN_SFX_PATH)
	_audio.bus = "Master"
	_audio.volume_db = -80.0
	_audio.autoplay = false

func set_weather(new_weather: int) -> void:
	weather = new_weather
	_drops.clear()
	_splashes.clear()
	if weather == WeatherType.RAIN:
		_init_rain()
		if _audio and _audio.stream and not _audio.playing:
			_audio.volume_db = -80.0
			_audio.play()
			_audio_fading_in = true
			_audio_fade_elapsed = 0.0
	else:
		if _audio and _audio.playing:
			_audio.stop()
		_audio_fading_in = false
	queue_redraw()

func _init_rain() -> void:
	var count = int(rain_density * clamp(intensity, 0.05, 1.0))
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(count):
		_drops.append(_make_drop(rng, true))

func _make_drop(rng: RandomNumberGenerator, spread: bool) -> Dictionary:
	var b := _get_draw_bounds()
	var layer := rng.randi() % LAYERS
	var speed_scale = lerp(0.6, 1.0, float(layer) / float(LAYERS - 1))
	var alpha_scale = lerp(0.45, 1.0, float(layer) / float(LAYERS - 1))
	var x := rng.randf_range(b.x - 200.0, b.x + b.z + 200.0)
	var y := rng.randf_range(b.y, b.y + b.w) if spread else b.y - rng.randf() * 150.0
	return {
		"x": x, "y": y,
		"layer": layer,
		"speed": rain_speed * speed_scale * (0.82 + rng.randf() * 0.36),
		"alpha": (0.55 + rng.randf() * 0.45) * alpha_scale,
		"len":   rain_streak_len * speed_scale * (0.7 + rng.randf() * 0.6),
		"width": lerp(1.0, 2.2, float(layer) / float(LAYERS - 1)),
	}

func _process(delta: float) -> void:
	if weather == WeatherType.NONE and _blend <= 0.0:
		return

	_time += delta

	var target_blend := intensity if weather == WeatherType.RAIN else 0.0
	_blend = move_toward(_blend, target_blend, BLEND_SPEED * delta)

	if weather == WeatherType.RAIN:
		_update_rain(delta)

		# Volume tracks intensity — louder when heavier
		var target_db = lerp(RAIN_VOLUME_MIN, RAIN_VOLUME_DB, intensity)
		if _audio_fading_in:
			_audio_fade_elapsed += delta
			var t = clamp(_audio_fade_elapsed / FADE_IN_DURATION, 0.0, 1.0)
			var eased = 1.0 - (1.0 - t) * (1.0 - t)
			_audio.volume_db = lerp(-80.0, target_db, eased)
			if t >= 1.0:
				_audio.volume_db = target_db
				_audio_fading_in = false
		else:
			# Smoothly track intensity changes after fade-in
			_audio.volume_db = move_toward(_audio.volume_db, target_db, 6.0 * delta)

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
	var dx := sin(angle_rad) + rain_wind / rain_speed
	var dy := cos(angle_rad)
	var b  := _get_draw_bounds()
	var ground_y := _get_ground_y()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_time * 4000.0) ^ 0xC0FFEE

	for i in range(_drops.size()):
		var d := _drops[i]
		d["x"] += dx * d["speed"] * delta
		d["y"] += dy * d["speed"] * delta
		if d["y"] >= ground_y or d["x"] > b.x + b.z + 300.0 or d["x"] < b.x - 300.0:
			if d["y"] >= ground_y:
				_splashes.append({"x": d["x"], "y": ground_y, "t": 0.0, "alpha": d["alpha"] * 0.8, "layer": d["layer"]})
			_drops[i] = _make_drop(rng, false)
		else:
			_drops[i] = d

func _draw() -> void:
	if _blend < 0.01:
		return
	_draw_rain_atmosphere()
	_draw_rain_streaks()
	_draw_splashes()
	_draw_rain_mist()

func _draw_rain_atmosphere() -> void:
	var b := _get_draw_bounds()
	# Heavier overlay — scales strongly with intensity for dramatic effect
	var atmo_alpha = lerp(0.18, 0.52, intensity) * _blend
	draw_rect(Rect2(b.x, b.y, b.z, b.w + 2000.0), Color(0.05, 0.07, 0.12, atmo_alpha), true)
	# Second pass: cool blue-grey tint in the lower half to sell the wet look
	draw_rect(Rect2(b.x, b.y + b.w * 0.5, b.z, b.w * 0.5 + 2000.0),
			  Color(0.10, 0.14, 0.20, atmo_alpha * 0.5), true)

func _draw_rain_streaks() -> void:
	var angle_rad := deg_to_rad(rain_angle_deg)
	var udx := sin(angle_rad)
	var udy := cos(angle_rad)
	for layer in range(LAYERS):
		for d in _drops:
			if d["layer"] != layer:
				continue
			var a = d["alpha"] * _blend * intensity
			if a < 0.02:
				continue
			var px: float = d["x"]
			var py: float = d["y"]
			draw_line(Vector2(px, py), Vector2(px - udx * d["len"], py - udy * d["len"]),
					  Color(rain_color.r, rain_color.g, rain_color.b, a), d["width"], true)

func _draw_splashes() -> void:
	for s in _splashes:
		var t_norm = s["t"] / splash_duration
		var eased  = 1.0 - (1.0 - t_norm) * (1.0 - t_norm)
		var r      = splash_radius * eased * (0.8 + intensity * 0.6)
		var a      = s["alpha"] * (1.0 - t_norm) * _blend
		var cx: float = s["x"]
		var cy: float = s["y"]
		for si in range(12):
			var ang0 := PI + float(si) / 12.0 * PI
			var ang1 := PI + float(si + 1) / 12.0 * PI
			draw_line(
				Vector2(cx + cos(ang0) * r * 1.8, cy + sin(ang0) * r * 0.5),
				Vector2(cx + cos(ang1) * r * 1.8, cy + sin(ang1) * r * 0.5),
				Color(rain_color.r, rain_color.g + 0.08, rain_color.b + 0.10, a), 1.4, true)

func _draw_rain_mist() -> void:
	var b := _get_draw_bounds()
	var ground_y := _get_ground_y()
	var mist_a = lerp(0.06, 0.18, intensity) * _blend
	# More mist bands and taller for heavier rain
	var band_count := 3 + int(intensity * 4)
	for mi in range(band_count):
		var band_h = lerp(14.0, 28.0, intensity)
		draw_rect(Rect2(b.x, ground_y - float(mi) * band_h - 6.0, b.z, band_h),
				  Color(0.68, 0.74, 0.84, mist_a * (1.0 - float(mi) / float(band_count))), true)

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

func get_hold_friction_modifier() -> float:
	if weather == WeatherType.RAIN:
		return lerp(1.0, 0.60, _blend)
	return 1.0

func get_stamina_drain_modifier() -> float:
	if weather == WeatherType.RAIN:
		return lerp(1.0, 1.28, _blend)
	return 1.0

func get_gravity_modifier() -> float:
	return 1.0

func get_wind_force() -> Vector2:
	if weather == WeatherType.RAIN:
		return Vector2(rain_wind * 0.3 * _blend, 0.0)
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
