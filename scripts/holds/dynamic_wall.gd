extends Node2D
class_name DynamicWall
## Dynamic wall with click-to-select top edges, animated environment backgrounds

# =============================================================================
# TEXTURE SETTINGS
# =============================================================================
var wall_texture_enabled := true
var texture_variation := 0.05

# =============================================================================
# BOLT HOLE SETTINGS (GYM ONLY)
# =============================================================================
var hole_spacing := Vector2(64, 64)
var hole_radius := 2.5
var hole_color := Color(0.15, 0.15, 0.15)
var hole_jitter := 4.0

# =============================================================================
# EDGE SETTINGS
# =============================================================================
var edge_color := Color(0.2, 0.2, 0.25)
var edge_thickness := 8.0
var top_edge_color := Color(0.9, 0.4, 0.2)

# =============================================================================
# WALL BOUNDS
# =============================================================================
var wall_min := Vector2.ZERO
var wall_max := Vector2.ZERO
var wall_valid := false

const WALL_PADDING_TOP = 100.0
const WALL_PADDING_BOTTOM = 150.0
const WALL_PADDING_SIDES = 100.0
const BACKGROUND_EXPANSION = 2000.0

# =============================================================================
# POLYGON EDITING
# =============================================================================
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

# =============================================================================
# ENVIRONMENT STATE
# =============================================================================
var current_wall_color: Color = Color(0.82, 0.75, 0.62)
var background_color: Color = Color(0.53, 0.81, 0.92)
var show_bolt_holes: bool = true
var is_granite: bool = false
var current_environment: String = "gym"
var is_in_editor: bool = false

# =============================================================================
# GROUND SETTINGS
# =============================================================================
var ground_enabled := true
var ground_height := 1000.0
var ground_color := Color(0.298, 0.298, 0.298, 1.0)

# =============================================================================
# CLOUD SYSTEM
# Each cloud: { x, y, sx, sy, speed, alpha, layer, seed }
# =============================================================================
var _clouds: Array[Dictionary] = []
var _cloud_time: float = 0.0
const CLOUD_COUNT = 22
const CLOUD_LAYERS = 3

# =============================================================================
# ENVIRONMENT THEME DATA
# =============================================================================
var _env: Dictionary = {}

# =============================================================================
# SCENERY SEED — randomized each session so mountains/terrain never repeat
# =============================================================================
var _scenery_seed: int = 0

# =============================================================================
# LIFECYCLE
# =============================================================================
func _ready():
	z_index = -10
	add_to_group("environment_walls")
	_scenery_seed = randi()  # Random each session — mountains/terrain never repeat
	_init_clouds()
	call_deferred("update_environment_settings")

var _redraw_timer: float = 0.0
const REDRAW_INTERVAL = 0.05  # 20fps max for animated elements

func _process(delta: float):
	_redraw_timer += delta
	if _redraw_timer < REDRAW_INTERVAL:
		return
	_redraw_timer = 0.0
	var has_animation = _env.get("has_stars", false) or (_env.get("cloud_color", Color(1,1,1)).a > 0.02) \
		or _env.get("has_gym_interior", false)
	if has_animation:
		_cloud_time += REDRAW_INTERVAL
		_update_clouds(REDRAW_INTERVAL)
		queue_redraw()

# =============================================================================
# CLOUD INITIALIZATION & ANIMATION
# =============================================================================
func _init_clouds():
	_clouds.clear()
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(CLOUD_COUNT):
		_clouds.append(_make_cloud(rng, true))

func _make_cloud(rng: RandomNumberGenerator, initial_spread: bool) -> Dictionary:
	var layer = rng.randi() % CLOUD_LAYERS
	var bg_left = wall_min.x - BACKGROUND_EXPANSION if wall_valid else -3000.0
	var bg_right = wall_max.x + BACKGROUND_EXPANSION if wall_valid else 3000.0
	var sky_top = (wall_min.y - BACKGROUND_EXPANSION) if wall_valid else -2000.0
	var sky_bottom = ground_y - 120.0 if wall_valid else -400.0

	var sx = 60.0 + rng.randf() * 220.0 + float(layer) * 50.0
	var sy = 22.0 + rng.randf() * 38.0 + float(layer) * 8.0
	var speed = (0.18 + rng.randf() * 0.25) * (1.0 + float(layer) * 0.6) * 40.0
	var alpha = 0.4 + rng.randf() * 0.45
	var y = sky_top + 40.0 + rng.randf() * max(sky_bottom - sky_top - 100.0, 100.0)
	var x: float
	if initial_spread:
		x = bg_left + rng.randf() * (bg_right - bg_left)
	else:
		x = bg_right + sx + rng.randf() * 200.0

	return { "x": x, "y": y, "sx": sx, "sy": sy, "speed": speed,
			 "alpha": alpha, "layer": layer, "seed": rng.randi() }

func _update_clouds(delta: float):
	var bg_left = wall_min.x - BACKGROUND_EXPANSION if wall_valid else -3000.0
	var bg_right = wall_max.x + BACKGROUND_EXPANSION if wall_valid else 3000.0
	var rng = RandomNumberGenerator.new()
	rng.seed = int(_cloud_time * 100.0) ^ 0xDEADBEEF

	for i in range(_clouds.size()):
		var c = _clouds[i]
		c["x"] -= c["speed"] * delta
		if c["x"] + c["sx"] < bg_left - 100.0:
			_clouds[i] = _make_cloud(rng, false)
		else:
			_clouds[i] = c

# =============================================================================
# EDITOR MODE
# =============================================================================
func set_editor_mode(enabled: bool):
	is_in_editor = enabled
	queue_redraw()

# =============================================================================
# ENVIRONMENT SYSTEM
# =============================================================================
func update_environment_settings():
	var env_config := get_node_or_null("/root/EnvironmentConfig")
	if env_config == null:
		call_deferred("update_environment_settings")
		return
	var data = env_config.get_environment_data()
	current_wall_color = data.get("wall_color", Color(0.82, 0.75, 0.62))
	background_color = data.get("background_color", Color(0.53, 0.81, 0.92))
	show_bolt_holes = data.get("show_bolt_holes", false)
	is_granite = data.get("show_granite_texture", false)
	current_environment = env_config.get_current_environment_name().to_lower()
	_apply_environment_theme()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	queue_redraw()

func _apply_environment_theme():
	match current_environment:
		"outdoor", "cliff", "crag", "rock":
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
		"cave", "underground", "mine":
			_env = {
				"sky_top": Color(0.04, 0.04, 0.06),
				"sky_horizon": Color(0.08, 0.07, 0.12),
				"cloud_color": Color(0.14, 0.12, 0.20, 0.6),
				"cloud_shadow": Color(0.08, 0.07, 0.12),
				"has_sun": false, "has_mountains": false,
				"has_stalactites": true,
				"ground_type": "stone",
				"ground_top": Color(0.30, 0.28, 0.26),
				"ground_mid": Color(0.22, 0.20, 0.18),
				"ground_deep": Color(0.14, 0.13, 0.12),
				"ground_detail": "cracks",
				"fog_color": Color(0.08, 0.06, 0.12, 0.18),
				"has_torch_glow": true,
			}
		"gym", "indoor", "competition":
			_env = {
				"sky_top": Color(0.96, 0.96, 0.97),
				"sky_horizon": Color(0.92, 0.92, 0.93),
				"cloud_color": Color(1.0, 1.0, 1.0, 0.0),
				"has_sun": false, "has_mountains": false,
				"has_gym_interior": true,
				"ground_type": "gym_floor",
				"ground_top": Color(0.22, 0.22, 0.24),
				"ground_mid": Color(0.16, 0.16, 0.18),
				"ground_deep": Color(0.11, 0.11, 0.12),
				}
		"sunset", "dusk", "dawn":
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
		"night", "moonlight":
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

# =============================================================================
# INPUT
# =============================================================================
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
		np.y = ground_y
		if dragging_point == ground_left_index:
			np.x = min(np.x, control_points[ground_right_index].x - 50.0)
		else:
			np.x = max(np.x, control_points[ground_left_index].x + 50.0)
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
# DRAWING MASTER
# =============================================================================
func _draw():
	if not wall_valid: return
	_draw_sky()
	if _env.get("has_stars", false): _draw_stars()
	if _env.get("has_sun", false): _draw_sun()
	if _env.get("has_moon", false): _draw_moon()
	if _env.get("has_mountains", false): _draw_mountains()
	if _env.get("has_stalactites", false): _draw_stalactites()
	_draw_clouds()
	_draw_fog()
	if _env.get("has_gym_interior", false): _draw_gym_interior()
	if _env.get("has_scaffold", false): _draw_scaffold()
	if use_polygon_mode and control_points.size() >= 3: _draw_polygon_wall()
	else: _draw_rectangle_wall()
	_draw_wall_base_shadow()
	if show_bolt_holes:
		if use_polygon_mode and control_points.size() >= 3: draw_bolt_holes_on_polygon()
		else: draw_bolt_holes(wall_min, wall_max)
	if is_granite and not use_polygon_mode: draw_granite_texture()
	if ground_enabled: _draw_ground()
	draw_edges()
	if is_in_editor and use_polygon_mode and control_points.size() > 0: _draw_control_points()
	if is_in_editor and edit_mode and use_polygon_mode: _draw_edge_highlights()

# =============================================================================
# SKY
# =============================================================================
func _draw_sky():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var st = wall_min.y - BACKGROUND_EXPANSION
	var sw = br - bl
	var col_top: Color = _env.get("sky_top", background_color)
	var col_horiz: Color = _env.get("sky_horizon", background_color.lightened(0.15))
	var bands = 6
	for i in range(bands):
		var t = float(i) / float(bands)
		var y0 = st + t * (ground_y - st)
		var h = (ground_y - st) / float(bands) + 1.0
		draw_rect(Rect2(Vector2(bl, y0), Vector2(sw, h)), col_top.lerp(col_horiz, t), true)
	draw_rect(Rect2(Vector2(bl, ground_y), Vector2(sw, ground_height + 200.0)), col_horiz, true)

# =============================================================================
# STARS
# =============================================================================
func _draw_stars():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var st = wall_min.y - BACKGROUND_EXPANSION
	var sw = br - bl
	for i in range(80):
		var seed = (_scenery_seed ^ 0xBEEF) + i * 17
		var sx = bl + _hf(seed) * sw
		var sy = st + _hf(seed + 1) * (ground_y - st - 80.0)
		var bright = 0.5 + _hf(seed + 2) * 0.5
		var size = 1.0 + _hf(seed + 3) * 2.0
		var twinkle = 0.7 + 0.3 * sin(_cloud_time * (1.5 + _hf(seed + 4) * 3.0) + float(i))
		draw_circle(Vector2(sx, sy), size, Color(1.0, 1.0, 1.0, bright * twinkle * 0.9))

# =============================================================================
# SUN
# =============================================================================
func _draw_sun():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var sx = bl + (br - bl) * 0.78
	var sy = wall_min.y - BACKGROUND_EXPANSION * 0.5 + 180.0
	var sc: Color = _env.get("sun_color", Color(1.0, 0.95, 0.70))
	for gi in range(6):
		draw_circle(Vector2(sx, sy), 52.0 + float(gi) * 30.0, Color(sc.r, sc.g, sc.b, 0.07 - float(gi) * 0.01))
	draw_circle(Vector2(sx, sy), 52.0, sc)
	draw_circle(Vector2(sx, sy), 38.0, Color(1.0, 1.0, 0.96, 1.0))

# =============================================================================
# MOON
# =============================================================================
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

# =============================================================================
# MOUNTAINS
# =============================================================================
func _draw_mountains():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var hs: Color = _env.get("sky_horizon", background_color)
	var ht: Color = _env.get("sky_top", background_color)
	# Extra far layer for more vertical depth
	_draw_hill_layer(bl, br, ground_y - 60.0,  240.0, 600.0, 90, hs.lerp(ht, 0.6).darkened(0.06), _scenery_seed ^ 0x0A1B2C)
	_draw_hill_layer(bl, br, ground_y - 20.0,  160.0, 420.0, 80, hs.lerp(ht, 0.4).darkened(0.10), _scenery_seed ^ 0x1A2B3C)
	_draw_hill_layer(bl, br, ground_y - 5.0,    90.0, 230.0, 55, hs.darkened(0.25),                _scenery_seed ^ 0x4D5E6F)
	_draw_hill_layer(bl, br, ground_y,           40.0, 110.0, 45, hs.darkened(0.42),                _scenery_seed ^ 0x7F8A9B)

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

# =============================================================================
# STALACTITES
# =============================================================================
func _draw_stalactites():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var st = wall_min.y - BACKGROUND_EXPANSION
	var count = 50
	var step = (br - bl) / float(count)
	for si in range(count):
		var seed = (_scenery_seed ^ 0xCAFE) + si * 19
		var sx = bl + float(si) * step + _hf(seed) * step
		var sh = 40.0 + _hf(seed + 1) * 200.0
		var sw = 8.0 + _hf(seed + 2) * 28.0
		var sc = Color(0.22, 0.20, 0.18, 0.8 + _hf(seed + 3) * 0.2)
		draw_colored_polygon(PackedVector2Array([
			Vector2(sx, st), Vector2(sx - sw * 0.5, st + sh),
			Vector2(sx, st + sh + sw * 0.4), Vector2(sx + sw * 0.5, st + sh)
		]), sc)
		draw_line(Vector2(sx, st + sh * 0.5), Vector2(sx, st + sh + sw * 0.3),
				  Color(0.5, 0.6, 0.8, 0.3), 1.5, true)

# =============================================================================
# CLOUDS
# =============================================================================
func _draw_clouds():
	var cc: Color = _env.get("cloud_color", Color(1, 1, 1))
	if cc.a < 0.02: return
	var sc: Color = _env.get("cloud_shadow", Color(0.78, 0.84, 0.92))
	for layer in range(CLOUD_LAYERS):
		for c in _clouds:
			if c["layer"] != layer: continue
			var ba = c["alpha"] * cc.a
			_draw_cloud_shape(c["x"], c["y"], c["sx"], c["sy"],
				Color(cc.r, cc.g, cc.b, ba),
				Color(sc.r, sc.g, sc.b, ba * 0.45),
				c["seed"])

func _draw_cloud_shape(cx: float, cy: float, sx: float, sy: float,
					   color: Color, shadow: Color, seed: int):
	_draw_oval(cx, cy + sy * 0.38, sx * 0.85, sy * 0.52, shadow)
	_draw_oval(cx, cy, sx, sy, color)
	var offsets = [
		Vector2(-sx * 0.32, -sy * 0.42), Vector2(sx * 0.30, -sy * 0.36),
		Vector2(0.0, -sy * 0.62), Vector2(-sx * 0.52, -sy * 0.18),
		Vector2(sx * 0.48, -sy * 0.22),
	]
	var sizes = [0.50, 0.44, 0.48, 0.38, 0.36]
	for pi in range(offsets.size()):
		var wobble = Vector2((_hf(seed + pi * 3) - 0.5) * sx * 0.10,
							 (_hf(seed + pi * 3 + 1) - 0.5) * sy * 0.12)
		_draw_oval(cx + offsets[pi].x + wobble.x, cy + offsets[pi].y + wobble.y,
				   sx * sizes[pi], sy * (sizes[pi] + 0.1), color)

func _draw_oval(cx: float, cy: float, rx: float, ry: float, color: Color):
	var steps = 18
	var pts: PackedVector2Array = []
	for i in range(steps):
		var angle = (float(i) / float(steps)) * TAU
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	draw_colored_polygon(pts, color)

# =============================================================================
# ATMOSPHERIC FOG
# =============================================================================
func _draw_fog():
	var fc: Color = _env.get("fog_color", Color(0, 0, 0, 0))
	if fc.a < 0.01: return
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var bt = wall_min.y - BACKGROUND_EXPANSION
	draw_rect(Rect2(Vector2(bl, bt), Vector2(br - bl, ground_y + ground_height - bt)), fc, true)

# =============================================================================
# GYM INTERIOR
# =============================================================================
func _draw_gym_interior():
	var bl = wall_min.x - BACKGROUND_EXPANSION
	var br = wall_max.x + BACKGROUND_EXPANSION
	var width = br - bl
	var vis_top = wall_min.y
	var vis_bot = ground_y
	var vis_h   = vis_bot - vis_top

	# ── BACK WALL ─────────────────────────────────────────────────────────────
	for i in range(8):
		var t = float(i) / 8.0
		draw_rect(Rect2(Vector2(bl, vis_top + t*vis_h), Vector2(width, vis_h/8.0+2.0)),
				  Color(0.93-t*0.03, 0.93-t*0.025, 0.94-t*0.02), true)

	# ── WINDOW LAYOUT ─────────────────────────────────────────────────────────
	var win_top    = vis_top + vis_h * 0.10
	var win_h      = vis_h * 0.78
	var win_bot    = win_top + win_h
	var win_w      = 400.0
	var win_gap    = 150.0
	var win_stride = win_w + win_gap
	var win_count  = int(ceil(width / win_stride)) + 2
	var wall_col   = Color(0.93, 0.93, 0.94)

	# ── PARALLAX ──────────────────────────────────────────────────────────────
	var ct    = get_viewport().get_canvas_transform()
	var zoom  = ct.x.x
	var cam_x = -ct.origin.x / zoom
	var cam_y = -ct.origin.y / zoom

	var sky_top_c  = Color(0.20, 0.44, 0.84)
	var sky_mid_c  = Color(0.44, 0.70, 0.93)
	var sky_haze_c = Color(0.70, 0.86, 0.97)

	# Sun — one, world-anchored, drifts at 3% of camera speed
	var sun_wx = wall_min.x + (wall_max.x - wall_min.x) * 0.68 + cam_x * 0.03

	for wi in range(win_count):
		var wx  = bl + float(wi) * win_stride + win_gap * 0.5
		var wx2 = wx + win_w

		# ── SKY ───────────────────────────────────────────────────────────────
		for gi in range(10):
			var gt = float(gi) / 10.0
			var sc: Color
			if gt < 0.5:
				sc = sky_top_c.lerp(sky_mid_c, gt * 2.0)
			else:
				sc = sky_mid_c.lerp(sky_haze_c, (gt-0.5)*2.0)
			draw_rect(Rect2(Vector2(wx, win_top + gt*win_h), Vector2(win_w, win_h/10.0+1.0)), sc, true)

		# ── SUN ───────────────────────────────────────────────────────────────
		if sun_wx >= wx + 20.0 and sun_wx <= wx2 - 20.0:
			var sun_y = win_top + win_h * 0.15
			for ri in range(6):
				draw_circle(Vector2(sun_wx, sun_y), 8.0 + ri*20.0,
							Color(1.0, 0.96, 0.72, 0.048 - ri*0.007))
			draw_circle(Vector2(sun_wx, sun_y), 10.0, Color(1.0, 0.97, 0.80, 0.72))
			draw_circle(Vector2(sun_wx, sun_y), 55.0, Color(1.0, 0.95, 0.65, 0.07))

		# ── MOUNTAINS ─────────────────────────────────────────────────────────
		# Mountains are drawn using the full horizontal range (mtn_span wide),
		# centred on the window but offset by parallax. We DON'T clamp x —
		# instead we only emit points that actually fall within wx..wx2,
		# plus we always anchor left=wx and right=wx2 at the base so the
		# polygon is never degenerate.
		var mtn_span = win_w * 8.0   # wide enough that parallax never reveals edge
		var msegs    = 80            # many segments so clipping is smooth
		for mi in range(4):
			var mseed  = (_scenery_seed ^ (0xC001 + mi * 0x999)) + wi * 61
			var mpar   = cam_x * (0.04 + mi * 0.055)  # 0.04 / 0.095 / 0.15 / 0.205
			var mhmin  = win_h * (0.06 + mi * 0.09)
			var mhmax  = win_h * (0.20 + mi * 0.11)
			var mleft  = wx + win_w * 0.5 - mtn_span * 0.5 + mpar
			var mstep  = mtn_span / float(msegs)
			var mbase  = win_bot + 6.0
			var mcol: Color
			match mi:
				0: mcol = Color(0.72, 0.82, 0.91)
				1: mcol = Color(0.54, 0.67, 0.80)
				2: mcol = Color(0.38, 0.52, 0.66)
				_: mcol = Color(0.24, 0.38, 0.53)

			# Collect ridge points that fall inside the window
			var ridge: Array = []
			for si in range(msegs + 1):
				var px = mleft + si * mstep
				if px < wx - mstep or px > wx2 + mstep:
					continue
				var mh0 = _hf(mseed+(si-1)*7)*(mhmax-mhmin)+mhmin
				var mh1 = _hf(mseed+si*7)    *(mhmax-mhmin)+mhmin
				var mh2 = _hf(mseed+(si+1)*7)*(mhmax-mhmin)+mhmin
				var py  = mbase - (mh0*0.2+mh1*0.6+mh2*0.2)
				ridge.append(Vector2(clamp(px, wx, wx2), py))

			if ridge.size() < 2:
				continue
			# Build closed polygon: base-left, ridge, base-right
			var mpts = PackedVector2Array()
			mpts.append(Vector2(wx, mbase))
			for rp in ridge:
				mpts.append(rp)
			mpts.append(Vector2(wx2, mbase))
			if mpts.size() >= 4:
				draw_colored_polygon(mpts, mcol)

		# ── DISTANT HILLS / GROUND PLANE ──────────────────────────────────────
		# Solid dark band at bottom — represents forested ground, no trees
		var gnd_h   = win_h * 0.09
		var gnd_par = cam_x * 0.22
		# Irregular ground horizon — gentle bumps
		var gsegs = 40
		var gstep = win_w / float(gsegs)
		var gpts  = PackedVector2Array()
		gpts.append(Vector2(wx, win_bot + 4.0))
		for gi2 in range(gsegs + 1):
			var gseed = (_scenery_seed ^ 0x9F01) + wi*37 + gi2*5
			var gx2   = wx + gi2 * gstep
			gx2 = clamp(gx2, wx, wx2)
			var gh    = gnd_h * (0.6 + _hf(gseed) * 0.4)
			gpts.append(Vector2(gx2, win_bot - gh))
		gpts.append(Vector2(wx2, win_bot + 4.0))
		if gpts.size() >= 4:
			draw_colored_polygon(gpts, Color(0.18, 0.26, 0.19))
		# Darker fill below horizon
		draw_rect(Rect2(Vector2(wx, win_bot - gnd_h * 0.6), Vector2(win_w, gnd_h * 0.6 + 6.0)),
				  Color(0.13, 0.19, 0.14), true)

		# ── FROSTED GLASS ─────────────────────────────────────────────────────
		draw_rect(Rect2(Vector2(wx, win_top), Vector2(win_w, win_h)),
				  Color(1.0, 1.0, 1.0, 0.10), true)
		# Left-edge reflection band
		draw_rect(Rect2(Vector2(wx, win_top), Vector2(win_w*0.10, win_h)),
				  Color(1.0, 1.0, 1.0, 0.07), true)
		draw_rect(Rect2(Vector2(wx, win_top), Vector2(win_w*0.04, win_h)),
				  Color(1.0, 1.0, 1.0, 0.05), true)

	# ── OVERDRAW GAPS BETWEEN WINDOWS ─────────────────────────────────────────
	for wi in range(win_count + 1):
		var gx = bl + float(wi) * win_stride + win_gap * 0.5 - win_gap
		draw_rect(Rect2(Vector2(gx, vis_top), Vector2(win_gap + 4.0, vis_h)), wall_col, true)
	draw_rect(Rect2(Vector2(bl, vis_top), Vector2(width, win_top - vis_top + 1.0)), wall_col, true)
	draw_rect(Rect2(Vector2(bl, win_bot - 1.0), Vector2(width, vis_bot - win_bot + 2.0)), wall_col, true)

	# ── WINDOW FRAMES — border only ────────────────────────────────────────────
	for wi in range(win_count):
		var wx  = bl + float(wi) * win_stride + win_gap * 0.5
		var fc  = Color(0.15, 0.16, 0.19)
		var ft  = 10.0
		draw_rect(Rect2(Vector2(wx-ft,       win_top-ft), Vector2(win_w+ft*2.0, ft)), fc, true)
		draw_rect(Rect2(Vector2(wx-ft,       win_bot),    Vector2(win_w+ft*2.0, ft)), fc, true)
		draw_rect(Rect2(Vector2(wx-ft,       win_top-ft), Vector2(ft, win_h+ft*2.0)), fc, true)
		draw_rect(Rect2(Vector2(wx+win_w,    win_top-ft), Vector2(ft, win_h+ft*2.0)), fc, true)
		# Inner bright edge — light catching frame lip
		draw_line(Vector2(wx, win_top), Vector2(wx+win_w, win_top), Color(0.55,0.57,0.62), 2.0, true)
		draw_line(Vector2(wx, win_top), Vector2(wx, win_bot),       Color(0.55,0.57,0.62), 2.0, true)
		# Glass specular
		draw_line(Vector2(wx+12.0, win_top+14.0), Vector2(wx+62.0, win_top+14.0),
				  Color(1.0,1.0,1.0,0.24), 3.0, true)
		draw_line(Vector2(wx+14.0, win_top+25.0), Vector2(wx+40.0, win_top+25.0),
				  Color(1.0,1.0,1.0,0.11), 2.0, true)

	# ── FLOOR ──────────────────────────────────────────────────────────────────
	draw_rect(Rect2(Vector2(bl, vis_bot-28.0), Vector2(width, 28.0)),
			  Color(0.22, 0.22, 0.24), true)
	for mi in range(int(ceil(width/900.0))+1):
		draw_line(Vector2(bl+mi*900.0, vis_bot-28.0), Vector2(bl+mi*900.0, vis_bot),
				  Color(0.17, 0.17, 0.19), 2.0, true)

	# ── CEILING TRUSS ──────────────────────────────────────────────────────────
	draw_rect(Rect2(Vector2(bl, vis_top-16.0), Vector2(width, 16.0)),
			  Color(0.48, 0.48, 0.50), true)
	draw_rect(Rect2(Vector2(bl, vis_top-18.0), Vector2(width, 2.0)),
			  Color(0.32, 0.32, 0.34), true)
	for ti in range(int(ceil(width/600.0))+1):
		draw_rect(Rect2(Vector2(bl+ti*600.0-9.0, vis_top-16.0), Vector2(18.0, 16.0)),
				  Color(0.36, 0.36, 0.38), true)
	draw_rect(Rect2(Vector2(bl, vis_top-1.0), Vector2(width, 4.0)),
			  Color(1.0, 1.0, 0.93, 0.86), true)

func _draw_scaffold():
	# A simple freestanding timber frame: two vertical posts on each side,
	# horizontal cross-beams top and mid, diagonal braces for realism.
	var post_inset = 28.0
	var post_w = 18.0
	var post_col    = Color(0.42, 0.32, 0.20)
	var post_hi     = Color(0.55, 0.44, 0.28)
	var post_shadow = Color(0.28, 0.20, 0.12)
	var beam_col    = Color(0.38, 0.28, 0.17)

	var lx = wall_min.x - post_inset
	var rx = wall_max.x + post_inset
	var top_y = wall_min.y - 36.0
	var bot_y = ground_y + 14.0

	# Vertical posts — left and right
	for px in [lx, rx]:
		draw_rect(Rect2(Vector2(px - post_w * 0.5, top_y), Vector2(post_w, bot_y - top_y)),
				  post_col, true)
		draw_rect(Rect2(Vector2(px - post_w * 0.5, top_y), Vector2(5, bot_y - top_y)),
				  post_shadow, true)
		draw_rect(Rect2(Vector2(px + post_w * 0.5 - 4, top_y), Vector2(4, bot_y - top_y)),
				  post_hi, true)

	# Top cap beam
	var beam_h = 14.0
	draw_rect(Rect2(Vector2(lx - post_w, top_y - beam_h), Vector2(rx - lx + post_w * 2.0, beam_h)),
			  beam_col, true)
	draw_line(Vector2(lx - post_w, top_y - beam_h),
			  Vector2(rx + post_w, top_y - beam_h), post_hi, 2.0, true)

	# Mid horizontal beam
	var mid_y = top_y + (ground_y - top_y) * 0.5
	draw_rect(Rect2(Vector2(lx - post_w * 0.5, mid_y - 7.0), Vector2(rx - lx + post_w, 14.0)),
			  beam_col, true)
	draw_line(Vector2(lx - post_w * 0.5, mid_y - 7.0),
			  Vector2(rx + post_w * 0.5, mid_y - 7.0), post_hi, 1.5, true)

	# Diagonal braces — left side
	var brace_col = Color(0.35, 0.26, 0.15, 0.9)
	draw_line(Vector2(lx, top_y + 60.0), Vector2(lx - 70.0, mid_y),     brace_col, 9.0, true)
	draw_line(Vector2(lx, mid_y + 30.0), Vector2(lx - 70.0, ground_y),  brace_col, 9.0, true)
	# Right side
	draw_line(Vector2(rx, top_y + 60.0), Vector2(rx + 70.0, mid_y),     brace_col, 9.0, true)
	draw_line(Vector2(rx, mid_y + 30.0), Vector2(rx + 70.0, ground_y),  brace_col, 9.0, true)

	# Concrete foot anchors
	for px in [lx, rx]:
		draw_rect(Rect2(Vector2(px - 22.0, ground_y - 8.0), Vector2(44.0, 22.0)),
				  Color(0.50, 0.50, 0.52), true)
		draw_line(Vector2(px - 22.0, ground_y - 8.0), Vector2(px + 22.0, ground_y - 8.0),
				  Color(0.65, 0.65, 0.67), 2.0, true)

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

# =============================================================================
# EDGES
# =============================================================================
func draw_edges():
	if use_polygon_mode and control_points.size() >= 3:
		for i in range(control_points.size()):
			var p1 = control_points[i]
			var p2 = control_points[(i + 1) % control_points.size()]
			var color = edge_color
			var thickness = edge_thickness
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
		draw_line(tl, tr, edge_color, 4.0, true); draw_line(bl, br, sc, 6.0, true)
		for pt in [tl, tr, bl, br]: draw_circle(pt, r, sc)

# =============================================================================
# GYM BACKGROUND WALLS
# =============================================================================
func _draw_ground():
	if not wall_valid: return
	match _env.get("ground_type", "grass"):
		"grass", "grass_dusk", "grass_night": _draw_ground_grass()
		"stone": _draw_ground_stone()
		"gym_floor": _draw_ground_gym()
		_: _draw_ground_grass()

func _draw_ground_grass():
	var left = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	var cd: Color = _env.get("ground_deep", Color(0.20, 0.14, 0.08))
	var cm: Color = _env.get("ground_mid",  Color(0.32, 0.22, 0.12))
	var ct: Color = _env.get("ground_top",  Color(0.22, 0.52, 0.14))

	# Deep subsoil
	draw_rect(Rect2(Vector2(left, ground_y + 32.0), Vector2(width, ground_height)), cd, true)

	# Dirt band — single flat rect with a couple of tone variations
	draw_rect(Rect2(Vector2(left, ground_y + 4.0), Vector2(width, 30.0)), cm, true)
	# A few horizontal dirt streaks for subtle texture
	for si in range(8):
		var seed = (_scenery_seed ^ 0x57AA) + si * 31
		var sy = ground_y + 7.0 + _hf(seed) * 22.0
		var sx_s = left + _hf(seed + 1) * width * 0.4
		var sx_e = sx_s + 80.0 + _hf(seed + 2) * 320.0
		draw_line(Vector2(sx_s, sy), Vector2(min(sx_e, right), sy),
				  Color(cd.r, cd.g, cd.b, 0.25 + _hf(seed + 3) * 0.20), 2.0, true)

	# 3-pass grass strip — dark underlay, main, bright top edge
	var gc = [ct.darkened(0.28), ct, ct.lightened(0.18)]
	var segs = 80
	var step = width / float(segs)
	for pass_i in range(3):
		var seed = (_scenery_seed ^ 0x6A55) + pass_i * 200
		var amp = 10.0 - float(pass_i) * 2.5
		var oy = float(pass_i) * 2.0
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

	# Crisp top edge highlight
	draw_line(Vector2(left, ground_y), Vector2(right, ground_y), ct.lightened(0.35), 2.0, true)

func _draw_ground_stone():
	var left = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	var cd: Color = _env.get("ground_deep", Color(0.12, 0.11, 0.10))
	var ct: Color = _env.get("ground_top",  Color(0.28, 0.26, 0.24))

	draw_rect(Rect2(Vector2(left, ground_y), Vector2(width, ground_height)), cd, true)

	var row_h = 44.0
	var avg_stone_w = 100.0
	var max_stones = int(ceil(width / avg_stone_w)) + 4
	for row in range(3):
		var ty = ground_y + float(row) * row_h
		var x = left - (55.0 if row % 2 == 1 else 0.0)
		for stone_i in range(max_stones):
			if x > right + 60.0:
				break
			var seed = (_scenery_seed ^ 0xF00D) + row * 500 + stone_i * 13
			var sw = 70.0 + _hf(seed) * 60.0
			var bright = 0.80 + _hf(seed + 1) * 0.28
			var col = Color(ct.r * bright, ct.g * bright, ct.b * bright)
			draw_rect(Rect2(Vector2(x + 2, ty + 2), Vector2(sw - 4, row_h - 4)), col, true)
			draw_line(Vector2(x + 2, ty + 2), Vector2(x + sw - 2, ty + 2),
					  Color(1.0, 1.0, 1.0, 0.08), 1.5, true)
			draw_rect(Rect2(Vector2(x, ty), Vector2(2, row_h)), cd, true)
			draw_rect(Rect2(Vector2(x, ty), Vector2(sw, 2)), cd, true)
			x += sw

	for ci in range(10):
		var seed = (_scenery_seed ^ 0xCCCC) + ci * 37
		var cx = left + _hf(seed) * width
		var cy1 = ground_y + 6.0 + _hf(seed + 1) * 30.0
		var cy2 = cy1 + 12.0 + _hf(seed + 2) * 20.0
		var cx2 = cx + (_hf(seed + 3) - 0.5) * 24.0
		draw_line(Vector2(cx, cy1), Vector2(cx2, cy2), Color(cd.r, cd.g, cd.b, 0.5), 1.0, true)

	if _env.get("has_torch_glow", false):
		for ti in range(4):
			var tx = left + (float(ti) / 3.0) * width
			draw_colored_polygon(PackedVector2Array([
				Vector2(tx - 160, ground_y), Vector2(tx + 160, ground_y),
				Vector2(tx + 80, ground_y + 60), Vector2(tx - 80, ground_y + 60)
			]), Color(0.9, 0.45, 0.08, 0.055))

	draw_line(Vector2(left, ground_y), Vector2(right, ground_y), ct.lightened(0.18), 2.0, true)

func _draw_ground_gym():
	var left  = wall_min.x - BACKGROUND_EXPANSION
	var right = wall_max.x + BACKGROUND_EXPANSION
	var width = right - left
	var ct: Color = _env.get("ground_top",  Color(0.22, 0.22, 0.24))
	var cd: Color = _env.get("ground_deep", Color(0.11, 0.11, 0.12))

	# Main floor surface
	draw_rect(Rect2(Vector2(left, ground_y), Vector2(width, ground_height)), ct, true)

	# Rubber mat tiles with subtle variation
	var tile_w = 200.0
	var tile_count = int(ceil(width / tile_w)) + 1
	for ti in range(tile_count):
		var tx   = left + float(ti) * tile_w
		var seed = (_scenery_seed ^ 0xAABB) + ti * 7
		var v    = (_hf(seed) - 0.5) * 0.018
		draw_rect(Rect2(Vector2(tx+2.0, ground_y+1.0), Vector2(tile_w-4.0, 40.0)),
				  Color(ct.r+v, ct.g+v, ct.b+v+0.01), true)
		draw_line(Vector2(tx, ground_y), Vector2(tx, ground_y+42.0),
				  Color(cd.r, cd.g, cd.b, 0.8), 2.0, true)

	# Floor/wall join line
	draw_line(Vector2(left, ground_y), Vector2(right, ground_y),
			  Color(0.50, 0.50, 0.52, 0.9), 2.0, true)

func draw_textured_wall(start_pos: Vector2, size: Vector2):
	var tile := 128.0
	var cols := int(ceil(size.x / tile)) + 1
	var rows := int(ceil(size.y / tile)) + 1
	var gx = floor(start_pos.x / tile) * tile
	var gy = floor(start_pos.y / tile) * tile
	for x in cols:
		for y in rows:
			var px = gx + x * tile; var py = gy + y * tile
			var seed := int(px / tile) + int(py / tile) * 1000
			var v := (_hf(seed) - 0.5) * texture_variation
			var tr2 = Rect2(Vector2(px, py), Vector2(tile, tile))
			var wr = Rect2(wall_min, wall_max - wall_min)
			var cl = tr2.intersection(wr)
			if cl.has_area():
				draw_rect(cl, Color(current_wall_color.r + v, current_wall_color.g + v,
									current_wall_color.b + v, current_wall_color.a))

# =============================================================================
# BOLT HOLES
# =============================================================================
func draw_bolt_holes(start_pos: Vector2, end_pos: Vector2):
	var margin = 15.0
	var dmx = start_pos.x + margin; var dMx = end_pos.x - margin
	var dmy = start_pos.y + margin; var dMy = end_pos.y - margin
	var sx = floor(dmx / hole_spacing.x) * hole_spacing.x
	var sy = floor(dmy / hole_spacing.y) * hole_spacing.y
	var x = sx
	while x <= ceil(dMx / hole_spacing.x) * hole_spacing.x:
		var y = sy
		while y <= ceil(dMy / hole_spacing.y) * hole_spacing.y:
			var seed := int(x / hole_spacing.x) + int(y / hole_spacing.y) * 1000
			var hp = Vector2(x, y) + Vector2((_hf(seed) - 0.5) * hole_jitter, (_hf(seed + 1) - 0.5) * hole_jitter)
			if hp.x >= dmx and hp.x <= dMx and hp.y >= dmy and hp.y <= dMy:
				draw_circle(hp, hole_radius, hole_color)
			y += hole_spacing.y
		x += hole_spacing.x

func draw_bolt_holes_on_polygon():
	if control_points.size() < 3: return
	var margin = 15.0
	var dmx = wall_min.x + margin; var dMx = wall_max.x - margin
	var dmy = wall_min.y + margin; var dMy = wall_max.y - margin
	var sx = floor(dmx / hole_spacing.x) * hole_spacing.x
	var sy = floor(dmy / hole_spacing.y) * hole_spacing.y
	var x = sx
	while x <= ceil(dMx / hole_spacing.x) * hole_spacing.x:
		var y = sy
		while y <= ceil(dMy / hole_spacing.y) * hole_spacing.y:
			var seed := int(x / hole_spacing.x) + int(y / hole_spacing.y) * 1000
			var hp = Vector2(x, y) + Vector2((_hf(seed) - 0.5) * hole_jitter, (_hf(seed + 1) - 0.5) * hole_jitter)
			if _point_in_polygon(hp): draw_circle(hp, hole_radius, hole_color)
			y += hole_spacing.y
		x += hole_spacing.x

func _point_in_polygon(point: Vector2) -> bool:
	var inside = false; var j = control_points.size() - 1
	for i in range(control_points.size()):
		var pi = control_points[i]; var pj = control_points[j]
		if ((pi.y > point.y) != (pj.y > point.y)) and \
		   (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = not inside
		j = i
	return inside

# =============================================================================
# GRANITE
# =============================================================================
func draw_granite_texture():
	var ws = wall_max - wall_min
	var rs = int(wall_min.x + wall_min.y)
	for i in range(int(ws.x / 200.0) + 2):
		var xp = wall_min.x + (float(i) / (int(ws.x / 200.0) + 2)) * ws.x + (hash(rs + i) % 50 - 25)
		if xp >= wall_min.x and xp <= wall_max.x:
			draw_line(Vector2(xp, wall_min.y), Vector2(xp, wall_max.y), Color(0.45, 0.43, 0.4, 0.3), 2.0)

# =============================================================================
# EDITOR OVERLAYS
# =============================================================================
func _draw_edge_highlights():
	if hovered_edge < 0 or control_points.size() < 2: return
	if _is_ground_edge(hovered_edge): return
	var p1 = control_points[hovered_edge]
	var p2 = control_points[(hovered_edge + 1) % control_points.size()]
	var color = edge_hover_color
	var lt = "RIGHT-CLICK: Add point | SHIFT+RIGHT-CLICK: Mark as TOP-OUT"
	if hovered_edge in top_edge_indices:
		color = Color(1.0, 0.5, 0.0, 0.9); lt = "MARKED AS TOP-OUT | SHIFT+RIGHT-CLICK: Unmark"
	draw_line(p1, p2, color, 8.0, true)
	var mp = get_global_mouse_position()
	var seg = p2 - p1; var slsq = seg.length_squared()
	if slsq > 0:
		var np = p1 + clamp((mp - p1).dot(seg) / slsq, 0.0, 1.0) * seg
		draw_circle(np, 8.0, color)
		var lp = np + Vector2(0, -30)
		var ls = ThemeDB.fallback_font.get_string_size(lt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_rect(Rect2(lp - Vector2(ls.x/2 + 8, 8), ls + Vector2(16, 16)), Color(0, 0, 0, 0.9), true)
		draw_string(ThemeDB.fallback_font, lp, lt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, color)

func _draw_control_points():
	for i in range(control_points.size()):
		var pt = control_points[i]; var color = point_color
		if i == ground_left_index or i == ground_right_index: color = ground_point_color
		elif edit_mode:
			if dragging_point == i: color = point_drag_color
			elif hovered_point == i: color = point_hover_color
		draw_circle(pt, POINT_RADIUS + 3, Color(0, 0, 0, 0.5))
		draw_circle(pt, POINT_RADIUS, color)
		draw_string(ThemeDB.fallback_font, pt + Vector2(-5, 6), str(i + 1),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	if edit_mode and control_points.size() > 0:
		var mk = "" if top_edge_indices.is_empty() else " | MARKED: " + str(top_edge_indices)
		var text = "LEFT-DRAG: Move | RIGHT-CLICK: Add | SHIFT+RIGHT-CLICK on EDGE: Mark Top" + mk
		var pos = Vector2(wall_min.x, wall_min.y - 40)
		var sz = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_rect(Rect2(pos - Vector2(8, 22), sz + Vector2(16, 30)), Color(0, 0, 0, 0.8), true)
		draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.6))

# =============================================================================
# BOUNDS
# =============================================================================
func calculate_bounds_from_holds(holds_container: Node2D):
	if not holds_container or holds_container.get_child_count() == 0:
		wall_valid = false; queue_redraw(); return
	var mn_x = INF; var mx_x = -INF; var mn_y = INF; var mx_y = -INF
	for hold in holds_container.get_children():
		if not hold is Node2D: continue
		var pos = hold.global_position
		mn_x = min(mn_x, pos.x); mx_x = max(mx_x, pos.x)
		mn_y = min(mn_y, pos.y); mx_y = max(mx_y, pos.y)
	wall_min = Vector2(mn_x - WALL_PADDING_SIDES, mn_y - WALL_PADDING_TOP)
	wall_max = Vector2(mx_x + WALL_PADDING_SIDES, mx_y + WALL_PADDING_BOTTOM)
	wall_valid = true; ground_y = wall_max.y
	if control_points.is_empty():
		control_points = [wall_min, Vector2(wall_max.x, wall_min.y),
						  Vector2(wall_max.x, wall_max.y), Vector2(wall_min.x, wall_max.y)]
		ground_left_index = 3; ground_right_index = 2; use_polygon_mode = true
	else:
		if ground_left_index >= 0 and ground_left_index < control_points.size():
			control_points[ground_left_index].y = ground_y
		if ground_right_index >= 0 and ground_right_index < control_points.size():
			control_points[ground_right_index].y = ground_y
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	_init_clouds()
	queue_redraw()

func _update_bounds_from_polygon():
	if control_points.is_empty(): return
	var mn_x = INF; var mx_x = -INF; var mn_y = INF; var mx_y = -INF
	for p in control_points:
		mn_x = min(mn_x, p.x); mx_x = max(mx_x, p.x)
		mn_y = min(mn_y, p.y); mx_y = max(mx_y, p.y)
	wall_min = Vector2(mn_x, mn_y); wall_max = Vector2(mx_x, mx_y); wall_valid = true

# =============================================================================
# POLYGON MANIPULATION
# =============================================================================
func add_point_between_nearest_edge(pos: Vector2):
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
	if ground_left_index >= ni: ground_left_index += 1
	if ground_right_index >= ni: ground_right_index += 1
	var ute: Array[int] = []
	for ei in top_edge_indices: ute.append(ei + 1 if ei >= nei else ei)
	top_edge_indices = ute
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	queue_redraw()

func remove_point(index: int):
	if index == ground_left_index or index == ground_right_index:
		push_warning("Cannot remove ground points"); return
	if control_points.size() <= 4:
		push_warning("Cannot remove - need at least 4 points"); return
	if index >= 0 and index < control_points.size():
		control_points.remove_at(index)
		if ground_left_index > index: ground_left_index -= 1
		if ground_right_index > index: ground_right_index -= 1
		if dragging_point == index: dragging_point = -1
		elif dragging_point > index: dragging_point -= 1
		if hovered_point == index: hovered_point = -1
		elif hovered_point > index: hovered_point -= 1
		var ute: Array[int] = []
		for ei in top_edge_indices:
			if ei == index: continue
			ute.append(ei - 1 if ei > index else ei)
		top_edge_indices = ute
		_update_bounds_from_polygon()
		if not top_edge_indices.is_empty(): _create_top_edge_holds()
		queue_redraw()

func enable_polygon_mode(enabled: bool = true):
	use_polygon_mode = enabled
	if enabled and control_points.is_empty() and wall_valid:
		control_points = [wall_min, Vector2(wall_max.x, wall_min.y),
						  Vector2(wall_max.x, wall_max.y), Vector2(wall_min.x, wall_max.y)]
		ground_left_index = 3; ground_right_index = 2; ground_y = wall_max.y
	queue_redraw()

func enable_edit_mode(enabled: bool = true):
	edit_mode = enabled
	if not enabled: dragging_point = -1; hovered_point = -1; hovered_edge = -1
	queue_redraw()

func reset_polygon():
	use_polygon_mode = false; edit_mode = false
	control_points.clear(); top_edge_indices.clear()
	ground_left_index = -1; ground_right_index = -1
	dragging_point = -1; hovered_point = -1; hovered_edge = -1
	for child in get_children():
		if child.has_meta("is_top_edge_hold"): child.queue_free()
	queue_redraw()

func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var seg = seg_end - seg_start; var lsq = seg.length_squared()
	if lsq == 0: return point.distance_to(seg_start)
	return point.distance_to(seg_start + clamp((point - seg_start).dot(seg) / lsq, 0.0, 1.0) * seg)

# =============================================================================
# TOP EDGE HOLDS
# =============================================================================
func _create_top_edge_holds():
	for child in get_children():
		if child.has_meta("is_top_edge_hold"): child.queue_free()
	if not use_polygon_mode or top_edge_indices.is_empty(): return
	for edge_idx in top_edge_indices:
		if edge_idx >= control_points.size(): continue
		var p1 = control_points[edge_idx]
		var p2 = control_points[(edge_idx + 1) % control_points.size()]
		_create_top_hold_at((p1 + p2) / 2.0, p1.distance_to(p2))

func _create_top_hold_at(position: Vector2, width: float):
	var top_hold = Area2D.new()
	top_hold.set_meta("is_top_edge_hold", true)
	top_hold.collision_layer = 2; top_hold.collision_mask = 0
	top_hold.monitoring = false; top_hold.monitorable = true; top_hold.name = "TopEdgeHold"
	var shape = RectangleShape2D.new(); shape.size = Vector2(width, 50)
	var collision = CollisionShape2D.new(); collision.shape = shape; top_hold.add_child(collision)
	var hold_point = Marker2D.new(); hold_point.name = "HoldPoint"; hold_point.position = Vector2.ZERO
	top_hold.add_child(hold_point)
	top_hold.global_position = position; add_child(top_hold); top_hold.add_to_group("holds")
	call_deferred("_assign_top_hold_script", top_hold)

func _assign_top_hold_script(top_hold):
	var script_code = """
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
	var hold_script = GDScript.new(); hold_script.source_code = script_code
	hold_script.reload(); top_hold.set_script(hold_script)

# =============================================================================
# QUERIES
# =============================================================================
func get_bounds() -> Dictionary:
	return {"min": wall_min, "max": wall_max, "valid": wall_valid}

func get_top_edge_y() -> float:
	if use_polygon_mode and not top_edge_indices.is_empty():
		var ty = INF
		for ei in top_edge_indices:
			if ei >= control_points.size(): continue
			var p1 = control_points[ei]; var p2 = control_points[(ei + 1) % control_points.size()]
			ty = min(ty, min(p1.y, p2.y))
		return ty if ty != INF else wall_min.y
	return wall_min.y

func get_wall_height() -> float: return ground_y - get_top_edge_y()
func get_wall_width() -> float: return wall_max.x - wall_min.x

func _hf(v: int) -> float:
	return float(hash(v) % 10000) / 10000.0

func hash_to_float(v: int) -> float:
	return _hf(v)

# =============================================================================
# SAVE / LOAD
# =============================================================================
func get_polygon_data() -> Dictionary:
	if not use_polygon_mode or control_points.is_empty(): return {}
	var pts = []
	for p in control_points: pts.append({"x": p.x, "y": p.y})
	return { "enabled": true, "points": pts,
			 "ground_left_index": ground_left_index,
			 "ground_right_index": ground_right_index,
			 "top_edge_indices": top_edge_indices.duplicate() }

func set_polygon_data(data: Dictionary):
	if not data or data.is_empty() or not data.get("enabled", false): return
	use_polygon_mode = true; control_points.clear()
	for pd in data.get("points", []):
		control_points.append(Vector2(pd.get("x", 0), pd.get("y", 0)))
	ground_left_index = data.get("ground_left_index", -1)
	ground_right_index = data.get("ground_right_index", -1)
	top_edge_indices.clear()
	for ei in data.get("top_edge_indices", []):
		if ei is float or ei is int: top_edge_indices.append(int(ei))
	if ground_left_index >= 0 and ground_left_index < control_points.size():
		ground_y = control_points[ground_left_index].y
	_update_bounds_from_polygon()
	if not top_edge_indices.is_empty(): _create_top_edge_holds()
	_init_clouds()
	queue_redraw()
	print("  Polygon loaded: " + str(control_points.size()) + " points, " + str(top_edge_indices.size()) + " top edges")
