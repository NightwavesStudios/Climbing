extends Control
## Level Select Screen - Shows levels from current collection


# ─────────────────────────────────────────────────────────────
# Node references (direct paths)
# ─────────────────────────────────────────────────────────────
@onready var level_container: VBoxContainer = $LevelContainer
@onready var collection_title: Label = $CollectionTitle
@onready var progress_label: Label = $ProgressLabel


func _ready() -> void:
	# Safety check
	if level_container == null:
		push_error("LevelContainer node not found — check scene tree path!")
		return
	
	if collection_title == null:
		push_error("CollectionTitle node not found — check scene tree path!")
	
	if progress_label == null:
		push_error("ProgressLabel node not found — check scene tree path!")
	
	_populate_levels()


# ─────────────────────────────────────────────────────────────
# UI population
# ─────────────────────────────────────────────────────────────
func _populate_levels() -> void:
	var collection_id := GameState.get_current_collection()
	
	if collection_id == "":
		push_error("No collection selected!")
		return
	
	var data := GameState.get_collection_data(collection_id)
	if data.is_empty():
		push_error("Invalid collection!")
		return
	
	# Header
	if collection_title:
		collection_title.text = data.name
	
	# Progress
	var progress := GameState.get_collection_progress(collection_id)
	if progress_label:
		progress_label.text = "%d/%d Complete" % [progress.completed, progress.total]
	
	# Clear existing buttons
	for child in level_container.get_children():
		child.queue_free()
	
	# Create buttons for each level
	for i in range(data.levels.size()):
		var level_path = data.levels[i]
		var unlocked := GameState.is_level_unlocked(collection_id, i)
		var completed := GameState.is_level_completed(level_path)
		
		level_container.add_child(
			_create_level_button(i, level_path, unlocked, completed)
		)


# ─────────────────────────────────────────────────────────────
# Button creation
# ─────────────────────────────────────────────────────────────
func _create_level_button(index: int, level_path: String, unlocked: bool, completed: bool) -> Button:
	var button := Button.new()
	
	# Size and layout
	button.custom_minimum_size = Vector2(420, 64)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	
	# Text
	var level_name := _get_level_name_from_path(level_path)
	var text := "%d. %s" % [index + 1, level_name]
	
	if completed:
		text += " ✓"
		var time := GameState.get_level_completion_time(level_path)
		if time > 0:
			text += " (%s)" % _format_time(time)
	
	button.text = text
	button.disabled = not unlocked
	
	# Visual state
	if not unlocked:
		button.modulate = Color(0.55, 0.55, 0.55, 0.75)
		button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	elif completed:
		button.modulate = Color(0.6, 1.0, 0.6)
	else:
		button.modulate = Color.WHITE
	
	# Interaction
	button.pressed.connect(_on_level_selected.bind(level_path, unlocked))
	
	return button


# ─────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────
func _on_level_selected(level_path: String, unlocked: bool) -> void:
	if not unlocked:
		_show_locked_message()
		return
	
	GameState.set_current_level(level_path)
	Transition.to("res://scenes/main/main_scene.tscn")


func _show_locked_message() -> void:
	print("Complete the previous level to unlock this one!")
	# Optional: popup or toast can go here


# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────
func _get_level_name_from_path(path: String) -> String:
	var filename := path.get_file().get_basename()
	var words := filename.split("_")
	
	var result := ""
	for word in words:
		if word.length() > 0:
			result += word.capitalize() + " "
	
	return result.strip_edges()


func _format_time(seconds: float) -> String:
	var mins := int(seconds / 60)
	var secs := int(seconds) % 60
	return "%02d:%02d" % [mins, secs]


func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/collections_select.tscn")
