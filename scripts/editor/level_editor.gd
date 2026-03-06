extends Node2D

var camera: Camera2D
var holds_container: Node2D
var preview_container: Node2D
var crashpads_container: Node2D
var wall: Node2D

var ui_layer: CanvasLayer
var info_label: Label
var hold_type_dropdown: OptionButton
var environment_dropdown: OptionButton
var climb_name_input: LineEdit
var grade_dropdown: OptionButton

var discipline_dropdown: OptionButton
var discipline_settings_panel: VBoxContainer
var speed_time_input: SpinBox
var belayer_placement_button: Button
var placing_belayer: bool = false
var belayer_marker: Node2D = null

var crashpad_button: Button

var weather_dropdown: OptionButton
var weather_intensity_slider: HSlider
var weather_intensity_label: Label

var ui_panel_collapsed: bool = true
var top_bar: ColorRect
var drawer_panel: ColorRect
var drawer_container: MarginContainer
var fold_button: Button

const BAR_HEIGHT:    float = 42.0
const DRAWER_HEIGHT: float = 148.0

var selected_hold_type: String = ""
var preview_hold: Node2D = null
var dragging_hold: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO
var drag_start_position: Vector2 = Vector2.ZERO

var is_testing: bool = false
var preview_player_ref: Node2D = null

var _speed_timer_node: Node = null
var _speed_fail_pending: bool = false

var placing_crashpad: bool = false
var preview_crashpad: Node2D = null
var dragging_crashpad: Node2D = null
var crashpad_drag_start_position: Vector2 = Vector2.ZERO

var climb_name: String = ""
var climb_grade: String = "VB"

var current_discipline: String = "bouldering"
var speed_time_limit: float = 60.0
var belayer_position: Vector2 = Vector2.ZERO

var current_weather: int = 0
var current_weather_intensity: float = 1.0
const WEATHER_NAMES := ["None", "Rain", "Night", "Snow"]

var grid_enabled: bool = true
var grid_size: float = 32.0

var undo_stack: Array = []
const MAX_UNDO_STACK: int = 50

const MAX_START_HOLDS: int = 2
const MAX_TOP_HOLDS: int = 1
const MIN_HOLD_DISTANCE: float = 40.0
const MAX_REACH_DISTANCE: float = 250.0

const V_GRADES   = ["VB","V0","V1","V2","V3","V4","V5","V6","V7","V8","V9","V10","V11","V12"]
const YDS_GRADES = ["5.5","5.6","5.7","5.8","5.9","5.10a","5.10b","5.10c","5.10d",
					"5.11a","5.11b","5.11c","5.11d","5.12a","5.12b","5.12c","5.12d","5.13a","5.13b"]

const HOLD_TYPES  = ["START","TOP","JUG","CRIMP","SLOPER","POCKET","FOOT","WINDOW","LEDGE"]
const HOLD_SCENES = {
	"START":  "res://scenes/holds/start.tscn",
	"TOP":    "res://scenes/holds/top_out.tscn",
	"JUG":    "res://scenes/holds/jug.tscn",
	"CRIMP":  "res://scenes/holds/crimp.tscn",
	"SLOPER": "res://scenes/holds/sloper.tscn",
	"POCKET": "res://scenes/holds/pocket.tscn",
	"FOOT":   "res://scenes/holds/foothold.tscn",
	"WINDOW": "res://scenes/holds/window.tscn",
	"LEDGE":  "res://scenes/holds/ledge.tscn",
}
const CRASHPAD_SCENE = "res://scenes/props/crashpad.tscn"

var loaded_scenes: Dictionary = {}
var crashpad_scene: PackedScene = null

const ZOOM_SPEED          = 0.15
const TRACKPAD_ZOOM_SPEED = 0.2
const PAN_SPEED           = 1000.0
const MIN_ZOOM            = 0.2
const MAX_ZOOM            = 3.0

const CANVAS_MIN_X = -1500.0
const CANVAS_MAX_X =  2500.0
const CANVAS_MIN_Y = -3000.0
const CANVAS_MAX_Y =  2000.0

const WALL_PADDING_SIDES  = 100.0
const WALL_PADDING_TOP    = 100.0
const WALL_PADDING_BOTTOM = 150.0

@export_group("Audio Settings")
@export var enable_editor_sounds: bool = true
@export var master_volume_db: float = -6.0

@export_subgroup("Action Pitches")
@export var pitch_place_hold:     float = 1.2
@export var pitch_delete_hold:    float = 0.7
@export var pitch_place_crashpad: float = 1.15
@export var pitch_copy_json:      float = 1.3
@export var pitch_paste_json:     float = 1.25
@export var pitch_clear:          float = 0.6
@export var pitch_error:          float = 0.5
@export var pitch_success:        float = 1.4
@export var pitch_preview:        float = 1.2

@export_subgroup("Pitch Randomization")
@export var randomize_pitch:  bool  = true
@export var pitch_variation:  float = 0.05

const CLICK_SOUND = preload("res://assets/audio/sfx/button-clicked.wav")
var _audio_player: AudioStreamPlayer


func _ready():
	_setup_audio()

	wall = get_node_or_null("Wall")
	if wall and wall.has_method("set_editor_mode"):
		wall.set_editor_mode(true)
	if wall and wall.has_method("_init_weather"):
		wall._init_weather()

	if has_node("Camera2D"):
		camera = get_node("Camera2D")
	else:
		camera = Camera2D.new()
		camera.name     = "Camera2D"
		camera.zoom     = Vector2(0.5, 0.5)
		camera.position = Vector2(500, 0)
		add_child(camera)

	camera.make_current()
	if "position_smoothing_enabled" in camera:
		camera.position_smoothing_enabled = false
	if "drag_horizontal_enabled" in camera:
		camera.drag_horizontal_enabled = false
		camera.drag_vertical_enabled   = false

	holds_container     = _get_or_create_node2d("Holds")
	crashpads_container = _get_or_create_node2d("Crashpads")
	preview_container   = _get_or_create_node2d("PreviewContainer")
	preview_container.z_index = 100

	for type_name in HOLD_SCENES:
		if ResourceLoader.exists(HOLD_SCENES[type_name]):
			loaded_scenes[type_name] = load(HOLD_SCENES[type_name])
	if ResourceLoader.exists(CRASHPAD_SCENE):
		crashpad_scene = load(CRASHPAD_SCENE)

	setup_ui()
	update_wall_bounds()

func _get_or_create_node2d(node_name: String) -> Node2D:
	if has_node(node_name):
		return get_node(node_name)
	var n      = Node2D.new()
	n.name     = node_name
	add_child(n)
	return n

func _process(delta):
	update_camera(delta)
	update_preview()
	update_info_label()
	if is_testing and is_instance_valid(preview_player_ref):
		camera.position = camera.position.lerp(preview_player_ref.global_position, 8.0 * delta)
	queue_redraw()


func _setup_audio():
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name      = "EditorAudioPlayer"
	_audio_player.stream    = CLICK_SOUND
	_audio_player.volume_db = master_volume_db
	add_child(_audio_player)

func play_sound(base_pitch: float):
	if not enable_editor_sounds:
		return
	var final_pitch = base_pitch
	if randomize_pitch:
		final_pitch += randf_range(-pitch_variation, pitch_variation)
	_audio_player.pitch_scale = final_pitch
	_audio_player.play()


func setup_ui():
	ui_layer       = CanvasLayer.new()
	ui_layer.name  = "UI"
	ui_layer.layer = 10
	add_child(ui_layer)

	top_bar       = ColorRect.new()
	top_bar.color = Color(0.10, 0.10, 0.13, 0.96)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.size.y        = BAR_HEIGHT
	top_bar.mouse_filter  = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(top_bar)

	var accent       = ColorRect.new()
	accent.color     = Color(0.35, 0.60, 1.0, 0.55)
	accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent.position.y = BAR_HEIGHT - 2
	accent.size.y     = 2
	ui_layer.add_child(accent)

	var bar_margin = MarginContainer.new()
	bar_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar_margin.size.y = BAR_HEIGHT
	bar_margin.add_theme_constant_override("margin_left",   12)
	bar_margin.add_theme_constant_override("margin_right",  12)
	bar_margin.add_theme_constant_override("margin_top",     7)
	bar_margin.add_theme_constant_override("margin_bottom",  7)
	ui_layer.add_child(bar_margin)

	var bar_hbox = HBoxContainer.new()
	bar_hbox.add_theme_constant_override("separation", 8)
	bar_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar_margin.add_child(bar_hbox)

	var logo_label = create_simple_label("✦ ROUTE")
	logo_label.add_theme_font_size_override("font_size", 10)
	logo_label.add_theme_color_override("font_color", Color(0.4, 0.65, 1.0))
	logo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_hbox.add_child(logo_label)

	climb_name_input = LineEdit.new()
	climb_name_input.placeholder_text = "Unnamed Route"
	climb_name_input.custom_minimum_size = Vector2(120, 28)
	climb_name_input.add_theme_font_size_override("font_size", 11)
	climb_name_input.text_changed.connect(_on_climb_name_changed)
	bar_hbox.add_child(climb_name_input)

	_add_bar_separator(bar_hbox)

	discipline_dropdown = OptionButton.new()
	discipline_dropdown.custom_minimum_size = Vector2(90, 28)
	discipline_dropdown.add_item("Boulder")
	discipline_dropdown.add_item("Roped")
	discipline_dropdown.add_item("Speed")
	discipline_dropdown.select(0)
	discipline_dropdown.item_selected.connect(_on_discipline_changed)
	bar_hbox.add_child(discipline_dropdown)

	grade_dropdown = OptionButton.new()
	grade_dropdown.custom_minimum_size = Vector2(70, 28)
	populate_grade_dropdown()
	grade_dropdown.item_selected.connect(_on_grade_changed)
	bar_hbox.add_child(grade_dropdown)

	_add_bar_separator(bar_hbox)

	hold_type_dropdown = OptionButton.new()
	hold_type_dropdown.custom_minimum_size = Vector2(90, 28)
	if has_node("/root/HoldRegistry"):
		var registry = get_node("/root/HoldRegistry")
		for type_name in registry.get_all_hold_types():
			hold_type_dropdown.add_item(registry.get_hold_display_name(type_name))
			hold_type_dropdown.set_item_metadata(
				hold_type_dropdown.get_item_count() - 1, type_name)
	else:
		for type_name in HOLD_TYPES:
			hold_type_dropdown.add_item(type_name)
	hold_type_dropdown.item_selected.connect(_on_hold_type_selected)
	bar_hbox.add_child(hold_type_dropdown)

	_add_bar_separator(bar_hbox)

	var copy_btn  = _make_bar_button("Copy",   func(): _on_copy_json())
	var paste_btn = _make_bar_button("Paste",  func(): _on_paste_json())
	var test_btn  = _make_bar_button("▶ Test", func(): _on_preview())
	test_btn.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	bar_hbox.add_child(copy_btn)
	bar_hbox.add_child(paste_btn)
	bar_hbox.add_child(test_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_hbox.add_child(spacer)

	fold_button = _make_bar_button("▼ More", func(): _on_fold_button_pressed())
	fold_button.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	bar_hbox.add_child(fold_button)

	drawer_panel       = ColorRect.new()
	drawer_panel.color = Color(0.10, 0.11, 0.14, 0.93)
	drawer_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	drawer_panel.position.y   = BAR_HEIGHT + 2
	drawer_panel.size.y       = DRAWER_HEIGHT
	drawer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(drawer_panel)

	drawer_container = MarginContainer.new()
	drawer_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	drawer_container.position.y = BAR_HEIGHT + 2
	drawer_container.size.y     = DRAWER_HEIGHT
	drawer_container.add_theme_constant_override("margin_left",   18)
	drawer_container.add_theme_constant_override("margin_right",  18)
	drawer_container.add_theme_constant_override("margin_top",    10)
	drawer_container.add_theme_constant_override("margin_bottom", 10)
	ui_layer.add_child(drawer_container)

	var drawer_hbox = HBoxContainer.new()
	drawer_hbox.add_theme_constant_override("separation", 16)
	drawer_container.add_child(drawer_hbox)

	var env_col = VBoxContainer.new()
	env_col.add_theme_constant_override("separation", 6)
	drawer_hbox.add_child(env_col)

	var env_row = _make_labeled_row("Environment", env_col)
	environment_dropdown = OptionButton.new()
	environment_dropdown.custom_minimum_size = Vector2(120, 26)
	_populate_environment_dropdown()
	environment_dropdown.item_selected.connect(on_environment_changed)
	env_row.add_child(environment_dropdown)

	var weather_row = _make_labeled_row("Weather", env_col)
	weather_dropdown = OptionButton.new()
	weather_dropdown.custom_minimum_size = Vector2(120, 26)
	_populate_weather_dropdown()
	weather_dropdown.item_selected.connect(_on_weather_changed)
	weather_row.add_child(weather_dropdown)

	var intensity_row = _make_labeled_row("Intensity", env_col)
	weather_intensity_slider = HSlider.new()
	weather_intensity_slider.min_value = 0.1
	weather_intensity_slider.max_value = 1.0
	weather_intensity_slider.step      = 0.05
	weather_intensity_slider.value     = 1.0
	weather_intensity_slider.custom_minimum_size = Vector2(90, 20)
	weather_intensity_slider.value_changed.connect(_on_weather_intensity_changed)
	intensity_row.add_child(weather_intensity_slider)
	weather_intensity_label = create_simple_label("100%")
	weather_intensity_label.add_theme_font_size_override("font_size", 10)
	intensity_row.add_child(weather_intensity_label)

	intensity_row.visible = false
	weather_intensity_slider.set_meta("intensity_row", intensity_row)

	_add_drawer_separator(drawer_hbox)

	var place_col = VBoxContainer.new()
	place_col.add_theme_constant_override("separation", 6)
	drawer_hbox.add_child(place_col)

	var place_label = create_simple_label("PLACEMENT")
	place_label.add_theme_font_size_override("font_size", 10)
	place_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	place_col.add_child(place_label)

	crashpad_button = create_flat_button("☁ Place Crashpad", Vector2(140, 26))
	crashpad_button.pressed.connect(_on_place_crashpad_pressed)
	place_col.add_child(crashpad_button)

	discipline_settings_panel = VBoxContainer.new()
	discipline_settings_panel.visible = false
	discipline_settings_panel.add_theme_constant_override("separation", 4)
	place_col.add_child(discipline_settings_panel)

	var speed_hbox = HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", 6)
	var speed_lbl = create_simple_label("Time Limit:")
	speed_hbox.add_child(speed_lbl)
	speed_time_input = SpinBox.new()
	speed_time_input.min_value = 10.0
	speed_time_input.max_value = 300.0
	speed_time_input.step      = 5.0
	speed_time_input.value     = 60.0
	speed_time_input.suffix    = "s"
	speed_time_input.custom_minimum_size = Vector2(90, 26)
	speed_time_input.value_changed.connect(_on_speed_time_changed)
	speed_hbox.add_child(speed_time_input)
	discipline_settings_panel.add_child(speed_hbox)

	belayer_placement_button = create_flat_button("⚓ Place Rope Anchor", Vector2(140, 26))
	belayer_placement_button.pressed.connect(_on_place_belayer_pressed)
	discipline_settings_panel.add_child(belayer_placement_button)

	_add_drawer_separator(drawer_hbox)

	var act_col = VBoxContainer.new()
	act_col.add_theme_constant_override("separation", 6)
	drawer_hbox.add_child(act_col)

	var act_label = create_simple_label("EDITOR")
	act_label.add_theme_font_size_override("font_size", 10)
	act_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	act_col.add_child(act_label)

	var act_row1 = HBoxContainer.new()
	act_row1.add_theme_constant_override("separation", 6)
	act_col.add_child(act_row1)

	var grid_btn = create_flat_button("Grid: ON", Vector2(74, 26))
	grid_btn.pressed.connect(func(): toggle_grid(grid_btn))
	act_row1.add_child(grid_btn)

	var wall_btn = create_flat_button("Edit Wall", Vector2(74, 26))
	wall_btn.pressed.connect(_on_toggle_wall_edit)
	act_row1.add_child(wall_btn)

	var act_row2 = HBoxContainer.new()
	act_row2.add_theme_constant_override("separation", 6)
	act_col.add_child(act_row2)

	var clear_btn = create_flat_button("Clear", Vector2(74, 26))
	clear_btn.pressed.connect(_on_clear)
	act_row2.add_child(clear_btn)

	var back_btn = create_flat_button("← Back", Vector2(74, 26))
	back_btn.pressed.connect(_on_back_pressed)
	back_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	act_row2.add_child(back_btn)

	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info_label.position.y = -26
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0.80, 0.80, 0.88, 0.80))
	info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	info_label.add_theme_constant_override("outline_size", 1)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(info_label)

	_apply_panel_fold_state()


func _add_bar_separator(parent: HBoxContainer):
	var sep = ColorRect.new()
	sep.color = Color(0.3, 0.3, 0.38, 0.45)
	sep.custom_minimum_size = Vector2(1, 20)
	parent.add_child(sep)

func _add_drawer_separator(parent: HBoxContainer):
	var sep = ColorRect.new()
	sep.color = Color(0.28, 0.28, 0.35, 0.35)
	sep.custom_minimum_size = Vector2(1, 110)
	parent.add_child(sep)

func _make_labeled_row(label_text: String, parent: VBoxContainer) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)
	var lbl = create_simple_label(label_text + ":")
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.custom_minimum_size = Vector2(68, 0)
	hbox.add_child(lbl)
	return hbox

func _make_bar_button(label_text: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, 28)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)

	var n = StyleBoxFlat.new()
	n.bg_color = Color(0.18, 0.19, 0.23)
	n.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", n)

	var h = StyleBoxFlat.new()
	h.bg_color = Color(0.24, 0.26, 0.32)
	h.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", h)

	var p = StyleBoxFlat.new()
	p.bg_color = Color(0.12, 0.13, 0.16)
	p.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("pressed", p)

	btn.pressed.connect(callback)
	return btn


func _on_fold_button_pressed() -> void:
	ui_panel_collapsed = !ui_panel_collapsed
	_apply_panel_fold_state()

func _apply_panel_fold_state() -> void:
	drawer_panel.visible     = not ui_panel_collapsed
	drawer_container.visible = not ui_panel_collapsed
	fold_button.text = "▲ Less" if not ui_panel_collapsed else "▼ More"

func is_mouse_over_ui() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()
	if mouse_pos.y < BAR_HEIGHT:
		return true
	if not ui_panel_collapsed and mouse_pos.y < BAR_HEIGHT + 2 + DRAWER_HEIGHT:
		return true
	return false


func _populate_weather_dropdown() -> void:
	weather_dropdown.clear()
	for n in WEATHER_NAMES:
		weather_dropdown.add_item(n)
	weather_dropdown.select(0)

func _on_weather_changed(index: int) -> void:
	current_weather = index
	if weather_intensity_slider.has_meta("intensity_row"):
		weather_intensity_slider.get_meta("intensity_row").visible = index > 0
	_apply_weather_to_wall()

	var is_night = (index < WEATHER_NAMES.size() and WEATHER_NAMES[index] == "Night")
	for hold in holds_container.get_children():
		hold.modulate = Color(1.4, 1.4, 1.6) if is_night else Color(1, 1, 1)

	show_notification("Weather: " + (WEATHER_NAMES[index] if index < WEATHER_NAMES.size() else "?"))

func _on_weather_intensity_changed(value: float) -> void:
	current_weather_intensity = value
	weather_intensity_label.text = "%d%%" % int(value * 100.0)
	_apply_weather_to_wall()

func _apply_weather_to_wall() -> void:
	if wall and wall.has_method("set_weather"):
		wall.set_weather(current_weather, current_weather_intensity)


func _populate_environment_dropdown():
	environment_dropdown.clear()
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if env_config:
		for env_type in env_config.get_all_environment_types():
			environment_dropdown.add_item(env_config.get_environment_name(env_type))
		environment_dropdown.select(env_config.get_current_environment())
	else:
		environment_dropdown.add_item("Gym")
		environment_dropdown.add_item("Granite")
		environment_dropdown.select(0)


func create_simple_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func add_vertical_separator(parent: HBoxContainer):
	var sep = ColorRect.new()
	sep.color = Color(0.3, 0.3, 0.35, 0.4)
	sep.custom_minimum_size = Vector2(2, 120)
	parent.add_child(sep)

func create_flat_button(button_text: String, min_size: Vector2) -> Button:
	var button = Button.new()
	button.text = button_text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)

	var n = StyleBoxFlat.new()
	n.bg_color = Color(0.18, 0.20, 0.24)
	n.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", n)

	var h = StyleBoxFlat.new()
	h.bg_color = Color(0.23, 0.26, 0.32)
	h.set_corner_radius_all(4)
	button.add_theme_stylebox_override("hover", h)

	var p = StyleBoxFlat.new()
	p.bg_color = Color(0.13, 0.15, 0.18)
	p.set_corner_radius_all(4)
	button.add_theme_stylebox_override("pressed", p)

	return button

func populate_grade_dropdown():
	grade_dropdown.clear()
	var grades = V_GRADES if current_discipline == "bouldering" else YDS_GRADES
	for grade in grades:
		grade_dropdown.add_item(grade)
	grade_dropdown.select(0)


func _on_discipline_changed(index: int):
	match index:
		0:
			current_discipline = "bouldering"
			climb_grade = "VB"
			discipline_settings_panel.visible = false
			crashpad_button.visible = true
			_clear_belayer_marker()
		1:
			current_discipline = "roped"
			climb_grade = "5.5"
			discipline_settings_panel.visible = true
			speed_time_input.visible = false
			belayer_placement_button.visible = true
			crashpad_button.visible = true
			show_notification("Click '⚓ Place Rope Anchor' to set belay point")
		2:
			current_discipline = "speed"
			climb_grade = "5.5"
			discipline_settings_panel.visible = true
			speed_time_input.visible = true
			belayer_placement_button.visible = false
			crashpad_button.visible = true
			_clear_belayer_marker()

	populate_grade_dropdown()

func _on_speed_time_changed(value: float):
	speed_time_limit = value

func _on_place_belayer_pressed():
	placing_belayer   = true
	selected_hold_type = ""
	placing_crashpad  = false
	clear_preview()
	show_notification("Click anywhere to place rope anchor point")

func _clear_belayer_marker():
	if belayer_marker and is_instance_valid(belayer_marker):
		belayer_marker.queue_free()
	belayer_marker   = null
	belayer_position = Vector2.ZERO

func _create_belayer_marker(pos: Vector2):
	_clear_belayer_marker()
	belayer_marker          = Node2D.new()
	belayer_marker.name     = "BelayerMarker"
	belayer_marker.z_index  = 100
	belayer_marker.global_position = pos
	belayer_position        = pos

	var marker_sprite = Sprite2D.new()
	var image = Image.create(32, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(48):
		for x in range(32):
			if Vector2(x - 16, y - 8).length() < 6:
				image.set_pixel(x, y, Color.ORANGE)
			if x >= 14 and x <= 18 and y >= 14 and y <= 32:
				image.set_pixel(x, y, Color.ORANGE)
			if y >= 18 and y <= 22 and x >= 8 and x <= 24:
				image.set_pixel(x, y, Color.ORANGE)
			if y >= 32 and y <= 46 and ((x >= 10 and x <= 13) or (x >= 19 and x <= 22)):
				image.set_pixel(x, y, Color.ORANGE)
	marker_sprite.texture = ImageTexture.create_from_image(image)
	belayer_marker.add_child(marker_sprite)
	add_child(belayer_marker)
	show_notification("Rope anchor placed!")

func _on_hold_type_selected(index: int):
	if hold_type_dropdown.get_item_metadata(index) != null:
		selected_hold_type = hold_type_dropdown.get_item_metadata(index)
	else:
		selected_hold_type = hold_type_dropdown.get_item_text(index)
	placing_crashpad  = false
	placing_belayer   = false
	clear_preview()

func _on_place_crashpad_pressed():
	placing_crashpad  = true
	selected_hold_type = ""
	placing_belayer   = false
	clear_preview()


func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed):
			if not is_testing:
				undo_last_action()
			return
		match event.keycode:
			KEY_DELETE:
				if not is_testing:
					if dragging_hold:     delete_hold(dragging_hold)
					elif dragging_crashpad: delete_crashpad(dragging_crashpad)
			KEY_ESCAPE:
				if is_testing:
					_stop_testing()
					return
				selected_hold_type = ""
				placing_crashpad   = false
				placing_belayer    = false
				clear_preview()
				dragging_hold      = null
				dragging_crashpad  = null

	if is_testing:
		return

	if is_mouse_over_ui():
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				handle_left_click()
			else:
				if dragging_hold and dragging_hold.global_position != drag_start_position:
					save_undo_state()
					update_wall_bounds()
				elif dragging_crashpad and dragging_crashpad.global_position != crashpad_drag_start_position:
					save_undo_state()
				dragging_hold     = null
				dragging_crashpad = null
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var pos  = get_global_mouse_position()
			var hold = get_hold_at_position(pos)
			if hold:
				delete_hold(hold)
			else:
				var crashpad = get_crashpad_at_position(pos)
				if crashpad:
					delete_crashpad(crashpad)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * (1.0 + ZOOM_SPEED)).clamp(
				Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom * (1.0 - ZOOM_SPEED)).clamp(
				Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))

	elif event is InputEventMagnifyGesture:
		var zoom_change = (event.factor - 1.0) * TRACKPAD_ZOOM_SPEED
		camera.zoom = (camera.zoom * (1.0 + zoom_change)).clamp(
			Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))

	elif event is InputEventPanGesture:
		camera.position += event.delta * 50.0 / camera.zoom.x

	elif event is InputEventMouseMotion:
		if dragging_hold:
			var new_pos = snap_to_grid(get_global_mouse_position() + drag_offset)
			new_pos.x = clamp(new_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
			new_pos.y = clamp(new_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
			dragging_hold.global_position = new_pos
		elif dragging_crashpad:
			var new_pos = snap_to_grid(get_global_mouse_position() + drag_offset)
			new_pos.x = clamp(new_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
			new_pos.y = clamp(new_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
			dragging_crashpad.global_position = new_pos

func handle_left_click():
	var pos = get_global_mouse_position()
	var wall_is_editing = wall and "edit_mode" in wall and wall.edit_mode

	if placing_belayer:
		var snapped_pos = snap_to_grid(pos)
		save_undo_state()
		_create_belayer_marker(snapped_pos)
		placing_belayer = false
		return

	if placing_crashpad and crashpad_scene:
		place_crashpad(snap_to_grid(pos))
	elif selected_hold_type and selected_hold_type in loaded_scenes:
		place_hold(snap_to_grid(pos))
	else:
		if wall_is_editing:
			return
		var hold = get_hold_at_position(pos)
		if hold:
			save_undo_state()
			dragging_hold       = hold
			drag_offset         = hold.global_position - pos
			drag_start_position = hold.global_position
		else:
			var crashpad = get_crashpad_at_position(pos)
			if crashpad:
				save_undo_state()
				dragging_crashpad = crashpad
				drag_offset       = crashpad.global_position - pos
				crashpad_drag_start_position = crashpad.global_position


func place_crashpad(pos: Vector2) -> bool:
	if not crashpad_scene:
		show_notification("Crashpad scene not found!", true)
		play_sound(pitch_error)
		return false
	pos.x = clamp(pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
	pos.y = clamp(pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
	save_undo_state()
	var crashpad = crashpad_scene.instantiate()
	crashpad.global_position = pos
	crashpads_container.add_child(crashpad)
	crashpad.add_to_group("crashpads")
	play_sound(pitch_place_crashpad)
	return true

func delete_crashpad(crashpad: Node2D):
	save_undo_state()
	if crashpad == dragging_crashpad:
		dragging_crashpad = null
	crashpad.queue_free()
	play_sound(pitch_delete_hold)

func get_crashpad_at_position(pos: Vector2, max_dist: float = 60.0) -> Node2D:
	var closest: Node2D = null
	var closest_dist = max_dist
	for crashpad in crashpads_container.get_children():
		var dist = crashpad.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest      = crashpad
	return closest


func _on_copy_json():
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	var environment_name = "gym"
	if env_config:
		environment_name = env_config.get_current_environment_name().to_lower()

	var level_data = {
		"name":              climb_name if climb_name != "" else "Unnamed Route",
		"grade":             climb_grade,
		"environment":       environment_name,
		"discipline":        current_discipline,
		"weather":           current_weather,
		"weather_intensity": current_weather_intensity,
		"speed_time_limit":  speed_time_limit,
		"holds":             [],
		"crashpads":         []
	}

	if current_discipline == "roped" and belayer_position != Vector2.ZERO:
		level_data["belayer_position"] = { "x": belayer_position.x, "y": belayer_position.y }

	if wall and wall.has_method("get_polygon_data"):
		var polygon_data = wall.get_polygon_data()
		if polygon_data:
			level_data["wall_polygon"] = polygon_data

	for hold in holds_container.get_children():
		level_data.holds.append({
			"type": get_hold_type(hold),
			"x":    hold.global_position.x,
			"y":    hold.global_position.y
		})

	for crashpad in crashpads_container.get_children():
		level_data.crashpads.append({
			"x": crashpad.global_position.x,
			"y": crashpad.global_position.y
		})

	DisplayServer.clipboard_set(JSON.stringify(level_data, "\t"))
	play_sound(pitch_copy_json)
	show_notification("Route copied to clipboard")

func _on_paste_json():
	var clipboard = DisplayServer.clipboard_get()
	if clipboard.is_empty():
		show_notification("Clipboard is empty!", true)
		play_sound(pitch_error)
		return

	var json  = JSON.new()
	var error = json.parse(clipboard)
	if error != OK:
		show_notification("Invalid route data in clipboard!", true)
		play_sound(pitch_error)
		return

	var data = json.data
	if not "holds" in data:
		show_notification("No route data found!", true)
		play_sound(pitch_error)
		return

	_on_clear()

	climb_name = data.get("name", "")
	if climb_name_input:
		climb_name_input.text = climb_name

	current_discipline = data.get("discipline", "bouldering")
	speed_time_limit   = float(data.get("speed_time_limit", 60.0))
	var saved_grade    = data.get("grade", "VB")

	if discipline_dropdown:
		match current_discipline:
			"bouldering": discipline_dropdown.select(0)
			"roped":      discipline_dropdown.select(1)
			"speed":      discipline_dropdown.select(2)
		_on_discipline_changed(discipline_dropdown.selected)

	if grade_dropdown:
		var grades = V_GRADES if current_discipline == "bouldering" else YDS_GRADES
		var idx    = grades.find(saved_grade)
		if idx >= 0:
			grade_dropdown.select(idx)
			_on_grade_changed(idx)

	if grade_dropdown:
		var grades = V_GRADES if current_discipline == "bouldering" else YDS_GRADES
		var idx    = grades.find(climb_grade)
		if idx >= 0:
			grade_dropdown.select(idx)
			_on_grade_changed(idx)

	if speed_time_input:
		speed_time_input.value = speed_time_limit

	if "belayer_position" in data and data.belayer_position:
		var bd = data.belayer_position
		_create_belayer_marker(Vector2(bd.get("x", 0), bd.get("y", 0)))

	var environment_name = data.get("environment", "gym")
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if env_config:
		var matched   = false
		var env_types = env_config.get_all_environment_types()
		for i in range(env_types.size()):
			if env_config.get_environment_name(env_types[i]).to_lower() == environment_name.to_lower():
				env_config.set_environment(env_types[i])
				environment_dropdown.select(i)
				matched = true
				break
		if not matched:
			env_config.set_environment(env_types[0])
			environment_dropdown.select(0)
		update_wall_bounds()

	var loaded_weather   := int(data.get("weather",           0))
	var loaded_intensity := float(data.get("weather_intensity", 1.0))
	current_weather           = loaded_weather
	current_weather_intensity = loaded_intensity
	if weather_dropdown:
		weather_dropdown.select(clamp(loaded_weather, 0, weather_dropdown.get_item_count() - 1))
		_on_weather_changed(loaded_weather)
	if weather_intensity_slider:
		weather_intensity_slider.value = loaded_intensity

	for hold_data in data.holds:
		var type_name = hold_data.get("type", "JUG")
		if type_name not in loaded_scenes:
			continue
		var hold = loaded_scenes[type_name].instantiate()
		if hold.has_method("set_hold_type_from_string"):
			hold.set_hold_type_from_string(type_name)
		hold.global_position = Vector2(hold_data.get("x", 0), hold_data.get("y", 0))
		holds_container.add_child(hold)
		hold.add_to_group("holds")
		hold.set_meta("editor_type", type_name)

	if "crashpads" in data and crashpad_scene:
		for cpd in data.crashpads:
			var cp = crashpad_scene.instantiate()
			cp.global_position = Vector2(cpd.get("x", 0), cpd.get("y", 0))
			crashpads_container.add_child(cp)
			cp.add_to_group("crashpads")

	if "wall_polygon" in data and wall and wall.has_method("set_polygon_data"):
		wall.set_polygon_data(data.wall_polygon)

	update_wall_bounds()
	play_sound(pitch_paste_json)
	show_notification("Route loaded: " + climb_name)


func get_hold_type(hold: Node2D) -> String:
	if hold.has_meta("editor_type"):
		return hold.get_meta("editor_type")
	if "hold_type" in hold:
		match hold.hold_type:
			0: return "JUG"
			1: return "START"
			2: return "TOP"
			3: return "CRIMP"
			4: return "SLOPER"
			5: return "FOOT"
			6: return "POCKET"
			7: return "WINDOW"
			8: return "LEDGE"
	return "JUG"

func update_wall_bounds():
	if wall and wall.has_method("calculate_bounds_from_holds"):
		wall.calculate_bounds_from_holds(holds_container)
	queue_redraw()

func place_hold(pos: Vector2) -> bool:
	if not selected_hold_type or selected_hold_type not in loaded_scenes:
		return false
	pos.x = clamp(pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
	pos.y = clamp(pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)

	if selected_hold_type == "START" and count_holds_of_type("START") >= MAX_START_HOLDS:
		show_notification("Maximum %d START holds allowed!" % MAX_START_HOLDS, true)
		play_sound(pitch_error)
		return false
	if selected_hold_type == "TOP" and count_holds_of_type("TOP") >= MAX_TOP_HOLDS:
		show_notification("Maximum %d TOP hold allowed!" % MAX_TOP_HOLDS, true)
		play_sound(pitch_error)
		return false
	if is_position_too_close(pos, null):
		show_notification("Hold too close to another hold!", true)
		play_sound(pitch_error)
		return false
	if not is_position_reachable(pos, null):
		show_notification("Hold too far from route!", true)
		play_sound(pitch_error)
		return false

	save_undo_state()
	var hold = loaded_scenes[selected_hold_type].instantiate()
	if hold.has_method("set_hold_type_from_string"):
		hold.set_hold_type_from_string(selected_hold_type)
	hold.global_position = pos
	holds_container.add_child(hold)
	hold.add_to_group("holds")
	hold.set_meta("editor_type", selected_hold_type)
	play_sound(pitch_place_hold)
	update_wall_bounds()
	return true

func count_holds_of_type(type_name: String) -> int:
	var count = 0
	for hold in holds_container.get_children():
		if get_hold_type(hold) == type_name:
			count += 1
	return count

func is_position_too_close(pos: Vector2, exclude_hold: Node2D) -> bool:
	for hold in holds_container.get_children():
		if hold == exclude_hold:
			continue
		if hold.global_position.distance_to(pos) < MIN_HOLD_DISTANCE:
			return true
	return false

func is_position_reachable(pos: Vector2, exclude_hold: Node2D) -> bool:
	if selected_hold_type == "START" or selected_hold_type == "FOOT":
		return true
	# WINDOW and LEDGE are wide holds — treat them like jugs for placement rules
	if selected_hold_type == "WINDOW" or selected_hold_type == "LEDGE":
		pass  # fall through to normal reachability check
	var non_start_count = 0
	for hold in holds_container.get_children():
		if hold != exclude_hold and get_hold_type(hold) != "START":
			non_start_count += 1
	if non_start_count == 0:
		return true
	var nearest_dist = INF
	for hold in holds_container.get_children():
		if hold == exclude_hold or get_hold_type(hold) == "START":
			continue
		nearest_dist = min(nearest_dist, hold.global_position.distance_to(pos))
	return nearest_dist <= MAX_REACH_DISTANCE

func delete_hold(hold: Node2D):
	save_undo_state()
	if hold == dragging_hold:
		dragging_hold = null
	hold.queue_free()
	play_sound(pitch_delete_hold)
	update_wall_bounds()

func get_hold_at_position(pos: Vector2, max_dist: float = 40.0) -> Node2D:
	var closest: Node2D = null
	var closest_dist    = max_dist
	for hold in holds_container.get_children():
		var dist = hold.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest      = hold
	return closest

func snap_to_grid(pos: Vector2) -> Vector2:
	if not grid_enabled:
		return pos
	return Vector2(round(pos.x / grid_size) * grid_size,
				   round(pos.y / grid_size) * grid_size)


func update_camera(delta):
	if is_testing:
		return
	var move = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if move.length() > 0:
		camera.position += move.normalized() * PAN_SPEED * delta / camera.zoom.x


func update_preview():
	if placing_crashpad and crashpad_scene:
		if not preview_crashpad or not is_instance_valid(preview_crashpad):
			clear_preview()
			preview_crashpad = crashpad_scene.instantiate()
			preview_crashpad.modulate = Color(1, 1, 1, 0.5)
			preview_crashpad.z_index  = 100
			preview_container.add_child(preview_crashpad)
		if is_mouse_over_ui():
			preview_crashpad.visible = false
		else:
			preview_crashpad.visible = true
			var sp = snap_to_grid(get_global_mouse_position())
			sp.x = clamp(sp.x, CANVAS_MIN_X, CANVAS_MAX_X)
			sp.y = clamp(sp.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
			preview_crashpad.global_position = sp
		return

	if not selected_hold_type or selected_hold_type not in loaded_scenes:
		clear_preview()
		return
	if is_mouse_over_ui():
		clear_preview()
		return

	if not preview_hold or not is_instance_valid(preview_hold):
		clear_preview()
		preview_hold = loaded_scenes[selected_hold_type].instantiate()
		preview_hold.modulate = Color(1, 1, 1, 0.5)
		preview_hold.z_index  = 100
		preview_container.add_child(preview_hold)

	var snapped_pos = snap_to_grid(get_global_mouse_position())
	snapped_pos.x = clamp(snapped_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
	snapped_pos.y = clamp(snapped_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)

	var too_close   = is_position_too_close(snapped_pos, null)
	var unreachable = not is_position_reachable(snapped_pos, null)
	preview_hold.modulate = Color(1, 0.3, 0.3, 0.5) if (too_close or unreachable) \
							else Color(1, 1, 1, 0.5)
	preview_hold.global_position = snapped_pos

func clear_preview():
	if preview_hold and is_instance_valid(preview_hold):
		preview_hold.queue_free()
	preview_hold = null
	if preview_crashpad and is_instance_valid(preview_crashpad):
		preview_crashpad.queue_free()
	preview_crashpad = null


func _on_climb_name_changed(new_text: String):
	climb_name = new_text

func _on_grade_changed(index: int):
	if current_discipline == "bouldering":
		if index >= 0 and index < V_GRADES.size():
			climb_grade = V_GRADES[index]
	else:
		if index >= 0 and index < YDS_GRADES.size():
			climb_grade = YDS_GRADES[index]

func on_environment_changed(index: int):
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if not env_config:
		return
	var env_types = env_config.get_all_environment_types()
	if index < env_types.size():
		env_config.set_environment(env_types[index])
	update_wall_bounds()
	for hold in holds_container.get_children():
		if hold.has_method("_update_sprite_for_environment"):
			hold._update_sprite_for_environment()
	for crashpad in crashpads_container.get_children():
		if crashpad.has_method("_update_sprite_for_environment"):
			crashpad._update_sprite_for_environment()


func _on_preview():
	if holds_container.get_child_count() == 0:
		show_notification("No holds to test!", true)
		play_sound(pitch_error)
		return

	var start_holds = []
	for hold in holds_container.get_children():
		var t = get_hold_type(hold)
		if t == "START": start_holds.append(hold)

	if start_holds.size() == 0:
		show_notification("Need at least one START hold!", true)
		play_sound(pitch_error)
		return

	var player_scene_path = "res://scenes/player/character.tscn"
	if not ResourceLoader.exists(player_scene_path):
		show_notification("Player scene not found!", true)
		play_sound(pitch_error)
		return

	var old_preview = get_node_or_null("PreviewPlayer")
	if old_preview:
		old_preview.queue_free()

	var player = load(player_scene_path).instantiate()
	player.name = "PreviewPlayer"
	add_child(player)
	_disable_player_cameras.call_deferred(player)

	preview_player_ref = player
	is_testing         = true
	_speed_fail_pending = false

	var spawn_pos = Vector2.ZERO
	if start_holds.size() == 1:
		var hp = start_holds[0].get_node_or_null("HoldPoint")
		spawn_pos = (hp.global_position if hp else start_holds[0].global_position) + Vector2(0, 80)
	else:
		var sum = Vector2.ZERO
		for hold in start_holds:
			var hp = hold.get_node_or_null("HoldPoint")
			sum += hp.global_position if hp else hold.global_position
		spawn_pos = sum / start_holds.size() + Vector2(0, 80)

	player.global_position = spawn_pos
	camera.position        = spawn_pos
	camera.zoom            = Vector2(1.0, 1.0)
	camera.make_current()

	if current_discipline == "speed":
		_setup_speed_timer_for_test()

	play_sound(pitch_preview)
	show_notification("Testing route — Press ESC to exit")

func _setup_speed_timer_for_test() -> void:
	var old_timer = get_node_or_null("TestSpeedTimer")
	if old_timer:
		old_timer.queue_free()

	var SpeedTimerScript = load("res://scripts/ui/speed_timer.gd")
	if not SpeedTimerScript:
		push_error("LevelEditor: Could not load speed_timer.gd — path may differ")
		return

	_speed_timer_node = SpeedTimerScript.new()
	_speed_timer_node.name = "TestSpeedTimer"
	add_child(_speed_timer_node)

	_speed_timer_node.set_time_limit(speed_time_limit)
	_speed_timer_node.show_timer()
	_speed_timer_node.start_timer()

	_speed_timer_node.time_expired.connect(_on_test_speed_time_expired)

func _on_test_speed_time_expired() -> void:
	if not is_testing or _speed_fail_pending:
		return
	_speed_fail_pending = true
	show_notification("TIME'S UP — resetting…", true)
	play_sound(pitch_error)

	var player = get_node_or_null("PreviewPlayer")
	if is_instance_valid(player):
		if player.has_method("release_all_holds"):
			player.release_all_holds()
		elif player.has_method("fall"):
			player.fall()
		else:
			if "can_grab" in player:
				player.can_grab = false

	await get_tree().create_timer(1.2).timeout

	if not is_testing:
		return

	_reset_speed_test()

func _reset_speed_test() -> void:
	_speed_fail_pending = false

	var start_holds = []
	for hold in holds_container.get_children():
		if get_hold_type(hold) == "START":
			start_holds.append(hold)

	var spawn_pos = Vector2.ZERO
	if start_holds.size() == 1:
		var hp = start_holds[0].get_node_or_null("HoldPoint")
		spawn_pos = (hp.global_position if hp else start_holds[0].global_position) + Vector2(0, 80)
	elif start_holds.size() > 1:
		var sum = Vector2.ZERO
		for hold in start_holds:
			var hp = hold.get_node_or_null("HoldPoint")
			sum += hp.global_position if hp else hold.global_position
		spawn_pos = sum / start_holds.size() + Vector2(0, 80)

	var player = get_node_or_null("PreviewPlayer")
	if is_instance_valid(player):
		player.global_position = spawn_pos
		if "can_grab" in player:
			player.can_grab = true
		if "velocity" in player:
			player.velocity = Vector2.ZERO

	camera.position = spawn_pos

	if is_instance_valid(_speed_timer_node):
		_speed_timer_node.stop_timer()
		_speed_timer_node.start_timer()

	show_notification("Restarting speed attempt…")

func _disable_player_cameras(player: Node) -> void:
	for cam in player.find_children("*", "Camera2D", true, false):
		cam.enabled = false
		cam.make_current()
	camera.make_current()

func _stop_testing() -> void:
	is_testing          = false
	_speed_fail_pending = false
	preview_player_ref  = null

	if is_instance_valid(_speed_timer_node):
		_speed_timer_node.queue_free()
	_speed_timer_node = null

	var preview_player = get_node_or_null("PreviewPlayer")
	if preview_player:
		preview_player.queue_free()
	camera.make_current()


func _on_clear():
	for hold     in holds_container.get_children():    hold.queue_free()
	for crashpad in crashpads_container.get_children(): crashpad.queue_free()

	if wall and wall.has_method("reset_polygon"):
		wall.reset_polygon()

	current_discipline = "bouldering"
	speed_time_limit   = 60.0
	_clear_belayer_marker()
	placing_belayer    = false

	if discipline_dropdown:
		discipline_dropdown.select(0)
		_on_discipline_changed(0)

	climb_name  = ""
	climb_grade = "VB"
	if climb_name_input:
		climb_name_input.text = ""

	populate_grade_dropdown()

	current_weather           = 0
	current_weather_intensity = 1.0
	if weather_dropdown:
		weather_dropdown.select(0)
		_on_weather_changed(0)
	if weather_intensity_slider:
		weather_intensity_slider.value = 1.0

	update_wall_bounds()
	play_sound(pitch_clear)
	undo_stack.clear()
	show_notification("Editor cleared")

func _on_back_pressed():
	_stop_testing()
	selected_hold_type = ""
	placing_crashpad   = false
	placing_belayer    = false
	clear_preview()
	Transition.to("res://scenes/menus/main_menu.tscn")

func toggle_grid(button: Button):
	grid_enabled = not grid_enabled
	button.text  = "Grid: ON" if grid_enabled else "Grid: OFF"
	queue_redraw()

func _on_toggle_wall_edit():
	if not wall:
		show_notification("No wall found!", true)
		play_sound(pitch_error)
		return
	if not wall.has_method("enable_edit_mode"):
		show_notification("Wall doesn't support editing", true)
		play_sound(pitch_error)
		return
	var is_editing = wall.edit_mode if "edit_mode" in wall else false
	if not is_editing:
		save_undo_state()
		selected_hold_type = ""
		placing_crashpad   = false
		placing_belayer    = false
		clear_preview()
	wall.enable_edit_mode(not is_editing)
	if not is_editing:
		show_notification("Wall edit ON — hold dragging suspended. Click line to add point, drag to move, right-click to delete")
	else:
		save_undo_state()
		show_notification("Wall edit mode OFF — hold placement/dragging re-enabled")


func save_undo_state():
	var state = {
		"holds":             [],
		"crashpads":         [],
		"belayer_position":  belayer_position,
		"wall_polygon":      null,
		"weather":           current_weather,
		"weather_intensity": current_weather_intensity,
	}
	for hold in holds_container.get_children():
		state.holds.append({
			"type": get_hold_type(hold),
			"x":    hold.global_position.x,
			"y":    hold.global_position.y
		})
	for crashpad in crashpads_container.get_children():
		state.crashpads.append({
			"x": crashpad.global_position.x,
			"y": crashpad.global_position.y
		})
	if wall and wall.has_method("get_polygon_data"):
		state.wall_polygon = wall.get_polygon_data()
	undo_stack.append(state)
	if undo_stack.size() > MAX_UNDO_STACK:
		undo_stack.pop_front()

func undo_last_action():
	if undo_stack.is_empty():
		show_notification("Nothing to undo")
		return
	var state = undo_stack.pop_back()

	for hold     in holds_container.get_children():    hold.queue_free()
	for crashpad in crashpads_container.get_children(): crashpad.queue_free()

	for hold_data in state.holds:
		var type_name = hold_data.type
		if type_name not in loaded_scenes:
			continue
		var hold = loaded_scenes[type_name].instantiate()
		if hold.has_method("set_hold_type_from_string"):
			hold.set_hold_type_from_string(type_name)
		hold.global_position = Vector2(hold_data.x, hold_data.y)
		holds_container.add_child(hold)
		hold.add_to_group("holds")
		hold.set_meta("editor_type", type_name)

	if crashpad_scene:
		for cpd in state.crashpads:
			var cp = crashpad_scene.instantiate()
			cp.global_position = Vector2(cpd.x, cpd.y)
			crashpads_container.add_child(cp)
			cp.add_to_group("crashpads")

	if state.belayer_position != Vector2.ZERO:
		_create_belayer_marker(state.belayer_position)
	else:
		_clear_belayer_marker()

	if state.wall_polygon and wall and wall.has_method("set_polygon_data"):
		wall.set_polygon_data(state.wall_polygon)

	if "weather" in state:
		current_weather           = state.weather
		current_weather_intensity = state.get("weather_intensity", 1.0)
		if weather_dropdown:
			weather_dropdown.select(clamp(current_weather, 0,
										 weather_dropdown.get_item_count() - 1))
			_on_weather_changed(current_weather)
		if weather_intensity_slider:
			weather_intensity_slider.value = current_weather_intensity

	update_wall_bounds()
	play_sound(pitch_success)
	show_notification("Undo successful")


func show_notification(text: String, is_error: bool = false):
	var old_notif = ui_layer.get_node_or_null("NotificationLabel")
	if old_notif:
		old_notif.queue_free()

	var ui_bottom = BAR_HEIGHT + 2 + (DRAWER_HEIGHT if not ui_panel_collapsed else 0.0) + 6.0

	var notif_bar = ColorRect.new()
	notif_bar.name     = "NotificationLabel"
	notif_bar.size     = Vector2(380, 36)
	notif_bar.position = Vector2(get_viewport_rect().size.x / 2.0 - 190.0, ui_bottom)
	notif_bar.color    = Color(0.65, 0.18, 0.18, 0.93) if is_error \
						 else Color(0.15, 0.55, 0.28, 0.93)

	var lbl = Label.new()
	lbl.text = text
	lbl.size = notif_bar.size
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	notif_bar.add_child(lbl)
	ui_layer.add_child(notif_bar)

	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(notif_bar):
		notif_bar.queue_free()

func update_info_label():
	var selected = "None"
	if placing_belayer:      selected = "Rope Anchor"
	elif placing_crashpad:   selected = "Crashpad"
	elif selected_hold_type: selected = selected_hold_type

	var disc_name = {"bouldering":"Boulder","roped":"Roped","speed":"Speed"} \
					.get(current_discipline, current_discipline)
	var parts = [
		"%s  %s" % [disc_name, climb_grade],
		"Holds: %d" % holds_container.get_child_count(),
		"S:%d/%d  T:%d/%d" % [count_holds_of_type("START"), MAX_START_HOLDS,
							   count_holds_of_type("TOP"),   MAX_TOP_HOLDS],
	]
	if current_discipline == "bouldering":
		parts.append("Pads: %d" % crashpads_container.get_child_count())
	elif current_discipline == "speed":
		parts.append("%ds" % int(speed_time_limit))
	elif current_discipline == "roped" and belayer_position != Vector2.ZERO:
		parts.append("Anchor ✓")
	if current_weather > 0:
		var wname = WEATHER_NAMES[current_weather] \
					if current_weather < WEATHER_NAMES.size() else "?"
		parts.append("%s %d%%" % [wname, int(current_weather_intensity * 100.0)])
	parts.append("Placing: %s" % selected)
	info_label.text = "  ·  ".join(parts)


func get_route_bounds() -> Dictionary:
	if holds_container.get_child_count() == 0:
		return { "min": Vector2.ZERO, "max": Vector2.ZERO, "valid": false }
	var min_x = INF;  var max_x = -INF
	var min_y = INF;  var max_y = -INF
	for hold in holds_container.get_children():
		var pos = hold.global_position
		min_x = min(min_x, pos.x);  max_x = max(max_x, pos.x)
		min_y = min(min_y, pos.y);  max_y = max(max_y, pos.y)
	var wall_min = Vector2(min_x - WALL_PADDING_SIDES, min_y - WALL_PADDING_TOP)
	var wall_max = Vector2(max_x + WALL_PADDING_SIDES, max_y + WALL_PADDING_BOTTOM)
	return {
		"min":    wall_min,
		"max":    wall_max,
		"center": (wall_min + wall_max) / 2.0,
		"size":   wall_max - wall_min,
		"valid":  true
	}


func _draw():
	var is_night = (current_weather < WEATHER_NAMES.size() and WEATHER_NAMES[current_weather] == "Night")
	var grid_color   = Color(0.55, 0.55, 0.65, 0.45) if is_night else Color(0.3, 0.3, 0.3, 0.2)
	var border_color = Color(0.55, 0.75, 1.0, 0.70)  if is_night else Color(0.15, 0.15, 0.2, 0.3)

	draw_rect(
		Rect2(CANVAS_MIN_X, CANVAS_MIN_Y,
			  CANVAS_MAX_X - CANVAS_MIN_X, CANVAS_MAX_Y - CANVAS_MIN_Y),
		border_color, false, 2.0)

	var bounds = get_route_bounds()
	if bounds.valid:
		var fill_alpha = 0.40 if is_night else 0.25
		draw_rect(Rect2(bounds.min, bounds.size), Color(0.3, 0.5, 0.8, fill_alpha), true)
		draw_rect(Rect2(bounds.min, bounds.size), Color(0.4, 0.7, 1.0, 0.80 if is_night else 0.60), false, 3.0)

	if belayer_position != Vector2.ZERO:
		draw_circle(belayer_position, 15, Color(1, 0.5, 0, 0.3))
		draw_arc(belayer_position, 20, 0, TAU, 32, Color.ORANGE, 2.0)

	if not grid_enabled:
		return

	var viewport_rect = get_viewport_rect()
	var cam_pos       = camera.position
	var cam_zoom      = camera.zoom.x
	var half_size     = viewport_rect.size / (2.0 * cam_zoom)
	var view_min      = cam_pos - half_size
	var view_max      = cam_pos + half_size

	var draw_min_x = max(view_min.x, CANVAS_MIN_X)
	var draw_max_x = min(view_max.x, CANVAS_MAX_X)
	var draw_min_y = max(view_min.y, CANVAS_MIN_Y)
	var draw_max_y = min(view_max.y, CANVAS_MAX_Y)

	var start_x = max(floor(draw_min_x / grid_size) * grid_size, CANVAS_MIN_X)
	var end_x   = min(ceil( draw_max_x / grid_size) * grid_size, CANVAS_MAX_X)
	var start_y = max(floor(draw_min_y / grid_size) * grid_size, CANVAS_MIN_Y)
	var end_y   = min(ceil( draw_max_y / grid_size) * grid_size, CANVAS_MAX_Y)

	var x = start_x
	while x <= end_x:
		draw_line(Vector2(x, draw_min_y), Vector2(x, draw_max_y), grid_color, 1.0)
		x += grid_size

	var y = start_y
	while y <= end_y:
		draw_line(Vector2(draw_min_x, y), Vector2(draw_max_x, y), grid_color, 1.0)
		y += grid_size
