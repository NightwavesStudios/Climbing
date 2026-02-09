extends Node2D
## EXAMPLE: Main game scene with dynamic wall integration

@export var default_level_path: String = "res://scenes/levels/tutorial/ladder.json"

@onready var level_loader: LevelLoader = $LevelLoader
@onready var player: CharacterBody2D = $Character
@onready var camera: Camera2D = $Camera2D

var _current_level_path: String = ""
var dynamic_wall: Node2D = null  # Changed from DynamicWall to Node2D to avoid type issues

func _ready():
	print("=== MAIN SCENE READY ===")
	
	# Create dynamic wall
	_setup_dynamic_wall()
	
	# Connect to LevelTransition signals if it exists
	if has_node("/root/LevelTransition"):
		var lt = get_node("/root/LevelTransition")
		lt.transition_started.connect(_on_transition_started)
		lt.level_loaded.connect(_on_level_loaded)
		lt.transition_finished.connect(_on_transition_finished)
	
	var initial_level = _get_initial_level()
	print("Initial level to load: ", initial_level)
	
	await _load_initial_level(initial_level)
	
	print("=== MAIN SCENE READY COMPLETE ===")

# =============================================================================
# DYNAMIC WALL SETUP
# =============================================================================

func _setup_dynamic_wall():
	"""Create and configure the dynamic wall"""
	var wall_script = preload("res://scripts/holds/dynamic_wall.gd")
	dynamic_wall = wall_script.new()
	dynamic_wall.name = "DynamicWall"
	dynamic_wall.z_index = -10
	add_child(dynamic_wall)
	print("Dynamic wall created")

# =============================================================================
# INITIAL LEVEL LOGIC
# =============================================================================

func _get_initial_level() -> String:
	print("  Checking GameState for current level...")
	
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("get_current_level"):
		var current_level = game_state.get_current_level()
		print("  GameState.current_level = ", current_level)
		
		if current_level and current_level != "":
			print("  Using level from GameState")
			return current_level
	
	print("  Using default level")
	return default_level_path

func _load_initial_level(path: String):
	print("  Loading level: ", path)
	
	# IMPORTANT: Set _current_level_path BEFORE loading
	_current_level_path = path
	
	# IMPORTANT: block until level is fully loaded
	if await level_loader.load_level(path):
		# Let holds finish _ready()
		await get_tree().process_frame
		await get_tree().process_frame
		
		# UPDATE DYNAMIC WALL BOUNDS
		_update_wall_bounds()
		
		var validation = level_loader.validate_level()
		if not validation.valid:
			print("  ERROR: Level validation failed!")
			return
		
		print("  Level loaded successfully: ", path)
		position_player_at_spawn()
		center_camera_on_route()
	else:
		print("  ERROR: Failed to load level: ", path)

func _update_wall_bounds():
	"""Calculate and apply wall bounds from loaded holds"""
	if not dynamic_wall:
		print("  WARNING: No dynamic wall!")
		return
	
	var holds_container = level_loader.get_node_or_null("Holds")
	if not holds_container:
		print("  WARNING: No holds container!")
		return
	
	print("  Calculating wall bounds from " + str(holds_container.get_child_count()) + " holds")
	
	# Call the method on dynamic_wall
	if dynamic_wall.has_method("calculate_bounds_from_holds"):
		dynamic_wall.calculate_bounds_from_holds(holds_container)
	
	# Get and print bounds
	if dynamic_wall.has_method("get_bounds"):
		var bounds = dynamic_wall.get_bounds()
		if bounds.valid:
			print("  Wall bounds: " + str(bounds.min) + " to " + str(bounds.max))
			if dynamic_wall.has_method("get_wall_width") and dynamic_wall.has_method("get_wall_height"):
				print("  Wall size: " + str(dynamic_wall.get_wall_width()) + "x" + str(dynamic_wall.get_wall_height()) + "px")

# =============================================================================
# PLAYER SPAWN
# =============================================================================

func position_player_at_spawn():
	if not player:
		return
	
	var spawn_pos = level_loader.get_player_spawn_position()
	player.global_position = spawn_pos
	
	if player.has_method("set_spawn_position"):
		player.set_spawn_position(spawn_pos)

# =============================================================================
# CAMERA
# =============================================================================

func center_camera_on_route():
	"""Center camera on the route"""
	if not camera or not dynamic_wall:
		return
	
	if not dynamic_wall.has_method("get_bounds"):
		return
	
	var bounds = dynamic_wall.get_bounds()
	if not bounds.valid:
		return
	
	# Center on the middle of the wall
	var center_x = (bounds.min.x + bounds.max.x) / 2.0
	var center_y = (bounds.min.y + bounds.max.y) / 2.0
	
	camera.position = Vector2(center_x, center_y)
	
	# Optionally zoom out to fit entire wall
	if dynamic_wall.has_method("get_wall_height"):
		var wall_height = dynamic_wall.get_wall_height()
		var viewport_height = get_viewport_rect().size.y
		
		if wall_height > viewport_height * 0.8:
			# Zoom out if wall is tall
			var zoom_factor = viewport_height / (wall_height * 1.2)
			camera.zoom = Vector2(zoom_factor, zoom_factor)
		else:
			camera.zoom = Vector2(1.0, 1.0)

# =============================================================================
# TOP-OUT DETECTION (for granite routes)
# =============================================================================

func check_player_top_out() -> bool:
	"""Check if player has topped out on granite routes"""
	if not player or not dynamic_wall:
		return false
	
	if not dynamic_wall.has_method("get_top_edge_y"):
		return false
	
	# Only for granite environment
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if not env_config or env_config.get_current_environment() != 1:
		return false
	
	var top_y = dynamic_wall.get_top_edge_y()
	var tolerance = 50.0  # 50px above top edge counts as topped out
	
	return player.global_position.y < (top_y + tolerance)

# Call this from your level completion check:
func _process(delta):
	# Your existing process logic...
	
	# Check for top-out (if you want automatic detection)
	if check_player_top_out():
		# Optional: auto-complete level when player reaches top
		# on_level_complete()
		pass

# =============================================================================
# PUBLIC API
# =============================================================================

func get_current_level_path() -> String:
	return _current_level_path

func set_current_level_path(path: String) -> void:
	print("  MainScene: set_current_level_path called with: ", path)
	_current_level_path = path

# =============================================================================
# LEVEL EVENTS
# =============================================================================

func on_level_complete():
	print("=== LEVEL COMPLETE ===")
	print("Completed level: ", _current_level_path)
	
	if _current_level_path == "":
		push_error("ERROR: _current_level_path is empty! Cannot record completion.")
		return
	
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("record_level_completion"):
		game_state.record_level_completion(_current_level_path, 0.0)
	
	await get_tree().create_timer(1.0).timeout
	
	print("Transitioning to level_completed.tscn")
	Transition.to("res://scenes/menus/level_completed.tscn")

func on_player_reset():
	position_player_at_spawn()
	center_camera_on_route()

# =============================================================================
# TRANSITION CALLBACKS
# =============================================================================

func _on_transition_started():
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)

func _on_level_loaded():
	pass

func _on_transition_finished():
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)
