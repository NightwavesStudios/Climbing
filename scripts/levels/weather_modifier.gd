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

var splash_duration  := 0.30
var splash_radius    := 6.0

var rain_sky_top      := Color(0.14, 0.16, 0.22)
var rain_sky_horizon  := Color(0.28, 0.30, 0.36)
var rain_cloud_color  := Color(0.30, 0.32, 0.38, 1.0)
var rain_cloud_shadow := Color(0.18, 0.20, 0.26)
var rain_fog_color    := Color(0.22, 0.24, 0.30, 0.28)

var _time: float = 0.0
# Each drop is a Dictionary with stable identity — no re-seeding every frame.
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

# ─── Stable per-drop RNG (seeded once at creation) ───────────────────────────
var _drop_rng := RandomNumberGenerator.new()

func _ready() -> void:
	z_index = 20
	_wall_ref = get_parent() if get_parent().has_method("get_bounds") else null
	_drop_rng.randomize()
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
	for i in range(count):
		_drops.append(_make_drop(true))

# ─── Drop factory — uses the stable _drop_rng, no frame-time seed ─────────────
func _make_drop(spread: bool) -> Dictionary:
	var b := _get_draw_bounds()
	var layer := _drop_rng.randi() % LAYERS
	var speed_scale = lerp(0.6, 1.0, float(layer) / float(LAYERS - 1))
	var alpha_scale = lerp(0.45, 1.0, float(layer) / float(LAYERS - 1))
	var x := _drop_rng.randf_range(b.x - 200.0, b.x + b.z + 200.0)
	var y := _drop_rng.randf_range(b.y, b.y + b.w) if spread \
			else b.y - _drop_rng.randf() * 150.0
	return {
		"x":     x,
		"y":     y,
		"layer": layer,
		"speed": rain_speed * speed_scale * (0.82 + _drop_rng.randf() * 0.36),
		"alpha": (0.55 + _drop_rng.randf() * 0.45) * alpha_scale,
		"len":   rain_streak_len * speed_scale * (0.7 + _drop_rng.randf() * 0.6),
		"width": lerp(1.0, 2.2, float(layer) / float(LAYERS - 1)),
		# Slight per-drop horizontal wobble to break up uniform slant
		"wx":    (_drop_rng.randf() - 0.5) * 0.04,
	}

func _process(delta: float) -> void:
	if weather == WeatherType.NONE and _blend <= 0.0:
		return

	_time += delta

	var target_blend := intensity if weather == WeatherType.RAIN else 0.0
	_blend = move_toward(_blend, target_blend, BLEND_SPEED * delta)

	if weather == WeatherType.RAIN:
		_update_rain(delta)

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
			_audio.volume_db = move_toward(_audio.volume_db, target_db, 6.0 * delta)

	# Advance splashes — simple ring ripple only, no physics
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

# ─── Spawn a minimal ground ripple — 2D side view, keep it subtle ─────────────
func _spawn_splash(sx: float, gy: float, drop_alpha: float, layer: int) -> void:
	# Only track a fraction of hits to keep count very low
	if _drop_rng.randf() > 0.12:
		return
	_splashes.append({
		"x":     sx,
		"gy":    gy,
		"t":     0.0,
		"alpha": drop_alpha * clamp(intensity, 0.3, 0.7),
	})

func _draw() -> void:
	if _blend < 0.01:
		return
	_draw_rain_streaks()
	_draw_splashes()
	_draw_rain_fog()

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
			draw_line(
				Vector2(px, py),
				Vector2(px - udx * d["len"], py - udy * d["len"]),
				Color(rain_color.r, rain_color.g, rain_color.b, a),
				d["width"], true)

# ─── Minimal splash: one tiny expanding ellipse ring at ground level ──────────
func _draw_splashes() -> void:
	var rc := Color(rain_color.r + 0.10, rain_color.g + 0.05, rain_color.b + 0.03)
	for s in _splashes:
		var t_norm = clamp(s["t"] / splash_duration, 0.0, 1.0)
		var ring_r  = t_norm * splash_radius * 2.2
		var ring_a  = (1.0 - t_norm) * s["alpha"] * _blend * 0.55
		if ring_r > 0.3 and ring_a > 0.01:
			_draw_ellipse_ring(s["x"], s["gy"], ring_r, ring_r * 0.28, ring_a, rc, 1.0)

# ─── Draw an ellipse as a polyline (no fill) ─────────────────────────────────
func _draw_ellipse_ring(cx: float, cy: float, rx: float, ry: float,
						alpha: float, color: Color, line_w: float) -> void:
	if rx < 0.5 or ry < 0.5 or alpha < 0.01:
		return
	const STEPS := 14
	var prev := Vector2.ZERO
	for i in range(STEPS + 1):
		var angle := (float(i) / float(STEPS)) * TAU
		var pt := Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry)
		if i > 0:
			draw_line(prev, pt, Color(color.r, color.g, color.b, alpha), line_w, true)
		prev = pt

# ─── Gradient quad helper — two triangles for correct per-vertex colour ───────
func _draw_grad_quad(x: float, y0: float, w: float, y1: float,
					 c_top: Color, c_bot: Color) -> void:
	var tl := Vector2(x,     y0)
	var tr := Vector2(x + w, y0)
	var br := Vector2(x + w, y1)
	var bl := Vector2(x,     y1)
	draw_polygon(PackedVector2Array([tl, tr, br]), PackedColorArray([c_top, c_top, c_bot]))
	draw_polygon(PackedVector2Array([tl, br, bl]), PackedColorArray([c_top, c_bot, c_bot]))

# ─── Atmospheric fog — gradient triangle pairs ────────────────────────────────
func _draw_rain_fog() -> void:
	var b        := _get_draw_bounds()
	var ground_y := _get_ground_y()
	var total_h  := ground_y - b.y + 300.0
	var w        := b.z

	# ── Sky haze: quadratic curve — nearly invisible at top, peaks at ground ──
	var haze_max_a = lerp(0.0, 0.35, intensity * _blend)
	var haze_steps := 8
	for i in range(haze_steps):
		var t0     := float(i)     / float(haze_steps)
		var t1     := float(i + 1) / float(haze_steps)
		var a0     = haze_max_a * (t0 * t0)
		var a1     = haze_max_a * (t1 * t1)
		var y0     := b.y + t0 * total_h
		var y1     := b.y + t1 * total_h
		_draw_grad_quad(b.x, y0, w, y1,
			Color(0.08, 0.11, 0.18, a0),
			Color(0.10, 0.14, 0.22, a1))

	# ── Ground mist: fades upward from ground line ────────────────────────────
	var mist_max_a   = lerp(0.0, 0.20, intensity * _blend)
	var mist_h       = lerp(30.0, 110.0, intensity)
	var mist_col     := Color(0.55, 0.64, 0.78)
	var mist_steps   := 6
	for i in range(mist_steps):
		var t0 := float(i)     / float(mist_steps)
		var t1 := float(i + 1) / float(mist_steps)
		var a0 = mist_max_a * (1.0 - t0)
		var a1 = mist_max_a * (1.0 - t1)
		var y0 = ground_y - t0 * mist_h
		var y1 = ground_y - t1 * mist_h
		_draw_grad_quad(b.x, y0, w, y1,
			Color(mist_col.r, mist_col.g, mist_col.b, a0),
			Color(mist_col.r, mist_col.g, mist_col.b, a1))

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
