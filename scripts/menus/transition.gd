extends Node

signal transition_started
signal transition_finished

@export var fade_scene_path: String = "res://scenes/menus/fade.tscn"

var _fade_instance: CanvasLayer
var _is_transitioning: bool = false
var _next_scene_path: String = ""

func _ready() -> void:
	_fade_instance = load(fade_scene_path).instantiate()
	add_child(_fade_instance)
	_fade_instance.layer = 1000
	_fade_instance.color_rect.visible = false

func to(scene_path: String) -> void:
	if _is_transitioning:
		print("WARNING: Transition already in progress")
		return
	
	if scene_path == "":
		push_error("Invalid scene path")
		return
	
	_is_transitioning = true
	_next_scene_path = scene_path
	
	emit_signal("transition_started")
	
	# Connect fade out finished
	if not _fade_instance.fade_out_finished.is_connected(_on_fade_out_finished):
		_fade_instance.fade_out_finished.connect(_on_fade_out_finished, CONNECT_ONE_SHOT)
	
	_fade_instance.fade_out()

func _on_fade_out_finished() -> void:
	# Screen is now BLACK - load new scene while black
	await _load_scene(_next_scene_path)

func _load_scene(scene_path: String) -> void:
	print("Transition: Loading scene: " + scene_path)
	
	# Get current scene
	var old_scene = get_tree().current_scene
	
	# Load new scene
	var new_scene_res = ResourceLoader.load(scene_path)
	if not new_scene_res:
		push_error("Failed to load scene: " + scene_path)
		await _finish_transition(false)
		return
	
	var new_scene = new_scene_res.instantiate()
	if not new_scene:
		push_error("Failed to instantiate scene: " + scene_path)
		await _finish_transition(false)
		return
	
	# Hide new scene until ready
	new_scene.visible = false
	
	# Add new scene to tree
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	
	# CRITICAL: Wait for new scene to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Remove old scene (this fixes the overlay issue!)
	if old_scene and is_instance_valid(old_scene):
		print("Transition: Removing old scene: " + old_scene.name)
		old_scene.queue_free()
	
	# Wait for old scene to be fully removed
	await get_tree().process_frame
	
	# Show new scene
	new_scene.visible = true
	
	print("Transition: Scene loaded successfully")
	
	# Fade in
	await _finish_transition(true)

func _finish_transition(success: bool) -> void:
	# Small pause before fade in
	await get_tree().create_timer(0.1).timeout
	
	# Fade in (black → transparent)
	_fade_instance.fade_in()
	await _fade_instance.fade_in_finished
	
	_is_transitioning = false
	emit_signal("transition_finished")

func is_transitioning() -> bool:
	return _is_transitioning

func reload() -> void:
	"""Reload current scene"""
	var current_path = get_tree().current_scene.scene_file_path
	if current_path:
		to(current_path)
	else:
		push_error("Cannot reload: current scene has no file path")
