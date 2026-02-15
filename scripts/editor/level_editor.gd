extends Node2D
## Improved Level Editor - User-Friendly Design

var camera: Camera2D
var holds_container: Node2D
var preview_container: Node2D
var crashpads_container: Node2D
var wall: Node2D

# UI
var ui_layer: CanvasLayer
var info_label: Label
var hold_type_dropdown: OptionButton
var environment_dropdown: OptionButton
var climb_name_input: LineEdit
var grade_dropdown: OptionButton

# Discipline UI
var discipline_dropdown: OptionButton
var discipline_settings_panel: VBoxContainer
var speed_time_input: SpinBox
var belayer_placement_button: Button
var placing_belayer: bool = false
var belayer_marker: Node2D = null

# Crashpad UI (bouldering only)
var crashpad_button: Button

# State
var selected_hold_type: String = ""
var preview_hold: Node2D = null
var dragging_hold: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO

# Crashpad state
var placing_crashpad: bool = false
var preview_crashpad: Node2D = null
var dragging_crashpad: Node2D = null

# Climb metadata
var climb_name: String = ""
var climb_grade: String = "VB"

# Discipline state
var current_discipline: String = "bouldering"
var speed_time_limit: float = 60.0
var belayer_position: Vector2 = Vector2.ZERO

# Grid
var grid_enabled: bool = true
var grid_size: float = 32.0

# Auto-reset timer
var idle_timer: float = 0.0
const IDLE_RESET_TIME: float = 300.0  # 5 minutes instead of 50 minutes

# Hold limits
const MAX_START_HOLDS: int = 2
const MAX_TOP_HOLDS: int = 1
const MIN_HOLD_DISTANCE: float = 40.0
const MAX_REACH_DISTANCE: float = 250.0

# Difficulty grades
const V_GRADES = ["VB", "V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10", "V11", "V12"]
const YDS_GRADES = ["5.5", "5.6", "5.7", "5.8", "5.9", "5.10a", "5.10b", "5.10c", "5.10d", 
					"5.11a", "5.11b", "5.11c", "5.11d", "5.12a", "5.12b", "5.12c", "5.12d", "5.13a", "5.13b"]

# Hold types
const HOLD_TYPES = ["START", "TOP", "JUG", "CRIMP", "SLOPER", "POCKET", "FOOT"]

# Hold scenes
const HOLD_SCENES = {
	"START": "res://scenes/holds/start.tscn",
	"TOP": "res://scenes/holds/top_out.tscn",
	"JUG": "res://scenes/holds/jug.tscn",
	"CRIMP": "res://scenes/holds/crimp.tscn",
	"SLOPER": "res://scenes/holds/sloper.tscn",
	"POCKET": "res://scenes/holds/pocket.tscn",
	"FOOT": "res://scenes/holds/foothold.tscn"
}

const CRASHPAD_SCENE = "res://scenes/props/crashpad.tscn"

var loaded_scenes: Dictionary = {}
var crashpad_scene: PackedScene = null

# Camera settings
const ZOOM_SPEED = 0.15
const TRACKPAD_ZOOM_SPEED = 0.2
const PAN_SPEED = 1000.0
const MIN_ZOOM = 0.2
const MAX_ZOOM = 3.0

# Canvas boundaries
const CANVAS_MIN_X = -1500.0
const CANVAS_MAX_X = 2500.0
const CANVAS_MIN_Y = -3000.0
const CANVAS_MAX_Y = 2000.0

# Wall padding
const WALL_PADDING_SIDES = 100.0
const WALL_PADDING_TOP = 100.0
const WALL_PADDING_BOTTOM = 150.0

# Audio settings
@export_group("Audio Settings")
@export var enable_editor_sounds: bool = true
@export var master_volume_db: float = -6.0

@export_subgroup("Action Pitches")
@export var pitch_place_hold: float = 1.2
@export var pitch_delete_hold: float = 0.7
@export var pitch_place_crashpad: float = 1.15
@export var pitch_copy_json: float = 1.3
@export var pitch_paste_json: float = 1.25
@export var pitch_clear: float = 0.6
@export var pitch_error: float = 0.5
@export var pitch_success: float = 1.4
@export var pitch_preview: float = 1.2

@export_subgroup("Pitch Randomization")
@export var randomize_pitch: bool = true
@export var pitch_variation: float = 0.05

# Audio player
const CLICK_SOUND = preload("res://assets/audio/sfx/button-clicked.wav")
var _audio_player: AudioStreamPlayer

func _ready():
	_setup_audio()
	
	wall = get_node_or_null("Wall")
	
	if wall and wall.has_method("set_editor_mode"):
		wall.set_editor_mode(true)
		print("LevelEditor: Enabled editor mode on wall")
	
	if has_node("Camera2D"):
		camera = get_node("Camera2D")
	else:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = Vector2(0.5, 0.5)
		camera.position = Vector2(500, 0)
		add_child(camera)
	
	if has_node("Holds"):
		holds_container = get_node("Holds")
	else:
		holds_container = Node2D.new()
		holds_container.name = "Holds"
		add_child(holds_container)
	
	if has_node("Crashpads"):
		crashpads_container = get_node("Crashpads")
	else:
		crashpads_container = Node2D.new()
		crashpads_container.name = "Crashpads"
		add_child(crashpads_container)
	
	if has_node("PreviewContainer"):
		preview_container = get_node("PreviewContainer")
	else:
		preview_container = Node2D.new()
		preview_container.name = "PreviewContainer"
		preview_container.z_index = 100
		add_child(preview_container)
	
	# Load hold scenes
	for type_name in HOLD_SCENES:
		if ResourceLoader.exists(HOLD_SCENES[type_name]):
			loaded_scenes[type_name] = load(HOLD_SCENES[type_name])
	
	# Load crashpad scene
	if ResourceLoader.exists(CRASHPAD_SCENE):
		crashpad_scene = load(CRASHPAD_SCENE)
	
	setup_ui()
	update_wall_bounds()

func _process(delta):
	update_camera(delta)
	update_preview()
	update_info_label()
	update_idle_timer(delta)
	queue_redraw()

# =============================================================================
# AUDIO SYSTEM
# =============================================================================

func _setup_audio():
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "EditorAudioPlayer"
	_audio_player.stream = CLICK_SOUND
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

# =============================================================================
# UI SETUP
# =============================================================================

func setup_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	
	# Simple flat background bar at top
	var top_bar = ColorRect.new()
	top_bar.color = Color(0.12, 0.12, 0.14, 0.92)
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_top = 0.0
	top_bar.offset_bottom = 120
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(top_bar)
	
	# Main horizontal container for all controls
	var main_hbox = HBoxContainer.new()
	main_hbox.position = Vector2(20, 20)
	main_hbox.add_theme_constant_override("separation", 15)
	ui_layer.add_child(main_hbox)
	
	# === LEFT SECTION: ROUTE INFO ===
	var info_section = VBoxContainer.new()
	info_section.add_theme_constant_override("separation", 6)
	main_hbox.add_child(info_section)
	
	var title = Label.new()
	title.text = "ROUTE EDITOR"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	info_section.add_child(title)
	
	var info_grid = GridContainer.new()
	info_grid.columns = 2
	info_grid.add_theme_constant_override("h_separation", 8)
	info_grid.add_theme_constant_override("v_separation", 6)
	info_section.add_child(info_grid)
	
	# Name
	var name_label = create_simple_label("Name:")
	info_grid.add_child(name_label)
	climb_name_input = LineEdit.new()
	climb_name_input.placeholder_text = "Unnamed Route"
	climb_name_input.custom_minimum_size = Vector2(150, 28)
	climb_name_input.text_changed.connect(_on_climb_name_changed)
	info_grid.add_child(climb_name_input)
	
	# Discipline
	var disc_label = create_simple_label("Discipline:")
	info_grid.add_child(disc_label)
	discipline_dropdown = OptionButton.new()
	discipline_dropdown.custom_minimum_size = Vector2(150, 28)
	discipline_dropdown.add_item("Bouldering")
	discipline_dropdown.add_item("Roped")
	discipline_dropdown.add_item("Speed")
	discipline_dropdown.select(0)
	discipline_dropdown.item_selected.connect(_on_discipline_changed)
	info_grid.add_child(discipline_dropdown)
	
	# Grade
	var grade_label = create_simple_label("Grade:")
	info_grid.add_child(grade_label)
	grade_dropdown = OptionButton.new()
	grade_dropdown.custom_minimum_size = Vector2(150, 28)
	populate_grade_dropdown()
	grade_dropdown.item_selected.connect(_on_grade_changed)
	info_grid.add_child(grade_dropdown)
	
	# Environment
	var env_label = create_simple_label("Environment:")
	info_grid.add_child(env_label)
	environment_dropdown = OptionButton.new()
	environment_dropdown.custom_minimum_size = Vector2(150, 28)
	
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if env_config:
		environment_dropdown.add_item("Gym")
		environment_dropdown.add_item("Granite")
		var current_env = env_config.get_current_environment()
		environment_dropdown.select(current_env)
	else:
		environment_dropdown.add_item("Gym")
		environment_dropdown.add_item("Granite")
		environment_dropdown.select(0)
	
	environment_dropdown.item_selected.connect(on_environment_changed)
	info_grid.add_child(environment_dropdown)
	
	# Discipline settings (speed/roped)
	discipline_settings_panel = VBoxContainer.new()
	discipline_settings_panel.visible = false
	discipline_settings_panel.add_theme_constant_override("separation", 6)
	info_section.add_child(discipline_settings_panel)
	
	var speed_hbox = HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", 6)
	var speed_label = create_simple_label("Time Limit:")
	speed_hbox.add_child(speed_label)
	speed_time_input = SpinBox.new()
	speed_time_input.min_value = 10.0
	speed_time_input.max_value = 300.0
	speed_time_input.step = 5.0
	speed_time_input.value = 60.0
	speed_time_input.suffix = "s"
	speed_time_input.custom_minimum_size = Vector2(100, 28)
	speed_time_input.value_changed.connect(_on_speed_time_changed)
	speed_hbox.add_child(speed_time_input)
	discipline_settings_panel.add_child(speed_hbox)
	
	belayer_placement_button = create_flat_button("Place Rope Anchor", Vector2(150, 28))
	belayer_placement_button.pressed.connect(_on_place_belayer_pressed)
	discipline_settings_panel.add_child(belayer_placement_button)
	
	add_vertical_separator(main_hbox)
	
	# === MIDDLE SECTION: HOLDS ===
	var holds_section = VBoxContainer.new()
	holds_section.add_theme_constant_override("separation", 6)
	main_hbox.add_child(holds_section)
	
	var holds_label = create_simple_label("PLACE HOLDS")
	holds_label.add_theme_font_size_override("font_size", 12)
	holds_section.add_child(holds_label)
	
	hold_type_dropdown = OptionButton.new()
	hold_type_dropdown.custom_minimum_size = Vector2(150, 28)
	
	if has_node("/root/HoldRegistry"):
		var registry = get_node("/root/HoldRegistry")
		var hold_types = registry.get_all_hold_types()
		for type_name in hold_types:
			var display_name = registry.get_hold_display_name(type_name)
			hold_type_dropdown.add_item(display_name)
			hold_type_dropdown.set_item_metadata(
				hold_type_dropdown.get_item_count() - 1,
				type_name
			)
	else:
		for type_name in HOLD_TYPES:
			hold_type_dropdown.add_item(type_name)
	
	hold_type_dropdown.item_selected.connect(_on_hold_type_selected)
	holds_section.add_child(hold_type_dropdown)
	
	crashpad_button = create_flat_button("Place Crashpad", Vector2(150, 28))
	crashpad_button.pressed.connect(_on_place_crashpad_pressed)
	crashpad_button.visible = true
	holds_section.add_child(crashpad_button)
	
	add_vertical_separator(main_hbox)
	
	# === RIGHT SECTION: ACTIONS ===
	var actions_section = VBoxContainer.new()
	actions_section.add_theme_constant_override("separation", 6)
	main_hbox.add_child(actions_section)
	
	var actions_label = create_simple_label("ACTIONS")
	actions_label.add_theme_font_size_override("font_size", 12)
	actions_section.add_child(actions_label)
	
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 6)
	actions_section.add_child(actions_hbox)
	
	var copy_btn = create_flat_button("Copy", Vector2(70, 28))
	copy_btn.pressed.connect(_on_copy_json)
	actions_hbox.add_child(copy_btn)
	
	var paste_btn = create_flat_button("Paste", Vector2(70, 28))
	paste_btn.pressed.connect(_on_paste_json)
	actions_hbox.add_child(paste_btn)
	
	var actions_hbox2 = HBoxContainer.new()
	actions_hbox2.add_theme_constant_override("separation", 6)
	actions_section.add_child(actions_hbox2)
	
	var test_btn = create_flat_button("Test", Vector2(70, 28))
	test_btn.pressed.connect(_on_preview)
	actions_hbox2.add_child(test_btn)
	
	var clear_btn = create_flat_button("Clear", Vector2(70, 28))
	clear_btn.pressed.connect(_on_clear)
	actions_hbox2.add_child(clear_btn)
	
	add_vertical_separator(main_hbox)
	
	# Back button
	var back_btn = create_flat_button("Back", Vector2(80, 60))
	back_btn.pressed.connect(_on_back_pressed)
	main_hbox.add_child(back_btn)
	
	# Info label at bottom
	info_label = Label.new()
	info_label.position = Vector2(20, get_viewport_rect().size.y - 35)
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.85))
	info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	info_label.add_theme_constant_override("outline_size", 1)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(info_label)

func create_simple_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func add_vertical_separator(parent: HBoxContainer):
	var sep = ColorRect.new()
	sep.color = Color(0.3, 0.3, 0.35, 0.4)
	sep.custom_minimum_size = Vector2(2, 80)
	parent.add_child(sep)

func create_flat_button(button_text: String, min_size: Vector2) -> Button:
	var button = Button.new()
	button.text = button_text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	
	# Flat style
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.22, 0.26)
	normal_style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", normal_style)
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.27, 0.32)
	hover_style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.15, 0.17, 0.2)
	pressed_style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("pressed", pressed_style)
	
	return button

func populate_grade_dropdown():
	grade_dropdown.clear()
	
	if current_discipline == "bouldering":
		for grade in V_GRADES:
			grade_dropdown.add_item(grade)
	else:  # roped or speed
		for grade in YDS_GRADES:
			grade_dropdown.add_item(grade)
	
	grade_dropdown.select(0)

# =============================================================================
# DISCIPLINE CALLBACKS
# =============================================================================

func _on_discipline_changed(index: int):
	reset_idle_timer()
	
	match index:
		0:  # Bouldering
			current_discipline = "bouldering"
			climb_grade = "VB"
			discipline_settings_panel.visible = false
			crashpad_button.visible = true
			_clear_belayer_marker()
		1:  # Roped
			current_discipline = "roped"
			climb_grade = "5.5"
			discipline_settings_panel.visible = true
			speed_time_input.visible = false
			belayer_placement_button.visible = true
			crashpad_button.visible = false
			_clear_all_crashpads()
			show_notification("Click 'Place Rope Anchor' to set belay point")
		2:  # Speed
			current_discipline = "speed"
			climb_grade = "5.5"
			discipline_settings_panel.visible = true
			speed_time_input.visible = true
			belayer_placement_button.visible = false
			crashpad_button.visible = false
			_clear_all_crashpads()
			_clear_belayer_marker()
	
	populate_grade_dropdown()
	print("Discipline changed to: " + current_discipline)

func _on_speed_time_changed(value: float):
	speed_time_limit = value
	reset_idle_timer()

func _on_place_belayer_pressed():
	placing_belayer = true
	selected_hold_type = ""
	placing_crashpad = false
	clear_preview()
	show_notification("Click anywhere to place rope anchor point")

func _clear_belayer_marker():
	if belayer_marker and is_instance_valid(belayer_marker):
		belayer_marker.queue_free()
	belayer_marker = null
	belayer_position = Vector2.ZERO

func _clear_all_crashpads():
	for crashpad in crashpads_container.get_children():
		crashpad.queue_free()

func _create_belayer_marker(pos: Vector2):
	_clear_belayer_marker()
	
	belayer_marker = Node2D.new()
	belayer_marker.name = "BelayerMarker"
	belayer_marker.z_index = 100
	belayer_marker.global_position = pos
	belayer_position = pos
	
	# Create visual marker
	var marker_sprite = Sprite2D.new()
	var image = Image.create(32, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# Draw stick figure belayer
	for y in range(48):
		for x in range(32):
			# Head
			if Vector2(x - 16, y - 8).length() < 6:
				image.set_pixel(x, y, Color.ORANGE)
			# Body
			if x >= 14 and x <= 18 and y >= 14 and y <= 32:
				image.set_pixel(x, y, Color.ORANGE)
			# Arms
			if y >= 18 and y <= 22:
				if x >= 8 and x <= 24:
					image.set_pixel(x, y, Color.ORANGE)
			# Legs
			if y >= 32 and y <= 46:
				if (x >= 10 and x <= 13) or (x >= 19 and x <= 22):
					image.set_pixel(x, y, Color.ORANGE)
	
	var texture = ImageTexture.create_from_image(image)
	marker_sprite.texture = texture
	belayer_marker.add_child(marker_sprite)
	
	add_child(belayer_marker)
	show_notification("Rope anchor placed!")

func _on_hold_type_selected(index: int):
	if hold_type_dropdown.get_item_metadata(index) != null:
		selected_hold_type = hold_type_dropdown.get_item_metadata(index)
	else:
		selected_hold_type = hold_type_dropdown.get_item_text(index)
	
	placing_crashpad = false
	placing_belayer = false
	clear_preview()
	reset_idle_timer()

func _on_place_crashpad_pressed():
	if current_discipline != "bouldering":
		show_notification("Crashpads are only for bouldering!", true)
		play_sound(pitch_error)
		return
	
	placing_crashpad = true
	selected_hold_type = ""
	placing_belayer = false
	clear_preview()
	reset_idle_timer()

# =============================================================================
# INPUT HANDLING
# =============================================================================

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DELETE:
				if dragging_hold:
					delete_hold(dragging_hold)
				elif dragging_crashpad:
					delete_crashpad(dragging_crashpad)
			
			KEY_ESCAPE:
				selected_hold_type = ""
				placing_crashpad = false
				placing_belayer = false
				clear_preview()
				dragging_hold = null
				dragging_crashpad = null
				var preview_player = get_node_or_null("PreviewPlayer")
				if preview_player:
					preview_player.queue_free()
	
	if is_mouse_over_ui():
		return
	
	if event is InputEventMouseButton:
		reset_idle_timer()
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				handle_left_click()
			else:
				dragging_hold = null
				dragging_crashpad = null
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var pos = get_global_mouse_position()
			var hold = get_hold_at_position(pos)
			if hold:
				delete_hold(hold)
			else:
				var crashpad = get_crashpad_at_position(pos)
				if crashpad:
					delete_crashpad(crashpad)
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom *= (1.0 + ZOOM_SPEED)
			camera.zoom = camera.zoom.clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom *= (1.0 - ZOOM_SPEED)
			camera.zoom = camera.zoom.clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
	
	elif event is InputEventMagnifyGesture:
		reset_idle_timer()
		var zoom_change = (event.factor - 1.0) * TRACKPAD_ZOOM_SPEED
		camera.zoom *= (1.0 + zoom_change)
		camera.zoom = camera.zoom.clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
	
	elif event is InputEventPanGesture:
		reset_idle_timer()
		camera.position += event.delta * 50.0 / camera.zoom.x
	
	elif event is InputEventMouseMotion:
		if dragging_hold:
			reset_idle_timer()
			var new_pos = snap_to_grid(get_global_mouse_position() + drag_offset)
			new_pos.x = clamp(new_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
			new_pos.y = clamp(new_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
			dragging_hold.global_position = new_pos
			update_wall_bounds()
		
		elif dragging_crashpad:
			reset_idle_timer()
			var new_pos = snap_to_grid(get_global_mouse_position() + drag_offset)
			new_pos.x = clamp(new_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
			new_pos.y = clamp(new_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
			dragging_crashpad.global_position = new_pos

func handle_left_click():
	var pos = get_global_mouse_position()
	
	# Place belayer for roped climbing
	if placing_belayer:
		var snapped_pos = snap_to_grid(pos)
		_create_belayer_marker(snapped_pos)
		placing_belayer = false
		return
	
	if placing_crashpad and crashpad_scene:
		var snapped_pos = snap_to_grid(pos)
		place_crashpad(snapped_pos)
	elif selected_hold_type and selected_hold_type in loaded_scenes:
		var snapped_pos = snap_to_grid(pos)
		place_hold(snapped_pos)
	else:
		var hold = get_hold_at_position(pos)
		if hold:
			dragging_hold = hold
			drag_offset = hold.global_position - pos
		else:
			var crashpad = get_crashpad_at_position(pos)
			if crashpad:
				dragging_crashpad = crashpad
				drag_offset = crashpad.global_position - pos

# =============================================================================
# CRASHPAD MANAGEMENT
# =============================================================================

func place_crashpad(pos: Vector2) -> bool:
	if current_discipline != "bouldering":
		show_notification("Crashpads are only for bouldering!", true)
		play_sound(pitch_error)
		return false
	
	if not crashpad_scene:
		show_notification("Crashpad scene not found!", true)
		play_sound(pitch_error)
		return false
	
	pos.x = clamp(pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
	pos.y = clamp(pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
	
	var crashpad = crashpad_scene.instantiate()
	crashpad.global_position = pos
	crashpads_container.add_child(crashpad)
	crashpad.add_to_group("crashpads")
	
	play_sound(pitch_place_crashpad)
	return true

func delete_crashpad(crashpad: Node2D):
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
			closest = crashpad
	
	return closest

# =============================================================================
# JSON EXPORT/IMPORT
# =============================================================================

func _on_copy_json():
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	var environment_name = "gym"
	if env_config:
		environment_name = env_config.get_current_environment_name().to_lower()
	
	var level_data = {
		"name": climb_name if climb_name != "" else "Unnamed Route",
		"grade": climb_grade,
		"environment": environment_name,
		"discipline": current_discipline,
		"holds": [],
		"crashpads": []
	}
	
	# Add discipline-specific data
	if current_discipline == "speed":
		level_data["speed_time_limit"] = speed_time_limit
	elif current_discipline == "roped" and belayer_position != Vector2.ZERO:
		level_data["belayer_position"] = {
			"x": belayer_position.x,
			"y": belayer_position.y
		}
	
	# Save wall polygon data
	if wall and wall.has_method("get_polygon_data"):
		var polygon_data = wall.get_polygon_data()
		if polygon_data:
			level_data["wall_polygon"] = polygon_data
	
	for hold in holds_container.get_children():
		var hold_type_str = get_hold_type(hold)
		var hold_data = {
			"type": hold_type_str,
			"x": hold.global_position.x,
			"y": hold.global_position.y
		}
		level_data.holds.append(hold_data)
	
	# Only save crashpads for bouldering
	if current_discipline == "bouldering":
		for crashpad in crashpads_container.get_children():
			var crashpad_data = {
				"x": crashpad.global_position.x,
				"y": crashpad.global_position.y
			}
			level_data.crashpads.append(crashpad_data)
	
	var json_str = JSON.stringify(level_data, "\t")
	DisplayServer.clipboard_set(json_str)
	
	play_sound(pitch_copy_json)
	show_notification("Route copied to clipboard")

func _on_paste_json():
	var clipboard = DisplayServer.clipboard_get()
	
	if clipboard.is_empty():
		show_notification("Clipboard is empty!", true)
		play_sound(pitch_error)
		return
	
	var json = JSON.new()
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
	climb_grade = data.get("grade", "VB")
	
	if climb_name_input:
		climb_name_input.text = climb_name
	
	# Load discipline first to set up UI correctly
	current_discipline = data.get("discipline", "bouldering")
	speed_time_limit = data.get("speed_time_limit", 60.0)
	
	if discipline_dropdown:
		match current_discipline:
			"bouldering":
				discipline_dropdown.select(0)
			"roped":
				discipline_dropdown.select(1)
			"speed":
				discipline_dropdown.select(2)
		_on_discipline_changed(discipline_dropdown.selected)
	
	# Now populate grades based on discipline
	populate_grade_dropdown()
	
	# Set grade
	if grade_dropdown:
		if current_discipline == "bouldering":
			var grade_index = V_GRADES.find(climb_grade)
			if grade_index >= 0:
				grade_dropdown.select(grade_index)
		else:
			var grade_index = YDS_GRADES.find(climb_grade)
			if grade_index >= 0:
				grade_dropdown.select(grade_index)
	
	if speed_time_input:
		speed_time_input.value = speed_time_limit
	
	# Load belayer position for roped
	if "belayer_position" in data and data.belayer_position:
		var belayer_data = data.belayer_position
		var belayer_pos = Vector2(belayer_data.get("x", 0), belayer_data.get("y", 0))
		_create_belayer_marker(belayer_pos)
	
	# Load environment
	var environment_name = data.get("environment", "gym")
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if env_config:
		if environment_name == "granite":
			env_config.set_environment(1)
			environment_dropdown.select(1)
		else:
			env_config.set_environment(0)
			environment_dropdown.select(0)
		update_wall_bounds()
	
	# Load holds
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
	
	# Load crashpads (only for bouldering)
	if current_discipline == "bouldering" and "crashpads" in data and crashpad_scene:
		for crashpad_data in data.crashpads:
			var crashpad = crashpad_scene.instantiate()
			crashpad.global_position = Vector2(crashpad_data.get("x", 0), crashpad_data.get("y", 0))
			crashpads_container.add_child(crashpad)
			crashpad.add_to_group("crashpads")
	
	# Load wall polygon data
	if "wall_polygon" in data and wall and wall.has_method("set_polygon_data"):
		wall.set_polygon_data(data.wall_polygon)
	
	update_wall_bounds()
	play_sound(pitch_paste_json)
	show_notification("Route loaded: " + climb_name)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

func get_hold_type(hold: Node2D) -> String:
	if hold.has_meta("editor_type"):
		return hold.get_meta("editor_type")
	
	if "hold_type" in hold:
		var hold_type_value = hold.hold_type
		match hold_type_value:
			0: return "JUG"
			1: return "START"
			2: return "TOP"
			3: return "CRIMP"
			4: return "SLOPER"
			5: return "FOOT"
			6: return "POCKET"
	
	return "JUG"

func is_mouse_over_ui() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()
	# Check if mouse is over the top bar (first 120 pixels)
	if mouse_pos.y < 120:
		return true
	return false

func update_wall_bounds():
	if wall and wall.has_method("calculate_bounds_from_holds"):
		wall.calculate_bounds_from_holds(holds_container)
	queue_redraw()

func place_hold(pos: Vector2) -> bool:
	if not selected_hold_type or selected_hold_type not in loaded_scenes:
		return false
	
	pos.x = clamp(pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
	pos.y = clamp(pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
	
	if selected_hold_type == "START":
		var start_count = count_holds_of_type("START")
		if start_count >= MAX_START_HOLDS:
			show_notification("Maximum " + str(MAX_START_HOLDS) + " START holds allowed!", true)
			play_sound(pitch_error)
			return false
	
	if selected_hold_type == "TOP":
		var top_count = count_holds_of_type("TOP")
		if top_count >= MAX_TOP_HOLDS:
			show_notification("Maximum " + str(MAX_TOP_HOLDS) + " TOP hold allowed!", true)
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
		var dist = hold.global_position.distance_to(pos)
		nearest_dist = min(nearest_dist, dist)
	
	return nearest_dist <= MAX_REACH_DISTANCE

func delete_hold(hold: Node2D):
	if hold == dragging_hold:
		dragging_hold = null
	hold.queue_free()
	play_sound(pitch_delete_hold)
	update_wall_bounds()

func get_hold_at_position(pos: Vector2, max_dist: float = 40.0) -> Node2D:
	var closest: Node2D = null
	var closest_dist = max_dist
	
	for hold in holds_container.get_children():
		var dist = hold.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = hold
	
	return closest

func snap_to_grid(pos: Vector2) -> Vector2:
	if not grid_enabled:
		return pos
	return Vector2(
		round(pos.x / grid_size) * grid_size,
		round(pos.y / grid_size) * grid_size
	)

# =============================================================================
# CAMERA
# =============================================================================

func update_camera(delta):
	var move = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	
	if move.length() > 0:
		reset_idle_timer()
		camera.position += move.normalized() * PAN_SPEED * delta / camera.zoom.x

# =============================================================================
# PREVIEW
# =============================================================================

func update_preview():
	# Handle crashpad preview
	if placing_crashpad and crashpad_scene:
		if not preview_crashpad or not is_instance_valid(preview_crashpad):
			clear_preview()
			preview_crashpad = crashpad_scene.instantiate()
			preview_crashpad.modulate = Color(1, 1, 1, 0.5)
			preview_crashpad.z_index = 100
			preview_container.add_child(preview_crashpad)
		
		if is_mouse_over_ui():
			preview_crashpad.visible = false
		else:
			preview_crashpad.visible = true
			var mouse_pos = get_global_mouse_position()
			var snapped_pos = snap_to_grid(mouse_pos)
			snapped_pos.x = clamp(snapped_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
			snapped_pos.y = clamp(snapped_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
			preview_crashpad.global_position = snapped_pos
		
		return
	
	# Handle hold preview
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
		preview_hold.z_index = 100
		preview_container.add_child(preview_hold)
	
	var mouse_pos = get_global_mouse_position()
	var snapped_pos = snap_to_grid(mouse_pos)
	
	snapped_pos.x = clamp(snapped_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
	snapped_pos.y = clamp(snapped_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
	
	var too_close = is_position_too_close(snapped_pos, null)
	var unreachable = not is_position_reachable(snapped_pos, null)
	
	if too_close or unreachable:
		preview_hold.modulate = Color(1, 0.3, 0.3, 0.5)
	else:
		preview_hold.modulate = Color(1, 1, 1, 0.5)
	
	preview_hold.global_position = snapped_pos

func clear_preview():
	if preview_hold and is_instance_valid(preview_hold):
		preview_hold.queue_free()
	preview_hold = null
	
	if preview_crashpad and is_instance_valid(preview_crashpad):
		preview_crashpad.queue_free()
	preview_crashpad = null

# =============================================================================
# CALLBACKS
# =============================================================================

func _on_climb_name_changed(new_text: String):
	reset_idle_timer()
	climb_name = new_text

func _on_grade_changed(index: int):
	reset_idle_timer()
	
	if current_discipline == "bouldering":
		if index >= 0 and index < V_GRADES.size():
			climb_grade = V_GRADES[index]
	else:  # roped or speed
		if index >= 0 and index < YDS_GRADES.size():
			climb_grade = YDS_GRADES[index]

func on_environment_changed(index: int):
	reset_idle_timer()
	
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if not env_config:
		return
	
	env_config.set_environment(index)
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
	var top_holds = []
	
	for hold in holds_container.get_children():
		var hold_type_str = get_hold_type(hold)
		if hold_type_str == "START":
			start_holds.append(hold)
		if hold_type_str == "TOP":
			top_holds.append(hold)
	
	if start_holds.size() == 0:
		show_notification("Need at least one START hold!", true)
		play_sound(pitch_error)
		return
	
	if top_holds.size() == 0:
		show_notification("Need at least one TOP hold!", true)
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
	
	var player_scene = load(player_scene_path)
	var player = player_scene.instantiate()
	player.name = "PreviewPlayer"
	add_child(player)
	
	var spawn_pos = Vector2.ZERO
	if start_holds.size() == 1:
		var hold_point = start_holds[0].get_node_or_null("HoldPoint")
		if hold_point:
			spawn_pos = hold_point.global_position + Vector2(0, 80)
		else:
			spawn_pos = start_holds[0].global_position + Vector2(0, 80)
	else:
		var sum = Vector2.ZERO
		for hold in start_holds:
			var hold_point = hold.get_node_or_null("HoldPoint")
			if hold_point:
				sum += hold_point.global_position
			else:
				sum += hold.global_position
		spawn_pos = (sum / start_holds.size()) + Vector2(0, 80)
	
	player.global_position = spawn_pos
	camera.position = player.global_position
	
	play_sound(pitch_preview)
	show_notification("Testing route - Press ESC to exit")

func _on_clear():
	for hold in holds_container.get_children():
		hold.queue_free()
	
	for crashpad in crashpads_container.get_children():
		crashpad.queue_free()
	
	# Reset wall polygon
	if wall and wall.has_method("reset_polygon"):
		wall.reset_polygon()
	
	# Reset discipline
	current_discipline = "bouldering"
	speed_time_limit = 60.0
	_clear_belayer_marker()
	placing_belayer = false
	
	if discipline_dropdown:
		discipline_dropdown.select(0)
		_on_discipline_changed(0)
	
	climb_name = ""
	climb_grade = "VB"
	if climb_name_input:
		climb_name_input.text = ""
	
	populate_grade_dropdown()
	
	update_wall_bounds()
	play_sound(pitch_clear)
	idle_timer = 0.0
	
	show_notification("Editor cleared")

func _on_back_pressed():
	var preview_player = get_node_or_null("PreviewPlayer")
	if preview_player:
		preview_player.queue_free()
	
	selected_hold_type = ""
	placing_crashpad = false
	placing_belayer = false
	clear_preview()
	
	Transition.to("res://scenes/menus/main_menu.tscn")

# =============================================================================
# AUTO-RESET & INFO
# =============================================================================

func update_idle_timer(delta: float):
	if get_node_or_null("PreviewPlayer") != null:
		idle_timer = 0.0
		return
	
	idle_timer += delta
	
	if idle_timer >= IDLE_RESET_TIME:
		show_notification("Auto-clearing due to inactivity")
		await get_tree().create_timer(2.0).timeout
		_on_clear()
		idle_timer = 0.0

func reset_idle_timer():
	idle_timer = 0.0

func show_notification(text: String, is_error: bool = false):
	var old_notif = ui_layer.get_node_or_null("NotificationLabel")
	if old_notif:
		old_notif.queue_free()
	
	# Simple notification bar
	var notif_bar = ColorRect.new()
	notif_bar.name = "NotificationLabel"
	notif_bar.position = Vector2(get_viewport_rect().size.x / 2 - 200, 140)
	notif_bar.size = Vector2(400, 40)
	
	if is_error:
		notif_bar.color = Color(0.7, 0.2, 0.2, 0.9)
	else:
		notif_bar.color = Color(0.2, 0.6, 0.3, 0.9)
	
	var label = Label.new()
	label.text = text
	label.size = Vector2(400, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	notif_bar.add_child(label)
	
	ui_layer.add_child(notif_bar)
	
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(notif_bar):
		notif_bar.queue_free()

func update_info_label():
	var selected = ""
	if placing_belayer:
		selected = "Rope Anchor"
	elif placing_crashpad:
		selected = "Crashpad"
	elif selected_hold_type:
		selected = selected_hold_type
	else:
		selected = "None"
	
	var count = holds_container.get_child_count()
	var crashpad_count = crashpads_container.get_child_count()
	var start_count = count_holds_of_type("START")
	var top_count = count_holds_of_type("TOP")
	
	var discipline_name = ""
	match current_discipline:
		"bouldering":
			discipline_name = "Bouldering"
		"roped":
			discipline_name = "Roped"
		"speed":
			discipline_name = "Speed"
	
	var status_parts = []
	status_parts.append("%s (%s)" % [discipline_name, climb_grade])
	status_parts.append("Holds: %d" % count)
	status_parts.append("START: %d/%d" % [start_count, MAX_START_HOLDS])
	status_parts.append("TOP: %d/%d" % [top_count, MAX_TOP_HOLDS])
	
	if current_discipline == "bouldering":
		status_parts.append("Crashpads: %d" % crashpad_count)
	elif current_discipline == "speed":
		status_parts.append("Time: %ds" % int(speed_time_limit))
	elif current_discipline == "roped" and belayer_position != Vector2.ZERO:
		status_parts.append("Anchor: Set")
	
	status_parts.append("Placing: %s" % selected)
	
	info_label.text = " | ".join(status_parts)

func get_route_bounds() -> Dictionary:
	if holds_container.get_child_count() == 0:
		return {"min": Vector2.ZERO, "max": Vector2.ZERO, "valid": false}
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for hold in holds_container.get_children():
		var pos = hold.global_position
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x)
		min_y = min(min_y, pos.y)
		max_y = max(max_y, pos.y)
	
	var wall_min = Vector2(min_x - WALL_PADDING_SIDES, min_y - WALL_PADDING_TOP)
	var wall_max = Vector2(max_x + WALL_PADDING_SIDES, max_y + WALL_PADDING_BOTTOM)
	
	return {
		"min": wall_min,
		"max": wall_max,
		"center": (wall_min + wall_max) / 2.0,
		"size": wall_max - wall_min,
		"valid": true
	}

# =============================================================================
# DRAWING
# =============================================================================

func _draw():
	draw_rect(
		Rect2(CANVAS_MIN_X, CANVAS_MIN_Y, CANVAS_MAX_X - CANVAS_MIN_X, CANVAS_MAX_Y - CANVAS_MIN_Y), 
		Color(0.15, 0.15, 0.2, 0.3), 
		false, 
		2.0
	)
	
	var bounds = get_route_bounds()
	if bounds.valid:
		draw_rect(
			Rect2(bounds.min, bounds.size),
			Color(0.3, 0.5, 0.8, 0.25),
			true
		)
		
		draw_rect(
			Rect2(bounds.min, bounds.size),
			Color(0.4, 0.7, 1.0, 0.6),
			false,
			3.0
		)
	
	# Draw belayer position indicator
	if belayer_position != Vector2.ZERO:
		draw_circle(belayer_position, 15, Color(1, 0.5, 0, 0.3))
		draw_arc(belayer_position, 20, 0, TAU, 32, Color.ORANGE, 2.0)
	
	if not grid_enabled:
		return
	
	var viewport_rect = get_viewport_rect()
	var cam_pos = camera.position
	var cam_zoom = camera.zoom.x
	
	var half_size = viewport_rect.size / (2.0 * cam_zoom)
	var view_min = cam_pos - half_size
	var view_max = cam_pos + half_size
	
	var draw_min_x = max(view_min.x, CANVAS_MIN_X)
	var draw_max_x = min(view_max.x, CANVAS_MAX_X)
	var draw_min_y = max(view_min.y, CANVAS_MIN_Y)
	var draw_max_y = min(view_max.y, CANVAS_MAX_Y)
	
	var start_x = floor(draw_min_x / grid_size) * grid_size
	var end_x = ceil(draw_max_x / grid_size) * grid_size
	var start_y = floor(draw_min_y / grid_size) * grid_size
	var end_y = ceil(draw_max_y / grid_size) * grid_size
	
	start_x = max(start_x, CANVAS_MIN_X)
	end_x = min(end_x, CANVAS_MAX_X)
	start_y = max(start_y, CANVAS_MIN_Y)
	end_y = min(end_y, CANVAS_MAX_Y)
	
	var x = start_x
	while x <= end_x:
		draw_line(
			Vector2(x, draw_min_y),
			Vector2(x, draw_max_y),
			Color(0.3, 0.3, 0.3, 0.2),
			1.0
		)
		x += grid_size
	
	var y = start_y
	while y <= end_y:
		draw_line(
			Vector2(draw_min_x, y),
			Vector2(draw_max_x, y),
			Color(0.3, 0.3, 0.3, 0.2),
			1.0
		)
		y += grid_size
