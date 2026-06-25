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
	_fade_instance = load(fade_scene_path).instantiate()
	add_child(_fade_instance)
	_fade_instance.layer = 1000
	_fade_instance.color_rect.visible = false

func to(scene_path: String, level_path: String = "") -> void:
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

	_fade_instance.fade_out_finished.connect(_on_fade_out_finished, CONNECT_ONE_SHOT)
	_fade_instance.fade_out()

func reload() -> void:
	var game_scene = get_tree().current_scene
	if game_scene and game_scene.has_method("get_current_level_path"):
		var level_path = game_scene.get_current_level_path()
		to("res://scenes/main/main_scene.tscn", level_path)
	else:
		push_error("Cannot reload: current scene doesn't provide level path")

func _on_fade_out_finished() -> void:
	if _next_scene_path == "res://scenes/main/main_scene.tscn" and _next_level_path != "":
		await _load_level_scene(_next_scene_path, _next_level_path)
	else:
		await _load_simple_scene(_next_scene_path)

func _load_simple_scene(scene_path: String) -> void:
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_error("Failed to load scene: " + scene_path)
		await _finish_transition(false)
		return

	var new_scene = packed_scene.instantiate()
	new_scene.visible = false

	get_tree().root.add_child(new_scene)

	var old_scene = get_tree().current_scene
	get_tree().current_scene = new_scene

	await get_tree().process_frame

	if old_scene and old_scene != new_scene:
		old_scene.queue_free()

	await get_tree().process_frame

	new_scene.visible = true

	await _finish_transition(true)

func _load_level_scene(scene_path: String, level_path: String) -> void:
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_error("Failed to load scene: " + scene_path)
		await _finish_transition(false)
		return

	var new_scene = packed_scene.instantiate()
	new_scene.name = "GameScene"
	new_scene.visible = false

	get_tree().root.add_child(new_scene)

	var old_scene = get_tree().current_scene
	get_tree().current_scene = new_scene

	if new_scene.has_method("set_current_level_path"):
		new_scene.set_current_level_path(level_path)

	var loader = _find_level_loader(new_scene)
	if not loader:
		push_error("No LevelLoader in new scene")
		await _finish_transition(false)
		return

	var success = await loader.load_level(level_path)
	if not success:
		push_error("Failed to load level: " + level_path)
		await _finish_transition(false)
		return

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var validation = loader.validate_level()
	if not validation.valid:
		push_error("Level validation failed: " + level_path)
		for err in validation.errors:
			print("  - " + err)
		await _finish_transition(false)
		return

	if new_scene.has_method("position_player_at_spawn"):
		new_scene.position_player_at_spawn()

	if old_scene and old_scene != new_scene:
		old_scene.queue_free()

	await get_tree().process_frame

	new_scene.visible = true

	print("✓ Level loaded: " + level_path)
	emit_signal("level_loaded")

	await _finish_transition(true)

func _finish_transition(_success: bool) -> void:
	await get_tree().create_timer(0.1).timeout
	_fade_instance.fade_in()
	await _fade_instance.fade_in_finished
	_is_transitioning = false
	emit_signal("transition_finished")

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

func fade_out_only() -> void:
	_fade_instance.fade_out()
	await _fade_instance.fade_out_finished

func fade_in_only() -> void:
	_fade_instance.fade_in()
	await _fade_instance.fade_in_finished
