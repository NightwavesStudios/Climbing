extends Control

## Collection Select Screen - Map Version

# Map container reference (the existing Locations node)
@onready var map_container: Control = $Locations

# Map buttons to collection IDs
var button_to_collection = {}

# Panning and zooming variables
var is_dragging = false
var drag_start_position = Vector2.ZERO
var map_offset = Vector2.ZERO
var zoom_level = 1.0
var min_zoom = 0.5
var max_zoom = 2.0
var zoom_speed = 0.1

# Visual state colors
var COLOR_UNLOCKED = Color(1.0, 1.0, 1.0, 1.0)  # White - available
var COLOR_COMPLETED = Color(0.4, 1.0, 0.4, 1.0)  # Green - completed
var COLOR_LOCKED = Color(0.3, 0.3, 0.3, 0.5)  # Dark gray - locked

func _ready() -> void:
	# Get all buttons from Locations node
	_find_all_buttons()
	_setup_button_mapping()
	_update_collection_states()
	
	# Center on most recently unlocked gym
	_center_on_latest_unlocked()

func _find_all_buttons():
	"""Find all Button nodes in the Locations container"""
	if not map_container:
		push_error("Locations node not found!")
		return
	
	# Get all children of Locations
	for child in map_container.get_children():
		if child is Button:
			# Connect button pressed signals dynamically
			if not child.pressed.is_connected(_on_button_pressed):
				child.pressed.connect(_on_button_pressed.bind(child))

func _center_on_latest_unlocked():
	"""Center the map on the most recently unlocked gym"""
	var latest_unlocked_button: Button = null
	var latest_collection_id = ""
	
	# Find the last unlocked collection
	var collection_order = ["tutorial", "flow", "precision", "instability", "long_haul"]
	
	for collection_id in collection_order:
		if GameState.is_collection_unlocked(collection_id):
			latest_collection_id = collection_id
			# Find the button for this collection
			for button in button_to_collection.keys():
				if button_to_collection[button] == collection_id:
					latest_unlocked_button = button
		else:
			# Stop at first locked collection
			break
	
	if latest_unlocked_button:
		_center_on_button(latest_unlocked_button)
	else:
		# Fallback to default centering
		_center_map()

func _center_on_button(button: Button):
	"""Center the map view on a specific button"""
	var viewport_size = get_viewport_rect().size
	var button_global_pos = button.global_position
	
	# Calculate offset to center the button
	map_offset = viewport_size / 2 - button.position * zoom_level
	_update_map_transform()

func _center_map():
	"""Center the map view on the viewport"""
	var viewport_size = get_viewport_rect().size
	map_offset = viewport_size / 2
	_update_map_transform()

func _input(event: InputEvent) -> void:
	# Handle mouse dragging for panning
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				drag_start_position = event.position
			else:
				is_dragging = false
		
		# Handle zoom with mouse wheel or trackpad pinch
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_position(event.position, 1 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_position(event.position, 1 - zoom_speed)
	
	elif event is InputEventMouseMotion:
		if is_dragging:
			var delta = event.position - drag_start_position
			drag_start_position = event.position
			map_offset += delta
			_update_map_transform()
	
	# Handle trackpad gestures for zooming
	elif event is InputEventMagnifyGesture:
		_zoom_at_position(event.position, event.factor)
	
	# Handle trackpad pan gestures
	elif event is InputEventPanGesture:
		map_offset -= event.delta * 50  # Adjust multiplier for sensitivity
		_update_map_transform()

func _zoom_at_position(mouse_pos: Vector2, zoom_factor: float):
	"""Zoom centered on mouse position"""
	var old_zoom = zoom_level
	zoom_level = clamp(zoom_level * zoom_factor, min_zoom, max_zoom)
	
	# Adjust offset to zoom toward mouse position
	var zoom_change = zoom_level / old_zoom
	var mouse_offset = mouse_pos - map_offset
	map_offset = mouse_pos - (mouse_offset * zoom_change)
	
	_update_map_transform()

func _update_map_transform():
	"""Apply current pan and zoom to map container"""
	if map_container:
		map_container.position = map_offset
		map_container.scale = Vector2(zoom_level, zoom_level)

func _setup_button_mapping():
	"""Map buttons to their collection IDs based on their names"""
	if not map_container:
		return
	
	for child in map_container.get_children():
		if child is Button:
			var button_name = child.name.to_lower()
			
			# Map button names to collection IDs
			if "tutorial" in button_name or "tutorialgym" in button_name:
				button_to_collection[child] = "tutorial"
			elif "flow" in button_name or "chapter2" in button_name:
				button_to_collection[child] = "flow"
			elif "precision" in button_name or "chapter3" in button_name:
				button_to_collection[child] = "precision"
			elif "instability" in button_name or "chapter4" in button_name:
				button_to_collection[child] = "instability"
			elif "longhaul" in button_name or "long_haul" in button_name or "chapter5" in button_name:
				button_to_collection[child] = "long_haul"

func _update_collection_states():
	"""Update visual state of all collection buttons based on unlock status"""
	for button in button_to_collection.keys():
		var collection_id = button_to_collection[button]
		var is_unlocked = GameState.is_collection_unlocked(collection_id)
		var is_completed = GameState.is_collection_completed(collection_id)
		
		# Update button appearance based on state
		if is_completed:
			button.modulate = COLOR_COMPLETED
			button.disabled = false
			_add_completion_indicator(button)
		elif is_unlocked:
			button.modulate = COLOR_UNLOCKED
			button.disabled = false
			_remove_completion_indicator(button)
		else:
			button.modulate = COLOR_LOCKED
			button.disabled = false  # Keep enabled to show unlock requirement
			_add_lock_indicator(button)

func _add_completion_indicator(button: Button):
	"""Add a visual indicator showing the gym is completed"""
	# Remove any existing indicator
	_remove_completion_indicator(button)
	
	# Create a checkmark or completion icon
	var indicator = Label.new()
	indicator.name = "CompletionIndicator"
	indicator.text = "✓"  # Checkmark
	indicator.add_theme_font_size_override("font_size", 32)
	indicator.modulate = Color(0.0, 1.0, 0.0, 1.0)  # Bright green
	
	# Position in top-right corner
	indicator.position = Vector2(button.size.x - 40, -10)
	indicator.z_index = 1
	
	button.add_child(indicator)

func _remove_completion_indicator(button: Button):
	"""Remove completion indicator if it exists"""
	var indicator = button.get_node_or_null("CompletionIndicator")
	if indicator:
		indicator.queue_free()

func _add_lock_indicator(button: Button):
	"""Add a visual indicator showing the gym is locked"""
	# Remove any existing indicators
	_remove_completion_indicator(button)
	var existing_lock = button.get_node_or_null("LockIndicator")
	if existing_lock:
		return  # Already has lock indicator
	
	# Create a lock icon
	var indicator = Label.new()
	indicator.name = "LockIndicator"
	indicator.text = "🔒"  # Lock emoji
	indicator.add_theme_font_size_override("font_size", 32)
	
	# Center it on the button
	indicator.position = Vector2(button.size.x / 2 - 16, button.size.y / 2 - 16)
	indicator.z_index = 1
	
	button.add_child(indicator)

func _on_button_pressed(button: Button):
	"""Handle any button press from the map"""
	if button in button_to_collection:
		var collection_id = button_to_collection[button]
		_select_collection(collection_id)

func _select_collection(collection_id: String):
	"""Handle collection selection"""
	if not GameState.is_collection_unlocked(collection_id):
		_show_unlock_requirement(collection_id)
		return
	
	# Set current collection in GameState
	GameState.set_current_collection(collection_id)
	
	# Go to level select screen
	Transition.to("res://scenes/menus/level_select.tscn")

func _show_unlock_requirement(collection_id: String):
	"""Show a popup explaining how to unlock this collection"""
	var data = GameState.get_collection_data(collection_id)
	var req = data.unlock_requirement
	
	var message = "LOCKED\n\n"
	
	match req.type:
		"collection_complete":
			var req_collection_data = GameState.get_collection_data(req.collection)
			message += "Complete '" + req_collection_data.name + "' to unlock"
		
		"total_levels":
			var current = GameState.get_total_completed_levels()
			message += "Complete " + str(req.count) + " levels to unlock\n"
			message += "Progress: " + str(current) + "/" + str(req.count)
		
		"collections_complete":
			var current = GameState.completed_collections.size()
			message += "Complete " + str(req.count) + " collections to unlock\n"
			message += "Progress: " + str(current) + "/" + str(req.count)
	
	print(message)
	# You can create a popup here instead of just printing
	# _show_popup(data.name, message)

func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/main_menu.tscn")
