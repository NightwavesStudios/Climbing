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

const WEATHER_NAMES = { 0: "", 1: "Rain", 2: "Snow", 3: "Wind", 4: "Storm" }

const HOLD_SCENES = {
	"START":  "res://scenes/holds/start.tscn",
	"TOP":    "res://scenes/holds/top_out.tscn",
	"JUG":    "res://scenes/holds/jug.tscn",
	"CRIMP":  "res://scenes/holds/crimp.tscn",
	"SLOPER": "res://scenes/holds/sloper.tscn",
	"POCKET": "res://scenes/holds/pocket.tscn",
	"FOOT":   "res://scenes/holds/foothold.tscn",
}

func _ready() -> void:
	btn_prev.pressed.connect(_on_prev_pressed)
	btn_next.pressed.connect(_on_next_pressed)
	btn_back.pressed.connect(_on_back_pressed)
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

	var route_name:  String = json.get("name", "Route %d" % (index + 1))
	var grade:       String = json.get("grade", "—")
	var discipline:  String = json.get("discipline", "bouldering").capitalize()
	var environment: String = json.get("environment", "—").capitalize()
	var weather_int: int    = int(json.get("weather", 0))
	var holds:       Array  = json.get("holds", [])

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	page_container.add_child(root)

	# Grade + route number
	var top_hbox := HBoxContainer.new()
	_pad(top_hbox, root, 20, 20, 18, 4)
	var grade_lbl := Label.new()
	grade_lbl.text = grade
	grade_lbl.add_theme_font_size_override("font_size", 42)
	grade_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(grade_lbl)
	var num_lbl := Label.new()
	num_lbl.text = "#%02d" % (index + 1)
	num_lbl.add_theme_font_size_override("font_size", 14)
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top_hbox.add_child(num_lbl)

	# Route name
	var name_lbl := Label.new()
	name_lbl.text = route_name
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pad(name_lbl, root, 20, 20, 0, 8)

	# Meta line
	var meta_parts := [discipline, environment]
	if weather_int > 0:
		meta_parts.append(WEATHER_NAMES.get(weather_int, ""))
	var meta_lbl := Label.new()
	meta_lbl.text = " · ".join(meta_parts)
	meta_lbl.add_theme_font_size_override("font_size", 13)
	_pad(meta_lbl, root, 20, 20, 0, 14)

	root.add_child(HSeparator.new())

	# Hold preview using SubViewport
	if meta.unlocked and not holds.is_empty():
		var preview_wrapper := MarginContainer.new()
		preview_wrapper.add_theme_constant_override("margin_left", 16)
		preview_wrapper.add_theme_constant_override("margin_right", 16)
		preview_wrapper.add_theme_constant_override("margin_top", 14)
		preview_wrapper.add_theme_constant_override("margin_bottom", 14)
		preview_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview_wrapper.custom_minimum_size = Vector2(0, 200)
		root.add_child(preview_wrapper)

		var preview: SubViewportContainer = await _build_hold_preview(holds, json.get("environment", "gym"))
		preview_wrapper.add_child(preview)
	else:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(spacer)

	root.add_child(HSeparator.new())

	# Best time
	if meta.completed and meta.time > 0.0:
		var time_lbl := Label.new()
		time_lbl.text = "Best: " + _format_time(meta.time)
		time_lbl.add_theme_font_size_override("font_size", 14)
		_pad(time_lbl, root, 20, 20, 10, 0)
		root.add_child(HSeparator.new())

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(bottom_spacer)

	# Action button
	if not meta.unlocked:
		var locked_lbl := Label.new()
		locked_lbl.text = "Complete the previous route to unlock."
		locked_lbl.add_theme_font_size_override("font_size", 12)
		locked_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_pad(locked_lbl, root, 20, 20, 10, 18)
	else:
		var btn := Button.new()
		btn.text = "Climb Again" if meta.completed else "Climb"
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_level_selected.bind(meta.path))
		_pad(btn, root, 20, 20, 10, 18)

	page_label.text = "%d / %d" % [index + 1, _levels.size()]
	_update_nav()


# ── SubViewport-based hold preview ────────────────────────────────────────────

func _build_hold_preview(holds: Array, environment: String) -> SubViewportContainer:
	# Holds in-game are placed at world coords (e.g. x:-96 to x:64, y:-192 to y:96).
	# Each hold sprite is roughly 64-128px at scale 1.0.
	# We place holds at their real world positions, then use a Camera2D to frame them.

	var container := SubViewportContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	container.stretch = true

	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(600, 300)
	sub_vp.transparent_bg = true
	sub_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(sub_vp)

	# Set environment BEFORE spawning holds so sprites pick up correct textures
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if env_config:
		for env_type in env_config.get_all_environment_types():
			if env_config.get_environment_name(env_type).to_lower() == environment.to_lower():
				env_config.set_environment(env_type)
				break

	# Compute bounds from raw world positions
	var min_x := (holds[0].get("x", 0.0)) as float
	var max_x := min_x
	var min_y := (holds[0].get("y", 0.0)) as float
	var max_y := min_y
	for hd in holds:
		var hx := hd.get("x", 0.0) as float
		var hy := hd.get("y", 0.0) as float
		min_x = min(min_x, hx); max_x = max(max_x, hx)
		min_y = min(min_y, hy); max_y = max(max_y, hy)

	var center_x := (min_x + max_x) * 0.5
	var center_y := (min_y + max_y) * 0.5
	var range_x  = max(max_x - min_x, 80.0)
	var range_y  = max(max_y - min_y, 80.0)

	# Padding in world units (hold sprites are ~64px wide at scale 1.0)
	var world_pad := 80.0
	var zoom_x = (range_x + world_pad * 2.0) / 600.0
	var zoom_y = (range_y + world_pad * 2.0) / 300.0
	var zoom   = max(zoom_x, zoom_y)

	# Camera frames all holds with correct zoom
	var cam := Camera2D.new()
	cam.position = Vector2(center_x, center_y)
	cam.zoom = Vector2(1.0 / zoom, 1.0 / zoom)
	sub_vp.add_child(cam)

	var root_node := Node2D.new()
	sub_vp.add_child(root_node)

	for hd in holds:
		var type := hd.get("type", "JUG") as String
		if type not in HOLD_SCENES or not ResourceLoader.exists(HOLD_SCENES[type]):
			continue
		var hold_node := (load(HOLD_SCENES[type]) as PackedScene).instantiate()
		# Place at real world position — Camera2D handles framing
		hold_node.position = Vector2(hd.get("x", 0.0), hd.get("y", 0.0))
		root_node.add_child(hold_node)
		if hold_node.has_method("_update_sprite_for_environment"):
			hold_node.call_deferred("_update_sprite_for_environment")
		elif hold_node.has_method("set_hold_type_from_string"):
			hold_node.call_deferred("set_hold_type_from_string", type)

	await get_tree().process_frame
	await get_tree().process_frame

	return container


# ── Helpers ───────────────────────────────────────────────────────────────────

func _pad(node: Node, parent: Control, left: int, right: int, top: int, bottom: int) -> void:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_child(node)
	parent.add_child(m)

func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60), int(seconds) % 60]

func _update_nav() -> void:
	btn_prev.disabled = _current_index <= 0
	btn_next.disabled = _current_index >= _levels.size() - 1

func _on_prev_pressed() -> void:
	if _current_index > 0:
		_flip_to(_current_index - 1, -1)

func _on_next_pressed() -> void:
	if _current_index < _levels.size() - 1:
		_flip_to(_current_index + 1, 1)

func _flip_to(new_index: int, direction: int) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	var slide := page_container.size.x * 0.25 * direction
	_tween.tween_property(page_container, "position:x", page_container.position.x - slide, 0.15)
	_tween.tween_callback(func():
		page_container.position.x += slide * 2
		_show_page(new_index)
	)
	_tween.tween_property(page_container, "position:x", page_container.position.x, 0.15)

func _on_level_selected(level_path: String) -> void:
	GameState.set_current_level(level_path)
	Transition.to("res://scenes/main/main_scene.tscn")

func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/collections_select.tscn")
