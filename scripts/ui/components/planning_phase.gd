extends CanvasLayer
class_name PlanningPhase
## Planning Phase overlay + controls.
##
## When active (route loaded but not started, or Tab-zoomed-out mid-route), the
## camera is free to pan (WASD/arrows) and zoom (trackpad/mouse wheel), the
## climber is locked, and hovering over a hold shows its properties. The player
## presses "Continue" (or Tab/Enter) to zoom back in and start the route.

signal continue_pressed

@onready var continue_button: Button = $ContinueButton
@onready var hint_label: Label = $HintContainer/HintLabel
@onready var tooltip: PanelContainer = $Tooltip
@onready var tooltip_label: RichTextLabel = $Tooltip/RichTextLabel

var _camera: Camera2D = null
var _active: bool = false
var _hovered_hold: Node = null

## Camera pan speed (px/s at zoom = 1.0; scaled by 1/zoom so zoomed-in pans are finer).
## Kept low so the camera doesn't feel twitchy when nudging across the route.
const PAN_SPEED := 400.0
const ZOOM_MIN := 0.15
const ZOOM_MAX := 1.5
const ZOOM_STEP := 1.15
## Screen-space radius (pixels) around a hold's on-screen position that counts
## as "hovering" it. Using screen space keeps the hover target consistent whether
## the camera is zoomed all the way out (small holds) or zoomed in.
const HOVER_SCREEN_RADIUS := 70.0

# =============================================================================
#  INPUT ACTIONS (registered at runtime so they don't collide with the existing
#  limb-selection bindings on A/D — they only matter while planning is active).
# =============================================================================

func _ensure_input_actions() -> void:
	var bindings := {
		"camera_left":  [KEY_A, KEY_LEFT],
		"camera_right": [KEY_D, KEY_RIGHT],
		"camera_up":    [KEY_W, KEY_UP],
		"camera_down":  [KEY_S, KEY_DOWN],
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

# =============================================================================
#  LIFECYCLE
# =============================================================================

func _ready() -> void:
	_ensure_input_actions()
	continue_button.pressed.connect(_on_continue)
	tooltip.visible = false
	visible = false
	set_process(false)

func enter(camera: Camera2D, overview_pos: Vector2, overview_zoom: Vector2) -> void:
	_camera = camera
	_active = true
	visible = true
	set_process(true)
	_hovered_hold = null
	tooltip.visible = false
	if _camera:
		_camera.global_position = overview_pos
		_camera.zoom = overview_zoom
		_camera.reset_smoothing()

func exit() -> void:
	_active = false
	visible = false
	set_process(false)
	_hovered_hold = null
	tooltip.visible = false

func is_active() -> bool:
	return _active

# =============================================================================
#  PER-FRAME
# =============================================================================

func _process(delta: float) -> void:
	if not _active or _camera == null:
		return
	_update_pan(delta)
	_update_hover()

func _unhandled_input(event: InputEvent) -> void:
	if not _active or _camera == null:
		return
	# Zoom with the mouse wheel / trackpad scroll.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor := ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
			var new_zoom := clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
			_camera.zoom = Vector2.ONE * new_zoom
			_camera.reset_smoothing()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_continue()
		get_viewport().set_input_as_handled()

func _update_pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("camera_left"):  dir.x -= 1.0
	if Input.is_action_pressed("camera_right"): dir.x += 1.0
	if Input.is_action_pressed("camera_up"):    dir.y -= 1.0
	if Input.is_action_pressed("camera_down"):  dir.y += 1.0
	if dir == Vector2.ZERO:
		return
	dir = dir.normalized()
	var speed := PAN_SPEED * (1.0 / _camera.zoom.x)
	_camera.global_position += dir * speed * delta
	_camera.reset_smoothing()

# =============================================================================
#  HOVER
# =============================================================================

func _update_hover() -> void:
	if _camera == null:
		return
	var canvas := get_viewport().get_canvas_transform()
	var mouse_screen := get_viewport().get_mouse_position()
	var nearest: Node = null
	var nearest_dist := HOVER_SCREEN_RADIUS
	for hold in get_tree().get_nodes_in_group("holds"):
		if not is_instance_valid(hold):
			continue
		var hold_screen: Vector2 = canvas * hold.global_position
		var d: float = hold_screen.distance_to(mouse_screen)
		if d < nearest_dist:
			nearest_dist = d
			nearest = hold
	if nearest != _hovered_hold:
		_hovered_hold = nearest
		var hold := _resolve_hold(nearest) if nearest else null
		if hold and _is_hold_queryable(hold):
			tooltip_label.text = _describe_hold(hold)
			tooltip.visible = true
			_position_tooltip(hold)
		else:
			tooltip.visible = false

func _is_hold_queryable(hold: Node) -> bool:
	return "hold_type" in hold

## Resolve the node that actually carries hold data. Holds are spawned as a
## wrapper Node2D with a script-bearing Area2D child; the "holds" group contains
## both, so walk up to the one that has hold_type.
func _resolve_hold(node: Node) -> Node:
	if "hold_type" in node:
		return node
	for child in node.get_children():
		if "hold_type" in child:
			return child
	return null

func _position_tooltip(hold: Node) -> void:
	var canvas := get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas * hold.global_position
	var vp := get_viewport().get_visible_rect().size
	var ts := tooltip.size
	# Give the tooltip a frame to size itself before clamping.
	tooltip.global_position = Vector2(
		clampf(screen_pos.x + 20.0, 4.0, vp.x - ts.x - 12.0),
		clampf(screen_pos.y - ts.y - 12.0, 4.0, vp.y - ts.y - 12.0)
	)

# =============================================================================
#  HOLD DESCRIPTION
# =============================================================================

func _describe_hold(hold: Node) -> String:
	var lines: Array[String] = []

	var type_name := "Hold"
	if "hold_type" in hold and hold.hold_type is int:
		type_name = ClimbingHold.HoldType.keys()[hold.hold_type].capitalize()
	lines.append("[b]%s[/b]" % type_name)

	var is_grabbable := true
	if "is_grabbable" in hold:
		is_grabbable = hold.is_grabbable
	if not is_grabbable:
		lines.append("Decor: not grabbable")
		return "\n".join(lines)

	var specialty := _hold_specialty(hold)
	if not specialty.is_empty():
		lines.append(specialty)

	var rest_value := 0.0
	if "rest_value" in hold:
		rest_value = hold.rest_value
	if hold.hold_type == ClimbingHold.HoldType.FOOTHOLD:
		lines.append("No stamina drain")
	elif rest_value > 0.0:
		lines.append("Rest hold: restores stamina")
	else:
		lines.append("Drains stamina")

	var mods := _get_modifiers(hold)
	if not mods.is_empty():
		lines.append("")
		lines.append("[b]Modifiers:[/b]")
		for m: String in mods:
			lines.append("  • " + m)

	return "\n".join(lines)

## Describe a hold's special usage trait (e.g. pockets are one-limb, footholds
## are feet-only). Returns "" for holds with no notable specialty.
func _hold_specialty(hold: Node) -> String:
	match hold.hold_type:
		ClimbingHold.HoldType.POCKET:
			return "One limb only"
		ClimbingHold.HoldType.FOOTHOLD:
			return "Feet only"
		ClimbingHold.HoldType.UNDERCLING:
			return "Needs a foot placement"
		ClimbingHold.HoldType.TOP_OUT:
			return "Finishes the route"
		ClimbingHold.HoldType.WINDOW:
			return "Holds several limbs"
		_:
			return ""

func _get_modifiers(hold: Node) -> Array[String]:
	var out: Array[String] = []
	for child in hold.get_children():
		if not ("modifier_type" in child):
			continue
		var mtype: String = child.modifier_type
		var data: Dictionary = child.serialize() if child.has_method("serialize") else {}
		match mtype:
			"falling":
				out.append("Falling: falls %.1fs after grab (resets %.1fs)" % [
					float(data.get("fall_delay", 2.2)),
					float(data.get("reset_delay", 4.0)),
				])
			"moving":
				out.append("Moving: travels at %.0f px/s" % float(data.get("speed", 80.0)))
			"soft_hold":
				out.append("Soft Hold: crumbles after %d grabs" % int(data.get("max_uses", 4)))
			"undercling":
				out.append("Undercling: needs a foot placement")
			_:
				out.append(child.get_display_name() if child.has_method("get_display_name") else mtype.capitalize())
	return out

# =============================================================================
#  ACTIONS
# =============================================================================

func _on_continue() -> void:
	if not _active:
		return
	continue_pressed.emit()