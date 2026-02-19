extends Control
## Level Select Screen — Map Route Layout
## Levels are laid out in a snaking grid (left→right, right→left, repeat),
## connected by a continuous path line drawn on a SubViewport canvas.


# ─────────────────────────────────────────────
# Layout tuning
# ─────────────────────────────────────────────
@export_range(0.5, 1.0, 0.05)
var container_width_ratio := 0.85

@export_range(0.6, 1.0, 0.05)
var container_height_ratio := 0.85

## How many level nodes per row
@export_range(2, 8, 1)
var columns: int = 4

## Visual size of each level node button
@export var node_size: Vector2 = Vector2(96, 96)

## Horizontal and vertical spacing between nodes
@export var h_spacing: float = 40.0
@export var v_spacing: float = 80.0

## Thickness of the connecting path line
@export var path_line_width: float = 10.0

## Color of the completed path segment
@export var path_complete_color: Color = Color(0.4, 0.9, 0.5)

## Color of the locked / future path segment
@export var path_locked_color: Color = Color(0.35, 0.35, 0.45, 0.6)

## Color of the node border when completed
@export var node_complete_color: Color = Color(0.3, 0.85, 0.45)

## Color of the node border when unlocked but not completed
@export var node_unlocked_color: Color = Color(0.9, 0.85, 0.3)

## Color of the node border when locked
@export var node_locked_color: Color = Color(0.4, 0.4, 0.5, 0.8)


# ─────────────────────────────────────────────
# Node references
# ─────────────────────────────────────────────
@onready var scroll_container: ScrollContainer = $CenterContainer/ScrollContainer
@onready var map_layer: Control        = $CenterContainer/ScrollContainer/MapLayer
@onready var nodes_layer: Control      = $CenterContainer/ScrollContainer/MapLayer/NodesLayer
@onready var collection_title: Label   = $CollectionTitle
@onready var progress_label: Label     = $ProgressLabel

var _layout_ready := false

## Stores [{pos, unlocked, completed, path}] after layout is computed
var _node_meta: Array = []


# ─────────────────────────────────────────────
# Ready
# ─────────────────────────────────────────────
func _ready() -> void:
	_layout_ready = true
	_update_layout()
	_populate_levels()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _layout_ready:
		_update_layout()
		_rebuild_map()


# ─────────────────────────────────────────────
# Layout
# ─────────────────────────────────────────────
func _update_layout() -> void:
	if scroll_container == null:
		return

	var vp := get_viewport_rect().size
	scroll_container.custom_minimum_size = Vector2(
		vp.x * container_width_ratio,
		vp.y * container_height_ratio
	)
	scroll_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll_container.size_flags_vertical   = Control.SIZE_SHRINK_CENTER


# ─────────────────────────────────────────────
# UI population (entry point)
# ─────────────────────────────────────────────
func _populate_levels() -> void:
	var collection_id := GameState.get_current_collection()

	if collection_id == "":
		push_warning("level_select: no collection set, falling back to first unlocked")
		for id in GameState.get_all_collection_ids():
			if GameState.is_collection_unlocked(id):
				collection_id = id
				GameState.set_current_collection(id)
				break

	if collection_id == "":
		push_error("level_select: No unlocked collections found — cannot populate!")
		return

	var data := GameState.get_collection_data(collection_id)
	if data.is_empty():
		push_error("level_select: Collection '%s' has no data!" % collection_id)
		return

	print("level_select: Populating map for collection '%s'" % collection_id)

	collection_title.text = data.get("name", collection_id)

	var progress := GameState.get_collection_progress(collection_id)
	progress_label.text   = "%d / %d Complete" % [progress.completed, progress.total]

	# Pre-compute metadata for every level
	_node_meta.clear()
	for i in range(data.levels.size()):
		var lpath     := data.levels[i] as String
		var unlocked  := GameState.is_level_unlocked(collection_id, i)
		var completed := GameState.is_level_completed(lpath)
		var time      := GameState.get_level_completion_time(lpath) if completed else 0.0

		_node_meta.append({
			"index":     i,
			"path":      lpath,
			"unlocked":  unlocked,
			"completed": completed,
			"time":      time,
			"name":      _level_name(lpath),
		})

	_rebuild_map()


# ─────────────────────────────────────────────
# Map rebuild — call whenever data or size changes
# ─────────────────────────────────────────────
func _rebuild_map() -> void:
	if _node_meta.is_empty():
		return

	# --- clear old children ---
	for child in nodes_layer.get_children():
		child.queue_free()

	# --- compute node world positions ---
	var positions: Array[Vector2] = []
	var row_count := ceili(float(_node_meta.size()) / float(columns))

	# Total content area so we can center rows
	var total_w := columns * node_size.x + (columns - 1) * h_spacing
	var total_h := row_count * node_size.y + (row_count - 1) * v_spacing

	# Give the map layer enough room
	map_layer.custom_minimum_size = Vector2(total_w + node_size.x, total_h + node_size.y)

	var padding := node_size * 0.5   # half-node padding on each side

	for i in range(_node_meta.size()):
		var row := i / columns
		var col := i % columns

		# Alternate row direction for the snake effect
		var effective_col := col if (row % 2 == 0) else (columns - 1 - col)

		var x := padding.x + effective_col * (node_size.x + h_spacing)
		var y := padding.y + row        * (node_size.y + v_spacing)
		positions.append(Vector2(x, y))

	# --- store positions back into meta ---
	for i in range(_node_meta.size()):
		_node_meta[i]["pos"] = positions[i]

	# --- create node buttons ---
	for i in range(_node_meta.size()):
		var meta = _node_meta[i]
		var btn  := _create_node_button(meta)
		btn.position = meta["pos"] - node_size * 0.5
		nodes_layer.add_child(btn)

		# Animate nodes in with a staggered pop
		btn.scale  = Vector2.ZERO
		btn.pivot_offset = node_size * 0.5
		var tween := btn.create_tween()
		tween.tween_interval(i * 0.04)
		tween.tween_property(btn, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ─────────────────────────────────────────────
# Node button creation
# ─────────────────────────────────────────────
func _create_node_button(meta: Dictionary) -> UniversalButton:
	var btn := UniversalButton.new()

	btn.custom_minimum_size   = node_size
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode            = Control.FOCUS_NONE
	btn.hover_scale           = 1.08
	btn.press_scale           = 0.90
	btn.animation_speed       = 14
	btn.enable_outline_pulse  = meta["unlocked"] and not meta["completed"]
	btn.click_volume_db       = -12

	# Label: level number on top, name below, time if completed
	var label_text := str(meta["index"] + 1)
	if meta["completed"]:
		label_text += "\n✓"
		if meta["time"] > 0.0:
			label_text += "\n" + _format_time(meta["time"])
	elif not meta["unlocked"]:
		label_text += "\n🔒"

	btn.text     = label_text
	btn.disabled = not meta["unlocked"]

	# Tooltip with full name
	btn.tooltip_text = meta["name"]

	# Visual tint
	if not meta["unlocked"]:
		btn.set_visual_state(node_locked_color)
	elif meta["completed"]:
		btn.set_visual_state(node_complete_color)
	else:
		btn.set_visual_state(node_unlocked_color)

	btn.pressed.connect(_on_level_selected.bind(meta["path"], meta["unlocked"]))
	return btn


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
func _level_name(path: String) -> String:
	var words  := path.get_file().get_basename().split("_")
	var result := ""
	for word in words:
		result += word.capitalize() + " "
	return result.strip_edges()


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60), int(seconds) % 60]
