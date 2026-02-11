extends Node2D
## Level Editor (Modifiers Removed)

var camera: Camera2D
var holds_container: Node2D
var preview_container: Node2D
var wall: Node2D

# UI
var ui_layer: CanvasLayer
var info_label: Label
var hold_type_dropdown: OptionButton
var environment_dropdown: OptionButton
var climb_name_input: LineEdit
var grade_dropdown: OptionButton

# State
var selected_hold_type: String = ""
var preview_hold: Node2D = null
var dragging_hold: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO

# Climb metadata
var climb_name: String = ""
var climb_grade: String = "VB"

# Grid
var grid_enabled: bool = true
var grid_size: float = 32.0

# Auto-reset timer
var idle_timer: float = 0.0
const IDLE_RESET_TIME: float = 30.0

# Hold limits
const MAX_START_HOLDS: int = 2
const MAX_TOP_HOLDS: int = 1
const MIN_HOLD_DISTANCE: float = 40.0
const MAX_REACH_DISTANCE: float = 250.0

# Difficulty grades
const V_GRADES = ["VB", "V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10"]
const YDS_GRADES = ["5.5", "5.6", "5.7", "5.8", "5.9", "5.10a", "5.10b", "5.10c", "5.10d", 
					"5.11a", "5.11b", "5.11c", "5.11d", "5.12a", "5.12b", "5.12c", "5.12d", "5.13"]

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

var loaded_scenes: Dictionary = {}

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

func _ready():
	wall = get_node_or_null("Wall")
	
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
	
	setup_ui()
	update_wall_bounds()

func _process(delta):
	update_camera(delta)
	update_preview()
	update_info_label()
	update_idle_timer(delta)
	queue_redraw()

# =============================================================================
# UI SETUP
# =============================================================================

func setup_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	
	var toolbar = PanelContainer.new()
	toolbar.position = Vector2(10, 10)
	toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(toolbar)
	
	var vbox_main = VBoxContainer.new()
	vbox_main.mouse_filter = Control.MOUSE_FILTER_STOP
	toolbar.add_child(vbox_main)
	
	# ROW 1: Climb Info
	var info_row = HBoxContainer.new()
	info_row.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox_main.add_child(info_row)
	
	var name_label = Label.new()
	name_label.text = "Climb Name:"
	info_row.add_child(name_label)
	
	climb_name_input = LineEdit.new()
	climb_name_input.placeholder_text = "Enter climb name..."
	climb_name_input.custom_minimum_size = Vector2(200, 30)
	climb_name_input.text_changed.connect(_on_climb_name_changed)
	info_row.add_child(climb_name_input)
	
	info_row.add_child(VSeparator.new())
	
	var grade_label = Label.new()
	grade_label.text = "Grade:"
	info_row.add_child(grade_label)
	
	grade_dropdown = OptionButton.new()
	grade_dropdown.custom_minimum_size = Vector2(80, 30)
	
	for grade in V_GRADES:
		grade_dropdown.add_item(grade)
	
	grade_dropdown.add_separator("YDS Scale")
	
	for grade in YDS_GRADES:
		grade_dropdown.add_item(grade)
	
	grade_dropdown.item_selected.connect(_on_grade_changed)
	info_row.add_child(grade_dropdown)
	
	info_row.add_child(VSeparator.new())
	
	var env_label = Label.new()
	env_label.text = "Environment:"
	info_row.add_child(env_label)
	
	environment_dropdown = OptionButton.new()
	environment_dropdown.custom_minimum_size = Vector2(100, 30)
	
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
	info_row.add_child(environment_dropdown)
	
	# ROW 2: Hold Type
	var hold_row = HBoxContainer.new()
	hold_row.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox_main.add_child(hold_row)
	
	var hold_label = Label.new()
	hold_label.text = "Hold Type:"
	hold_row.add_child(hold_label)
	
	hold_type_dropdown = OptionButton.new()
	hold_type_dropdown.custom_minimum_size = Vector2(120, 30)
	
	for type_name in HOLD_TYPES:
		hold_type_dropdown.add_item(type_name)
	
	hold_type_dropdown.item_selected.connect(_on_hold_type_selected)
	hold_row.add_child(hold_type_dropdown)
	
	# ROW 3: Actions
	var actions_row = HBoxContainer.new()
	actions_row.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox_main.add_child(actions_row)
	
	var copy_btn = Button.new()
	copy_btn.text = "COPY JSON"
	copy_btn.custom_minimum_size = Vector2(90, 30)
	copy_btn.pressed.connect(_on_copy_json)
	actions_row.add_child(copy_btn)
	
	var paste_btn = Button.new()
	paste_btn.text = "PASTE JSON"
	paste_btn.custom_minimum_size = Vector2(90, 30)
	paste_btn.pressed.connect(_on_paste_json)
	actions_row.add_child(paste_btn)
	
	var preview_btn = Button.new()
	preview_btn.text = "PREVIEW"
	preview_btn.custom_minimum_size = Vector2(70, 30)
	preview_btn.pressed.connect(_on_preview)
	actions_row.add_child(preview_btn)
	
	var clear_btn = Button.new()
	clear_btn.text = "CLEAR"
	clear_btn.custom_minimum_size = Vector2(60, 30)
	clear_btn.pressed.connect(_on_clear)
	actions_row.add_child(clear_btn)
	
	var back_btn = Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(60, 30)
	back_btn.pressed.connect(_on_back_pressed)
	actions_row.add_child(back_btn)
	
	# Info label
	info_label = Label.new()
	info_label.position = Vector2(10, 700)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 2)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(info_label)

func _on_hold_type_selected(index: int):
	selected_hold_type = HOLD_TYPES[index]
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
			KEY_ESCAPE:
				selected_hold_type = ""
				clear_preview()
				dragging_hold = null
				var preview_player = get_node_or_null("PreviewPlayer")
				if preview_player:
					preview_player.queue_free()
			KEY_G:
				grid_enabled = !grid_enabled
			KEY_C:
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
					_on_copy_json()
			KEY_V:
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
					_on_paste_json()
			KEY_R:
				var preview_player = get_node_or_null("PreviewPlayer")
				if preview_player:
					preview_player.queue_free()
					return
	
	if is_mouse_over_ui():
		return
	
	if event is InputEventMouseButton:
		reset_idle_timer()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				handle_left_click()
			else:
				dragging_hold = null
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var pos = get_global_mouse_position()
			var hold = get_hold_at_position(pos)
			if hold:
				delete_hold(hold)
		
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

func handle_left_click():
	var pos = get_global_mouse_position()
	
	if selected_hold_type and selected_hold_type in loaded_scenes:
		var snapped_pos = snap_to_grid(pos)
		place_hold(snapped_pos)
	else:
		var hold = get_hold_at_position(pos)
		if hold:
			dragging_hold = hold
			drag_offset = hold.global_position - pos

# =============================================================================
# JSON EXPORT/IMPORT
# =============================================================================

func _on_copy_json():
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	var environment_name = "gym"
	if env_config:
		environment_name = env_config.get_current_environment_name().to_lower()
	
	var level_data = {
		"name": climb_name if climb_name != "" else "Unnamed Climb",
		"grade": climb_grade,
		"environment": environment_name,
		"holds": []
	}
	
	for hold in holds_container.get_children():
		var hold_type_str = get_hold_type(hold)
		var hold_data = {
			"type": hold_type_str,
			"x": hold.global_position.x,
			"y": hold.global_position.y
		}
		level_data.holds.append(hold_data)
	
	var json_str = JSON.stringify(level_data, "\t")
	DisplayServer.clipboard_set(json_str)
	
	show_notification("JSON copied! " + level_data.name + " (" + level_data.grade + ") - " + 
					  str(level_data.holds.size()) + " holds")

func _on_paste_json():
	var clipboard = DisplayServer.clipboard_get()
	
	if clipboard.is_empty():
		show_notification("Clipboard is empty!", true)
		return
	
	var json = JSON.new()
	var error = json.parse(clipboard)
	
	if error != OK:
		show_notification("Invalid JSON in clipboard!", true)
		return
	
	var data = json.data
	
	if not "holds" in data:
		show_notification("No 'holds' array in JSON!", true)
		return
	
	_on_clear()
	
	climb_name = data.get("name", "")
	climb_grade = data.get("grade", "VB")
	
	if climb_name_input:
		climb_name_input.text = climb_name
	
	if grade_dropdown:
		var grade_index = 0
		if climb_grade in V_GRADES:
			grade_index = V_GRADES.find(climb_grade)
		elif climb_grade in YDS_GRADES:
			grade_index = V_GRADES.size() + 1 + YDS_GRADES.find(climb_grade)
		grade_dropdown.select(grade_index)
	
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
	
	update_wall_bounds()
	show_notification("Loaded: " + climb_name + " (" + climb_grade + ")")

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
	
	if hold.has_method("is_start_hold") and hold.is_start_hold():
		return "START"
	elif hold.has_method("is_top_out") and hold.is_top_out():
		return "TOP"
	elif hold.has_method("is_crimp") and hold.is_crimp():
		return "CRIMP"
	elif hold.has_method("is_sloper") and hold.is_sloper():
		return "SLOPER"
	elif hold.has_method("is_pocket") and hold.is_pocket():
		return "POCKET"
	elif hold.has_method("is_foothold") and hold.is_foothold():
		return "FOOT"
	
	return "JUG"

func is_mouse_over_ui() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()
	var toolbar = ui_layer.get_node_or_null("PanelContainer")
	if toolbar:
		var toolbar_rect = Rect2(toolbar.position, toolbar.size)
		if toolbar_rect.has_point(mouse_pos):
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
			return false
	
	if selected_hold_type == "TOP":
		var top_count = count_holds_of_type("TOP")
		if top_count >= MAX_TOP_HOLDS:
			show_notification("Maximum " + str(MAX_TOP_HOLDS) + " TOP hold allowed!", true)
			return false
	
	if is_position_too_close(pos, null):
		show_notification("Hold too close to another hold!", true)
		return false
	
	if not is_position_reachable(pos, null):
		show_notification("Hold too far from route!", true)
		return false
	
	var hold = loaded_scenes[selected_hold_type].instantiate()
	
	if hold.has_method("set_hold_type_from_string"):
		hold.set_hold_type_from_string(selected_hold_type)
	
	hold.global_position = pos
	holds_container.add_child(hold)
	hold.add_to_group("holds")
	hold.set_meta("editor_type", selected_hold_type)
	
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

# =============================================================================
# CALLBACKS
# =============================================================================

func _on_climb_name_changed(new_text: String):
	reset_idle_timer()
	climb_name = new_text

func _on_grade_changed(index: int):
	reset_idle_timer()
	
	if index < V_GRADES.size():
		climb_grade = V_GRADES[index]
	else:
		var yds_index = index - V_GRADES.size() - 1
		if yds_index >= 0 and yds_index < YDS_GRADES.size():
			climb_grade = YDS_GRADES[yds_index]

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

func _on_preview():
	if holds_container.get_child_count() == 0:
		show_notification("No holds to preview!", true)
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
		show_notification("No START holds!", true)
		return
	
	if top_holds.size() == 0:
		show_notification("No TOP holds!", true)
		return
	
	var player_scene_path = "res://scenes/player/character.tscn"
	if not ResourceLoader.exists(player_scene_path):
		show_notification("Player scene not found!", true)
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
	
	show_notification("PREVIEW MODE - Press ESC/R to exit")

func _on_clear():
	for hold in holds_container.get_children():
		hold.queue_free()
	
	climb_name = ""
	climb_grade = "VB"
	if climb_name_input:
		climb_name_input.text = ""
	if grade_dropdown:
		grade_dropdown.select(0)
	
	update_wall_bounds()
	idle_timer = 0.0

func _on_back_pressed():
	var preview_player = get_node_or_null("PreviewPlayer")
	if preview_player:
		preview_player.queue_free()
	
	selected_hold_type = ""
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
		_on_clear()
		idle_timer = 0.0

func reset_idle_timer():
	idle_timer = 0.0

func show_notification(text: String, is_error: bool = false):
	var old_label = ui_layer.get_node_or_null("NotificationLabel")
	if old_label:
		old_label.queue_free()
	
	var label = Label.new()
	label.name = "NotificationLabel"
	label.text = text
	label.position = Vector2(10, 130)
	label.add_theme_color_override("font_color", Color.RED if is_error else Color.YELLOW)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 20)
	ui_layer.add_child(label)
	
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(label):
		label.queue_free()

func update_info_label():
	var selected = selected_hold_type if selected_hold_type else "None"
	var count = holds_container.get_child_count()
	var grid_status = "ON" if grid_enabled else "OFF"
	var start_count = count_holds_of_type("START")
	var top_count = count_holds_of_type("TOP")
	var auto_reset_remaining = int(IDLE_RESET_TIME - idle_timer)
	
	var climb_info = climb_name if climb_name != "" else "Unnamed"
	climb_info += " (" + climb_grade + ")"
	
	var bounds = get_route_bounds()
	var route_height = 0
	if bounds.valid:
		route_height = int(abs(bounds.max.y - bounds.min.y))
	
	info_label.text = "%s | Holds: %d (START:%d/%d, TOP:%d/%d) | Height: %dpx | Placing: %s | Grid: %s | Zoom: %.1fx | Auto-reset: %ds" % [
		climb_info, count, start_count, MAX_START_HOLDS, top_count, MAX_TOP_HOLDS, route_height, selected, grid_status, camera.zoom.x, auto_reset_remaining
	]

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
