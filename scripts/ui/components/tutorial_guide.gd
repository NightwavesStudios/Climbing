class_name TutorialGuide
extends CanvasLayer
## Step-by-step tutorial for Route #1 (Ladder).
## Guides the player through placing hands, then feet, then unlocking full control.

signal tutorial_completed()

enum Step { INTRO_JUGS, PLACE_FEET, UNLOCK_ALL, NEAR_TOP, FINISHED }

var _current_step: int = Step.INTRO_JUGS
var _player: CharacterBody2D = null
var _panel: Panel = null
var _dim_overlay: ColorRect = null
var _label: Label = null
var _title_label: Label = null
var _hands_placed: bool = false
var _feet_placed: bool = false
var _transition_timer: float = -1.0
var _pending_step: int = -1
var _dismissing: bool = false


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
	_dim_overlay.name = "DimOverlay"
	_dim_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_dim_overlay.color = Color(0, 0, 0, 0.3)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim_overlay)

	# Panel at bottom center (absolute positioning)
	_panel = Panel.new()
	_panel.name = "TutorialPanel"
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
	_title_label.name = "TitleLabel"
	_title_label.position = Vector2(20, 8)
	_title_label.size = Vector2(840, 24)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
	_title_label.text = "TUTORIAL"
	_panel.add_child(_title_label)

	_label = Label.new()
	_label.name = "TutorialLabel"
	_label.position = Vector2(20, 36)
	_label.size = Vector2(840, 96)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	_label.add_theme_constant_override("line_spacing", 4)
	_panel.add_child(_label)


func setup(player: CharacterBody2D) -> void:
	_player = player
	# Keep the auto-grabbed hands on the start holds so the player doesn't fall.
	# The player can manually release a hand (Q/E) to practice grabbing.
	_hands_placed = false  # Will advance when both hands are on holds
	_start_step_intro_jugs()


func reset() -> void:
	"""Reset the tutorial when the player falls. The player's reset_climb()
	re-grabs the hands, so we keep them on the start holds."""
	_hands_placed = false
	_feet_placed = false
	_transition_timer = -1.0
	_pending_step = -1
	_dismissing = false
	_start_step_intro_jugs()


func _start_step_intro_jugs() -> void:
	_current_step = Step.INTRO_JUGS
	if _player:
		_player.set_hands_enabled(true)
		_player.set_feet_enabled(false)
	_title_label.text = "STEP 1: JUGS"
	var left_key := InputHelper.get_action_key_name("select_left")
	var right_key := InputHelper.get_action_key_name("select_right")
	_label.text = "Jugs are the easiest climbing holds. Any 2 limbs can grip them.\nPress %s or %s to select a hand, aim, and release to grab.\nMove both hands to the next set of jugs to continue." % [left_key, right_key]


func _start_step_place_feet() -> void:
	_current_step = Step.PLACE_FEET
	if _player:
		_player.set_hands_enabled(false)
		_player.set_feet_enabled(true)
	_title_label.text = "STEP 2: FOOTHOLDS"
	var left_key := InputHelper.get_action_key_name("select_left_foot")
	var right_key := InputHelper.get_action_key_name("select_right_foot")
	_label.text = "The green holds are footholds, they can only be used by your feet.\nUse %s or %s to select a foot, aim, and release to place it.\nPlace both feet on footholds to continue." % [left_key, right_key]


func _start_step_unlock_all() -> void:
	_current_step = Step.UNLOCK_ALL
	if _player:
		_player.set_hands_enabled(true)
		_player.set_feet_enabled(true)
	_title_label.text = "STEP 3: CLIMB!"
	_label.text = "Your feet push your body up the wall! Getting your feet high is key.\nAll controls are unlocked. Climb to the top to finish the route!"


func _start_step_near_top() -> void:
	_current_step = Step.NEAR_TOP
	_title_label.text = "ALMOST THERE!"
	_label.text = "You're close to the top! Place both hands on the jug with the tape to finish the route."


func _on_dismiss_timer_end() -> void:
	if _dismissing:
		return
	_dismissing = true
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
				Step.PLACE_FEET:
					_start_step_place_feet()
				Step.UNLOCK_ALL:
					_start_step_unlock_all()
			_pending_step = -1
		return

	if not _player:
		return

	# If the climb was completed, dismiss the tutorial immediately
	if _player.climb_completed:
		_on_dismiss_timer_end()
		return

	match _current_step:
		Step.INTRO_JUGS:
			var both_on_holds: bool = _player.lh.hold != null and _player.rh.hold != null
			var both_on_next_jugs: bool = false # flag
			if both_on_holds:
				var lh_hold: ClimbingHold = _player.lh.hold as ClimbingHold
				var rh_hold: ClimbingHold = _player.rh.hold as ClimbingHold
				if lh_hold != null and rh_hold != null:
					both_on_next_jugs = lh_hold.hold_type != ClimbingHold.HoldType.START and rh_hold.hold_type != ClimbingHold.HoldType.START
			if both_on_next_jugs:
				# Player moved hands to the next set of jugs — advance
				if not _hands_placed:
					_hands_placed = true
					_label.text = "Great! Both hands are on the jugs."
					_transition_timer = 2
					_pending_step = Step.PLACE_FEET
			else:
				# Player is still on start holds or released a hand
				_hands_placed = false

		Step.PLACE_FEET:
			# Advance when both feet are placed on footholds
			if _player.lf.hold != null and _player.rf.hold != null:
				if not _feet_placed:
					_feet_placed = true
					_label.text = "Excellent! Feet are placed."
					_transition_timer = 2
					_pending_step = Step.UNLOCK_ALL

		Step.UNLOCK_ALL:
			# Check if player is near the top (TOP hold is at y=-448, highest jugs at y=-384)
			if _player.global_position.y < -350:
				_start_step_near_top()

		Step.NEAR_TOP:
			# Climb completion is handled by the general check above
			pass
