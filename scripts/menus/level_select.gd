extends Control

@onready var collection_title: Label = $CollectionTitle
@onready var btn_back: Button        = $BtnBack
@onready var btn_prev: Button        = $BtnPrev
@onready var btn_next: Button        = $BtnNext
@onready var page_label: Label       = $PageLabel
@onready var page_container: Control = $PageContainer

var _levels: Array = []
var _current_index: int = 0
var _tween: Tween = null
var _transitioning: bool = false

const WEATHER_NAMES = { 0: "", 1: "Rain", 2: "Snow", 3: "Wind", 4: "Storm" }

const HOLD_SCENE_MAP = {
	"JUG":    "res://scenes/holds/jug.tscn",
	"CRIMP":  "res://scenes/holds/crimp.tscn",
	"SLOPER": "res://scenes/holds/sloper.tscn",
	"POCKET": "res://scenes/holds/pocket.tscn",
	"FOOT":   "res://scenes/holds/foothold.tscn",
	"START":  "res://scenes/holds/start.tscn",
	"TOP":    "res://scenes/holds/top_out.tscn",
}

const ENV_COLORS = {
	"gym":      { "wall": Color(0.68, 0.60, 0.50), "sky": Color(0.30, 0.28, 0.26), "edge": Color(0.82, 0.75, 0.62), "ground": Color(0.20, 0.18, 0.16) },
	"outdoor":  { "wall": Color(0.52, 0.48, 0.42), "sky": Color(0.22, 0.34, 0.50), "edge": Color(0.65, 0.60, 0.52), "ground": Color(0.18, 0.22, 0.16) },
	"granite":  { "wall": Color(0.58, 0.56, 0.56), "sky": Color(0.26, 0.32, 0.44), "edge": Color(0.70, 0.68, 0.68), "ground": Color(0.16, 0.18, 0.20) },
	"sandstone":{ "wall": Color(0.78, 0.60, 0.40), "sky": Color(0.44, 0.30, 0.18), "edge": Color(0.86, 0.68, 0.48), "ground": Color(0.28, 0.20, 0.12) },
	"limestone":{ "wall": Color(0.80, 0.78, 0.70), "sky": Color(0.28, 0.36, 0.46), "edge": Color(0.86, 0.84, 0.76), "ground": Color(0.18, 0.20, 0.18) },
	"cave":     { "wall": Color(0.24, 0.22, 0.26), "sky": Color(0.08, 0.07, 0.10), "edge": Color(0.36, 0.32, 0.40), "ground": Color(0.10, 0.08, 0.12) },
	"ice":      { "wall": Color(0.68, 0.84, 0.94), "sky": Color(0.18, 0.28, 0.46), "edge": Color(0.80, 0.92, 1.00), "ground": Color(0.20, 0.26, 0.36) },
}

func _get_env_palette(env: String) -> Dictionary:
	return ENV_COLORS.get(env.to_lower(), ENV_COLORS["gym"])

func _ready() -> void:
	btn_prev.pressed.connect(_on_prev_pressed)
	btn_next.pressed.connect(_on_next_pressed)
	_populate_levels()
	_show_page(0)

func _populate_levels() -> void:
	var collection_id := GameState.get_current_collection()
	if collection_id == "":
		for id in GameState.get_all_collection_ids():
			if GameState.is_collection_unlocked(id):
				collection_id = id
				GameState.set_current_collection(id)
				break
	if collection_id == "":
		return
	var data := GameState.get_collection_data(collection_id)
	collection_title.text = data.get("name", collection_id)
	_levels.clear()
	for i in range(data.levels.size()):
		var lpath := data.levels[i] as String
		_levels.append({
			"index":     i,
			"path":      lpath,
			"unlocked":  GameState.is_level_unlocked(collection_id, i),
			"completed": GameState.is_level_completed(lpath),
			"time":      GameState.get_level_completion_time(lpath),
		})

func _load_json(level_path: String) -> Dictionary:
	if not FileAccess.file_exists(level_path):
		return {}
	var file := FileAccess.open(level_path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data

func _show_page(index: int) -> void:
	if _levels.is_empty():
		return
	_current_index = index
	for child in page_container.get_children():
		child.queue_free()
	await get_tree().process_frame

	var meta: Dictionary = _levels[index]
	var json: Dictionary = _load_json(meta.path)

	var route_name:  String = json.get("name",       "Route %d" % (index + 1))
	var grade:       String = json.get("grade",       "—")
	var discipline:  String = json.get("discipline",  "bouldering")
	var environment: String = json.get("environment", "gym")
	var weather_int: int    = int(json.get("weather", 0))
	var holds:       Array  = json.get("holds",       [])
	var palette             = _get_env_palette(environment)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	page_container.add_child(hbox)

	var diagram_wrap := Control.new()
	diagram_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagram_wrap.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	diagram_wrap.size_flags_stretch_ratio = 0.56
	diagram_wrap.clip_contents = true
	hbox.add_child(diagram_wrap)

	var diagram: Control
	if meta.unlocked:
		diagram = _build_route_diagram(json)
	else:
		diagram = _build_locked_diagram(palette, environment)
	diagram.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	diagram_wrap.add_child(diagram)

	var divider := ColorRect.new()
	divider.color = Color(1, 1, 1, 0.08)
	divider.custom_minimum_size = Vector2(1, 0)
	divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(divider)

	var info_wrap := Control.new()
	info_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_wrap.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	info_wrap.size_flags_stretch_ratio = 0.44
	hbox.add_child(info_wrap)

	var info_vbox := VBoxContainer.new()
	info_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_vbox.add_theme_constant_override("separation", 0)
	info_wrap.add_child(info_vbox)

	var header_ctrl := Control.new()
	header_ctrl.custom_minimum_size = Vector2(0, 80)
	header_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(header_ctrl)

	var header_bg := ColorRect.new()
	header_bg.color = Color(palette.wall.r * 0.7, palette.wall.g * 0.7, palette.wall.b * 0.7, 1.0)
	header_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_ctrl.add_child(header_bg)

	var header_m := MarginContainer.new()
	header_m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_m.add_theme_constant_override("margin_left",   18)
	header_m.add_theme_constant_override("margin_right",  14)
	header_m.add_theme_constant_override("margin_top",    10)
	header_m.add_theme_constant_override("margin_bottom", 10)
	header_ctrl.add_child(header_m)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 0)
	header_m.add_child(header_hbox)

	var grade_lbl := Label.new()
	grade_lbl.text = grade if meta.unlocked else "?"
	grade_lbl.add_theme_font_size_override("font_size", 52)
	grade_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grade_lbl.add_theme_color_override("font_color", Color.WHITE)
	header_hbox.add_child(grade_lbl)

	var num_lbl := Label.new()
	num_lbl.text = "#%02d" % (index + 1)
	num_lbl.add_theme_font_size_override("font_size", 12)
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	num_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.40))
	header_hbox.add_child(num_lbl)

	var accent := ColorRect.new()
	accent.color = palette.edge
	accent.custom_minimum_size = Vector2(0, 2)
	accent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(accent)

	var name_m := MarginContainer.new()
	name_m.add_theme_constant_override("margin_left",   18)
	name_m.add_theme_constant_override("margin_right",  14)
	name_m.add_theme_constant_override("margin_top",    16)
	name_m.add_theme_constant_override("margin_bottom", 2)
	var name_lbl := Label.new()
	name_lbl.text = route_name if meta.unlocked else "Locked Route"
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.88) if meta.unlocked else Color(1,1,1,0.25))
	name_m.add_child(name_lbl)
	info_vbox.add_child(name_m)

	var tags_m := MarginContainer.new()
	tags_m.add_theme_constant_override("margin_left",   18)
	tags_m.add_theme_constant_override("margin_right",  14)
	tags_m.add_theme_constant_override("margin_top",    8)
	tags_m.add_theme_constant_override("margin_bottom", 16)
	var tags_hbox := HBoxContainer.new()
	tags_hbox.add_theme_constant_override("separation", 5)
	tags_m.add_child(tags_hbox)
	info_vbox.add_child(tags_m)

	if meta.unlocked:
		_add_tag(tags_hbox, discipline.capitalize(),   Color(palette.wall.r, palette.wall.g, palette.wall.b, 0.55))
		_add_tag(tags_hbox, environment.capitalize(),  Color(palette.wall.r * 0.7, palette.wall.g * 0.7, palette.wall.b * 0.7, 0.55))
		if weather_int > 0:
			_add_tag(tags_hbox, WEATHER_NAMES.get(weather_int, ""), Color(0.25, 0.38, 0.55, 0.7))

	var sep1 := ColorRect.new()
	sep1.color = Color(1, 1, 1, 0.06)
	sep1.custom_minimum_size = Vector2(0, 1)
	sep1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(sep1)

	var stats_m := MarginContainer.new()
	stats_m.add_theme_constant_override("margin_left",   18)
	stats_m.add_theme_constant_override("margin_right",  14)
	stats_m.add_theme_constant_override("margin_top",    16)
	stats_m.add_theme_constant_override("margin_bottom", 8)
	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 12)
	stats_m.add_child(stats_vbox)
	info_vbox.add_child(stats_m)

	if meta.unlocked:
		if meta.completed:
			_add_stat(stats_vbox, "STATUS", "Completed", Color(0.35, 0.88, 0.50))
		else:
			_add_stat(stats_vbox, "STATUS", "Not yet climbed", Color(1, 1, 1, 0.35))
		if meta.completed and meta.time > 0.0:
			_add_stat(stats_vbox, "BEST TIME", _format_time(meta.time), Color(0.95, 0.80, 0.35))
		var foot_count := holds.filter(func(h): return h.get("type","") == "FOOT").size()
		var move_count := holds.size() - foot_count
		_add_stat(stats_vbox, "HOLDS", "%d moves  +  %d feet" % [move_count, foot_count], Color(1,1,1,0.55))
	else:
		_add_stat(stats_vbox, "STATUS", "Complete the previous route to unlock", Color(1,1,1,0.28))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(spacer)

	var sep2 := ColorRect.new()
	sep2.color = Color(1, 1, 1, 0.06)
	sep2.custom_minimum_size = Vector2(0, 1)
	sep2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(sep2)

	var btn_m := MarginContainer.new()
	btn_m.add_theme_constant_override("margin_left",   18)
	btn_m.add_theme_constant_override("margin_right",  14)
	btn_m.add_theme_constant_override("margin_top",    14)
	btn_m.add_theme_constant_override("margin_bottom", 18)
	info_vbox.add_child(btn_m)

	if meta.unlocked:
		var btn := Button.new()
		btn.text = "Climb Again" if meta.completed else "Climb"
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 42)
		btn.pressed.connect(_on_level_selected.bind(meta.path))
		btn_m.add_child(btn)
	else:
		var placeholder := Control.new()
		placeholder.custom_minimum_size = Vector2(0, 42)
		btn_m.add_child(placeholder)

	page_label.text = "%d / %d" % [index + 1, _levels.size()]
	_update_nav()

func _add_tag(parent: HBoxContainer, text: String, bg: Color) -> void:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   8)
	m.add_theme_constant_override("margin_right",  8)
	m.add_theme_constant_override("margin_top",    3)
	m.add_theme_constant_override("margin_bottom", 3)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	m.add_child(lbl)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left     = 3
	style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left  = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(m)
	parent.add_child(panel)

func _add_stat(parent: VBoxContainer, label_text: String, value_text: String, value_color: Color) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.28))
	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", value_color)
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lbl)
	row.add_child(val)
	parent.add_child(row)

func _build_locked_diagram(palette: Dictionary, environment: String = "gym") -> Control:
	var wrapper := Control.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	const VP_W := 900
	const VP_H := 600
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	var svp := SubViewport.new()
	svp.size = Vector2i(VP_W, VP_H)
	svp.transparent_bg = false
	svp.render_target_update_mode = SubViewport.UPDATE_ONCE
	svc.add_child(svp)
	wrapper.add_child(svc)

	var wmin := Vector2(-400, -600)
	var wmax := Vector2( 400,  0)
	var cam := Camera2D.new()
	cam.position = (wmin + wmax) * 0.5
	cam.zoom = Vector2(0.75, 0.75)
	svp.add_child(cam)

	if ResourceLoader.exists("res://scripts/holds/dynamic_wall.gd"):
		var wall_script = load("res://scripts/holds/dynamic_wall.gd")
		var wall = wall_script.new()
		wall.z_index = -10
		wall.set("current_environment", environment.to_lower())
		wall.set("current_wall_color", palette.wall)
		wall.set("wall_min",   wmin)
		wall.set("wall_max",   wmax)
		wall.set("ground_y",   wmax.y)
		wall.set("wall_valid", true)
		svp.add_child(wall)
		if wall.has_method("_apply_environment_theme"):
			wall._apply_environment_theme()
		wall.queue_redraw()

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0, 0, 0, 0.55)
	wrapper.add_child(veil)

	var lock_canvas := Control.new()
	lock_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lock_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_canvas.draw.connect(func():
		var cs := lock_canvas.size
		var cx  := cs.x * 0.5
		var cy  := cs.y * 0.48
		var scale = clamp(min(cs.x, cs.y) / 220.0, 0.7, 1.6)
		var body_w    = 44.0 * scale
		var body_h    = 34.0 * scale
		var shackle_r = 18.0 * scale
		var lc  := Color(1, 1, 1, 0.65)
		var lc2 := Color(1, 1, 1, 0.12)
		var shackle_cy = cy - body_h * 0.5
		lock_canvas.draw_arc(Vector2(cx, shackle_cy), shackle_r, PI, TAU, 40, lc, 5.0 * scale)
		lock_canvas.draw_rect(Rect2(cx - body_w*0.5, cy - body_h*0.5, body_w, body_h), lc)
		lock_canvas.draw_rect(Rect2(cx - body_w*0.5, cy - body_h*0.5, body_w, body_h), lc2, true)
		lock_canvas.draw_circle(Vector2(cx, cy - 2*scale), 6.0*scale, Color(0,0,0,0.5))
		lock_canvas.draw_rect(Rect2(cx - 3*scale, cy + 4*scale, 6*scale, 9*scale), Color(0,0,0,0.5))
	)
	wrapper.add_child(lock_canvas)
	return wrapper

func _build_route_diagram(json: Dictionary) -> Control:
	var holds: Array             = json.get("holds", [])
	var wall_polygon: Dictionary = json.get("wall_polygon", {})
	var environment: String      = json.get("environment", "gym")

	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	var poly_points: Array = wall_polygon.get("points", [])
	if poly_points.size() >= 3:
		for pt in poly_points:
			var p := Vector2(pt.get("x", 0.0), pt.get("y", 0.0))
			bmin = bmin.min(p); bmax = bmax.max(p)
	else:
		for hd in holds:
			var p := Vector2(hd.get("x", 0.0), hd.get("y", 0.0))
			bmin = bmin.min(p); bmax = bmax.max(p)
	if bmin.x == INF:
		bmin = Vector2(-200, -400); bmax = Vector2(200, 0)

	var pad_world := 80.0
	bmin -= Vector2(pad_world, pad_world)
	bmax += Vector2(pad_world, pad_world)
	var world_size := bmax - bmin

	const VP_W := 900
	const VP_H := 600

	var svc := SubViewportContainer.new()
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	svc.stretch = true

	var svp := SubViewport.new()
	svp.size = Vector2i(VP_W, VP_H)
	svp.transparent_bg = false
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(svp)

	var zoom_x := float(VP_W) / world_size.x
	var zoom_y := float(VP_H) / world_size.y
	var zoom   = min(zoom_x, zoom_y) * 0.95
	var cam := Camera2D.new()
	cam.position = (bmin + bmax) * 0.5
	cam.zoom = Vector2(zoom, zoom)
	svp.add_child(cam)

	if ResourceLoader.exists("res://scripts/holds/dynamic_wall.gd"):
		var wall_script = load("res://scripts/holds/dynamic_wall.gd")
		var wall = wall_script.new()
		wall.z_index = -10
		wall.set("current_environment", environment.to_lower())
		var env_config = get_node_or_null("/root/EnvironmentConfig")
		if env_config:
			for env_type in env_config.get_all_environment_types():
				if env_config.get_environment_name(env_type).to_lower() == environment.to_lower():
					env_config.set_environment(env_type)
					break
			var env_data = env_config.get_environment_data()
			wall.set("current_wall_color", env_data.get("wall_color",       Color(0.82, 0.75, 0.62)))
			wall.set("background_color",   env_data.get("background_color", Color(0.53, 0.81, 0.92)))
			wall.set("show_bolt_holes",    env_data.get("show_bolt_holes",   false))
			wall.set("is_granite",         env_data.get("show_granite_texture", false))
		wall.set("wall_min",   Vector2(bmin.x, bmin.y))
		wall.set("wall_max",   Vector2(bmax.x, bmax.y))
		wall.set("ground_y",   bmax.y)
		wall.set("wall_valid", true)
		if not wall_polygon.is_empty() and wall.has_method("set_polygon_data"):
			wall.set_polygon_data(wall_polygon)
		svp.add_child(wall)
		if wall.has_method("_apply_environment_theme"):
			wall._apply_environment_theme()
		wall.queue_redraw()

	for hd in holds:
		var type := (hd.get("type", "JUG") as String).to_upper()
		var scene_path: String = HOLD_SCENE_MAP.get(type, HOLD_SCENE_MAP["JUG"])
		if not ResourceLoader.exists(scene_path):
			continue
		var hold_scene = load(scene_path)
		if not hold_scene:
			continue
		var hold_node = hold_scene.instantiate()
		hold_node.position = Vector2(hd.get("x", 0.0), hd.get("y", 0.0))
		if hd.has("rotation"):
			hold_node.rotation = hd.get("rotation")
		if type == "FOOT":
			hold_node.scale    = Vector2(0.2, 0.2)
			hold_node.modulate = Color(1.0, 1.0, 1.0, 0.5)
		svp.add_child(hold_node)

	_defer_freeze_viewport(svp)

	var wrapper := Control.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(svc)

	return wrapper

func _defer_freeze_viewport(svp: SubViewport) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(svp):
		svp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60), int(seconds) % 60]

func _update_nav() -> void:
	btn_prev.disabled = _transitioning or _current_index <= 0
	btn_next.disabled = _transitioning or _current_index >= _levels.size() - 1

func _on_prev_pressed() -> void:
	if not _transitioning and _current_index > 0:
		_flip_to(_current_index - 1, -1)

func _on_next_pressed() -> void:
	if not _transitioning and _current_index < _levels.size() - 1:
		_flip_to(_current_index + 1, 1)

func _flip_to(new_index: int, direction: int) -> void:
	_transitioning = true
	_update_nav()

	if _tween:
		_tween.kill()

	var origin_x := page_container.position.x
	var slide    := page_container.size.x * 0.3 * direction

	_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(page_container, "position:x", origin_x - slide, 0.18)
	_tween.tween_callback(func():
		page_container.position.x = origin_x + slide
		_show_page(new_index)
	)
	_tween.tween_property(page_container, "position:x", origin_x, 0.18)
	_tween.tween_callback(func():
		_transitioning = false
		_update_nav()
	)

func _on_level_selected(level_path: String) -> void:
	GameState.set_current_level(level_path)
	Transition.to("res://scenes/main/main_scene.tscn")

func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/collections_select.tscn")
