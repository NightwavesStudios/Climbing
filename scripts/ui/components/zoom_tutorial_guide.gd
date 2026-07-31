class_name ZoomTutorialGuide
extends CanvasLayer
## Interactive tutorial for the zoom/route-view feature on the first roped climb.
## Guides the player through pressing Tab to zoom out, waits 3 seconds,
## then prompts Tab to unzoom and unlock everything.

signal tutorial_completed()

enum Step { ZOOM_INTRO, ZOOMING_OUT, UNZOOM, FINISHED }

var _current_step: int = Step.ZOOM_INTRO
var _player: CharacterBody2D = null
var _main_scene: Node = null
var _panel: Panel = null
var _dim_overlay: ColorRect = null
var _label: Label = null
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
	_dim_overlay.color = Color(0, 0, 0, 0.3)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim_overlay)

	# Panel at bottom center
	_panel = Panel.new()
	_panel.name = "ZoomTutorialPanel"
	_panel.position = Vector2(200, 500)
	_panel.size = Vector2(880, 140)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.85, 0.55, 0.1, 0.7)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	_title_label = Label.new()
	_title_label.name = "ZoomTitleLabel"
	_title_label.position = Vector2(20, 8)
	_title_label.size = Vector2(840, 24)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
	_title_label.text = "TUTORIAL"
	_panel.add_child(_title_label)

	_label = Label.new()
	_label.name = "ZoomTutorialLabel"
	_label.position = Vector2(20, 36)
	_label.size = Vector2(840, 96)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	_label.add_theme_constant_override("line_spacing", 4)
	_panel.add_child(_label)


func setup(player: CharacterBody2D, main_scene: Node) -> void:
	_player = player
	_main_scene = main_scene
	# Lock all movement while the tutorial is active
	_lock_movement()
	_start_step_zoom_intro()


func reset() -> void:
	"""Reset the tutorial state when the player falls."""
	_transition_timer = -1.0
	_pending_step = -1
	_dismissing = false
	_lock_movement()
	_start_step_zoom_intro()


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


func _start_step_zoom_intro() -> void:
	_current_step = Step.ZOOM_INTRO
	_title_label.text = "SEEING THE FULL ROUTE"
	var route_key := InputHelper.get_action_key_name("route_view")
	_label.text = "This is your first roped climb! Unlike a boulder, you can't see the full route in one camera. To zoom out your camera, press %s. This will allow you to see the full route." % route_key
	_unlock_on_dismiss = false


func _start_step_zooming_out() -> void:
	_current_step = Step.ZOOMING_OUT
	_title_label.text = "ZOOM FEATURE"
	_label.text = "Look at the full route overview! You can see the belayer at the bottom and all the holds going up. This allows you to preview the route and plan how you're going to climb it!"
	# Wait 3 seconds, then auto-advance to the unzoom step
	_transition_timer = 7.0
	_pending_step = Step.UNZOOM


func _start_step_unzoom() -> void:
	_current_step = Step.UNZOOM
	_title_label.text = "ZOOMING BACK IN"
	var route_key := InputHelper.get_action_key_name("route_view")
	_label.text = "Press %s to zoom back in to your climber. Good luck!" % route_key
	_unlock_on_dismiss = true


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


func _process(delta: float) -> void:
	if _transition_timer > 0:
		_transition_timer -= delta
		if _transition_timer <= 0:
			_transition_timer = -1.0
			match _pending_step:
				Step.UNZOOM:
					_start_step_unzoom()
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
		Step.ZOOM_INTRO:
			# Wait for Tab press to zoom out
			if Input.is_action_just_pressed("route_view") or Input.is_action_just_pressed("ui_focus_next"):
				_start_step_zooming_out()

		Step.UNZOOM:
			# Wait for Tab press to zoom back in
			if Input.is_action_just_pressed("route_view") or Input.is_action_just_pressed("ui_focus_next"):
				_transition_timer = 0.5
				_pending_step = Step.FINISHED
				_label.text = "Good luck!"

		Step.ZOOMING_OUT:
			# Waiting for the 3-second timer to auto-advance
			pass
