extends Node2D

# =============================================================================
# SIMPLIFIED LEVEL EDITOR - Clean, functional, dev-friendly
# =============================================================================

@onready var camera: Camera2D = $Camera2D
@onready var holds_container: Node2D = $Holds
@onready var preview_container: Node2D = $PreviewContainer

# UI
var ui_layer: CanvasLayer
var info_label: Label
var hold_buttons: Array[Button] = []

# State
var selected_hold_type: String = ""
var preview_hold: Node2D = null
var dragging_hold: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO
var unsaved_changes: bool = false

# Grid
var grid_enabled: bool = true
var grid_size: float = 32.0

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

# Camera
const ZOOM_SPEED = 0.15
const PAN_SPEED = 800.0
const MIN_ZOOM = 0.5
const MAX_ZOOM = 3.0

func _ready():
	# Ensure containers exist
	if not has_node("PreviewContainer"):
		preview_container = Node2D.new()
		preview_container.name = "PreviewContainer"
		preview_container.z_index = 100
		add_child(preview_container)
	
	if not has_node("Holds"):
		holds_container = Node2D.new()
		holds_container.name = "Holds"
		add_child(holds_container)
	
	# Load holds
	for type_name in HOLD_SCENES:
		if ResourceLoader.exists(HOLD_SCENES[type_name]):
			loaded_scenes[type_name] = load(HOLD_SCENES[type_name])
	
	setup_ui()

func _process(delta):
	update_camera(delta)
	update_preview()
	update_info_label()
	queue_redraw()

func _input(event):
	handle_input(event)

# =============================================================================
# UI SETUP - Minimal, non-blocking
# =============================================================================

func setup_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	
	# Top toolbar - doesn't block mouse
	var toolbar = PanelContainer.new()
	toolbar.position = Vector2(10, 10)
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE  # KEY: Don't block mouse
	ui_layer.add_child(toolbar)
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS  # Let clicks through except on buttons
	toolbar.add_child(hbox)
	
	# Hold type buttons
	for type_name in ["START", "TOP", "JUG", "CRIMP", "SLOPER", "POCKET", "FOOT"]:
		var btn = Button.new()
		btn.text = type_name
		btn.custom_minimum_size = Vector2(70, 30)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP  # Only buttons catch clicks
		btn.pressed.connect(_on_hold_selected.bind(type_name))
		hbox.add_child(btn)
		hold_buttons.append(btn)
	
	hbox.add_child(VSeparator.new())
	
	# Action buttons
	var save_btn = Button.new()
	save_btn.text = "SAVE"
	save_btn.custom_minimum_size = Vector2(60, 30)
	save_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	save_btn.pressed.connect(_on_save)
	hbox.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "LOAD"
	load_btn.custom_minimum_size = Vector2(60, 30)
	load_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	load_btn.pressed.connect(_on_load)
	hbox.add_child(load_btn)
	
	var test_btn = Button.new()
	test_btn.text = "TEST"
	test_btn.custom_minimum_size = Vector2(60, 30)
	test_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	test_btn.pressed.connect(_on_test)
	hbox.add_child(test_btn)
	
	var clear_btn = Button.new()
	clear_btn.text = "CLEAR"
	clear_btn.custom_minimum_size = Vector2(60, 30)
	clear_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	clear_btn.pressed.connect(_on_clear)
	hbox.add_child(clear_btn)
	
	var export_btn = Button.new()
	export_btn.text = "EXPORT"
	export_btn.custom_minimum_size = Vector2(70, 30)
	export_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	export_btn.pressed.connect(_on_export)
	hbox.add_child(export_btn)
	
	# Info label at bottom
	info_label = Label.new()
	info_label.position = Vector2(10, 700)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 2)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(info_label)

# =============================================================================
# INPUT HANDLING
# =============================================================================

func handle_input(event):
	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DELETE:
				if dragging_hold:
					delete_hold(dragging_hold)
			KEY_ESCAPE:
				selected_hold_type = ""
				clear_preview()
				dragging_hold = null
			KEY_G:
				grid_enabled = !grid_enabled
	
	# Mouse input
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				handle_left_click()
			else:
				dragging_hold = null
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right click = delete
			var pos = get_global_mouse_position()
			var hold = get_hold_at_position(pos)
			if hold:
				delete_hold(hold)
		
		# Zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom *= (1.0 + ZOOM_SPEED)
			camera.zoom = camera.zoom.clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom *= (1.0 - ZOOM_SPEED)
			camera.zoom = camera.zoom.clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
	
	elif event is InputEventMouseMotion:
		if dragging_hold:
			var new_pos = snap_to_grid(get_global_mouse_position() + drag_offset)
			dragging_hold.global_position = new_pos
			unsaved_changes = true

func handle_left_click():
	var pos = snap_to_grid(get_global_mouse_position())
	
	# If we have a hold type selected, place it
	if selected_hold_type and selected_hold_type in loaded_scenes:
		place_hold(pos)
	else:
		# Otherwise try to grab a hold
		var hold = get_hold_at_position(pos)
		if hold:
			dragging_hold = hold
			drag_offset = hold.global_position - pos

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
		camera.position += move.normalized() * PAN_SPEED * delta / camera.zoom.x

# =============================================================================
# PREVIEW
# =============================================================================

func update_preview():
	if not selected_hold_type or selected_hold_type not in loaded_scenes:
		clear_preview()
		return
	
	# Create preview if needed
	if not preview_hold or not is_instance_valid(preview_hold):
		clear_preview()
		preview_hold = loaded_scenes[selected_hold_type].instantiate()
		preview_hold.modulate = Color(1, 1, 1, 0.5)
		preview_hold.z_index = 100
		preview_container.add_child(preview_hold)
	
	# Update position
	preview_hold.global_position = snap_to_grid(get_global_mouse_position())

func clear_preview():
	if preview_hold and is_instance_valid(preview_hold):
		preview_hold.queue_free()
	preview_hold = null

# =============================================================================
# HOLD OPERATIONS
# =============================================================================

func place_hold(pos: Vector2):
	if not selected_hold_type or selected_hold_type not in loaded_scenes:
		return
	
	var hold = loaded_scenes[selected_hold_type].instantiate()
	hold.global_position = pos
	holds_container.add_child(hold)
	unsaved_changes = true

func delete_hold(hold: Node2D):
	if hold == dragging_hold:
		dragging_hold = null
	hold.queue_free()
	unsaved_changes = true

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
# UI CALLBACKS
# =============================================================================

func _on_hold_selected(type_name: String):
	selected_hold_type = type_name
	clear_preview()
	
	# Highlight selected button
	for btn in hold_buttons:
		btn.modulate = Color.WHITE if btn.text != type_name else Color.YELLOW

func _on_save():
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.filters = ["*.climb"]
	dialog.file_selected.connect(save_level)
	add_child(dialog)
	dialog.popup_centered(Vector2(600, 400))

func _on_load():
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.filters = ["*.climb"]
	dialog.file_selected.connect(load_level)
	add_child(dialog)
	dialog.popup_centered(Vector2(600, 400))

func _on_test():
	# Save temp level and test it
	var temp_path = "user://temp_test.climb"
	save_level(temp_path)
	
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		game_state.set_current_level(temp_path)
		get_tree().change_scene_to_file("res://main_game.tscn")

func _on_clear():
	for hold in holds_container.get_children():
		hold.queue_free()
	unsaved_changes = false

func _on_export():
	var level_data = {"holds": []}
	for hold in holds_container.get_children():
		level_data.holds.append(serialize_hold(hold))
	
	var json_str = JSON.stringify(level_data, "\t")
	DisplayServer.clipboard_set(json_str)
	
	# Also save to file with timestamp
	var time_str = Time.get_datetime_string_from_system().replace(":", "-")
	var export_path = "user://export_" + time_str + ".climb"
	var file = FileAccess.open(export_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("Exported to: " + export_path + " (also copied to clipboard)")

# =============================================================================
# SAVE/LOAD
# =============================================================================

func save_level(path: String):
	var level_data = {"holds": []}
	
	for hold in holds_container.get_children():
		level_data.holds.append(serialize_hold(hold))
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(level_data, "\t"))
		file.close()
		unsaved_changes = false
		print("Saved: " + path)

func load_level(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("Failed to load: " + path)
		return
	
	var json_str = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_str) != OK:
		print("Invalid JSON in: " + path)
		return
	
	var data = json.data
	
	# Clear existing
	for hold in holds_container.get_children():
		hold.queue_free()
	
	# Load holds
	if "holds" in data:
		for hold_data in data.holds:
			deserialize_hold(hold_data)
	
	unsaved_changes = false
	print("Loaded: " + path)

func serialize_hold(hold: Node2D) -> Dictionary:
	return {
		"type": get_hold_type(hold),
		"x": hold.global_position.x,
		"y": hold.global_position.y
	}

func deserialize_hold(data: Dictionary):
	var type_name = data.get("type", "JUG")
	if type_name not in loaded_scenes:
		return
	
	var hold = loaded_scenes[type_name].instantiate()
	hold.global_position = Vector2(data.get("x", 0), data.get("y", 0))
	holds_container.add_child(hold)

func get_hold_type(hold: Node2D) -> String:
	# Check hold methods to determine type
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

# =============================================================================
# INFO UPDATE
# =============================================================================

func update_info_label():
	var status = "*" if unsaved_changes else ""
	var selected = selected_hold_type if selected_hold_type else "None"
	var count = holds_container.get_child_count()
	var grid_status = "ON" if grid_enabled else "OFF"
	
	info_label.text = "%sHolds: %d | Selected: %s | Grid: %s | Zoom: %.1fx | WASD=Pan, Wheel=Zoom, LClick=Place, RClick=Delete, Del=Delete, G=ToggleGrid" % [
		status, count, selected, grid_status, camera.zoom.x
	]

# =============================================================================
# DRAWING - Grid overlay
# =============================================================================

func _draw():
	if not grid_enabled:
		return
	
	# Draw grid
	var viewport_rect = get_viewport_rect()
	var cam_pos = camera.position
	var cam_zoom = camera.zoom.x
	
	# Calculate visible area
	var half_size = viewport_rect.size / (2.0 * cam_zoom)
	var top_left = cam_pos - half_size
	var bottom_right = cam_pos + half_size
	
	# Snap to grid
	var start_x = floor(top_left.x / grid_size) * grid_size
	var start_y = floor(top_left.y / grid_size) * grid_size
	var end_x = ceil(bottom_right.x / grid_size) * grid_size
	var end_y = ceil(bottom_right.y / grid_size) * grid_size
	
	# Draw vertical lines
	var x = start_x
	while x <= end_x:
		draw_line(Vector2(x, start_y), Vector2(x, end_y), Color(0.3, 0.3, 0.3, 0.3), 1.0)
		x += grid_size
	
	# Draw horizontal lines
	var y = start_y
	while y <= end_y:
		draw_line(Vector2(start_x, y), Vector2(end_x, y), Color(0.3, 0.3, 0.3, 0.3), 1.0)
		y += grid_size
