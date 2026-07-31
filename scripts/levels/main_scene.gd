extends Node2D
## Main game scene with dynamic wall integration and climbing disciplines

@export var default_level_path: String = "res://data/levels/tutorial/tutorial_01.json"
signal ready_to_show
var camera_owned_by_main: bool = false
var _loading_complete := false
var _preview_complete: bool = false
@onready var level_loader: LevelLoader = $LevelLoader
@onready var player: CharacterBody2D = $Character
@onready var camera: Camera2D = $Camera2D
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var instructions: CanvasLayer = $Instructions
@onready var instructions_root: ColorRect = $Instructions/ColorRect
@onready var popup_sprite: Sprite2D = $Instructions/Sprite2D

var _current_level_path: String = ""
var dynamic_wall: Node2D = null

var rope_system: Node2D = null
var speed_timer: CanvasLayer = null
var weekly_timer: CanvasLayer = null
var current_discipline: int = 0

var level_complete_overlay: CanvasLayer = null
var demo_finished_overlay: CanvasLayer = null

const PROJECT_MODE_COMPLETE_SCENE := preload("res://scenes/menus/project_mode_complete.tscn")
var _project_mode_complete_overlay: ProjectModeComplete = null

var _popup_manager: PopupManager = null
var _tutorial_guide: TutorialGuide = null
var _zoom_tutorial_guide: ZoomTutorialGuide = null

# =============================================================================
#  PROJECT MODE (practice mode)
# =============================================================================

var project_mode_active: bool = false
var _project_mode_button: Button = null

# =============================================================================
#  ROUTE PREVIEW CAMERA
# =============================================================================

enum CameraMode { FOLLOW_PLAYER, ROUTE_PREVIEW }

var _cam_mode: CameraMode = CameraMode.FOLLOW_PLAYER
var _preview_tween: Tween = null
var _return_tween: Tween  = null
var _preview_zoom_normal := Vector2(1.0, 1.0)

## Whether Camera2D position_smoothing was enabled before preview — restored on finish.
var _smoothing_was_enabled: bool = false

const PREVIEW_ZOOM_MIN      := 0.22
const PREVIEW_ZOOM_MAX      := 0.55

## Auto-preview timings — starts zoomed out, holds, then zooms back in
const PREVIEW_HOLD_TIME     := 0.1    # seconds to linger at the overview

const PREVIEW_RETURN_TIME   := 3    # seconds to pan+zoom back to player
const PREVIEW_ZOOM_TIME     := 2.5    # seconds for the initial zoom-out

## Tab-toggle timings — slower and more deliberate
const TAB_ZOOM_OUT_TIME     := 2.5
const TAB_ZOOM_IN_TIME      := 2.5


func _get_route_overview_position() -> Vector2:
	if dynamic_wall and dynamic_wall.has_method("get_bounds"):
		var bounds = dynamic_wall.get_bounds()
		if bounds.valid:
			return Vector2(
				(bounds.min.x + bounds.max.x) * 0.5,
				(bounds.min.y + bounds.max.y) * 0.5
			)
	if player:
		return player.global_position + Vector2(0.0, -400.0)
	return camera.global_position


func _get_route_zoom() -> Vector2:
	if dynamic_wall and dynamic_wall.has_method("get_bounds"):
		var bounds = dynamic_wall.get_bounds()
		if bounds.valid:
			var route_h = bounds.max.y - bounds.min.y + 200.0
			var route_w = bounds.max.x - bounds.min.x + 200.0
			var vp      := get_viewport().get_visible_rect().size
			var zoom_v  = vp.y / route_h
			var zoom_h  = vp.x / route_w
			return Vector2.ONE * clamp(min(zoom_v, zoom_h), PREVIEW_ZOOM_MIN, PREVIEW_ZOOM_MAX)
	return Vector2.ONE * PREVIEW_ZOOM_MIN


func start_route_preview() -> void:
	camera_owned_by_main = true
	if not camera or not is_instance_valid(camera):
		camera_owned_by_main = false
		return

	# Disable player input so they can't move before the zoom-in completes
	_set_player_input(false)

	# Disable position smoothing during preview tween so tween_property controls
	# the actual rendered camera position, not just the smoothing target.
	_smoothing_was_enabled = camera.position_smoothing_enabled
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()

	_cam_mode = CameraMode.ROUTE_PREVIEW

	if _preview_tween and _preview_tween.is_valid():
		_preview_tween.kill()
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()

	var overview_pos  := _get_route_overview_position()
	var overview_zoom := _get_route_zoom()

	# Snap immediately to zoomed-out overview — no tween, happens before fade-in
	camera.global_position = overview_pos
	camera.zoom            = overview_zoom

	_preview_tween = create_tween() \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)

	# 1. Hold at the overview so the player can read the route
	_preview_tween.tween_interval(PREVIEW_HOLD_TIME)

	# 2. After the hold, start the return tween to where the player is NOW.
	#    Uses a separate tween (_return_tween) so player_pos is captured at
	#    the right moment (after 5s hold), not 5 seconds earlier.
	_preview_tween.tween_callback(_start_return_tween)

func _start_return_tween() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(player):
		_finish_preview()
		return

	# Capture the player's current position right NOW (after the 5s hold)
	var player_pos := player.global_position

	_return_tween = create_tween() \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)

	_return_tween.set_parallel(true)
	_return_tween.tween_property(camera, "zoom", _preview_zoom_normal, PREVIEW_RETURN_TIME)
	_return_tween.tween_property(camera, "global_position", player_pos, PREVIEW_RETURN_TIME)
	_return_tween.set_parallel(false)

	_return_tween.tween_callback(_finish_preview)

func _finish_preview() -> void:
	_preview_complete = true
	_cam_mode = CameraMode.FOLLOW_PLAYER
	camera_owned_by_main = false

	# Re-enable player input now that the zoom-in is complete
	_set_player_input(true)

	# Don't snap position/zoom — the tween already landed at the right values.
	# Just restore position_smoothing and call reset_smoothing() to eliminate
	# any smoothing lag, so the rendered position is exactly where the tween
	# left it. The player's own update_camera() lerp takes over from here.
	if is_instance_valid(camera):
		camera.position_smoothing_enabled = _smoothing_was_enabled
		camera.reset_smoothing()

	# Start the interactive tutorial for Route #1 (only if the popup is already dismissed)
	if _current_level_path.ends_with("tutorial_01.json") and _popup_manager and not _popup_manager.has_active_popup():
		_start_tutorial()

	# Start the zoom tutorial for the first roped route if the popup was already seen
	if _current_level_path.ends_with("tutorial_05.json") and _popup_manager and not _popup_manager.has_active_popup():
		_start_zoom_tutorial()

func _start_tutorial() -> void:
	"""Start the interactive tutorial guide for Route #1."""
	if _tutorial_guide:
		return
	_tutorial_guide = TutorialGuide.new()
	_tutorial_guide.name = "TutorialGuide"
	add_child(_tutorial_guide)
	_tutorial_guide.setup(player)
	_tutorial_guide.tutorial_completed.connect(_on_tutorial_completed)


func _on_tutorial_completed() -> void:
	_tutorial_guide = null


func _start_zoom_tutorial() -> void:
	"""Start the interactive zoom tutorial for the first roped route."""
	if _zoom_tutorial_guide:
		return
	_zoom_tutorial_guide = ZoomTutorialGuide.new()
	_zoom_tutorial_guide.name = "ZoomTutorialGuide"
	add_child(_zoom_tutorial_guide)
	_zoom_tutorial_guide.setup(player, self)
	_zoom_tutorial_guide.tutorial_completed.connect(_on_zoom_tutorial_completed)


func _on_zoom_tutorial_completed() -> void:
	_zoom_tutorial_guide = null
	# Re-enable player input in case it was locked
	_set_player_input(true)


func toggle_route_view() -> void:
	if not camera:
		return

	if _preview_tween and _preview_tween.is_valid():
		_preview_tween.kill()
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()

	_preview_tween = create_tween() \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)

	if _cam_mode == CameraMode.FOLLOW_PLAYER:
		_cam_mode = CameraMode.ROUTE_PREVIEW
		camera_owned_by_main = true
		# Disable smoothing so the tween controls the actual rendered position
		_smoothing_was_enabled = camera.position_smoothing_enabled
		camera.position_smoothing_enabled = false
		camera.reset_smoothing()
		var overview_pos  := _get_route_overview_position()
		var overview_zoom := _get_route_zoom()
		_preview_tween.set_parallel(true)
		_preview_tween.tween_property(camera, "global_position", overview_pos, TAB_ZOOM_OUT_TIME)
		_preview_tween.tween_property(camera, "zoom", overview_zoom, TAB_ZOOM_OUT_TIME)
	else:
		_cam_mode = CameraMode.FOLLOW_PLAYER
		var player_pos := player.global_position if player else camera.global_position
		_preview_tween.set_parallel(true)
		_preview_tween.tween_property(camera, "zoom", _preview_zoom_normal, TAB_ZOOM_IN_TIME)
		_preview_tween.tween_property(camera, "global_position", player_pos, TAB_ZOOM_IN_TIME)
		_preview_tween.set_parallel(false)
		_preview_tween.tween_callback(func():
			camera.position_smoothing_enabled = _smoothing_was_enabled
			camera.reset_smoothing()
			camera_owned_by_main = false
		)


func _set_player_input(enabled: bool) -> void:
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(enabled)

# =============================================================================
#  POPUP SYSTEM
# =============================================================================

## Maps level file names (e.g. "tutorial_01") to their popup config.
## Only the EXACT match level shows the popup.
func _build_popup_configs() -> void:
	# PopupManager is initialized in _ready() after nodes are available.
	pass

# =============================================================================
#  PROJECT MODE
# =============================================================================

func _setup_project_mode_ui() -> void:
	# Create a CanvasLayer for the project mode toggle button
	var project_ui := CanvasLayer.new()
	project_ui.name = "ProjectModeUI"
	project_ui.layer = 128
	add_child(project_ui)

	var btn := Button.new()
	btn.name = "ProjectModeButton"
	btn.text = "Project: OFF"
	btn.toggle_mode = true
	btn.theme_type_variation = &"ProjectModeButton"
	btn.size = Vector2(140, 32)
	btn.position = Vector2(10, 10)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	btn.add_theme_color_override("font_pressed_color", Color(0.3, 0.9, 0.6))
	btn.add_theme_color_override("button_pressed", Color(0.15, 0.35, 0.25))
	btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.15, 0.15, 0.15, 0.7), 4))
	btn.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.1, 0.3, 0.2, 0.8), 4))
	btn.add_theme_stylebox_override("hover", _make_stylebox(Color(0.2, 0.2, 0.2, 0.8), 4))
	btn.pressed.connect(_on_project_mode_toggled.bind(btn))
	project_ui.add_child(btn)
	_project_mode_button = btn

	# Hide and disable the project button by default.
	# It will be shown/enabled after the player reaches tutorial_11.
	_project_mode_button.visible = false
	_project_mode_button.disabled = true


func _make_stylebox(bg: Color, corner_radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = corner_radius
	sb.corner_radius_top_right = corner_radius
	sb.corner_radius_bottom_left = corner_radius
	sb.corner_radius_bottom_right = corner_radius
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _on_project_mode_toggled(btn: Button) -> void:
	project_mode_active = btn.button_pressed
	if player and player.has_method("set_project_mode"):
		player.set_project_mode(project_mode_active)
	
	if project_mode_active:
		btn.text = "Project: ON"
		btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
		show_message("Project Mode ON — falls respawn at last hold", Color(0.3, 1.0, 0.6))
	else:
		btn.text = "Project: OFF"
		btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		show_message("Project Mode OFF", Color(0.7, 0.7, 0.7))
		# Reset the climb when turning off project mode — no credit given
		_do_player_reset()


func _update_project_button_visibility(level_path: String) -> void:
	"""Show and enable the project button only after the player reaches tutorial_11.
	The button is hidden before that, and visible for all levels after."""
	if not _project_mode_button:
		return

	var gs := get_node_or_null("/root/GameState") as GameState
	if not gs:
		# Fallback: show if no GameState available
		_project_mode_button.visible = true
		_project_mode_button.disabled = false
		return

	var should_show := false

	# If the current collection is not the gym, the player has progressed past it
	if gs.current_collection != "intro-gym":
		should_show = true
	else:
		# Check if this level is tutorial_11 (index 10) or later
		var gym_levels: Array = gs.get_collection_data("intro-gym").get("levels", [])
		var level_index: int = gym_levels.find(level_path)
		if level_index >= 10:
			should_show = true
		# Also check if tutorial_11 has been completed (player might be replaying early levels)
		elif gym_levels.size() > 10 and gs.is_level_completed(gym_levels[10]):
			should_show = true

	_project_mode_button.visible = should_show
	_project_mode_button.disabled = not should_show


func is_project_mode_active() -> bool:
	return project_mode_active


# =============================================================================
#  PROJECT MODE TOP-OUT PROMPT
# =============================================================================

func on_project_mode_top_out() -> void:
	"""Called when the player reaches the top in project mode.
	Shows a "Complete" button like the "Next Climb" button."""
	# Disable player input while the prompt is shown
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	
	# Instantiate the project mode complete scene
	_project_mode_complete_overlay = PROJECT_MODE_COMPLETE_SCENE.instantiate()
	_project_mode_complete_overlay.complete_requested.connect(_on_complete_climb_pressed)
	add_child(_project_mode_complete_overlay)
	_project_mode_complete_overlay.show_overlay()


func _on_complete_climb_pressed() -> void:
	"""Player clicked 'Complete' — turn off project mode and reset the climb."""
	# Remove the overlay
	if _project_mode_complete_overlay and is_instance_valid(_project_mode_complete_overlay):
		_project_mode_complete_overlay.queue_free()
		_project_mode_complete_overlay = null
	
	# Turn off project mode
	project_mode_active = false
	if player and player.has_method("set_project_mode"):
		player.set_project_mode(false)
	
	# Update the project mode button to match
	if _project_mode_button:
		_project_mode_button.button_pressed = false
		_project_mode_button.text = "Project: OFF"
		_project_mode_button.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	
	# Reset the climb — no fade, no completion recording, no continue
	_do_player_reset()
	
	# Re-enable player input
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)


# =============================================================================
#  PATH CHECK (dev helper)
# =============================================================================

func _check_paths() -> void:
	var paths = [
		"res://data/levels/tutorial/tutorial_01.json",
		"res://scenes/props/crashpad.tscn",
		"res://scenes/holds/start.tscn",
		"res://scenes/holds/top_out.tscn",
		"res://scenes/holds/jug.tscn",
		"res://scenes/holds/crimp.tscn",
		"res://scenes/holds/sloper.tscn",
		"res://scenes/holds/pocket.tscn",
		"res://scenes/holds/foothold.tscn",
		"res://scenes/holds/window.tscn",
		"res://scenes/holds/ledge.tscn",
		"res://scripts/climbing/dynamic_wall.gd",
		"res://scripts/climbing/hold_modifiers.gd",
		"res://scripts/environment/weather_modifier.gd",
		"res://scripts/player/rope_system.gd",
		"res://scripts/levels/speed_timer.gd",
		"res://data/levels/granite_crag/granite_crag_01.json",
	]
	for path in paths:
		print("EXISTS ", path, ": ", FileAccess.file_exists(path) or ResourceLoader.exists(path))

# =============================================================================
#  READY
# =============================================================================

func _ready():
	print("=== MAIN SCENE READY ===")

	# ── Project mode UI setup ──────────────────────────────────────────
	_setup_project_mode_ui()

	# Hide the menu background — it's persistent at root level and
	# wastes CPU on _process / _draw even when invisible.
	if has_node("/root/MenuBackgroundManager"):
		MenuBackgroundManager.hide()

	_popup_manager = PopupManager.new(instructions, instructions_root, popup_sprite)
	add_to_group("main_scene")

	if instructions_root:
		instructions_root.modulate.a = 0.0

	# The popup instructions are hidden by default — don't waste
	# CPU running their internal Button._process every frame.
	instructions.process_mode = Node.PROCESS_MODE_DISABLED

	_setup_level_complete_overlay()
	_setup_demo_finished_overlay()
	_setup_pause_menu()
	_check_paths()

	# Connect to the unified Transition autoload
	var transition_manager := get_node_or_null("/root/Transition")
	if transition_manager:
		transition_manager.transition_started.connect(_on_transition_started)
		transition_manager.transition_finished.connect(_on_transition_finished)

	var initial_level = _get_initial_level()
	print("Initial level to load: ", initial_level)

	await _load_initial_level(initial_level)

	await get_tree().process_frame
	_show_popup_for_level(initial_level)

	# Start the interactive tutorial immediately (bypasses preview animation)
	if initial_level.ends_with("tutorial_01.json"):
		_finish_preview()

	_loading_complete = true
	ready_to_show.emit()
	print("=== MAIN SCENE READY COMPLETE ===")

# =============================================================================
#  TRANSITION READY HOOK
# =============================================================================

## Called by Transition autoload after the scene has been added to the tree
## but before the fade-in.  Returns as soon as the level is fully loaded,
## so the reveal shows everything at once.
func _on_before_show() -> void:
	if _loading_complete:
		return
	await ready_to_show


# =============================================================================
#  POPUP ENTRY POINT
# =============================================================================

func _show_popup_for_level(level_path: String) -> void:
	if _popup_manager:
		_popup_manager.show_popup_for_level(level_path)

func _get_env_from_path(level_path: String) -> String:
	# e.g. "res://data/levels/granite_crag/granite_crag_01.json" -> "granite_crag"
	var parts := level_path.split("/")
	return parts[-2]


func _get_next_level_path(current_path: String) -> String:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("get_next_level"):
		var nxt: String = gs.get_next_level(current_path)
		if nxt != "":
			return nxt

	if level_loader and level_loader.has_method("get_next_level_path"):
		return level_loader.get_next_level_path()

	return ""

# =============================================================================
#  PAUSE MENU
# =============================================================================

func _setup_pause_menu() -> void:
	if not pause_menu:
		push_error("PauseMenu node not found — add it to the scene tree")
		return

	pause_menu.resumed.connect(_on_pause_resumed)
	pause_menu.visible = false

func _unhandled_input(event: InputEvent) -> void:
	# Tab → toggle route view.
	if event.is_action_pressed("route_view") or event.is_action_pressed("ui_focus_next"):
		# Don't allow Tab-toggle during the auto-preview hold phase.
		# The return phase and normal FOLLOW_PLAYER allow it.
		if _preview_tween == null or not _preview_tween.is_running():
			toggle_route_view()
		return

	if event.is_action_pressed("ui_cancel"):
		if pause_menu and not pause_menu.visible:
			_open_pause_menu()

	# P key toggles project mode (only if the button is visible and enabled)
	if event.is_action_pressed("project_mode"):
		if _project_mode_button and _project_mode_button.visible and not _project_mode_button.disabled:
			_project_mode_button.button_pressed = not _project_mode_button.button_pressed
			_on_project_mode_toggled(_project_mode_button)

func _open_pause_menu() -> void:
	if not pause_menu:
		return
	if level_complete_overlay and level_complete_overlay.visible:
		return
	if instructions and instructions.visible:
		return
	pause_menu.show_pause_menu()

func _on_pause_resumed() -> void:
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)

# =============================================================================
#  LEVEL COMPLETE OVERLAY
# =============================================================================

func _setup_level_complete_overlay() -> void:
	var overlay_scene = load("res://scenes/menus/level_completed.tscn")
	if not overlay_scene:
		push_error("Could not load level_completed.tscn")
		return

	level_complete_overlay = overlay_scene.instantiate()
	add_child(level_complete_overlay)

	level_complete_overlay.next_level_requested.connect(_on_next_level_requested)
	level_complete_overlay.menu_requested.connect(_on_level_complete_menu_requested)
	level_complete_overlay.restart_requested.connect(_on_level_complete_restart_requested)
	level_complete_overlay.demo_finished.connect(_on_demo_finished)

# =============================================================================
#  LEVEL LOADING
# =============================================================================

func _get_initial_level() -> String:
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("get_current_level"):
		var lvl = game_state.get_current_level()
		if lvl and lvl != "":
			return lvl
	return default_level_path

func _load_initial_level(path: String) -> void:
	print("  Loading level: ", path)
	_current_level_path = path

	var success = await level_loader.load_level(path)
	if not success:
		print("  ERROR: Failed to load level: ", path)
		return

	await get_tree().process_frame
	await get_tree().process_frame

	dynamic_wall = level_loader.get_dynamic_wall()

	var validation = level_loader.validate_level()
	if not validation.valid:
		print("  WARNING: Level validation failed")
		for error in validation.errors:
			print("    - " + error)

	await setup_discipline_systems()

	position_player_at_spawn()

	await get_tree().process_frame
	center_camera_on_route()

	# ── Route preview (Option B) ──────────────────────────────────────────────
	# Wait one more frame so the camera is positioned before the tween fires.
	await get_tree().process_frame
	start_route_preview()
	# ─────────────────────────────────────────────────────────────────────────

	_update_project_button_visibility(path)

	print("  Level ready: ", path)

# =============================================================================
#  DISCIPLINE SYSTEM SETUP
# =============================================================================

func setup_discipline_systems():
	if not level_loader:
		return

	var discipline_str = level_loader.get_discipline()
	current_discipline = ClimbingDiscipline.from_string(discipline_str)

	print("\n═══ DISCIPLINE SETUP ═══")
	print("Discipline: " + ClimbingDiscipline.get_display_name(current_discipline))

	if not player:
		return

	if player.has_method("set_climbing_discipline"):
		player.set_climbing_discipline(current_discipline)

	match current_discipline:
		ClimbingDiscipline.Type.BOULDERING:
			setup_bouldering()
		ClimbingDiscipline.Type.ROPED:
			await setup_roped_climbing(level_loader, player)
		ClimbingDiscipline.Type.SPEED:
			setup_speed_climbing(level_loader, player)

	# Set up count-up timer for weekly levels (always, regardless of discipline)
	_setup_weekly_timer()

	print("═══════════════════════\n")

func setup_bouldering():
	print("  Mode: Standard bouldering")

func setup_roped_climbing(loader, plyr):
	print("  Mode: Roped climbing")

	var belayer_pos = loader.get_belayer_position()

	if belayer_pos == Vector2.ZERO:
		var wall_bounds = loader.get_wall_bounds()
		if wall_bounds.valid:
			belayer_pos = Vector2(
				(wall_bounds.min.x + wall_bounds.max.x) / 2,
				wall_bounds.max.y - 50
			)
		else:
			belayer_pos = plyr.global_position + Vector2(0, 200)

	if rope_system != null:
		push_warning("setup_roped_climbing: rope_system was not null — forcing cleanup")
		_force_free_node(rope_system)
		rope_system = null

	var RopeSystemScript = load("res://scripts/player/rope_system.gd")
	if not RopeSystemScript:
		print("  ERROR: Could not load rope_system.gd!")
		return

	rope_system = RopeSystemScript.new()
	rope_system.name = "RopeSystem"
	add_child(rope_system)
	await get_tree().process_frame

	if rope_system.has_method("setup_rope"):
		rope_system.setup_rope(belayer_pos, plyr)

	# ── When the rope catches a falling player, refresh fallen holds ─────
	if rope_system.player_caught.is_connected(_on_rope_caught):
		rope_system.player_caught.disconnect(_on_rope_caught)
	rope_system.player_caught.connect(_on_rope_caught)

	if plyr.has_method("set_rope_system"):
		plyr.set_rope_system(rope_system)

	print("  Rope system ready at: ", belayer_pos)

func setup_speed_climbing(loader, plyr):
	print("  Mode: Speed climbing")

	var time_limit = loader.get_speed_time_limit()

	var SpeedTimerScript = load("res://scripts/levels/speed_timer.gd")
	if not SpeedTimerScript:
		print("  ERROR: Could not load speed_timer.gd!")
		return

	speed_timer = SpeedTimerScript.new()
	speed_timer.name = "SpeedTimer"
	add_child(speed_timer)
	await get_tree().process_frame

	if speed_timer.has_method("set_time_limit"):
		speed_timer.set_time_limit(time_limit)

	if speed_timer.has_signal("time_expired"):
		speed_timer.time_expired.connect(_on_speed_time_expired)
	if speed_timer.has_signal("time_warning"):
		speed_timer.time_warning.connect(_on_speed_time_warning)
	if speed_timer.has_signal("timer_started_signal"):
		speed_timer.timer_started_signal.connect(_on_speed_timer_started)

	if plyr.has_method("set_speed_timer"):
		plyr.set_speed_timer(speed_timer)

	speed_timer.visible = true
	if speed_timer.has_method("show_timer"):
		speed_timer.show_timer()

	print("  Speed timer ready: ", time_limit, "s")

# =============================================================================
#  SPEED CALLBACKS
# =============================================================================

func _on_speed_time_expired():
	show_message("TIME'S UP!", Color.RED)
	await get_tree().create_timer(2.0).timeout
	reset_level()

func _on_speed_time_warning(seconds: float):
	if seconds <= 5.0:
		show_message(str(int(seconds)) + "!", Color.ORANGE)

func _on_speed_timer_started():
	print("Speed climb started!")

# =============================================================================
#  WEEKLY TIMER
# =============================================================================

func _setup_weekly_timer() -> void:
	# Only show the count-up timer for weekly levels
	if not _current_level_path.begins_with("res://data/levels/weekly/"):
		return

	var WeeklyTimerScript := load("res://scripts/levels/weekly_timer.gd")
	if not WeeklyTimerScript:
		push_error("Could not load weekly_timer.gd!")
		return

	# Clean up any previous instance
	if weekly_timer and is_instance_valid(weekly_timer):
		weekly_timer.queue_free()

	weekly_timer = WeeklyTimerScript.new()
	weekly_timer.name = "WeeklyTimer"
	add_child(weekly_timer)
	await get_tree().process_frame

	print("  Weekly timer ready")


func _get_weekly_elapsed_time() -> float:
	if weekly_timer and is_instance_valid(weekly_timer):
		if weekly_timer.has_method("get_elapsed_time"):
			return weekly_timer.get_elapsed_time()
	return 0.0


# =============================================================================
#  PLAYER SPAWN
# =============================================================================

func position_player_at_spawn():
	if not player or not level_loader:
		return

	var spawn_pos = level_loader.get_player_spawn_position()

	if spawn_pos == Vector2.ZERO:
		print("WARNING: spawn position is zero — check START holds or custom_spawn flag")
		return

	player.global_position = spawn_pos
	player.spawn_position   = spawn_pos

	if player.has_method("set_spawn_position"):
		player.set_spawn_position(spawn_pos)

	print("Player spawned at: ", spawn_pos)

# =============================================================================
#  CAMERA
# =============================================================================

func center_camera_on_route():
	if not camera or not dynamic_wall:
		return
	if not dynamic_wall.has_method("get_bounds"):
		return

	var bounds = dynamic_wall.get_bounds()
	if not bounds.valid:
		return

	camera.position = Vector2(
		(bounds.min.x + bounds.max.x) / 2.0,
		(bounds.min.y + bounds.max.y) / 2.0
	)
	camera.zoom = Vector2(1.0, 1.0)

# =============================================================================
#  TOP-OUT DETECTION
# =============================================================================

# =============================================================================
#  PUBLIC API
# =============================================================================

func get_current_level_path() -> String:
	return _current_level_path

func set_current_level_path(path: String) -> void:
	_current_level_path = path

# =============================================================================
#  LEVEL EVENTS
# =============================================================================

func on_level_complete():
	print("=== LEVEL COMPLETE ===")

	if _current_level_path == "":
		push_error("_current_level_path is empty!")
		return

	# Abort any active route preview so the overlay isn't blocked
	if _preview_tween and _preview_tween.is_valid():
		_preview_tween.kill()
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
	_cam_mode = CameraMode.FOLLOW_PLAYER

	if pause_menu and pause_menu.visible:
		pause_menu.hide_pause_menu()

	var completion_time := 0.0
	if current_discipline == ClimbingDiscipline.Type.SPEED and speed_timer:
		if speed_timer.has_method("get_time_remaining"):
			completion_time = speed_timer.get_time_remaining()

	var weekly_elapsed := 0.0
	var is_weekly_level := _current_level_path.begins_with("res://data/levels/weekly/")
	if is_weekly_level and weekly_timer and is_instance_valid(weekly_timer):
		if weekly_timer.has_method("stop_timer"):
			weekly_elapsed = weekly_timer.stop_timer()
			# Record weekly best time
			var gs := get_node_or_null("/root/GameState")
			if gs and gs.has_method("record_weekly_best_time"):
				gs.record_weekly_best_time(_current_level_path, weekly_elapsed)

			# Upload time to Steam leaderboard for this week
			var wl := get_node_or_null("/root/WeeklyLeaderboard")
			if wl and wl.has_method("upload_score"):
				wl.upload_score(weekly_elapsed)

	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("record_level_completion"):
		game_state.record_level_completion(_current_level_path, completion_time)

	# ── Achievement: speed-climb checks (SPEED_DEMON / PHOTO_FINISH) ────
	if current_discipline == ClimbingDiscipline.Type.SPEED \
			and speed_timer \
			and is_instance_valid(speed_timer) \
			and get_node_or_null("/root/Achievements"):
		var time_remaining = speed_timer.get_time_remaining()
		var time_limit     = speed_timer.time_limit
		Achievements.check_speed_demon(time_remaining, time_limit)
		Achievements.check_photo_finish(time_remaining)

	# ── Achievement: roped climb (ROPE_GUN) ─────────────────────────────
	if current_discipline == ClimbingDiscipline.Type.ROPED \
			and get_node_or_null("/root/Achievements"):
		Achievements.check_rope_gun()

	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)

	if level_complete_overlay:
		level_complete_overlay.show_overlay(_current_level_path, weekly_elapsed)
	else:
		Transition.to("res://scenes/menus/level_completed.tscn")

func on_player_reset():
	# Manual reset (Escape/R key) — does NOT count toward skip threshold
	if project_mode_active and player and player.has_method("project_mode_reset"):
		_project_mode_reset_player()
	else:
		_do_player_reset()

func on_player_fell():
	if project_mode_active and player and player.has_method("project_mode_reset"):
		_project_mode_reset_player()
	else:
		_do_player_reset()

func _do_player_reset():
	if player and not player._grab_initialized:
		return

	# Kill any active route preview tween so it doesn't fight the camera
	if _preview_tween and _preview_tween.is_valid():
		_preview_tween.kill()
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
	_cam_mode = CameraMode.FOLLOW_PLAYER

	position_player_at_spawn()
	camera_owned_by_main = false

	if player and player.has_method("reset_climb"):
		player.reset_climb()

	# Reset the tutorial guide if active
	if _tutorial_guide and is_instance_valid(_tutorial_guide):
		_tutorial_guide.reset()

	# Reset the zoom tutorial guide if active
	if _zoom_tutorial_guide and is_instance_valid(_zoom_tutorial_guide):
		_zoom_tutorial_guide.reset()

	if current_discipline == ClimbingDiscipline.Type.SPEED and speed_timer:
		if speed_timer.has_method("stop_timer"):
			speed_timer.stop_timer()

	# Reset weekly timer on fall/reset
	if weekly_timer and is_instance_valid(weekly_timer):
		if weekly_timer.has_method("reset_timer"):
			weekly_timer.reset_timer()

func _project_mode_reset_player() -> void:
	"""Reset the player to the last hold they grabbed (project mode).
	Keeps project mode active and doesn't show the level complete overlay."""
	if player and not player._grab_initialized:
		return

	# Kill any active route preview tween so it doesn't fight the camera
	if _preview_tween and _preview_tween.is_valid():
		_preview_tween.kill()
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
	_cam_mode = CameraMode.FOLLOW_PLAYER

	# Reset the player at the last hold
	if player and player.has_method("project_mode_reset"):
		player.project_mode_reset()
		camera_owned_by_main = false
		# Snap camera to player position
		if is_instance_valid(camera):
			camera.global_position = player.global_position
			camera.reset_smoothing()

	# Don't reset speed timer or weekly timer in project mode
	# (they don't matter since climbs don't count)

func on_climb_start():
	print("Climb started!")

	# If the player grabs before the auto-preview finishes, abort it cleanly
	# Only abort preview if enough time has passed (ignore the spawn grab)
	if _cam_mode == CameraMode.ROUTE_PREVIEW:
		var elapsed := 0.0
		var any_alive := false
		if _preview_tween and _preview_tween.is_valid():
			elapsed = _preview_tween.get_total_elapsed_time()
			any_alive = true
		elif _return_tween and _return_tween.is_valid():
			elapsed = PREVIEW_HOLD_TIME + _return_tween.get_total_elapsed_time()
			any_alive = true
		if any_alive and elapsed > PREVIEW_HOLD_TIME * 0.5:
			if _preview_tween and _preview_tween.is_valid():
				_preview_tween.kill()
			if _return_tween and _return_tween.is_valid():
				_return_tween.kill()
			# Snap zoom back to normal so camera doesn't stay zoomed out
			if is_instance_valid(camera):
				camera.zoom = _preview_zoom_normal
			_finish_preview()

	if current_discipline == ClimbingDiscipline.Type.SPEED:
		if speed_timer and speed_timer.has_method("start_timer"):
			speed_timer.start_timer()

	# Start weekly count-up timer on first move (for weekly levels)
	if weekly_timer and is_instance_valid(weekly_timer):
		if weekly_timer.has_method("start_timer"):
			weekly_timer.start_timer()

	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("notify_climb_start"):
			hold.notify_climb_start()

# =============================================================================
#  ROPE CATCH — reset falling holds without full reset
# =============================================================================

func _on_rope_caught() -> void:
	"""When the rope catches a fall, reset any falling/dropped holds
	back to their origin with a pop-in animation, without resetting
	the entire climb or repositioning the player."""
	for hold in get_tree().get_nodes_in_group("holds"):
		if is_instance_valid(hold) and hold.has_method("notify_caught_reset"):
			hold.notify_caught_reset()

func reset_level():
	cleanup_discipline_systems()
	if _current_level_path != "":
		await _load_initial_level(_current_level_path)

# =============================================================================
#  OVERLAY SIGNAL HANDLERS
# =============================================================================

func _on_next_level_requested(next_level_path: String) -> void:
	print("Next level: ", next_level_path)

	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	if pause_menu:
		pause_menu.pausing_enabled = false

	await Transition.fade_out_only()

	if player and player.has_method("reset_climb"):
		player.reset_climb()
	await get_tree().process_frame

	cleanup_discipline_systems()
	level_loader.unload_level()

	await _load_initial_level(next_level_path)

	await get_tree().process_frame
	await get_tree().process_frame
	if player and player.has_method("reset_climb"):
		player.reset_climb()

	_show_popup_for_level(next_level_path)
	_update_project_button_visibility(next_level_path)

	await get_tree().create_timer(0.1).timeout

	await Transition.fade_in_only()

	if pause_menu:
		pause_menu.pausing_enabled = true
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)

func _on_level_complete_menu_requested() -> void:
	cleanup_discipline_systems()
	# Weekly levels go back to main menu; other levels go to collections
	if _current_level_path.begins_with("res://data/levels/weekly/"):
		Transition.to("res://scenes/menus/main_menu.tscn")
	else:
		Transition.to("res://scenes/menus/collections_select.tscn")

func _on_level_complete_restart_requested() -> void:
	print("Restarting: ", _current_level_path)

	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	if pause_menu:
		pause_menu.pausing_enabled = false

	await Transition.fade_out_only()

	if player and player.has_method("reset_climb"):
		player.reset_climb()
	await get_tree().process_frame

	cleanup_discipline_systems()
	level_loader.unload_level()

	await _load_initial_level(_current_level_path)

	await get_tree().create_timer(0.1).timeout

	await Transition.fade_in_only()

	if pause_menu:
		pause_menu.pausing_enabled = true
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)

# =============================================================================
#  DEMO FINISHED OVERLAY
# =============================================================================

func _setup_demo_finished_overlay() -> void:
	var scene := load("res://scenes/menus/demo_finished.tscn")
	if not scene:
		push_error("Could not load demo_finished.tscn")
		return

	demo_finished_overlay = scene.instantiate()
	add_child(demo_finished_overlay)
	demo_finished_overlay.menu_requested.connect(_on_level_complete_menu_requested)


func _on_demo_finished() -> void:
	"""Called when the level_completed overlay emits demo_finished (end of demo)."""
	print("=== DEMO FINISHED ===")

	# ── Achievement: demo complete ───────────────────────────────────────
	if get_node_or_null("/root/Achievements"):
		Achievements.check_demo_complete()

	if demo_finished_overlay:
		demo_finished_overlay.show_overlay()

# =============================================================================
#  DISCIPLINE CLEANUP
# =============================================================================

func _force_free_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	node.set_process(false)
	node.set_physics_process(false)
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.free()

func cleanup_discipline_systems():
	# Kill any active preview tween before cleanup so it doesn't reference
	# nodes that are about to be freed
	if _preview_tween and _preview_tween.is_valid():
		_preview_tween.kill()
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
	_cam_mode = CameraMode.FOLLOW_PLAYER

	if rope_system != null:
		if is_instance_valid(rope_system):
			if rope_system.has_method("cleanup"):
				rope_system.cleanup()
			_force_free_node(rope_system)
		rope_system = null
		if is_instance_valid(player) and player.has_method("set_rope_system"):
			player.set_rope_system(null)

	if speed_timer != null:
		if is_instance_valid(speed_timer):
			if speed_timer.has_method("cleanup"):
				speed_timer.cleanup()
			_force_free_node(speed_timer)
		speed_timer = null

	if weekly_timer != null:
		if is_instance_valid(weekly_timer):
			if weekly_timer.has_method("cleanup"):
				weekly_timer.cleanup()
			_force_free_node(weekly_timer)
		weekly_timer = null

	# Clean up the zoom tutorial guide if it's active
	if _zoom_tutorial_guide != null:
		if is_instance_valid(_zoom_tutorial_guide):
			_force_free_node(_zoom_tutorial_guide)
		_zoom_tutorial_guide = null

	current_discipline = 0

# =============================================================================
#  MESSAGES
# =============================================================================

func show_message(text: String, color: Color = Color.WHITE):
	var label = Label.new()
	label.text = text
	label.position = Vector2(get_viewport().size.x / 2 - 100, 200)
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(label):
		label.queue_free()

# =============================================================================
#  TRANSITION CALLBACKS
# =============================================================================

func _on_transition_started():
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	if pause_menu:
		pause_menu.pausing_enabled = false

func _on_transition_finished():
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)
	if pause_menu:
		pause_menu.pausing_enabled = true

# =============================================================================
#  INSTRUCTIONS / POPUP DISMISS
# =============================================================================

func _on_hide_instructions_pressed() -> void:
	if _popup_manager:
		_popup_manager.try_dismiss()
	# Start the interactive tutorial after dismissing the popup for Route #1.
	# Wait for the route preview to finish first so the camera is in FOLLOW_PLAYER mode.
	if _current_level_path.ends_with("tutorial_01.json") and _preview_complete:
		_start_tutorial()
	# Start zoom tutorial after dismissing the popup for the first roped route.
	# Wait for the route preview to finish first so the camera is in FOLLOW_PLAYER mode.
	if _current_level_path.ends_with("tutorial_05.json") and _preview_complete:
		_start_zoom_tutorial()
