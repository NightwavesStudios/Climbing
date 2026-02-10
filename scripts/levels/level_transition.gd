extends Node

signal transition_started
signal level_loaded
signal transition_finished

@export var fade_scene_path: String = "res://scenes/menus/fade.tscn"

var _fade_instance: CanvasLayer
var _is_transitioning: bool = false
var _next_level_path: String = ""
var _next_scene_path: String = ""

func _ready() -> void:
	# Load fade overlay
	_fade_instance = load(fade_scene_path).instantiate()
	add_child(_fade_instance)
	_fade_instance.layer = 1000
	_fade_instance.color_rect.visible = false

func to(scene_path: String, level_path: String = "") -> void:
	"""Load a scene, optionally with a level path for main_scene.tscn"""
	if _is_transitioning:
		print("WARNING: Transition already in progress")
		return
	
	if scene_path == "":
		push_error("Invalid scene path")
		return
	
	_is_transitioning = true
	_next_scene_path = scene_path
	_next_level_path = level_path
	
	emit_signal("transition_started")
	
	# Connect fade out finished
	_fade_instance.fade_out_finished.connect(_on_fade_out_finished, CONNECT_ONE_SHOT)
	_fade_instance.fade_out()

func reload() -> void:
	var game_scene = get_tree().current_scene
	if game_scene and game_scene.has_method("get_current_level_path"):
		var level_path = game_scene.get_current_level_path()
		to("res://scenes/main/main_scene.tscn", level_path)
	else:
		push_error("Cannot reload: current scene doesn't provide level path")

# --- Called when fade out completes ---
func _on_fade_out_finished() -> void:
	# Screen is now BLACK - load new scene while black
	if _next_scene_path == "res://scenes/main/main_scene.tscn" and _next_level_path != "":
		await _load_level_scene(_next_scene_path, _next_level_path)
	else:
		await _load_simple_scene(_next_scene_path)

# --- Load scene without level (menus, etc.) ---
func _load_simple_scene(scene_path: String) -> void:
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_error("Failed to load scene: " + scene_path)
		await _finish_transition(false)
		return
	
	var new_scene = packed_scene.instantiate()
	new_scene.visible = false  # Hide until fade in
	
	get_tree().root.add_child(new_scene)
	
	var old_scene = get_tree().current_scene
	get_tree().current_scene = new_scene
	
	# Wait a frame
	await get_tree().process_frame
	
	# Remove old scene
	if old_scene and old_scene != new_scene:
		old_scene.queue_free()
	
	await get_tree().process_frame
	
	# Show new scene
	new_scene.visible = true
	
	# Fade in
	await _finish_transition(true)

# --- Load scene and level ---
func _load_level_scene(scene_path: String, level_path: String) -> void:
	# Load packed scene
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_error("Failed to load scene: " + scene_path)
		await _finish_transition(false)
		return
	
	# Instantiate new scene
	var new_scene = packed_scene.instantiate()
	new_scene.name = "GameScene"
	
	# CRITICAL FIX: Hide new scene until we're ready to fade in
	new_scene.visible = false
	
	get_tree().root.add_child(new_scene)
	
	# Remember old scene
	var old_scene = get_tree().current_scene
	get_tree().current_scene = new_scene
	
	# Set level path in new scene
	if new_scene.has_method("set_current_level_path"):
		new_scene.set_current_level_path(level_path)
	
	# Find LevelLoader
	var loader = _find_level_loader(new_scene)
	if not loader:
		push_error("No LevelLoader in new scene")
		await _finish_transition(false)
		return
	
	# Load level
	var success = await loader.load_level(level_path)
	if not success:
		push_error("Failed to load level: " + level_path)
		await _finish_transition(false)
		return
	
	# Wait extra frames for level to fully initialize
	# This ensures holds are ready for character initial grab
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Validate level
	var validation = loader.validate_level()
	if not validation.valid:
		push_error("Level validation failed: " + level_path)
		for err in validation.errors:
			print("  - " + err)
		await _finish_transition(false)
		return
	
	# Position player
	if new_scene.has_method("position_player_at_spawn"):
		new_scene.position_player_at_spawn()
	
	# Remove old scene BEFORE making new scene visible
	if old_scene and old_scene != new_scene:
		old_scene.queue_free()
	
	# Wait one more frame to ensure old scene is fully removed
	await get_tree().process_frame
	
	# NOW show the new scene (still behind black fade overlay)
	new_scene.visible = true
	
	print("✓ Level loaded: " + level_path)
	emit_signal("level_loaded")
	
	# Now fade in to reveal the new scene
	await _finish_transition(true)

# --- Fade in and finish transition ---
func _finish_transition(success: bool) -> void:
	# CRITICAL: Wait a moment before fading in to avoid flicker
	await get_tree().create_timer(0.1).timeout
	
	# Fade in (black → transparent, revealing scene)
	_fade_instance.fade_in()
	await _fade_instance.fade_in_finished
	
	_is_transitioning = false
	emit_signal("transition_finished")

# --- Helper to find LevelLoader recursively ---
func _find_level_loader(node: Node) -> Node:
	if node.get_class() == "LevelLoader" or node.name == "LevelLoader":
		return node
	for child in node.get_children():
		var res = _find_level_loader(child)
		if res:
			return res
	return null

func is_transitioning() -> bool:
	return _is_transitioning
