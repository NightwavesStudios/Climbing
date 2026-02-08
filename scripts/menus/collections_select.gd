extends Control
## Collection Select Screen

@onready var tutorial_button: Button = $TutorialCollection if has_node("TutorialCollection") else null
@onready var flow_button: Button = $FlowCollection if has_node("FlowCollection") else null
@onready var precision_button: Button = $PrecisionCollection if has_node("PrecisionCollection") else null
@onready var instability_button: Button = $InstabilityCollection if has_node("InstabilityCollection") else null
@onready var long_haul_button: Button = $LongHaulCollection if has_node("LongHaulCollection") else null

# Map buttons to collection IDs
var button_to_collection = {}

func _ready() -> void:
	_setup_button_mapping()
	_update_collection_states()

func _setup_button_mapping():
	"""Map buttons to their collection IDs"""
	if tutorial_button:
		button_to_collection[tutorial_button] = "tutorial"
	if flow_button:
		button_to_collection[flow_button] = "flow"
	if precision_button:
		button_to_collection[precision_button] = "precision"
	if instability_button:
		button_to_collection[instability_button] = "instability"
	if long_haul_button:
		button_to_collection[long_haul_button] = "long_haul"

func _update_collection_states():
	"""Update visual state of all collection buttons based on unlock status"""
	for button in button_to_collection.keys():
		var collection_id = button_to_collection[button]
		var is_unlocked = GameState.is_collection_unlocked(collection_id)
		var is_completed = GameState.is_collection_completed(collection_id)
		var progress = GameState.get_collection_progress(collection_id)
		
		# Update button appearance
		_style_collection_button(button, collection_id, is_unlocked, is_completed, progress)

func _style_collection_button(button: Button, collection_id: String, unlocked: bool, completed: bool, progress: Dictionary):
	"""Style the button based on its state"""
	if not button:
		return
	
	var data = GameState.get_collection_data(collection_id)
	
	# Set button text
	var text = data.name
	if completed:
		text += " ✓"  # Checkmark for completed
	elif progress.completed > 0:
		text += " (" + str(progress.completed) + "/" + str(progress.total) + ")"
	
	button.text = text
	button.disabled = not unlocked
	
	# Visual styling
	if not unlocked:
		# Locked state - gray and disabled
		button.modulate = Color(0.5, 0.5, 0.5, 0.7)
		button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		
		# Add lock icon or text hint
		if button.get_node_or_null("LockIcon"):
			button.get_node("LockIcon").visible = true
		
	elif completed:
		# Completed state - gold/special color
		button.modulate = Color(1.0, 0.9, 0.5, 1.0)
		
	else:
		# Unlocked but not completed - normal
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)

# =============================================================================
# BUTTON CALLBACKS
# =============================================================================

func _on_tutorial_collection_pressed() -> void:
	_select_collection("tutorial")

func _on_flow_collection_pressed() -> void:
	_select_collection("flow")

func _on_precision_collection_pressed() -> void:
	_select_collection("precision")

func _on_instability_collection_pressed() -> void:
	_select_collection("instability")

func _on_long_haul_collection_pressed() -> void:
	_select_collection("long_haul")

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
