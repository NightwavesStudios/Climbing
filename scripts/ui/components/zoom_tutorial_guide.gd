class_name ZoomTutorialGuide
extends CanvasLayer
## Interactive tutorial for the route-planning (route view) feature on the first
## roped climb (level 5, tutorial_05).
##
## Flow:
##   1. CLIMB      — monitoring only (no panel). When the player reaches a jug
##                   about halfway up, pause them and teach Tab-during-a-climb.
##   2. MID_ROUTE  — locked; the player presses Tab to zoom out, then Tab again
##                   to zoom back in, then the tutorial completes.

signal tutorial_completed()

enum Step { CLIMB, MID_ROUTE, FINISHED }
## Sub-states for the MID_ROUTE step.
enum MidState { WAIT_ZOOM_OUT, WAIT_ZOOM_IN }

var _current_step: int = Step.CLIMB
var _mid_state: int = MidState.WAIT_ZOOM_OUT
var _player: CharacterBody2D = null
var _main_scene: Node = null
var _panel: Panel = null
var _dim_overlay: ColorRect = null
var _label: RichTextLabel = null
var _title_label: Label = null
var _transition_timer: float = -1.0
var _pending_step: int = -1
var _dismissing: bool = false
var _unlock_on_dismiss: bool = false


func _ready() -> void:
	layer = 100
	_build_ui()
	# Fade in the panel and dim overlay
	_panel.modulate = Color(1, 1, 1, 0)
	_dim_overlay.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate", Color.WHITE, 0.4)
	tween.tween_property(_dim_overlay, "modulate", Color.WHITE, 0.4)


func _build_ui() -> void:
	# Dim overlay (fills the full viewport)
	_dim_overlay = ColorRect.new()
	_dim_overlay.name = "ZoomDimOverlay"
	_dim_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_dim_overlay.color = Color(0, 0, 0, 0.35)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim_overlay)

	# Panel at bottom center
	_panel = Panel.new()
	_panel.name = "ZoomTutorialPanel"
	_panel.position = Vector2(200, 496)
	_panel.size = Vector2(880, 156)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.06, 0.08, 0.95)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(1, 1, 1, 0.1)
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_left = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.shadow_color = Color(0, 0, 0, 0.4)
	panel_style.shadow_size = 10
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	_title_label = Label.new()
	_title_label.name = "ZoomTitleLabel"
	_title_label.position = Vector2(24, 24)
	_title_label.size = Vector2(832, 28)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	_title_label.text = "TUTORIAL"
	_panel.add_child(_title_label)

	# Body text container — centers the label vertically regardless of line count
	var body_container := VBoxContainer.new()
	body_container.name = "BodyContainer"
	body_container.position = Vector2(30, 58)
	body_container.size = Vector2(820, 92)
	body_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(body_container)

	_label = RichTextLabel.new()
	_label.name = "ZoomTutorialLabel"
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.fit_content = true
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("default_color", Color(0.92, 0.92, 0.96))
	_label.add_theme_constant_override("line_spacing", 6)
	body_container.add_child(_label)


func _key(key_name: String) -> String:
	return "[b][color=#e8b84b]" + InputHelper.get_action_key_name(key_name) + "[/color][/b]"


func setup(player: CharacterBody2D, main_scene: Node) -> void:
	_player = player
	_main_scene = main_scene
	# Start in climb-monitoring mode. There is no beginning intro — the tutorial
	# only activates partway up the climb to teach planning-during-a-climb.
	_start_step_climb()


func reset() -> void:
	"""Reset the tutorial state when the player falls. Return to the climb
	monitor so the mid-route check can re-arm cleanly."""
	_transition_timer = -1.0
	_pending_step = -1
	_dismissing = false
	_mid_state = MidState.WAIT_ZOOM_OUT
	_start_step_climb()


func _lock_movement() -> void:
	"""Disable hands and feet so the player can't climb during the tutorial."""
	if _player:
		_player.set_hands_enabled(false)
		_player.set_feet_enabled(false)


func _unlock_movement() -> void:
	"""Re-enable hands and feet so the player can climb."""
	if _player:
		_player.set_hands_enabled(true)
		_player.set_feet_enabled(true)


func _show_ui() -> void:
	_panel.visible = true
	_dim_overlay.visible = true


func _hide_ui() -> void:
	_panel.visible = false
	_dim_overlay.visible = false


func _start_step_climb() -> void:
	_current_step = Step.CLIMB
	_unlock_movement()
	_hide_ui()


func _start_step_mid_route() -> void:
	_current_step = Step.MID_ROUTE
	_mid_state = MidState.WAIT_ZOOM_OUT
	_lock_movement()
	_title_label.text = "PLAN YOUR MOVES"
	_label.text = "[center]You're halfway up the route! Press %s at any time during a climb to zoom out and plan your next moves.\nTry it now: press %s to zoom out.[/center]" % [_key("route_view"), _key("route_view")]
	_unlock_on_dismiss = false
	_show_ui()


func _start_mid_zoom_in() -> void:
	_mid_state = MidState.WAIT_ZOOM_IN
	_label.text = "[center]Great! That's planning mode during a climb! Now press %s again to zoom back in and continue climbing.[/center]" % _key("route_view")


func _on_dismiss_timer_end() -> void:
	if _dismissing:
		return
	_dismissing = true
	if _unlock_on_dismiss:
		_unlock_movement()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.6)
	tween.tween_property(_dim_overlay, "modulate:a", 0.0, 0.6)
	tween.tween_callback(_on_fade_complete)


func _on_fade_complete() -> void:
	if is_instance_valid(self):
		tutorial_completed.emit()
		queue_free()


# ── Mid-route detection helpers ────────────────────────────────────────────

func _reached_halfway_jug() -> bool:
	for hand in [_player.lh, _player.rh]:
		var hold: Area2D = hand.hold
		if hold != null and _is_halfway_jug(hold):
			return true
	return false


func _is_halfway_jug(hold: Area2D) -> bool:
	if not ("hold_type" in hold):
		return false
	if hold.hold_type != ClimbingHold.HoldType.JUG:
		return false
	return hold.global_position.y < _halfway_y()


func _halfway_y() -> float:
	if _main_scene and is_instance_valid(_main_scene):
		var wall: Node = _main_scene.dynamic_wall
		if wall and wall.has_method("get_bounds"):
			var bounds: Dictionary = wall.get_bounds()
			if bounds.valid:
				return (bounds.min.y + bounds.max.y) * 0.5
	return -700.0


func _camera_zoomed_out() -> bool:
	var cam: Camera2D = _main_scene.camera
	return cam != null and cam.zoom.x < 0.99


func _camera_zoomed_in() -> bool:
	var cam: Camera2D = _main_scene.camera
	return cam != null and cam.zoom.x >= 0.99


func _process(delta: float) -> void:
	if _dismissing:
		return

	if _transition_timer > 0:
		_transition_timer -= delta
		if _transition_timer <= 0:
			_transition_timer = -1.0
			match _pending_step:
				Step.FINISHED:
					_on_dismiss_timer_end()
			_pending_step = -1
		return

	if not _player or not _main_scene:
		return

	# If the climb was completed, dismiss the tutorial immediately
	if _player.climb_completed:
		_unlock_on_dismiss = true
		_on_dismiss_timer_end()
		return

	match _current_step:
		Step.CLIMB:
			# Wait until the player reaches a jug about halfway up.
			if _reached_halfway_jug():
				_start_step_mid_route()

		Step.MID_ROUTE:
			if _mid_state == MidState.WAIT_ZOOM_OUT:
				if _camera_zoomed_out():
					_start_mid_zoom_in()
			elif _mid_state == MidState.WAIT_ZOOM_IN:
				if Input.is_action_just_pressed("route_view") or Input.is_action_just_pressed("ui_focus_next") or _camera_zoomed_in():
					_unlock_on_dismiss = true
					_on_dismiss_timer_end()