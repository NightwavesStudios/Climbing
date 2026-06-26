## menu_background.gd
## A self-contained animated cinematic background for the main menu.
## Attach to a Node2D that lives behind all UI.  No holds, no wall editor.
##
## Features
##   • Full sky that cycles slowly through dawn → day → sunset → dusk → night
##   • 4-layer parallax mountains that respond to mouse movement
##   • Animated multi-layer cloud system
##   • Smooth radial-gradient sun with warm golden-hour palette
##   • All colour palettes derived from the current cycle position — nothing hardcoded
##
## Usage
##   Add as an AutoLoad or as a child node, then call  start()  (called automatically
##   in _ready).  You can also call  set_time_of_day(0..1)  to jump to a moment.
class_name MenuBackground
extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
# EXPORTS
# ─────────────────────────────────────────────────────────────────────────────

## Total seconds for one full day/night cycle.
@export var cycle_duration: float       = 180.0
## How strongly the mountains drift with the mouse (pixels).
@export var parallax_strength: Vector2  = Vector2(28.0, 14.0)
## Lerp speed for the parallax drift.
@export var parallax_speed:    float    = 2.8

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

const CLOUD_COUNT   = 5
const CLOUD_LAYERS  = 2
const REDRAW_HZ     = 60.0          # target internal redraws per second
const REDRAW_DT     = 1.0 / REDRAW_HZ

# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE STATE
# ─────────────────────────────────────────────────────────────────────────────

var _cycle_t:      float = 0.35     # 0..1, starts near sunset
var _cloud_time:   float = 0.0
var _redraw_timer: float = 0.0

var _clouds:       Array[Dictionary] = []
var _scenery_seed: int = 0

# Parallax
var _parallax_offset: Vector2 = Vector2.ZERO

# ─────────────────────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	z_index = -100
	_scenery_seed = randi()
	_clouds.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in CLOUD_COUNT:
		_clouds.append(_make_cloud(rng, true))

func _process(delta: float) -> void:
	_cycle_t = fmod(_cycle_t + delta / cycle_duration, 1.0)
	_cloud_time += delta
	_redraw_timer += delta

	# Update cloud positions every frame (cheap)
	_update_clouds(delta)

	# Limit GPU redraws
	if _redraw_timer >= REDRAW_DT:
		_redraw_timer = 0.0
		queue_redraw()

	# Mouse parallax
	var vp   := get_viewport_rect().size
	var mp   := get_viewport().get_mouse_position()
	var norm := (mp / vp - Vector2(0.5, 0.5)) * 2.0
	var tgt  := Vector2(-norm.x * parallax_strength.x, -norm.y * parallax_strength.y)
	_parallax_offset = _parallax_offset.lerp(tgt, delta * parallax_speed)

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

## Jump to a specific moment in the cycle.  0 = dawn, 0.25 = midday, 0.5 = sunset, 0.75 = night.
func set_time_of_day(t: float) -> void:
	_cycle_t = clampf(t, 0.0, 1.0)

# ─────────────────────────────────────────────────────────────────────────────
# COLOR PALETTE — derived entirely from cycle position
# ─────────────────────────────────────────────────────────────────────────────

## Returns a Dictionary with all scene colors for the current _cycle_t.
## t=0 dawn, t=0.25 midday, t=0.5 sunset, t=0.75 night, t=1 = dawn again.
func _get_palette() -> Dictionary:
	var t := _cycle_t

	# ── Key colour stops (dawn/day/sunset/dusk/night) ──────────────────────
	# sky_top
	var sky_tops := [
		Color(0.25, 0.18, 0.42),   # pre-dawn deep purple
		Color(0.92, 0.58, 0.78),   # dawn soft pink-purple
		Color(0.55, 0.68, 0.92),   # midday cool blue
		Color(0.72, 0.55, 0.85),   # afternoon lavender
		Color(0.95, 0.52, 0.68),   # sunset vibrant rose
		Color(0.65, 0.38, 0.58),   # dusk rich purple
		Color(0.09, 0.08, 0.22),   # night deep indigo
		Color(0.15, 0.12, 0.28),   # late night
		Color(0.25, 0.18, 0.42),   # loop
	]
	# sky_horizon
	var sky_horizons := [
		Color(0.85, 0.48, 0.55),
		Color(0.98, 0.72, 0.68),   # warm dawn
		Color(0.78, 0.85, 0.96),
		Color(0.88, 0.75, 0.92),
		Color(0.98, 0.68, 0.45),   # strong sunset orange-pink
		Color(0.78, 0.42, 0.55),
		Color(0.14, 0.16, 0.28),
		Color(0.18, 0.15, 0.32),
		Color(0.85, 0.48, 0.55),
	]
	# cloud color
	var cloud_colors := [
		Color(0.95, 0.82, 0.88, 0.78),
		Color(1.00, 0.88, 0.92, 0.88),
		Color(0.98, 0.96, 1.00, 0.92),
		Color(0.94, 0.90, 0.96, 0.85),
		Color(1.00, 0.82, 0.75, 0.88),
		Color(0.85, 0.65, 0.78, 0.78),
		Color(0.35, 0.38, 0.52, 0.65),
		Color(0.28, 0.30, 0.45, 0.55),
		Color(0.95, 0.82, 0.88, 0.78),
	]
	# sun / moon — richer golds
	var sun_colors := [
		Color(1.00, 0.64, 0.22),  # dawn warm
		Color(1.00, 0.86, 0.54),  # day golden
		Color(1.00, 0.86, 0.54),
		Color(1.00, 0.78, 0.36),
		Color(1.00, 0.52, 0.12),  # sunset deep orange
		Color(0.0,  0.0,  0.0 ),  # dusk (sun gone)
		Color(0.0,  0.0,  0.0 ),
		Color(0.0,  0.0,  0.0 ),
		Color(1.00, 0.64, 0.22),
	]
	# mountain colors — list of 4 layers per key frame (more purple/gray tones)
	var mtn_palettes := [
		[Color(0.38,0.26,0.40), Color(0.28,0.19,0.30), Color(0.19,0.13,0.22), Color(0.12,0.08,0.16)],
		[Color(0.68,0.48,0.62), Color(0.52,0.36,0.48), Color(0.38,0.26,0.36), Color(0.24,0.16,0.24)],
		[Color(0.58,0.66,0.82), Color(0.44,0.54,0.72), Color(0.32,0.42,0.60), Color(0.20,0.30,0.48)],
		[Color(0.65,0.52,0.70), Color(0.48,0.38,0.55), Color(0.35,0.28,0.42), Color(0.22,0.18,0.28)],
		[Color(0.58,0.42,0.52), Color(0.42,0.28,0.38), Color(0.28,0.18,0.26), Color(0.16,0.10,0.16)],
		[Color(0.42,0.28,0.38), Color(0.30,0.19,0.28), Color(0.20,0.12,0.19), Color(0.12,0.07,0.12)],
		[Color(0.12,0.11,0.20), Color(0.08,0.08,0.15), Color(0.05,0.05,0.10), Color(0.03,0.03,0.07)],
		[Color(0.16,0.14,0.24), Color(0.11,0.10,0.18), Color(0.07,0.07,0.13), Color(0.04,0.04,0.08)],
		[Color(0.38,0.26,0.40), Color(0.28,0.19,0.30), Color(0.19,0.13,0.22), Color(0.12,0.08,0.16)],
	]
	# ground top — grayish purple / rocky tones
	var ground_tops := [
		Color(0.32, 0.26, 0.36),
		Color(0.45, 0.38, 0.45),
		Color(0.38, 0.45, 0.35),
		Color(0.40, 0.42, 0.38),
		Color(0.42, 0.36, 0.40),   # grayish purple
		Color(0.30, 0.25, 0.32),
		Color(0.14, 0.14, 0.19),
		Color(0.12, 0.13, 0.18),
		Color(0.32, 0.26, 0.36),
	]

	# ── Key frame positions ────────────────────────────────────────────────
	var keys := [0.00, 0.12, 0.25, 0.40, 0.50, 0.62, 0.75, 0.90, 1.00]

	# Find surrounding keys
	var ki := 0
	for i in range(keys.size() - 1):
		if t >= keys[i] and t < keys[i + 1]:
			ki = i
			break

	var local_t: float = (t - keys[ki]) / (keys[ki + 1] - keys[ki])
	# Smooth the interpolation
	local_t = local_t * local_t * (3.0 - 2.0 * local_t)

	var pal := {}
	pal["sky_top"]    = (sky_tops[ki]    as Color).lerp(sky_tops[ki + 1],    local_t)
	pal["sky_horiz"]  = (sky_horizons[ki] as Color).lerp(sky_horizons[ki + 1], local_t)
	pal["cloud"]      = (cloud_colors[ki] as Color).lerp(cloud_colors[ki + 1], local_t)
	pal["sun"]        = (sun_colors[ki]   as Color).lerp(sun_colors[ki + 1],   local_t)
	pal["ground_top"] = (ground_tops[ki]  as Color).lerp(ground_tops[ki + 1],  local_t)

	var ml: Array = []
	for li in range(4):
		ml.append((mtn_palettes[ki][li] as Color).lerp(mtn_palettes[ki + 1][li], local_t))
	pal["mtn_layers"] = ml

	# Derived flags
	pal["has_sun"]   = pal["sun"].r + pal["sun"].g + pal["sun"].b > 0.05
	pal["has_moon"]  = t > 0.58 or t < 0.10
	pal["has_stars"] = t > 0.65 or t < 0.08
	pal["sun_angle"] = t * TAU   # sun arc position

	return pal

# ─────────────────────────────────────────────────────────────────────────────
# CLOUD SYSTEM
# ─────────────────────────────────────────────────────────────────────────────

func _make_cloud(rng: RandomNumberGenerator, spread: bool) -> Dictionary:
	var vp    := get_viewport_rect()
	var sx    := 70.0 + rng.randf() * 200.0 + float(rng.randi() % CLOUD_LAYERS) * 55.0
	var sy    := 24.0 + rng.randf() * 42.0
	var layer := rng.randi() % CLOUD_LAYERS
	var speed := (0.18 + rng.randf() * 0.28) * (1.0 + float(layer) * 0.55) * 38.0
	var alpha := 0.32 + rng.randf() * 0.38
	var y     := vp.size.y * (0.04 + rng.randf() * 0.40)
	var x     := vp.size.x * rng.randf() if spread else vp.size.x + sx + rng.randf() * 200.0
	return { "x": x, "y": y, "sx": sx, "sy": sy,
			 "speed": speed, "alpha": alpha, "layer": layer, "seed": rng.randi() }

func _update_clouds(delta: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_cloud_time * 80.0) ^ 0xDEADBEEF
	var speed_mult := 1.0
	for i in _clouds.size():
		var c = _clouds[i]
		c["x"] -= c["speed"] * delta * speed_mult
		if c["x"] + c["sx"] < -200.0:
			_clouds[i] = _make_cloud(rng, false)
		else:
			_clouds[i] = c

# ─────────────────────────────────────────────────────────────────────────────
# DRAW DISPATCH
# ─────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var pal := _get_palette()
	var vp  := get_viewport_rect()

	_draw_sky(vp, pal)
	if pal["has_stars"]: _draw_stars(vp, pal)
	if pal["has_moon"]:  _draw_moon(vp, pal)
	if pal["has_sun"]:   _draw_sun(vp, pal)
	_draw_mountains(vp, pal)
	_draw_clouds(pal)
	_draw_fog_base(vp, pal)
	_draw_ground(vp, pal)

# ─────────────────────────────────────────────────────────────────────────────
# SKY
# ─────────────────────────────────────────────────────────────────────────────

func _draw_sky(vp: Rect2, pal: Dictionary) -> void:
	var top   : Color = pal["sky_top"]
	var horiz : Color = pal["sky_horiz"]

	var ground_y := vp.size.y * 0.82
	var bands    := 22
	var total_h  := ground_y
	for i in bands:
		var t0 := float(i)     / float(bands)
		var t1 := float(i + 1) / float(bands)
		var c0 := top.lerp(horiz, t0 * t0)
		var c1 := top.lerp(horiz, t1 * t1)
		_draw_vgrad(0.0, t0 * total_h, vp.size.x, t1 * total_h, c0, c1)

	# Below horizon fill
	draw_rect(Rect2(0.0, ground_y, vp.size.x, vp.size.y - ground_y + 10.0), horiz, true)

# ─────────────────────────────────────────────────────────────────────────────
# STARS
# ─────────────────────────────────────────────────────────────────────────────

func _draw_stars(vp: Rect2, pal: Dictionary) -> void:
	var night_t := 0.0
	# Stars fade in after t=0.62 and before t=0.10
	if _cycle_t > 0.65:
		night_t = clampf((_cycle_t - 0.65) / 0.10, 0.0, 1.0)
	elif _cycle_t < 0.08:
		night_t = clampf((0.08 - _cycle_t) / 0.08, 0.0, 1.0)
	if night_t < 0.02: return

	var sky_top : Color = pal["sky_top"]
	for i in 90:
		var ss  := (_scenery_seed ^ 0xBEEF) + i * 17
		var sx  := _hf(ss)     * vp.size.x
		var sy  := _hf(ss + 1) * vp.size.y * 0.70
		var br  := (0.45 + _hf(ss + 2) * 0.55) * night_t
		var sz  := 0.8 + _hf(ss + 3) * 1.6
		var tw  := 0.72 + 0.28 * sin(_cloud_time * (1.4 + _hf(ss + 4) * 2.8) + float(i))
		# Only draw against dark sky
		if sky_top.v > 0.35: continue
		draw_circle(Vector2(sx, sy), sz, Color(1.0, 0.98, 0.95, br * tw))

# ─────────────────────────────────────────────────────────────────────────────
# SUN
# ─────────────────────────────────────────────────────────────────────────────

func _draw_sun(vp: Rect2, pal: Dictionary) -> void:
	var sc  : Color = pal["sun"]
	if sc.r + sc.g + sc.b < 0.01: return

	# Sun arc: rises left, sets right
	var ang := _cycle_t * TAU - TAU * 0.25
	var sx  := vp.size.x * 0.5 + cos(ang) * vp.size.x * 0.38
	var sy  := vp.size.y * 0.42 - sin(ang) * vp.size.y * 0.45
	var horizon_y := vp.size.y * 0.82
	if sy > horizon_y: return

	# Outer glow — soft atmospheric falloff
	for gi in range(12):
		var t := float(gi) / 12.0
		var r := 50.0 + t * 120.0
		var a := (0.042 - t * 0.038) * maxf(sc.a, 1.0)
		draw_circle(Vector2(sx, sy), r, Color(sc.r, sc.g, sc.b, maxf(a, 0.0)))

	# Single smooth sun disc — radial gradient from bright core to soft edge
	for gi in range(16):
		var t := float(gi) / 16.0
		var r := 48.0 * (1.0 - t * 0.94)  # 48 → ~3
		var a := (1.0 - t * t) * maxf(sc.a, 1.0)
		draw_circle(Vector2(sx, sy), r, Color(sc.r, sc.g, sc.b, a))

	# Horizon glow bar (only when sun is near horizon)
	var closeness := 1.0 - clampf(abs(sy - horizon_y) / (vp.size.y * 0.25), 0.0, 1.0)
	if closeness > 0.05:
		var gsteps := 12
		for gi in gsteps:
			var t0 := float(gi)     / float(gsteps)
			var t1 := float(gi + 1) / float(gsteps)
			var a0 := closeness * 0.28 * (1.0 - t0 * t0)
			var a1 := closeness * 0.28 * (1.0 - t1 * t1)
			_draw_vgrad(0.0, horizon_y - (1.0 - t0) * 80.0, vp.size.x,
						horizon_y - (1.0 - t1) * 80.0,
						Color(sc.r, sc.g * 0.7, sc.b * 0.2, a1),
						Color(sc.r, sc.g * 0.7, sc.b * 0.2, a0))

# ─────────────────────────────────────────────────────────────────────────────
# MOON
# ─────────────────────────────────────────────────────────────────────────────

func _draw_moon(vp: Rect2, pal: Dictionary) -> void:
	var sky_top : Color = pal["sky_top"]
	var night_t := 0.0
	if _cycle_t > 0.65:
		night_t = clampf((_cycle_t - 0.65) / 0.12, 0.0, 1.0)
	elif _cycle_t < 0.10:
		night_t = clampf((0.10 - _cycle_t) / 0.10, 0.0, 1.0)
	if night_t < 0.02: return

	var mx := vp.size.x * 0.72
	var my := vp.size.y * 0.18
	var mr := 34.0
	for gi in range(5):
		draw_circle(Vector2(mx, my), mr + float(gi) * 18.0, Color(0.72, 0.78, 0.92, 0.035 * night_t))
	draw_circle(Vector2(mx, my), mr, Color(0.88, 0.90, 0.96, night_t))
	draw_circle(Vector2(mx + mr * 0.34, my - mr * 0.10), mr * 0.82, sky_top)
	for ci in range(4):
		var cs := 6100 + ci * 41
		draw_circle(
			Vector2(mx - mr * 0.28 + _hf(cs) * mr * 0.48, my - mr * 0.18 + _hf(cs+1) * mr * 0.38),
			1.8 + _hf(cs + 2) * 3.8, Color(0.68, 0.70, 0.76, 0.32 * night_t))

# ─────────────────────────────────────────────────────────────────────────────
# MOUNTAINS  (4 layers, parallax-shifted)
# ─────────────────────────────────────────────────────────────────────────────

func _draw_mountains(vp: Rect2, pal: Dictionary) -> void:
	var mtn : Array  = pal["mtn_layers"]
	var ground_y     := vp.size.y * 0.82
	var w            := vp.size.x

	# Layer configs: [base_y_frac, min_h, max_h, segs, parallax_frac, seed_xor]
	var layers := [
		[0.78, 200.0, 520.0, 90,  0.04, 0x0A1B2C],
		[0.80, 140.0, 360.0, 80,  0.08, 0x1A2B3C],
		[0.81,  80.0, 210.0, 65,  0.14, 0x4D5E6F],
		[0.82,  38.0, 100.0, 50,  0.20, 0x7F8A9B],
	]

	for li in layers.size():
		var lc: Array = layers[li]
		var base_y := vp.size.y * float(lc[0])
		var px_off := _parallax_offset.x * float(lc[4])
		var col    : Color = mtn[li] if li < mtn.size() else Color(0.15, 0.15, 0.20)
		_draw_hill_layer(-200.0 + px_off, w + 200.0 + px_off, base_y,
						  float(lc[1]), float(lc[2]), int(lc[3]), col,
						  _scenery_seed ^ int(lc[5]))

	# Horizon haze
	var horiz : Color = pal["sky_horiz"]
	_draw_vgrad(0.0, ground_y - 28.0, w, ground_y + 10.0,
		Color(horiz.r, horiz.g, horiz.b, 0.0),
		Color(horiz.r, horiz.g, horiz.b, 0.44))
	_draw_vgrad(0.0, ground_y + 10.0, w, ground_y + 40.0,
		Color(horiz.r, horiz.g, horiz.b, 0.44),
		Color(horiz.r, horiz.g, horiz.b, 0.0))

func _draw_hill_layer(left: float, right: float, base_y: float,
					  min_h: float, max_h: float, segs: int,
					  color: Color, hill_seed: int) -> void:
	if segs < 1 or right <= left: return
	var step := (right - left) / float(segs)
	var pts  := PackedVector2Array()
	pts.append(Vector2(left, base_y + 600.0))
	for i in segs + 1:
		var h0 := _hf(hill_seed + (i - 1) * 7) * (max_h - min_h) + min_h
		var h1 := _hf(hill_seed + i       * 7) * (max_h - min_h) + min_h
		var h2 := _hf(hill_seed + (i + 1) * 7) * (max_h - min_h) + min_h
		pts.append(Vector2(left + i * step, base_y - (h0 * 0.2 + h1 * 0.6 + h2 * 0.2)))
	pts.append(Vector2(right, base_y + 600.0))
	if _polygon_valid(pts):
		draw_colored_polygon(pts, color)

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDS
# ─────────────────────────────────────────────────────────────────────────────

func _draw_clouds(pal: Dictionary) -> void:
	var cc : Color = pal["cloud"]
	var sc : Color = cc.darkened(0.22)
	sc.a = cc.a * 0.42

	if cc.a < 0.02: return

	for layer in CLOUD_LAYERS:
		for c in _clouds:
			if c["layer"] != layer: continue
			var ba: float = c["alpha"] * cc.a
			ba = minf(ba, 0.90)
			_draw_cloud(c["x"], c["y"], c["sx"], c["sy"],
						Color(cc.r, cc.g, cc.b, ba),
						Color(sc.r, sc.g, sc.b, ba * 0.44),
						c["seed"])

func _draw_cloud(cx: float, cy: float, sx: float, sy: float,
				 col: Color, shadow: Color, cseed: int) -> void:
	_draw_oval(cx, cy + sy * 0.38, sx * 0.84, sy * 0.50, shadow)
	_draw_oval(cx, cy, sx, sy, col)
	var offsets := [
		Vector2(-sx * 0.32, -sy * 0.44), Vector2( sx * 0.30, -sy * 0.37),
		Vector2(  0.0,      -sy * 0.64), Vector2(-sx * 0.52, -sy * 0.20),
		Vector2( sx * 0.48, -sy * 0.22),
	]
	var szs := [0.50, 0.44, 0.48, 0.38, 0.36]
	for pi in offsets.size():
		var wob := Vector2((_hf(cseed + pi * 3) - 0.5) * sx * 0.08,
						   (_hf(cseed + pi * 3 + 1) - 0.5) * sy * 0.10)
		_draw_oval(cx + offsets[pi].x + wob.x, cy + offsets[pi].y + wob.y,
				   sx * szs[pi], sy * (szs[pi] + 0.10), col)

func _draw_oval(cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	if rx < 0.5 or ry < 0.5: return
	var steps := 22
	var pts   := PackedVector2Array()
	for i in steps:
		var a := (float(i) / float(steps)) * TAU
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	if _polygon_valid(pts): draw_colored_polygon(pts, color)

# ─────────────────────────────────────────────────────────────────────────────
# FOG BASE (always-present low haze)
# ─────────────────────────────────────────────────────────────────────────────

func _draw_fog_base(vp: Rect2, pal: Dictionary) -> void:
	var horiz : Color = pal["sky_horiz"]
	var steps := 8
	var fog_h := vp.size.y * 0.12
	var base  := vp.size.y * 0.74
	for i in steps:
		var t0 := float(i)     / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a0 := 0.08 * sin(t0 * PI)
		var a1 := 0.08 * sin(t1 * PI)
		_draw_vgrad(0.0, base + t0 * fog_h, vp.size.x, base + t1 * fog_h,
			Color(horiz.r, horiz.g, horiz.b, a0),
			Color(horiz.r, horiz.g, horiz.b, a1))

# ─────────────────────────────────────────────────────────────────────────────
# GROUND (simple rolling silhouette)
# ─────────────────────────────────────────────────────────────────────────────

func _draw_ground(vp: Rect2, pal: Dictionary) -> void:
	var ground_y := vp.size.y * 0.82
	var gt  : Color = pal["ground_top"]
	var gd  : Color = gt.darkened(0.35)

	draw_rect(Rect2(0.0, ground_y, vp.size.x, vp.size.y - ground_y), gd, true)
	# Soft gradient — no bright specular highlight at the top edge
	_draw_vgrad(0.0, ground_y, vp.size.x, ground_y + 48.0, gt, gt.darkened(0.10))
	_draw_vgrad(0.0, ground_y + 48.0, vp.size.x, ground_y + 120.0, gt.darkened(0.10), gd)

	# Subtle rolling surface — low profile, matte finish
	var segs := 80
	var step := vp.size.x / float(segs)
	var pts  := PackedVector2Array()
	pts.append(Vector2(-10.0, ground_y + 40.0))
	for i in segs + 1:
		var gx := float(i) * step
		var h0 := _hf((_scenery_seed ^ 0x6A55) + (i - 1) * 11) * 4.0
		var h1 := _hf((_scenery_seed ^ 0x6A55) + i       * 11) * 4.0
		var h2 := _hf((_scenery_seed ^ 0x6A55) + (i + 1) * 11) * 4.0
		pts.append(Vector2(gx, ground_y - (h0 * 0.2 + h1 * 0.6 + h2 * 0.2)))
	pts.append(Vector2(vp.size.x + 10.0, ground_y + 40.0))
	if _polygon_valid(pts): draw_colored_polygon(pts, gt)

	# Horizon blend
	var horiz : Color = pal["sky_horiz"]
	_draw_vgrad(0.0, ground_y - 1.0, vp.size.x, ground_y + 16.0,
		Color(horiz.r, horiz.g, horiz.b, 0.18), Color(horiz.r, horiz.g, horiz.b, 0.0))

# ─────────────────────────────────────────────────────────────────────────────
# DRAW PRIMITIVES
# ─────────────────────────────────────────────────────────────────────────────

## Vertical gradient quad.
func _draw_vgrad(x: float, y0: float, w: float, y1: float, c_top: Color, c_bot: Color) -> void:
	if w < 0.5 or absf(y1 - y0) < 0.5: return
	var tl  := Vector2(x,     y0); var tr_ := Vector2(x + w, y0)
	var br  := Vector2(x + w, y1); var bl  := Vector2(x,     y1)
	draw_polygon(PackedVector2Array([tl, tr_, br]), PackedColorArray([c_top, c_top, c_bot]))
	draw_polygon(PackedVector2Array([tl, br, bl]), PackedColorArray([c_top, c_bot, c_bot]))

## Deterministic pseudo-random float in 0..1 from integer seed.
func _hf(v: int) -> float:
	return float(hash(v) % 10000) / 10000.0

## Returns true if the polygon has at least one non-degenerate triangle.
func _polygon_valid(pts: PackedVector2Array) -> bool:
	if pts.size() < 3: return false
	for i in pts.size():
		var a := pts[i]; var b := pts[(i + 1) % pts.size()]; var c := pts[(i + 2) % pts.size()]
		if abs((b - a).cross(c - a)) > 0.01: return true
	return false
