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


# ── Scene transitions (replace the current scene) ─────────────────────────

## Transition to another scene with a full fade-out, scene-swap, fade-in.
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


## Reload the current scene.
func reload() -> void:
	var current := get_tree().current_scene
	if current == null:
		push_error("Cannot reload scene")
		return
	to(current.scene_file_path)


func is_transitioning() -> bool:
	return _transitioning


# ── Fade-only helpers (no scene swap — for in-place reloads / next level) ─

## Fade to opaque without swapping scenes. The caller is responsible for
## making scene changes under the cover of the fade, then calling
## fade_in_only() to reveal the result.
func fade_out_only() -> void:
	if _transitioning:
		push_warning("Transition: fade_out_only skipped — already transitioning")
		return
	_transitioning = true
	transition_started.emit()
	_fade_instance.fade_out()
	await _fade_instance.fade_out_finished


## Fade back in after a fade_out_only(). Await this before continuing.
func fade_in_only() -> void:
	_fade_instance.fade_in()
	await _fade_instance.fade_in_finished
	_transitioning = false
	transition_finished.emit()


# ── Internal ──────────────────────────────────────────────────────────────

func _start_fade_out() -> void:
	if not _fade_instance.fade_out_finished.is_connected(_on_fade_finished):
		_fade_instance.fade_out_finished.connect(_on_fade_finished, CONNECT_ONE_SHOT)
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
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	if old_scene and is_instance_valid(old_scene):
		old_scene.queue_free()
	await get_tree().process_frame


func _finish_transition() -> void:
	_transitioning = false
	transition_finished.emit()
