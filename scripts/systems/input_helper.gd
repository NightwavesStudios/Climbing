extends Node
## Autoload that detects controller usage and provides human-readable
## action names for the current input method (keyboard vs controller).
## Access via `InputHelper` (global singleton) or `Engine.get_singleton("InputHelper")`.

signal input_method_changed(is_controller: bool)

## All actions that the player can rebind — used by settings UI and loader.
const ALL_REBINDABLE_ACTIONS: Array[String] = [
	"select_left",
	"select_right",
	"select_left_foot",
	"select_right_foot",
	"restart",
	"project_mode",
	"route_view",
	"ui_cancel",
]

## Friendly display labels for rebindable actions (used in settings UI).
const ACTION_LABELS: Dictionary = {
	"select_left": "Left Hand",
	"select_right": "Right Hand",
	"select_left_foot": "Left Foot",
	"select_right_foot": "Right Foot",
	"restart": "Restart Climb",
	"project_mode": "Project Mode (P)",
	"route_view": "Route View (Tab)",
	"ui_cancel": "Pause / Cancel",
}

var is_using_controller: bool = false

# Track the last input event time to detect controller vs keyboard
var _last_input_time: float = 0.0
const INPUT_METHOD_COOLDOWN: float = 0.5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Detect already-connected controllers
	is_using_controller = not Input.get_connected_joypads().is_empty()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _input(event: InputEvent) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_input_time < INPUT_METHOD_COOLDOWN:
		return

	var was_controller := is_using_controller

	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		is_using_controller = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		is_using_controller = false

	if is_using_controller != was_controller:
		_last_input_time = now
		input_method_changed.emit(is_using_controller)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	var had_controller := is_using_controller
	is_using_controller = not Input.get_connected_joypads().is_empty()
	if is_using_controller != had_controller:
		input_method_changed.emit(is_using_controller)


## Returns the human-readable label for an action (e.g. "Left Hand").
func get_action_label(action: String) -> String:
	return ACTION_LABELS.get(action, action.capitalize())


## Returns the best display name for an action's primary input,
## preferring controller buttons when a controller is in use.
func get_action_key_name(action: String, prefer_controller: bool = false) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "(unbound)"

	# If we prefer controller, look for a joypad event first
	if prefer_controller or is_using_controller:
		for e in events:
			if e is InputEventJoypadButton:
				return _get_joypad_button_name(e.button_index)
			if e is InputEventJoypadMotion:
				return _get_joypad_axis_name(e.axis, e.axis_value)

	# Fallback to keyboard
	for e in events:
		if e is InputEventKey:
			return e.as_text_physical_keycode()
		if e is InputEventMouseButton:
			return _get_mouse_button_name(e.button_index)

	# If no keyboard event, return the first joypad event
	for e in events:
		if e is InputEventJoypadButton:
			return _get_joypad_button_name(e.button_index)

	return "(unknown)"


static func _get_joypad_button_name(button: int) -> String:
	match button:
		0:  return "Cross (A)"
		1:  return "Circle (B)"
		2:  return "Square (X)"
		3:  return "Triangle (Y)"
		4:  return "L1 (LB)"
		5:  return "R1 (RB)"
		6:  return "L2 (LT)"
		7:  return "R2 (RT)"
		8:  return "Select"
		9:  return "Start"
		10: return "L3 (LS)"
		11: return "R3 (RS)"
		12: return "D-Pad Up"
		13: return "D-Pad Down"
		14: return "D-Pad Left"
		15: return "D-Pad Right"
		_:   return "Button %d" % button


static func _get_joypad_axis_name(axis: int, value: float) -> String:
	var dir := "Left" if value < 0 else "Right"
	match axis:
		0:  return "LS %s" % dir
		1:  return "LS %s" % ("Up" if value < 0 else "Down")
		2:  return "RS %s" % ("Left" if value < 0 else "Right")
		3:  return "RS %s" % ("Up" if value < 0 else "Down")
		4:  return "L2 Axis"
		5:  return "R2 Axis"
		_:  return "Axis %d %s" % [axis, dir]


static func _get_mouse_button_name(button: int) -> String:
	match button:
		MOUSE_BUTTON_LEFT:    return "Left Click"
		MOUSE_BUTTON_RIGHT:   return "Right Click"
		MOUSE_BUTTON_MIDDLE:  return "Middle Click"
		_:                    return "Mouse %d" % button