extends Node
## Autoload singleton for managing level transitions with fade effects
## Usage: LevelTransition.to("res://levels/level_2.json")

signal transition_started
signal level_loaded
signal transition_finished

@export var fade_scene_path: String = "res://scenes/menus/fade.tscn"

var _fade_instance: CanvasLayer
var _next_level_path: String = ""
var _is_transitioning: bool = false

func _ready() -> void:
	# Load and setup fade overlay
	_fade_instance = load(fade_scene_path).instantiate()
	add_child(_fade_instance)
	_fade_instance.layer = 1000  # Ensure it's on top
	_fade_instance.color_rect.visible = false

## Load a new level with fade transition
func to(level_path: String) -> void:
	if _is_transitioning:
		print("WARNING: Transition already in progress")
		return
	
	if level_path == "":
		push_error("Invalid level path")
		return
	
	_is_transitioning = true
	_next_level_path = level_path
	
	emit_signal("transition_started")
	
	# Start fade out
	if _fade_instance.has_node("AnimationPlayer"):
		var anim_player = _fade_instance.get_node("AnimationPlayer")
		anim_player.speed_scale = 1.0
	
	_fade_instance.fade_out()
	_fade_instance.fade_out_finished.connect(_on_fade_out_finished, CONNECT_ONE_SHOT)

## Reload current level with fade
func reload() -> void:
	var game_scene = get_tree().current_scene
	if game_scene and game_scene.has_method("get_current_level_path"):
		var current_path = game_scene.get_current_level_path()
		to(current_path)
	else:
		push_error("Cannot reload: current scene doesn't provide level path")

func _on_fade_out_finished() -> void:
	_load_level(_next_level_path)

func _load_level(level_path: String) -> void:
	var game_scene = get_tree().current_scene
	
	if not game_scene:
		push_error("No current scene found")
		_finish_transition(false)
		return
	
	# Find the LevelLoader in the scene
	var level_loader = _find_level_loader(game_scene)
	if not level_loader:
		push_error("No LevelLoader found in current scene")
		_finish_transition(false)
		return
	
	# Load the level
	var success = level_loader.load_level(level_path)
	if not success:
		push_error("Failed to load level: " + level_path)
		_finish_transition(false)
		return
	
	# Wait for holds to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Validate level
	var validation = level_loader.validate_level()
	if not validation.valid:
		push_error("Level validation failed: " + level_path)
		for error in validation.errors:
			print("  - " + error)
		_finish_transition(false)
		return
	
	# Update the game scene's level path
	if game_scene.has_method("set_current_level_path"):
		game_scene.set_current_level_path(level_path)
	
	# Position player at spawn
	if game_scene.has_method("position_player_at_spawn"):
		game_scene.position_player_at_spawn()
	
	print("✓ Level loaded: " + level_path + " (" + str(validation.start_count) + " START, " + str(validation.top_count) + " TOP)")
	
	emit_signal("level_loaded")
	_finish_transition(true)

func _finish_transition(success: bool) -> void:
	# Fade back in
	_fade_instance.fade_in()
	await _fade_instance.fade_in_finished
	
	_is_transitioning = false
	emit_signal("transition_finished")

func _find_level_loader(node: Node) -> Node:
	"""Recursively find LevelLoader node"""
	if node.get_class() == "LevelLoader" or node.name == "LevelLoader":
		return node
	
	for child in node.get_children():
		var result = _find_level_loader(child)
		if result:
			return result
	
	return null

## Check if a transition is currently happening
func is_transitioning() -> bool:
	return _is_transitioning
