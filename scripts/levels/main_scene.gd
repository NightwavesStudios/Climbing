extends Node2D
## Main game scene with dynamic wall integration and climbing disciplines

@export var default_level_path: String = "res://scenes/levels/tutorial/ladder.json"

@onready var level_loader: LevelLoader = $LevelLoader
@onready var player: CharacterBody2D = $Character
@onready var camera: Camera2D = $Camera2D

var _current_level_path: String = ""
var dynamic_wall: Node2D = null

# Discipline systems
var rope_system: Node2D = null
var speed_timer: CanvasLayer = null
var current_discipline: int = 0  # 0=Boulder, 1=Roped, 2=Speed

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
			print("  WARNING: Level validation failed, but continuing anyway")
			for error in validation.errors:
				print("    - " + error)
		else:
			print("  ✓ Level validation passed")
		
		print("  Level loaded successfully: ", path)
		
		# Setup discipline-specific systems (even if validation failed)
		await setup_discipline_systems()
		
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
# DISCIPLINE SYSTEM SETUP
# =============================================================================

func setup_discipline_systems():
	"""Initialize discipline-specific systems"""
	
	# Get discipline from level loader
	if not level_loader:
		print("WARNING: LevelLoader not found")
		return
	
	var discipline_str = level_loader.get_discipline()
	current_discipline = ClimbingDiscipline.from_string(discipline_str)
	
	print("\n═══ DISCIPLINE SETUP ═══")
	print("Discipline: " + ClimbingDiscipline.get_display_name(current_discipline))
	
	# Get player
	if not player:
		print("ERROR: Player not found!")
		return
	
	# Set discipline on player
	if player.has_method("set_climbing_discipline"):
		player.set_climbing_discipline(current_discipline)
	
	match current_discipline:
		ClimbingDiscipline.Type.BOULDERING:
			setup_bouldering()
		
		ClimbingDiscipline.Type.ROPED:
			await setup_roped_climbing(level_loader, player)
		
		ClimbingDiscipline.Type.SPEED:
			setup_speed_climbing(level_loader, player)
	
	print("═══════════════════════\n")

func setup_bouldering():
	"""Setup for bouldering (no special systems needed)"""
	print("  Mode: Standard bouldering")

func setup_roped_climbing(loader, plyr):
	"""Setup rope system for roped climbing"""
	print("  Mode: Roped climbing")
	
	var belayer_pos = loader.get_belayer_position()
	
	if belayer_pos == Vector2.ZERO:
		print("  WARNING: No belayer position set, using default")
		# Use bottom-center of wall as fallback
		var wall_bounds = loader.get_wall_bounds()
		if wall_bounds.valid:
			belayer_pos = Vector2(
				(wall_bounds.min.x + wall_bounds.max.x) / 2,
				wall_bounds.max.y - 50
			)
		else:
			# Ultimate fallback
			belayer_pos = plyr.global_position + Vector2(0, 200)
	
	# Only create rope system if it doesn't exist
	if not rope_system or not is_instance_valid(rope_system):
		print("  Creating rope system...")
		
		# Load rope system script dynamically
		var RopeSystemScript = load("res://scripts/systems/rope_system.gd")
		if not RopeSystemScript:
			print("  ERROR: Could not load rope_system.gd!")
			return
		
		rope_system = RopeSystemScript.new()
		rope_system.name = "RopeSystem"
		
		# IMPORTANT: Add to scene tree BEFORE calling setup_rope
		add_child(rope_system)
		
		# Wait one frame for rope system to initialize
		await get_tree().process_frame
		
		print("  ✓ Rope system created")
	else:
		print("  Using existing rope system")
	
	# Always setup the rope (even if system already exists)
	if rope_system.has_method("setup_rope"):
		rope_system.setup_rope(belayer_pos, plyr)
	else:
		print("  ERROR: rope_system missing setup_rope method!")
	
	# Attach to player
	if plyr.has_method("set_rope_system"):
		plyr.set_rope_system(rope_system)
		print("  Rope system attached to player")
	
	print("  ✓ Rope system ready at: ", belayer_pos)

func setup_speed_climbing(loader, plyr):
	"""Setup timer for speed climbing"""
	print("  Mode: Speed climbing")
	
	var time_limit = loader.get_speed_time_limit()
	
	print("  Creating speed timer UI...")
	
	# Load speed timer script dynamically
	var SpeedTimerScript = load("res://scripts/levels/speed_timer.gd")
	if not SpeedTimerScript:
		print("  ERROR: Could not load speed_timer.gd!")
		return
	
	speed_timer = SpeedTimerScript.new()
	speed_timer.name = "SpeedTimer"
	
	# Add to scene tree
	add_child(speed_timer)
	
	# Wait for it to be ready
	await get_tree().process_frame
	
	# Configure timer
	if speed_timer.has_method("set_time_limit"):
		speed_timer.set_time_limit(time_limit)
	
	# Connect signals
	if speed_timer.has_signal("time_expired"):
		speed_timer.time_expired.connect(_on_speed_time_expired)
	if speed_timer.has_signal("time_warning"):
		speed_timer.time_warning.connect(_on_speed_time_warning)
	if speed_timer.has_signal("timer_started_signal"):
		speed_timer.timer_started_signal.connect(_on_speed_timer_started)
	
	# Attach to player
	if plyr.has_method("set_speed_timer"):
		plyr.set_speed_timer(speed_timer)
		print("  Speed timer attached to player")
	
	# Make sure it's visible
	speed_timer.visible = true
	if speed_timer.has_method("show_timer"):
		speed_timer.show_timer()
	
	print("  ✓ Speed timer created: ", time_limit, " seconds")

# =============================================================================
# SPEED CLIMBING CALLBACKS
# =============================================================================

func _on_speed_time_expired():
	"""Handle speed climbing time running out"""
	print("⏰ TIME'S UP! Speed climb failed.")
	
	# Show failure message
	show_message("TIME'S UP!", Color.RED)
	
	# Reset after delay
	await get_tree().create_timer(2.0).timeout
	reset_level()

func _on_speed_time_warning(seconds: float):
	"""Handle speed climbing warnings"""
	if seconds <= 5.0:
		show_message(str(int(seconds)) + "!", Color.ORANGE)

func _on_speed_timer_started():
	"""Handle speed timer starting"""
	print("🏃 Speed climb started!")

# =============================================================================
# PLAYER SPAWN
# =============================================================================

func position_player_at_spawn():
	if not player:
		print("ERROR: No player found in position_player_at_spawn!")
		return
	
	if not level_loader:
		print("ERROR: No level_loader found in position_player_at_spawn!")
		return
	
	var spawn_pos = level_loader.get_player_spawn_position()
	print("\n═══ PLAYER SPAWN ═══")
	print("Spawn position retrieved: ", spawn_pos)
	
	if spawn_pos == Vector2.ZERO:
		print("⚠️  WARNING: Spawn position is (0,0) - start hold may not be found!")
		print("Attempting manual start hold search...")
		
		# Try to find start holds manually as fallback
		var holds_container = level_loader.get_node_or_null("Holds")
		if holds_container:
			var hold_count = holds_container.get_child_count()
			print("Found holds container with ", hold_count, " children")
			
			var start_holds_found = []
			for hold in holds_container.get_children():
				if hold.has_method("is_start_hold") and hold.is_start_hold():
					start_holds_found.append(hold)
			
			if start_holds_found.size() > 0:
				print("✓ Found ", start_holds_found.size(), " start hold(s)")
				# Use the center of all start holds
				var total_pos = Vector2.ZERO
				for hold in start_holds_found:
					total_pos += hold.global_position
					print("  - Start hold at: ", hold.global_position)
				spawn_pos = total_pos / start_holds_found.size()
				print("✓ Using average position: ", spawn_pos)
			else:
				print("✗ No start holds found in manual search!")
				if hold_count > 0:
					print("Listing first 5 holds and their types:")
					for i in min(5, hold_count):
						var hold = holds_container.get_child(i)
						var is_start = hold.has_method("is_start_hold") and hold.is_start_hold()
						var hold_type = hold.get("hold_type") if "hold_type" in hold else "unknown"
						print("  [%d] Position: %s, Type: %s, IsStart: %s" % [i, hold.global_position, hold_type, is_start])
		else:
			print("✗ ERROR: No holds container found!")
		
		if spawn_pos == Vector2.ZERO:
			print("✗ CRITICAL: Could not find any start holds! Player will spawn at origin (0,0)")
			print("  Check that:")
			print("  1. Level JSON has holds marked as 'start'")
			print("  2. Hold script has is_start_hold() method")
			print("  3. Holds are being loaded correctly")
	else:
		print("✓ Valid spawn position found")
	
	player.global_position = spawn_pos
	print("Player positioned at: ", player.global_position)
	
	if player.has_method("set_spawn_position"):
		player.set_spawn_position(spawn_pos)
		print("✓ Spawn position set on player")
	
	print("═══════════════════\n")

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
		#var wall_height = dynamic_wall.get_wall_height()
		#var viewport_height = get_viewport_rect().size.y
		
		#if wall_height > viewport_height * 0.8:
			# Zoom out if wall is tall
			#var zoom_factor = viewport_height / (wall_height * 1.2)
			#camera.zoom = Vector2(zoom_factor, zoom_factor)
		#else:
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

func _process(_delta):
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
	
	# Get completion time for speed climbing
	var completion_time = 0.0
	if current_discipline == ClimbingDiscipline.Type.SPEED and speed_timer:
		if speed_timer.has_method("get_time_remaining"):
			completion_time = speed_timer.get_time_remaining()
			print("  Speed climb time remaining: ", completion_time, "s")
	
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("record_level_completion"):
		game_state.record_level_completion(_current_level_path, completion_time)
	
	# Cleanup discipline systems
	cleanup_discipline_systems()
	
	await get_tree().create_timer(1.0).timeout
	
	print("Transitioning to level_completed.tscn")
	Transition.to("res://scenes/menus/level_completed.tscn")

func on_player_reset():
	"""Called when player falls on crashpad - does NOT clean up rope system"""
	print("Player reset requested (from crashpad)")
	
	# Just reset player position and state
	position_player_at_spawn()
	center_camera_on_route()
	
	# Reset player state if method exists
	if player and player.has_method("reset_climb"):
		player.reset_climb()
	
	# Reset speed timer if active (but don't delete it)
	if current_discipline == ClimbingDiscipline.Type.SPEED and speed_timer:
		if speed_timer.has_method("stop_timer"):
			speed_timer.stop_timer()
	
	# NOTE: Rope system is NOT deleted here - it persists across resets!

func on_climb_start():
	"""Called when player makes first move"""
	print("🎬 First grab detected - climb started!")
	
	# Start speed timer if in speed mode
	if current_discipline == ClimbingDiscipline.Type.SPEED:
		if speed_timer and speed_timer.has_method("start_timer"):
			speed_timer.start_timer()
	
	# Notify all holds that climb has started
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("notify_climb_start"):
			hold.notify_climb_start()

func reset_level():
	"""Reset the current level - full reload"""
	print("Resetting level...")
	
	cleanup_discipline_systems()
	
	# Reload level
	if _current_level_path != "":
		await _load_initial_level(_current_level_path)
	else:
		position_player_at_spawn()
		center_camera_on_route()

# =============================================================================
# DISCIPLINE CLEANUP
# =============================================================================

func cleanup_discipline_systems():
	"""Clean up discipline-specific systems - ONLY called on level change"""
	
	if rope_system and is_instance_valid(rope_system):
		if rope_system.has_method("cleanup"):
			rope_system.cleanup()
		else:
			rope_system.queue_free()
		rope_system = null
	
	if speed_timer and is_instance_valid(speed_timer):
		if speed_timer.has_method("cleanup"):
			speed_timer.cleanup()
		else:
			speed_timer.queue_free()
		speed_timer = null
	
	current_discipline = 0
	print("Discipline systems cleaned up")

# =============================================================================
# HELPER TO SHOW MESSAGES
# =============================================================================

func show_message(text: String, color: Color = Color.WHITE):
	"""Show temporary message on screen"""
	var label = Label.new()
	label.text = text
	label.position = Vector2(get_viewport().size.x / 2 - 100, 200)
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(label):
		label.queue_free()

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
