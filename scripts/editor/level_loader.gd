extends Node2D
class_name LevelLoader

# Hold scenes mapping
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
var holds_container: Node2D

func _ready():
	# Load all hold scenes
	for type_name in HOLD_SCENES:
		if ResourceLoader.exists(HOLD_SCENES[type_name]):
			loaded_scenes[type_name] = load(HOLD_SCENES[type_name])
		else:
			print("WARNING: Hold scene not found: " + HOLD_SCENES[type_name])
	
	# Create holds container
	if not has_node("Holds"):
		holds_container = Node2D.new()
		holds_container.name = "Holds"
		add_child(holds_container)
	else:
		holds_container = get_node("Holds")

# =============================================================================
# LOAD LEVEL
# =============================================================================

func load_level(path: String) -> bool:
	"""Load a .json level file from res://levels/"""
	
	clear_holds()
	
	# Load JSON resource
	if not FileAccess.file_exists(path):
		print("ERROR: Level file not found: " + path)
		return false
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("ERROR: Could not open: " + path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		print("ERROR: Invalid JSON in: " + path)
		return false
	
	var level_data = json.data
	
	if not "holds" in level_data:
		print("ERROR: No 'holds' array in: " + path)
		return false
	
	# Spawn holds
	for hold_data in level_data.holds:
		spawn_hold(hold_data)
	
	print("✓ Loaded: " + path + " (" + str(level_data.holds.size()) + " holds)")
	return true

# =============================================================================
# HOLD SPAWNING - FIXED!
# =============================================================================

func spawn_hold(hold_data: Dictionary) -> Node2D:
	var type_name = hold_data.get("type", "JUG")
	if type_name not in loaded_scenes:
		print("WARNING: Unknown hold type: " + type_name)
		return null
	
	var hold = loaded_scenes[type_name].instantiate()
	hold.global_position = Vector2(hold_data.get("x", 0.0), hold_data.get("y", 0.0))
	
	# CRITICAL FIX: Set the hold type BEFORE adding to tree
	# This way _ready() will see _type_was_set_manually = true
	if hold.has_method("set_hold_type_from_string"):
		hold.set_hold_type_from_string(type_name)
	
	# NOW add to tree - _ready() will respect the manual setting
	holds_container.add_child(hold)
	hold.add_to_group("holds")
	
	return hold
	
# =============================================================================
# UTILITY
# =============================================================================
func clear_holds():
	if holds_container:
		for child in holds_container.get_children():
			child.queue_free()

func get_hold_count() -> int:
	return holds_container.get_child_count() if holds_container else 0

func get_start_holds() -> Array[Node2D]:
	var starts: Array[Node2D] = []
	if holds_container:
		for hold in holds_container.get_children():
			if hold.has_method("is_start_hold") and hold.is_start_hold():
				starts.append(hold)
	return starts

func get_top_holds() -> Array[Node2D]:
	var tops: Array[Node2D] = []
	if holds_container:
		for hold in holds_container.get_children():
			if hold.has_method("is_top_out") and hold.is_top_out():
				tops.append(hold)
	return tops

func get_player_spawn_position() -> Vector2:
	"""Get the position where player should spawn based on start holds"""
	var starts = get_start_holds()
	
	if starts.size() == 0:
		print("WARNING: No START holds found!")
		return Vector2(400, 300)  # Default fallback
	
	# If one start hold, spawn directly below it
	if starts.size() == 1:
		var hold_point = starts[0].get_node_or_null("HoldPoint")
		if hold_point:
			return hold_point.global_position + Vector2(0, 80)
		return starts[0].global_position + Vector2(0, 80)
	
	# If multiple start holds, spawn between them
	var sum = Vector2.ZERO
	for hold in starts:
		var hold_point = hold.get_node_or_null("HoldPoint")
		if hold_point:
			sum += hold_point.global_position
		else:
			sum += hold.global_position
	
	var center = sum / starts.size()
	return center + Vector2(0, 80)  # Spawn 80 pixels below the center

func validate_level() -> Dictionary:
	var result = {
		"valid": false,
		"has_start": false,
		"has_top": false,
		"start_count": 0,
		"top_count": 0,
		"total_holds": 0,
		"errors": []
	}
	
	result.total_holds = get_hold_count()
	
	if result.total_holds == 0:
		result.errors.append("No holds in level")
		return result
	
	var starts = get_start_holds()
	var tops = get_top_holds()
	
	result.start_count = starts.size()
	result.top_count = tops.size()
	result.has_start = result.start_count > 0
	result.has_top = result.top_count > 0
	
	if not result.has_start:
		result.errors.append("No START holds")
	if not result.has_top:
		result.errors.append("No TOP holds")
	
	result.valid = result.has_start and result.has_top
	
	return result
