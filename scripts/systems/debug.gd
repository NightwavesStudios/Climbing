extends Node

## FPS counter: prints framerate to the console every second.
## Press F3 to toggle on/off.

var _fps_timer: Timer
var _fps_enabled: bool = false


func _ready() -> void:
	_fps_timer = Timer.new()
	_fps_timer.name = "FpsTimer"
	_fps_timer.one_shot = false
	_fps_timer.wait_time = 1.0
	_fps_timer.timeout.connect(_on_fps_tick)
	add_child(_fps_timer)

	print("[FPS] Press F3 to show/hide framerate in console.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_fps_toggle") or \
	   (event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo):
		get_viewport().set_input_as_handled()
		_fps_enabled = not _fps_enabled
		if _fps_enabled:
			_fps_timer.start()
			# Print the first reading immediately
			_on_fps_tick()
			print("[FPS] Enabled.")
		else:
			_fps_timer.stop()
			print("[FPS] Disabled.")


func _on_fps_tick() -> void:
	var fps := Engine.get_frames_per_second()
	print("[FPS] %d" % fps)
