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
var dynamic_wall: Node2D = null

# Current level metadata
var current_level_name: String = ""
var current_level_grade: String = ""
var current_level_environment: String = "gym"

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
	
	# Create dynamic wall
	_create_dynamic_wall()

func _create_dynamic_wall():
	var wall_script = preload("res://scripts/holds/dynamic_wall.gd")
	dynamic_wall = wall_script.new()
	dynamic_wall.name = "DynamicWall"
	dynamic_wall.z_index = -10
	get_parent().add_child(dynamic_wall)


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
	
	# Load metadata
	current_level_name = level_data.get("name", "")
	current_level_grade = level_data.get("grade", "")
	current_level_environment = level_data.get("environment", "gym")
	
	# CRITICAL: Set environment FIRST
	print("Setting environment to: " + current_level_environment)
	set_environment_from_string(current_level_environment)
	
	# Wait for environment to propagate
	await get_tree().process_frame
	
	# Store metadata in GameState
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("set_climb_metadata"):
		game_state.set_climb_metadata(path, current_level_name, current_level_grade)
	
	# Spawn holds AFTER environment is set
	for hold_data in level_data.holds:
		spawn_hold(hold_data)
	
	# CRITICAL: Wait for holds' deferred sprite updates to complete
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Force update all holds (just to be sure)
	print("Forcing all holds to update sprites...")
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("_update_sprite_for_environment"):
			hold._update_sprite_for_environment()
	
	# UPDATE DYNAMIC WALL BOUNDS
	update_wall_bounds()
	
	print("✓ Loaded: " + path)
	if current_level_name != "":
		print("  Name: " + current_level_name + " (" + current_level_grade + ")")
	print("  Environment: " + current_level_environment)
	print("  Holds: " + str(level_data.holds.size()))
	
	return true

func set_environment_from_string(env_name: String):
	"""Set the environment based on string from JSON"""
	if not has_node("/root/EnvironmentConfig"):
		print("WARNING: EnvironmentConfig not available")
		return
	
	var env_config = get_node("/root/EnvironmentConfig")
	
	match env_name.to_lower():
		"gym":
			env_config.set_environment(0)  # EnvironmentType.GYM
			print("Level environment set to: GYM")
		"granite":
			env_config.set_environment(1)  # EnvironmentType.GRANITE
			print("Level environment set to: GRANITE")
		_:
			print("WARNING: Unknown environment: " + env_name + ", defaulting to gym")
			env_config.set_environment(0)
	
	# Update wall appearance based on environment
	if dynamic_wall and dynamic_wall.has_method("update_environment"):
		dynamic_wall.update_environment()

# =============================================================================
# DYNAMIC WALL BOUNDS
# =============================================================================
func update_wall_bounds():
	dynamic_wall.calculate_bounds_from_holds(holds_container)

func get_wall_bounds() -> Dictionary:
	"""Get the current wall bounds (for camera positioning, etc.)"""
	if dynamic_wall and dynamic_wall.has_method("get_bounds"):
		return dynamic_wall.get_bounds()
	return {"min": Vector2.ZERO, "max": Vector2.ZERO, "valid": false}

func get_dynamic_wall() -> Node2D:
	"""Get reference to the dynamic wall"""
	return dynamic_wall

# =============================================================================
# HOLD SPAWNING
# =============================================================================

func spawn_hold(hold_data: Dictionary) -> Node2D:
	var type_name = hold_data.get("type", "JUG")
	if type_name not in loaded_scenes:
		print("WARNING: Unknown hold type: " + type_name)
		return null
	
	var hold = loaded_scenes[type_name].instantiate()
	hold.global_position = Vector2(hold_data.get("x", 0.0), hold_data.get("y", 0.0))
	
	# CRITICAL: Set the hold type BEFORE adding to tree
	# This way _ready() will see _type_was_set_manually = true
	if hold.has_method("set_hold_type_from_string"):
		hold.set_hold_type_from_string(type_name)
	
	# NOW add to tree - _ready() will respect the manual setting
	holds_container.add_child(hold)
	hold.add_to_group("holds")
	
	return hold

# =============================================================================
# METADATA GETTERS
# =============================================================================

func get_current_level_name() -> String:
	return current_level_name

func get_current_level_grade() -> String:
	return current_level_grade

func get_current_level_environment() -> String:
	return current_level_environment
	
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
