extends Node2D
## Main game scene that manages level loading and player state

@export var default_level_path: String = "res://scenes/levels/tutorial/ladder.json"

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
	
	var initial_level = _get_initial_level()
	await _load_initial_level(initial_level)

# =============================================================================
# INITIAL LEVEL LOGIC
# =============================================================================

func _get_initial_level() -> String:
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("get_current_level"):
		var current_level = game_state.get_current_level()
		if current_level and current_level != "":
			return current_level
	
	return default_level_path

func _load_initial_level(path: String):
	# IMPORTANT: block until level is fully loaded
	if await level_loader.load_level(path):
		# Let holds finish _ready()
		await get_tree().process_frame
		await get_tree().process_frame
		
		var validation = level_loader.validate_level()
		if not validation.valid:
			return
		
		_current_level_path = path
		position_player_at_spawn()

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
# PUBLIC API
# =============================================================================

func get_current_level_path() -> String:
	return _current_level_path

func set_current_level_path(path: String) -> void:
	_current_level_path = path

# =============================================================================
# LEVEL EVENTS
# =============================================================================

func on_level_complete():
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("record_level_completion"):
		game_state.record_level_completion(_current_level_path, 0.0)
	
	await get_tree().create_timer(1.0).timeout
	Transition.to("res://scenes/menus/level_completed.tscn")

func on_player_reset():
	position_player_at_spawn()

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
