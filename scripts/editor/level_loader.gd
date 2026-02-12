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

const CRASHPAD_SCENE = "res://scenes/props/crashpad.tscn"

var loaded_scenes: Dictionary = {}
var holds_container: Node2D
var crashpads_container: Node2D
var dynamic_wall: Node2D = null

# Current level metadata
var current_level_name: String = ""
var current_level_grade: String = ""
var current_level_environment: String = "gym"

# =============================================================================
# READY
# =============================================================================
func _ready():
	# Load hold scenes
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
	
	# Create crashpads container
	if not has_node("Crashpads"):
		crashpads_container = Node2D.new()
		crashpads_container.name = "Crashpads"
		add_child(crashpads_container)
	else:
		crashpads_container = get_node("Crashpads")
	
	# Defer dynamic wall creation to avoid "parent busy"
	call_deferred("_create_dynamic_wall")

# =============================================================================
# DYNAMIC WALL
# =============================================================================
func _create_dynamic_wall():
	var wall_script = preload("res://scripts/holds/dynamic_wall.gd")
	dynamic_wall = wall_script.new()
	dynamic_wall.name = "DynamicWall"
	dynamic_wall.z_index = -10
	# Safely add to parent
	get_parent().add_child(dynamic_wall)

# Update bounds
func update_wall_bounds():
	if dynamic_wall:
		dynamic_wall.calculate_bounds_from_holds(holds_container)

func get_wall_bounds() -> Dictionary:
	if dynamic_wall and dynamic_wall.has_method("get_bounds"):
		return dynamic_wall.get_bounds()
	return {"min": Vector2.ZERO, "max": Vector2.ZERO, "valid": false}

func get_dynamic_wall() -> Node2D:
	return dynamic_wall

# =============================================================================
# LEVEL LOADING
# =============================================================================
func load_level(path: String) -> bool:
	"""Load a .json level file"""
	clear_holds()
	clear_crashpads()
	
	# Load JSON
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
	
	print("Setting environment to: " + current_level_environment)
	set_environment_from_string(current_level_environment)
	
	# Wait one frame for environment to update
	await get_tree().process_frame
	
	# Store metadata in GameState
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("set_climb_metadata"):
		game_state.set_climb_metadata(path, current_level_name, current_level_grade)
	
	# Spawn holds
	print("\n=== SPAWNING HOLDS ===")
	
	for hold_data in level_data.holds:
		spawn_hold(hold_data)
		await get_tree().process_frame
	
	# Wait for all holds to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Force update all holds for environment
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("_update_sprite_for_environment"):
			hold._update_sprite_for_environment()
	
	# Load crashpads
	load_crashpads(level_data)
	
	# Update dynamic wall bounds
	update_wall_bounds()
	
	print("\n═══════════════════════════════════════")
	print("✓ LEVEL LOADED: " + path)
	if current_level_name != "":
		print("  Name: " + current_level_name + " (" + current_level_grade + ")")
	print("  Environment: " + current_level_environment)
	print("  Holds: " + str(level_data.holds.size()))
	if "crashpads" in level_data:
		print("  Crashpads: " + str(level_data.crashpads.size()))
	print("═══════════════════════════════════════\n")
	
	return true

# =============================================================================
# ENVIRONMENT
# =============================================================================
func set_environment_from_string(env_name: String):
	if not has_node("/root/EnvironmentConfig"):
		print("WARNING: EnvironmentConfig not available")
		return
	
	var env_config = get_node("/root/EnvironmentConfig")
	match env_name.to_lower():
		"gym":
			env_config.set_environment(0)
			print("Level environment set to: GYM")
		"granite":
			env_config.set_environment(1)
			print("Level environment set to: GRANITE")
		_:
			print("WARNING: Unknown environment: " + env_name + ", defaulting to gym")
			env_config.set_environment(0)
	
	if dynamic_wall and dynamic_wall.has_method("update_environment"):
		dynamic_wall.update_environment()

# =============================================================================
# HOLDS
# =============================================================================
func spawn_hold(hold_data: Dictionary) -> Node2D:
	var type_name = hold_data.get("type", "JUG")
	if type_name not in loaded_scenes:
		print("WARNING: Unknown hold type: " + type_name)
		return null
	
	var hold = loaded_scenes[type_name].instantiate()
	hold.global_position = Vector2(hold_data.get("x", 0.0), hold_data.get("y", 0.0))
	
	if hold.has_method("set_hold_type_from_string"):
		hold.set_hold_type_from_string(type_name)
	
	holds_container.add_child(hold)
	hold.add_to_group("holds")
	return hold

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
	var starts = get_start_holds()
	if starts.size() == 0:
		print("WARNING: No START holds found!")
		return Vector2(400, 300)
	
	if starts.size() == 1:
		var hold_point = starts[0].get_node_or_null("HoldPoint")
		if hold_point:
			return hold_point.global_position + Vector2(0, 80)
		return starts[0].global_position + Vector2(0, 80)
	
	var sum = Vector2.ZERO
	for hold in starts:
		var hold_point = hold.get_node_or_null("HoldPoint")
		if hold_point:
			sum += hold_point.global_position
		else:
			sum += hold.global_position
	
	return sum / starts.size() + Vector2(0, 80)

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

# =============================================================================
# CRASHPADS
# =============================================================================
func load_crashpads(level_data: Dictionary) -> void:
	"""Load crashpads from level data"""
	if not "crashpads" in level_data:
		print("  No crashpads in level data")
		return
	
	if not crashpads_container:
		crashpads_container = Node2D.new()
		crashpads_container.name = "Crashpads"
		add_child(crashpads_container)
		print("  Created Crashpads container")
	
	# Check if crashpad scene exists
	if not ResourceLoader.exists(CRASHPAD_SCENE):
		push_error("Crashpad scene not found at: " + CRASHPAD_SCENE)
		return
	
	var crashpad_scene = load(CRASHPAD_SCENE)
	var crashpad_count = 0
	
	print("\n=== SPAWNING CRASHPADS ===")
	
	for crashpad_data in level_data.crashpads:
		var crashpad = crashpad_scene.instantiate()
		crashpad.global_position = Vector2(
			crashpad_data.get("x", 0),
			crashpad_data.get("y", 0)
		)
		crashpads_container.add_child(crashpad)
		crashpad.add_to_group("crashpads")
		crashpad_count += 1
		
		print("  Spawned crashpad at: " + str(crashpad.global_position))
	
	# Wait for crashpads to be ready
	await get_tree().process_frame
	
	# Force update crashpads for environment
	for crashpad in get_tree().get_nodes_in_group("crashpads"):
		if crashpad.has_method("_update_sprite_for_environment"):
			crashpad._update_sprite_for_environment()
	
	print("  Loaded " + str(crashpad_count) + " crashpads")

func clear_crashpads():
	if crashpads_container:
		for child in crashpads_container.get_children():
			child.queue_free()

func get_crashpad_count() -> int:
	return crashpads_container.get_child_count() if crashpads_container else 0
