extends Node2D

@export var level_path: String = "res://scenes/levels/tutorial.json"

@onready var level_loader: LevelLoader = $LevelLoader
@onready var player: CharacterBody2D = $Character

func _ready():
	# Load the level specified in the export variable
	if level_path and level_path != "":
		load_and_start_level(level_path)
	else:
		# Fallback: check if GameState singleton has a level set
		var game_state = get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("get_current_level"):
			var current_level = game_state.get_current_level()
			if current_level:
				load_and_start_level(current_level)
			else:
				load_default_level()
		else:
			load_default_level()

func load_and_start_level(path: String):
	"""Load a level and position player at start holds"""
	
	if level_loader.load_level(path):
		# CRITICAL: Wait for holds to finish their _ready() before validating
		await get_tree().process_frame
		await get_tree().process_frame
		
		# Now validate
		var validation = level_loader.validate_level()
		if validation.valid:
			print("✓ Level valid: " + str(validation.start_count) + " START, " + str(validation.top_count) + " TOP")
			position_player_at_spawn()
		else:
			print("ERROR: Level is invalid!")
			for error in validation.errors:
				print("  - " + error)
	else:
		print("Failed to load level: " + path)

func load_default_level():
	"""Load a built-in default level"""
	var default_path = "res://levels/tutorial.json"
	
	if FileAccess.file_exists(default_path):
		load_and_start_level(default_path)
	else:
		print("No default level found at: " + default_path)
		create_minimal_level()

func create_minimal_level():
	"""Create a minimal test level for testing without a level file"""
	print("Creating minimal test level...")
	
	# Create a simple vertical climb
	var minimal_json = """
	{
		"holds": [
			{"type": "START", "x": 400, "y": 500},
			{"type": "JUG", "x": 450, "y": 400},
			{"type": "JUG", "x": 400, "y": 300},
			{"type": "TOP", "x": 400, "y": 200}
		]
	}
	"""
	
	# Parse and load
	var json = JSON.new()
	if json.parse(minimal_json) == OK:
		var level_data = json.data
		if "holds" in level_data:
			for hold_data in level_data.holds:
				level_loader.spawn_hold(hold_data)
			
			print("Created minimal test level")
			
			# Wait for holds to be ready
			await get_tree().process_frame
			await get_tree().process_frame
			
			position_player_at_spawn()

func position_player_at_spawn():
	"""Position player at the spawn point determined by start holds"""
	if not player:
		print("WARNING: No player node found")
		return
	
	# Get spawn position from level loader
	var spawn_pos = level_loader.get_player_spawn_position()
	player.global_position = spawn_pos
	player.spawn_position = spawn_pos  # Also set the player's spawn_position variable
	
	print("Player spawned at: " + str(spawn_pos))

func get_player_spawn_position() -> Vector2:
	"""Get spawn position - called by player during reset"""
	return level_loader.get_player_spawn_position()

func switch_to_level(path: String):
	"""Switch to a different level during gameplay"""
	level_path = path
	load_and_start_level(path)

func reload_current_level():
	"""Reload the current level (for restart)"""
	if level_path and level_path != "":
		load_and_start_level(level_path)

func on_level_complete():
	"""Called when player tops out"""
	print("🎉 LEVEL COMPLETE!")
	
	# Record completion in GameState if it exists
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("record_level_completion"):
		game_state.record_level_completion(level_path, 0.0)
