extends Node

@export var fade_scene_path: String = "res://scenes/menus/fade.tscn"

var _fade_instance: CanvasLayer
var _next_scene_path: String = ""


func _ready() -> void:
	_fade_instance = load(fade_scene_path).instantiate()
	add_child(_fade_instance)
	_fade_instance.layer = 1000
	_fade_instance.color_rect.visible = false

func to(scene_path: String) -> void:
	if not _fade_instance:
		return
	if scene_path == "":
		get_tree().quit()
		return
	_next_scene_path = scene_path
	
	if _fade_instance.has_node("AnimationPlayer"):
		var anim_player = _fade_instance.get_node("AnimationPlayer")
		anim_player.speed_scale = 1.0
	
	_fade_instance.fade_out()
	_fade_instance.fade_out_finished.connect(_on_fade_out_finished)

func _on_fade_out_finished() -> void:
	_fade_instance.fade_out_finished.disconnect(_on_fade_out_finished)
	_load_scene(_next_scene_path)

func _load_scene(scene_path: String) -> void:
	var old_scene = get_tree().current_scene

	var new_scene_res = ResourceLoader.load(scene_path)
	if not new_scene_res:
		push_error("Failed to load scene: " + scene_path)
		_fade_instance.fade_in()
		return

	var new_scene = new_scene_res.instantiate()
	if not new_scene:
		push_error("Failed to instantiate scene: " + scene_path)
		_fade_instance.fade_in()
		return

	get_tree().root.add_child(new_scene)
	new_scene.owner = get_tree().root
	get_tree().current_scene = new_scene

	if old_scene:
		old_scene.queue_free()

	_fade_instance.fade_in()
