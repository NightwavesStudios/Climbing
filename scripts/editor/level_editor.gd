extends Node2D

# =============================================================================
# LEVEL EDITOR - Export-only workflow for developers
# FIXES: Start hold distance, canvas size, auto-reset, hold limits, overlap prevention
# =============================================================================

var camera: Camera2D
var holds_container: Node2D
var preview_container: Node2D

# UI
var ui_layer: CanvasLayer
var info_label: Label
var hold_buttons: Array[Button] = []

# State
var selected_hold_type: String = ""
var preview_hold: Node2D = null
var dragging_hold: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO

# Grid
var grid_enabled: bool = true
var grid_size: float = 32.0

# Auto-reset timer
var idle_timer: float = 0.0
const IDLE_RESET_TIME: float = 30.0  # Auto-reset after 30 seconds of no input

# Hold limits
const MAX_START_HOLDS: int = 2
const MAX_TOP_HOLDS: int = 1
const MIN_HOLD_DISTANCE: float = 40.0  # Minimum distance between holds

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

# Camera - INCREASED CANVAS AREA
const ZOOM_SPEED = 0.15
const TRACKPAD_ZOOM_SPEED = 0.2
const PAN_SPEED = 1000.0  # Increased for larger canvas
const MIN_ZOOM = 0.3  # Zoom out more for larger canvas
const MAX_ZOOM = 3.0

# Canvas boundaries (large climbing wall)
const CANVAS_MIN_X = -1000.0
const CANVAS_MAX_X = 2000.0
const CANVAS_MIN_Y = -500.0
const CANVAS_MAX_Y = 2000.0

func _ready():
	# Get or create camera
	if has_node("Camera2D"):
		camera = get_node("Camera2D")
	else:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = Vector2(0.8, 0.8)  # Start zoomed out
		camera.position = Vector2(500, 750)  # Center on canvas
		add_child(camera)
	
	# Get or create holds container
	if has_node("Holds"):
		holds_container = get_node("Holds")
	else:
		holds_container = Node2D.new()
		holds_container.name = "Holds"
		add_child(holds_container)
	
	# Get or create preview container
	if has_node("PreviewContainer"):
		preview_container = get_node("PreviewContainer")
	else:
		preview_container = Node2D.new()
		preview_container.name = "PreviewContainer"
		preview_container.z_index = 100
		add_child(preview_container)
	
	# Load holds
	for type_name in HOLD_SCENES:
		if ResourceLoader.exists(HOLD_SCENES[type_name]):
			loaded_scenes[type_name] = load(HOLD_SCENES[type_name])
	
	setup_ui()

func _process(delta):
	update_camera(delta)
	update_preview()
	update_info_label()
	update_idle_timer(delta)
	queue_redraw()

# =============================================================================
# AUTO-RESET TIMER
# =============================================================================

func update_idle_timer(delta: float):
	idle_timer += delta
	
	if idle_timer >= IDLE_RESET_TIME:
		print("Auto-resetting level editor after " + str(IDLE_RESET_TIME) + " seconds of inactivity")
		_on_clear()
		idle_timer = 0.0

func reset_idle_timer():
	idle_timer = 0.0

# =============================================================================
# UI SETUP
# =============================================================================

func setup_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	
	# Top toolbar
	var toolbar = PanelContainer.new()
	toolbar.position = Vector2(10, 10)
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(toolbar)
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	toolbar.add_child(hbox)
	
	# Hold type buttons
	for type_name in ["START", "TOP", "JUG", "CRIMP", "SLOPER", "POCKET", "FOOT"]:
		var btn = Button.new()
		btn.text = type_name
		btn.custom_minimum_size = Vector2(70, 30)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_hold_selected.bind(type_name))
		hbox.add_child(btn)
		hold_buttons.append(btn)
	
	hbox.add_child(VSeparator.new())
	
	# Action buttons
	var copy_btn = Button.new()
	copy_btn.text = "COPY JSON"
	copy_btn.custom_minimum_size = Vector2(90, 30)
	copy_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	copy_btn.pressed.connect(_on_copy_json)
	hbox.add_child(copy_btn)
	
	var paste_btn = Button.new()
	paste_btn.text = "PASTE JSON"
	paste_btn.custom_minimum_size = Vector2(90, 30)
	paste_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	paste_btn.pressed.connect(_on_paste_json)
	hbox.add_child(paste_btn)
	
	var preview_btn = Button.new()
	preview_btn.text = "PREVIEW"
	preview_btn.custom_minimum_size = Vector2(70, 30)
	preview_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_btn.pressed.connect(_on_preview)
	hbox.add_child(preview_btn)
	
	var clear_btn = Button.new()
	clear_btn.text = "CLEAR"
	clear_btn.custom_minimum_size = Vector2(60, 30)
	clear_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	clear_btn.pressed.connect(_on_clear)
	hbox.add_child(clear_btn)
	
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
	reset_idle_timer()  # Reset on any input
	
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
			KEY_C:
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
					_on_copy_json()
			KEY_V:
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
					_on_paste_json()
	
	if event is InputEventMouseButton:
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
		var zoom_change = (event.factor - 1.0) * TRACKPAD_ZOOM_SPEED
		camera.zoom *= (1.0 + zoom_change)
		camera.zoom = camera.zoom.clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
	
	elif event is InputEventPanGesture:
		camera.position += event.delta * 50.0 / camera.zoom.x
	
	elif event is InputEventMouseMotion:
		if dragging_hold:
			var new_pos = snap_to_grid(get_global_mouse_position() + drag_offset)
			
			# Clamp to canvas boundaries
			new_pos.x = clamp(new_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
			new_pos.y = clamp(new_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
			
			dragging_hold.global_position = new_pos

func handle_left_click():
	var pos = snap_to_grid(get_global_mouse_position())
	
	if selected_hold_type and selected_hold_type in loaded_scenes:
		place_hold(pos)
	else:
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
		reset_idle_timer()
		camera.position += move.normalized() * PAN_SPEED * delta / camera.zoom.x

# =============================================================================
# PREVIEW
# =============================================================================

func update_preview():
	if not selected_hold_type or selected_hold_type not in loaded_scenes:
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
	
	# Clamp preview to canvas
	snapped_pos.x = clamp(snapped_pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
	snapped_pos.y = clamp(snapped_pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
	
	# Check if position would overlap
	if is_position_too_close(snapped_pos, null):
		preview_hold.modulate = Color(1, 0.3, 0.3, 0.5)  # Red tint if too close
	else:
		preview_hold.modulate = Color(1, 1, 1, 0.5)  # Normal if OK
	
	preview_hold.global_position = snapped_pos

func clear_preview():
	if preview_hold and is_instance_valid(preview_hold):
		preview_hold.queue_free()
	preview_hold = null

# =============================================================================
# HOLD OPERATIONS
# =============================================================================

func place_hold(pos: Vector2) -> bool:
	if not selected_hold_type or selected_hold_type not in loaded_scenes:
		return false
	
	# Clamp to canvas
	pos.x = clamp(pos.x, CANVAS_MIN_X, CANVAS_MAX_X)
	pos.y = clamp(pos.y, CANVAS_MIN_Y, CANVAS_MAX_Y)
	
	# Check hold limits
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
	
	# Check for overlap
	if is_position_too_close(pos, null):
		show_notification("Hold too close to another hold! (min " + str(MIN_HOLD_DISTANCE) + "px)", true)
		return false
	
	var hold = loaded_scenes[selected_hold_type].instantiate()
	
	# SET TYPE BEFORE ADDING TO TREE - with debug
	print("DEBUG: Placing hold type: ", selected_hold_type)
	if hold.has_method("set_hold_type_from_string"):
		hold.set_hold_type_from_string(selected_hold_type)
		print("DEBUG: After set_hold_type_from_string:")
		print("  hold.hold_type = ", hold.hold_type)
		print("  _type_was_set_manually = ", hold.get("_type_was_set_manually"))
	else:
		print("ERROR: Hold doesn't have set_hold_type_from_string method!")
	
	hold.global_position = pos
	holds_container.add_child(hold)
	hold.add_to_group("holds")
	
	# Store the type we wanted in metadata for later retrieval
	hold.set_meta("editor_type", selected_hold_type)
	
	print("Placed " + selected_hold_type + " at " + str(pos))
	return true

func delete_hold(hold: Node2D):
	if hold == dragging_hold:
		dragging_hold = null
	hold.queue_free()
	print("Deleted hold at " + str(hold.global_position))

func get_hold_at_position(pos: Vector2, max_dist: float = 40.0) -> Node2D:
	var closest: Node2D = null
	var closest_dist = max_dist
	
	for hold in holds_container.get_children():
		var dist = hold.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = hold
	
	return closest

func is_position_too_close(pos: Vector2, exclude_hold: Node2D) -> bool:
	"""Check if position is too close to any existing hold"""
	for hold in holds_container.get_children():
		if hold == exclude_hold:
			continue
		
		if hold.global_position.distance_to(pos) < MIN_HOLD_DISTANCE:
			return true
	
	return false

func count_holds_of_type(type_name: String) -> int:
	"""Count how many holds of a specific type exist"""
	var count = 0
	
	for hold in holds_container.get_children():
		var hold_type_str = get_hold_type(hold)
		if hold_type_str == type_name:
			count += 1
	
	return count

func snap_to_grid(pos: Vector2) -> Vector2:
	if not grid_enabled:
		return pos
	return Vector2(
		round(pos.x / grid_size) * grid_size,
		round(pos.y / grid_size) * grid_size
	)

# =============================================================================
# JSON EXPORT/IMPORT
# =============================================================================

func _on_copy_json():
	"""Copy level JSON to clipboard - paste into your .json file"""
	var level_data = {"holds": []}
	
	for hold in holds_container.get_children():
		var hold_type_str = get_hold_type(hold)
		level_data.holds.append({
			"type": hold_type_str,
			"x": hold.global_position.x,
			"y": hold.global_position.y
		})
	
	var json_str = JSON.stringify(level_data, "\t")
	DisplayServer.clipboard_set(json_str)
	
	print("═══════════════════════════════════════")
	print("JSON COPIED TO CLIPBOARD!")
	print("Hold count: " + str(level_data.holds.size()))
	print("───────────────────────────────────────")
	print("NEXT STEPS:")
	print("1. Create a new file: res://levels/my_level.json")
	print("2. Paste the JSON from clipboard")
	print("3. Save the file")
	print("4. Load it in game with:")
	print("   level_loader.load_level('res://levels/my_level.json')")
	print("═══════════════════════════════════════")
	
	show_notification("JSON copied to clipboard! (" + str(level_data.holds.size()) + " holds)")

func _on_paste_json():
	"""Load level from clipboard JSON"""
	var clipboard = DisplayServer.clipboard_get()
	
	if clipboard.is_empty():
		print("Clipboard is empty!")
		show_notification("Clipboard is empty!", true)
		return
	
	var json = JSON.new()
	var error = json.parse(clipboard)
	
	if error != OK:
		print("Invalid JSON in clipboard!")
		show_notification("Invalid JSON in clipboard!", true)
		return
	
	var data = json.data
	
	if not "holds" in data:
		print("No 'holds' array in JSON!")
		show_notification("No 'holds' array in JSON!", true)
		return
	
	# Clear existing
	_on_clear()
	
	# Load holds
	for hold_data in data.holds:
		var type_name = hold_data.get("type", "JUG")
		if type_name not in loaded_scenes:
			continue
		
		var hold = loaded_scenes[type_name].instantiate()
		
		# SET TYPE BEFORE ADDING TO TREE
		if hold.has_method("set_hold_type_from_string"):
			hold.set_hold_type_from_string(type_name)
		
		hold.global_position = Vector2(hold_data.get("x", 0), hold_data.get("y", 0))
		holds_container.add_child(hold)
		hold.add_to_group("holds")
		
		# Store the type in metadata
		hold.set_meta("editor_type", type_name)
	
	print("Loaded " + str(data.holds.size()) + " holds from clipboard")
	show_notification("Loaded " + str(data.holds.size()) + " holds from clipboard")

func get_hold_type(hold: Node2D) -> String:
	"""Get the hold type - tries multiple methods to be robust"""
	
	# FIRST: Check if we stored the type in metadata (most reliable in editor)
	if hold.has_meta("editor_type"):
		return hold.get_meta("editor_type")
	
	# SECOND: Try to read the hold_type enum directly
	if "hold_type" in hold:
		var hold_type_value = hold.hold_type
		
		# Map enum values to strings (based on HoldType enum order)
		match hold_type_value:
			0: return "JUG"
			1: return "START"
			2: return "TOP"
			3: return "CRIMP"
			4: return "SLOPER"
			5: return "FOOT"
			6: return "POCKET"
	
	# THIRD: Fallback to method checking
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
	
	# Default fallback
	return "JUG"

# =============================================================================
# UI CALLBACKS
# =============================================================================

func _on_hold_selected(type_name: String):
	selected_hold_type = type_name
	clear_preview()
	
	for btn in hold_buttons:
		btn.modulate = Color.WHITE if btn.text != type_name else Color.YELLOW

func _on_preview():
	if holds_container.get_child_count() == 0:
		print("No holds to preview!")
		show_notification("No holds to preview!", true)
		return
	
	# Check for required holds
	var start_holds = []
	var top_holds = []
	
	# Wait a frame to ensure holds are ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	for hold in holds_container.get_children():
		var hold_type_str = get_hold_type(hold)
		if hold_type_str == "START":
			start_holds.append(hold)
		if hold_type_str == "TOP":
			top_holds.append(hold)
	
	if start_holds.size() == 0:
		print("WARNING: No START holds!")
		show_notification("No START holds - add at least one!", true)
		return
	
	if top_holds.size() == 0:
		print("WARNING: No TOP holds!")
		show_notification("No TOP holds - add at least one!", true)
		return
	
	# Check start hold distance
	if start_holds.size() == 2:
		var distance = start_holds[0].global_position.distance_to(start_holds[1].global_position)
		if distance < 100:
			show_notification("Warning: START holds should be further apart (currently " + str(int(distance)) + "px)", true)
	
	# Load player
	var player_scene_path = "res://scenes/player/character.tscn"
	if not ResourceLoader.exists(player_scene_path):
		player_scene_path = "res://scenes/player/character.tscn"
		if not ResourceLoader.exists(player_scene_path):
			print("Player scene not found")
			show_notification("Player scene not found!", true)
			return
	
	# Remove old preview
	var old_preview = get_node_or_null("PreviewPlayer")
	if old_preview:
		old_preview.queue_free()
	
	# Spawn player
	var player_scene = load(player_scene_path)
	var player = player_scene.instantiate()
	player.name = "PreviewPlayer"
	add_child(player)
	
	# Position at center of start holds (or single start)
	var spawn_pos = Vector2.ZERO
	if start_holds.size() == 1:
		var hold_point = start_holds[0].get_node_or_null("HoldPoint")
		if hold_point:
			spawn_pos = hold_point.global_position + Vector2(0, 80)
		else:
			spawn_pos = start_holds[0].global_position + Vector2(0, 80)
	else:
		# Position between start holds
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

func _input(event):
	# Exit preview
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_R:
			var preview_player = get_node_or_null("PreviewPlayer")
			if preview_player:
				preview_player.queue_free()
				var label = ui_layer.get_node_or_null("NotificationLabel")
				if label:
					label.queue_free()
				print("Exited preview")
				return
	
	handle_input(event)

func _on_clear():
	for hold in holds_container.get_children():
		hold.queue_free()
	print("Cleared all holds")
	idle_timer = 0.0  # Reset idle timer

# =============================================================================
# NOTIFICATIONS
# =============================================================================

func show_notification(text: String, is_error: bool = false):
	# Remove old notification
	var old_label = ui_layer.get_node_or_null("NotificationLabel")
	if old_label:
		old_label.queue_free()
	
	# Create new notification
	var label = Label.new()
	label.name = "NotificationLabel"
	label.text = text
	label.position = Vector2(10, 50)
	label.add_theme_color_override("font_color", Color.RED if is_error else Color.YELLOW)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 20)
	ui_layer.add_child(label)
	
	# Auto-remove after 3 seconds
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(label):
		label.queue_free()

# =============================================================================
# INFO
# =============================================================================

func update_info_label():
	var selected = selected_hold_type if selected_hold_type else "None"
	var count = holds_container.get_child_count()
	var grid_status = "ON" if grid_enabled else "OFF"
	var start_count = count_holds_of_type("START")
	var top_count = count_holds_of_type("TOP")
	var auto_reset_remaining = int(IDLE_RESET_TIME - idle_timer)
	
	info_label.text = "Holds: %d (START:%d/%d, TOP:%d/%d) | Selected: %s | Grid: %s | Zoom: %.1fx | Auto-reset: %ds | Ctrl+C=Copy, Ctrl+V=Paste, G=Grid" % [
		count, start_count, MAX_START_HOLDS, top_count, MAX_TOP_HOLDS, selected, grid_status, camera.zoom.x, auto_reset_remaining
	]

# =============================================================================
# GRID
# =============================================================================

func _draw():
	# Draw canvas boundary
	draw_rect(Rect2(CANVAS_MIN_X, CANVAS_MIN_Y, CANVAS_MAX_X - CANVAS_MIN_X, CANVAS_MAX_Y - CANVAS_MIN_Y), Color(0.2, 0.2, 0.3, 0.3), false, 3.0)
	
	if not grid_enabled:
		return
	
	var viewport_rect = get_viewport_rect()
	var cam_pos = camera.position
	var cam_zoom = camera.zoom.x
	
	var half_size = viewport_rect.size / (2.0 * cam_zoom)
	var top_left = cam_pos - half_size
	var bottom_right = cam_pos + half_size
	
	# Clamp grid to canvas boundaries
	var start_x = max(floor(top_left.x / grid_size) * grid_size, CANVAS_MIN_X)
	var start_y = max(floor(top_left.y / grid_size) * grid_size, CANVAS_MIN_Y)
	var end_x = min(ceil(bottom_right.x / grid_size) * grid_size, CANVAS_MAX_X)
	var end_y = min(ceil(bottom_right.y / grid_size) * grid_size, CANVAS_MAX_Y)
	
	var x = start_x
	while x <= end_x:
		draw_line(Vector2(x, max(start_y, CANVAS_MIN_Y)), Vector2(x, min(end_y, CANVAS_MAX_Y)), Color(0.3, 0.3, 0.3, 0.3), 1.0)
		x += grid_size
	
	var y = start_y
	while y <= end_y:
		draw_line(Vector2(max(start_x, CANVAS_MIN_X), y), Vector2(min(end_x, CANVAS_MAX_X), y), Color(0.3, 0.3, 0.3, 0.3), 1.0)
		y += grid_size
