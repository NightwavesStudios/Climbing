extends Node
class_name TransitionManager

signal transition_started
signal transition_finished

@export var fade_scene_path := "res://scenes/menus/fade.tscn"

var _fade_instance: CanvasLayer

var _transitioning := false
var _target_scene := ""

func _ready() -> void:
	_create_fade()

func _create_fade() -> void:
	_fade_instance = load(fade_scene_path).instantiate()

	add_child(_fade_instance)

	_fade_instance.layer = 1000
	_fade_instance.color_rect.visible = false

func to(scene_path: String) -> void:
	if _transitioning:
		push_warning("Transition already active")
		return

	if scene_path.is_empty():
		push_error("Invalid scene path")
		return

	_transitioning = true
	_target_scene = scene_path

	transition_started.emit()

	_start_fade_out()

func reload() -> void:
	var current := get_tree().current_scene

	if current == null:
		push_error("Cannot reload scene")
		return

	to(current.scene_file_path)

func is_transitioning() -> bool:
	return _transitioning

func _start_fade_out() -> void:
	if !_fade_instance.fade_out_finished.is_connected(
		_on_fade_finished
	):
		_fade_instance.fade_out_finished.connect(
			_on_fade_finished,
			CONNECT_ONE_SHOT
		)

	_fade_instance.fade_out()

func _on_fade_finished() -> void:
	await _change_scene(_target_scene)


func _start_fade_in() -> void:
	_fade_instance.fade_in()

	await _fade_instance.fade_in_finished

func _change_scene(path: String) -> void:
	var new_scene := _load_scene(path)

	if new_scene == null:
		_finish_transition()
		return


	await _replace_scene(new_scene)

	await _start_fade_in()

	_finish_transition()

func _load_scene(path: String) -> Node:
	var resource := ResourceLoader.load(path)

	if resource == null:
		push_error("Could not load: " + path)
		return null


	return resource.instantiate()

func _replace_scene(new_scene: Node) -> void:
	var old_scene := get_tree().current_scene


	new_scene.visible = false

	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene


	await get_tree().process_frame


	if old_scene and is_instance_valid(old_scene):
		old_scene.queue_free()


	await get_tree().process_frame


	new_scene.visible = true

func _finish_transition() -> void:
	_transitioning = false

	transition_finished.emit()
