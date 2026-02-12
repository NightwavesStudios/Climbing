extends Control
## Level Select Screen


# ─────────────────────────────────────────────
# Layout tuning
# ─────────────────────────────────────────────
@export_range(0.2, 0.9, 0.05)
var container_width_ratio := 0.5

@export_range(0.3, 0.9, 0.05)
var container_height_ratio := 0.7


# ─────────────────────────────────────────────
# Node references
# ─────────────────────────────────────────────
@onready var scroll_container: ScrollContainer = $CenterContainer/ScrollContainer
@onready var level_container: VBoxContainer = $CenterContainer/ScrollContainer/LevelContainer
@onready var collection_title: Label = $CollectionTitle
@onready var progress_label: Label = $ProgressLabel

var _layout_ready := false


# ─────────────────────────────────────────────
# Ready
# ─────────────────────────────────────────────
func _ready() -> void:
	_layout_ready = true
	_update_layout()
	_populate_levels()


func _notification(what):
	if what == NOTIFICATION_RESIZED and _layout_ready:
		_update_layout()


# ─────────────────────────────────────────────
# Layout logic
# ─────────────────────────────────────────────
func _update_layout() -> void:
	if scroll_container == null:
		return
	
	var viewport_size := get_viewport_rect().size
	
	var target_width := viewport_size.x * container_width_ratio
	var target_height := viewport_size.y * container_height_ratio
	
	scroll_container.custom_minimum_size = Vector2(target_width, target_height)
	scroll_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	level_container.alignment = BoxContainer.ALIGNMENT_CENTER


# ─────────────────────────────────────────────
# UI population
# ─────────────────────────────────────────────
func _populate_levels() -> void:
	var collection_id := GameState.get_current_collection()
	if collection_id == "":
		push_error("No collection selected!")
		return
	
	var data := GameState.get_collection_data(collection_id)
	if data.is_empty():
		push_error("Invalid collection!")
		return
	
	if collection_title:
		collection_title.text = data.name
	
	if progress_label:
		var progress := GameState.get_collection_progress(collection_id)
		progress_label.text = "%d/%d Complete" % [progress.completed, progress.total]
	
	for child in level_container.get_children():
		child.queue_free()
	
	for i in range(data.levels.size()):
		var level_path = data.levels[i]
		var unlocked := GameState.is_level_unlocked(collection_id, i)
		var completed := GameState.is_level_completed(level_path)
		
		level_container.add_child(
			_create_level_button(i, level_path, unlocked, completed)
		)


# ─────────────────────────────────────────────
# Button creation
# ─────────────────────────────────────────────
func _create_level_button(index: int, level_path: String, unlocked: bool, completed: bool) -> UniversalButton:
	var button := UniversalButton.new()
	
	button.custom_minimum_size = Vector2(420, 64)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	
	# 🎨 Fine-tune feel for level select
	button.hover_scale = 1.03
	button.press_scale = 0.95
	button.animation_speed = 16
	button.enable_outline_pulse = false
	button.click_volume_db = -12
	
	var text := "%d. %s" % [index + 1, _get_level_name_from_path(level_path)]
	
	if completed:
		text += " ✓"
		var time := GameState.get_level_completion_time(level_path)
		if time > 0:
			text += " (%s)" % _format_time(time)
	
	button.text = text
	button.disabled = not unlocked
	
	# Visual state coloring
	if not unlocked:
		button.set_visual_state(Color(0.55, 0.55, 0.55, 0.75))
	elif completed:
		button.set_visual_state(Color(0.6, 1.0, 0.6))
	else:
		button.set_visual_state(Color.WHITE)
	
	button.pressed.connect(_on_level_selected.bind(level_path, unlocked))
	
	return button


# ─────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────
func _on_level_selected(level_path: String, unlocked: bool) -> void:
	if not unlocked:
		return
	
	GameState.set_current_level(level_path)
	Transition.to("res://scenes/main/main_scene.tscn")


func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/collections_select.tscn")


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
func _get_level_name_from_path(path: String) -> String:
	var words := path.get_file().get_basename().split("_")
	var result := ""
	for word in words:
		result += word.capitalize() + " "
	return result.strip_edges()


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60), int(seconds) % 60]
