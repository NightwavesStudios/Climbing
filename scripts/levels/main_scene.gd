extends Node2D
## Main game scene that manages level loading and player state

@export var default_level_path: String = "res://scenes/levels/tutorial.json"

@onready var level_loader: LevelLoader = $LevelLoader
@onready var player: CharacterBody2D = $Character

var _current_level_path: String = ""

func _ready():
	# Connect to LevelTransition signals if it exists
	if has_node("/root/LevelTransition"):
		var lt = get_node("/root/LevelTransition")
		lt.transition_started.connect(_on_transition_started)
		lt.level_loaded.connect(_on_level_loaded)
		lt.transition_finished.connect(_on_transition_finished)
	
	# Load initial level
	var initial_level = _get_initial_level()
	print("DEBUG: About to load initial level: " + initial_level)
	_load_initial_level(initial_level)

func _get_initial_level() -> String:
	"""Determine which level to load initially"""
	# Check if GameState has a level set
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("get_current_level"):
		var current_level = game_state.get_current_level()
		print("DEBUG: GameState returned: " + str(current_level))
		if current_level and current_level != "":
			return current_level
	
	# Use default
	print("DEBUG: Using default level: " + default_level_path)
	return default_level_path

func _load_initial_level(path: String):
	"""Load the very first level (no fade needed on startup)"""
	print("DEBUG: Attempting to load: " + path)
	print("DEBUG: File exists: " + str(FileAccess.file_exists(path)))
	
	if level_loader.load_level(path):
		# Wait for holds to finish their _ready()
		await get_tree().process_frame
		await get_tree().process_frame
		
		# Validate
		var validation = level_loader.validate_level()
		if validation.valid:
			_current_level_path = path
			print("✓ Initial level loaded: " + str(validation.start_count) + " START, " + str(validation.top_count) + " TOP")
			position_player_at_spawn()
		else:
			print("ERROR: Initial level is invalid!")
			for error in validation.errors:
				print("  - " + error)
	else:
		print("ERROR: Failed to load initial level: " + path)

func position_player_at_spawn():
	"""Position player at the spawn point determined by start holds"""
	if not player:
		print("WARNING: No player node found")
		return
	
	var spawn_pos = level_loader.get_player_spawn_position()
	player.global_position = spawn_pos
	
	if player.has_method("set_spawn_position"):
		player.set_spawn_position(spawn_pos)
	
	print("Player spawned at: " + str(spawn_pos))

# =============================================================================
# PUBLIC API for LevelTransition
# =============================================================================

func get_current_level_path() -> String:
	"""Get the currently loaded level path"""
	return _current_level_path

func set_current_level_path(path: String) -> void:
	"""Set the current level path (called by LevelTransition)"""
	_current_level_path = path

# =============================================================================
# LEVEL EVENTS
# =============================================================================

func on_level_complete():
	"""Called when player tops out"""
	print("🎉 LEVEL COMPLETE!")
	
	# Record completion in GameState if it exists
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("record_level_completion"):
		game_state.record_level_completion(_current_level_path, 0.0)
	
	# You could auto-load next level here:
	# LevelTransition.to("res://scenes/levels/next_level.json")

func on_player_reset():
	"""Called when player resets position"""
	position_player_at_spawn()

# =============================================================================
# TRANSITION CALLBACKS
# =============================================================================

func _on_transition_started():
	"""Called when level transition begins"""
	# Could disable player input here
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)

func _on_level_loaded():
	"""Called after new level data is loaded"""
	pass

func _on_transition_finished():
	"""Called when transition completes and fade-in finishes"""
	# Re-enable player input
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)
