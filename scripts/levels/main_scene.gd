extends Node2D
## Main game scene with dynamic wall integration and climbing disciplines

@export var default_level_path: String = "res://data/levels/tutorial/tutorial_01.json"
var camera_owned_by_main: bool = false
var _preview_complete: bool = false
@onready var level_loader: LevelLoader = $LevelLoader
@onready var player: CharacterBody2D = $Character
@onready var camera: Camera2D = $Camera2D
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var instructions: CanvasLayer = $Instructions
@onready var instructions_root: ColorRect = $Instructions/ColorRect
@onready var popup_sprite: Sprite2D = $Instructions/Sprite2D
@onready var skip_level_layer: CanvasLayer = $SkipLevel

var _current_level_path: String = ""
var dynamic_wall: Node2D = null

var rope_system: Node2D = null
var speed_timer: CanvasLayer = null
var current_discipline: int = 0

var level_complete_overlay: CanvasLayer = null
var demo_finished_overlay: CanvasLayer = null

const INSTRUCTIONS_SAVE_PATH := "user://prefs.cfg"
const INSTRUCTIONS_SECTION  := "instructions"
const INSTRUCTIONS_KEY      := "shown"

const SKIP_THRESHOLD    : int    = 5
const SKIP_SECTION      : String = "skip"
const MAX_SKIPS_PER_ENV : int    = 2
var   _reset_count      : int    = 0

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

	# Don't snap position/zoom — the tween already landed at the right values.
	# Just restore position_smoothing and call reset_smoothing() to eliminate
	# any smoothing lag, so the rendered position is exactly where the tween
	# left it. The player's own update_camera() lerp takes over from here.
	if is_instance_valid(camera):
		camera.position_smoothing_enabled = _smoothing_was_enabled
		camera.reset_smoothing()

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

var POPUP_CONFIGS: Array = []

## Maps level file names (e.g. "tutorial_01") to their popup config.
## Only the EXACT match level shows the popup.
func _build_popup_configs() -> void:
	POPUP_CONFIGS = [
		{
			"image_path": "res://assets/images/popups/tutorial_popup.png",
			"condition":  _popup_cond_controls,
			"save_key":   "controls_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/stamina.png",
			"condition":  _popup_cond_stamina,
			"save_key":   "stamina_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/zoom.png",
			"condition":  _popup_cond_zoom,
			"save_key":   "zoom_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/falling-holds.png",
			"condition":  _popup_cond_falling_holds,
			"save_key":   "falling_holds_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/topping_out.png",
			"condition":  _popup_cond_granite_topping_out,
			"save_key":   "granite_topping_out_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/weather.png",
			"condition":  _popup_cond_weather,
			"save_key":   "weather_popup",
			"priority":   0,
		},
	]

# ── Level-specific popup conditions ──────────────────────────────────────
# Each returns true only when the loaded level matches the exact intended
# level file so the popup only fires once at the right moment.

## Gym, Level 1 — Controls (tutorial_popup.png)
static func _popup_cond_controls(level_path: String) -> bool:
	return level_path.ends_with("tutorial_01.json")

## Gym, Level 3 — Stamina (stamina.png)
static func _popup_cond_stamina(level_path: String) -> bool:
	return level_path.ends_with("tutorial_03.json")

## Gym, Level 4 — Zoom Out Guide (zoom.png)
static func _popup_cond_zoom(level_path: String) -> bool:
	return level_path.ends_with("tutorial_04.json")

## Gym, Level 6 — Falling Holds (falling-holds.png)
static func _popup_cond_falling_holds(level_path: String) -> bool:
	return level_path.ends_with("tutorial_06.json")

## Granite, Level 1 — Granite topping out (topping_out.png)
static func _popup_cond_granite_topping_out(level_path: String) -> bool:
	return level_path.ends_with("granite_crag_01.json")

## Granite, Level 2 — Weather (weather.png)
static func _popup_cond_weather(level_path: String) -> bool:
	return level_path.ends_with("granite_crag_02.json")

func _resolve_popup(level_path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)

	var best: Dictionary = {}
	for entry in POPUP_CONFIGS:
		var key: String = entry["save_key"]
		if cfg.get_value("popups", key, false):
			continue
		if entry["condition"].call(level_path):
			if best.is_empty() or entry["priority"] > best["priority"]:
				best = entry
	return best

func show_popup_image(image_path: String) -> void:
	if not instructions or not instructions_root:
		push_error("show_popup_image: Instructions nodes are null!")
		return

	if popup_sprite == null:
		push_error("show_popup_image: popup_sprite ($Instructions/Sprite2D) is null")
	else:
		var tex = load(image_path) as Texture2D
		if tex:
			popup_sprite.texture = tex
			print("  [Popup] Sprite2D texture set to: ", image_path)
		else:
			push_error("show_popup_image: Failed to load texture: " + image_path)

	instructions.process_mode = PROCESS_MODE_INHERIT
	instructions_root.modulate.a = 0.0
	instructions.show()
	instructions_root.show()

	var tween = create_tween()
	tween.tween_property(instructions_root, "modulate:a", 1.0, 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _mark_popup_seen(save_key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	cfg.set_value("popups", save_key, true)
	cfg.save(INSTRUCTIONS_SAVE_PATH)

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

	# Hide the menu background — it's persistent at root level and
	# wastes CPU on _process / _draw even when invisible.
	if has_node("/root/MenuBackgroundManager"):
		MenuBackgroundManager.hide()

	_build_popup_configs()
	add_to_group("main_scene")

	# TEMPORARY: Reset ALL popup seen-flags so every popup re-fires on each run.
	# Remove this entire block before shipping.
	var cfg_reset := ConfigFile.new()
	cfg_reset.set_value(INSTRUCTIONS_SECTION, INSTRUCTIONS_KEY, false)
	for _entry in POPUP_CONFIGS:
		cfg_reset.set_value("popups", _entry["save_key"], false)
	cfg_reset.save(INSTRUCTIONS_SAVE_PATH)
	print("  [DEBUG] All popup prefs reset")

	if instructions_root:
		instructions_root.modulate.a = 0.0

	# The popup instructions are hidden by default — don't waste
	# CPU running their internal Button._process every frame.
	instructions.process_mode = PROCESS_MODE_DISABLED

	_setup_skip_level()
	_setup_level_complete_overlay()
	_setup_demo_finished_overlay()
	_setup_pause_menu()
	_check_paths()

	if has_node("/root/LevelTransition"):
		var lt = get_node("/root/LevelTransition")
		lt.transition_started.connect(_on_transition_started)
		lt.level_loaded.connect(_on_level_loaded)
		lt.transition_finished.connect(_on_transition_finished)

	var initial_level = _get_initial_level()
	print("Initial level to load: ", initial_level)

	await _load_initial_level(initial_level)

	await get_tree().process_frame
	_show_popup_for_level(initial_level)
	print("=== MAIN SCENE READY COMPLETE ===")

# =============================================================================
#  POPUP ENTRY POINT
# =============================================================================

func _show_popup_for_level(level_path: String) -> void:
	var entry = _resolve_popup(level_path)
	if entry.is_empty():
		print("  [Popup] No popup for this level/state")
		return

	print("  [Popup] Showing: ", entry["image_path"], " (key: ", entry["save_key"], ")")
	show_popup_image(entry["image_path"])

	_active_popup_key = entry["save_key"]

var _active_popup_key: String = ""

# =============================================================================
#  SKIP LEVEL
# =============================================================================

func _setup_skip_level() -> void:
	if not skip_level_layer:
		push_error("SkipLevel CanvasLayer not found")
		return
	skip_level_layer.visible = false
	_reset_count = 0


func _increment_fall_count() -> void:
	if _is_level_skipped(_current_level_path):
		print("  [Skip] Level already skipped — not counting fall")
		return

	var env := _get_env_from_path(_current_level_path)
	var env_skip_count := _get_env_skip_count(env)
	if env_skip_count >= MAX_SKIPS_PER_ENV:
		print("  [Skip] Environment '%s' already used %d/%d skips — skip disabled" % [env, env_skip_count, MAX_SKIPS_PER_ENV])
		return

	_reset_count += 1
	print("  [Skip] Fall count: %d / %d   (env=%s, level=%s)" % [_reset_count, SKIP_THRESHOLD, env, _current_level_path])

	if _reset_count >= SKIP_THRESHOLD:
		_show_skip_button()


func _show_skip_button() -> void:
	if not skip_level_layer:
		push_error("  [Skip] Cannot show button — skip_level_layer is null!")
		return
	print("  [Skip] Showing skip button! count=%d threshold=%d" % [_reset_count, SKIP_THRESHOLD])
	skip_level_layer.visible = true


func _hide_skip_button(_instant: bool = false) -> void:
	if not skip_level_layer:
		return
	skip_level_layer.visible = false


func _reset_skip_state() -> void:
	_reset_count = 0
	_hide_skip_button(true)


func _mark_level_skipped(level_path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	cfg.set_value(SKIP_SECTION, level_path.md5_text(), true)

	# Track per-environment skip limit
	var env := _get_env_from_path(level_path)
	var env_count = cfg.get_value("env_skips", env, 0)
	cfg.set_value("env_skips", env, env_count + 1)
	print("  [Skip] Environment '%s' skips: %d / %d" % [env, env_count + 1, MAX_SKIPS_PER_ENV])

	cfg.save(INSTRUCTIONS_SAVE_PATH)

	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("record_level_skip"):
		gs.record_level_skip(level_path)


func _is_level_skipped(level_path: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	return cfg.get_value(SKIP_SECTION, level_path.md5_text(), false)


func _get_env_from_path(level_path: String) -> String:
	# e.g. "res://data/levels/granite_crag/granite_crag_01.json" -> "granite_crag"
	var parts := level_path.split("/")
	return parts[-2]


func _get_env_skip_count(env: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	return cfg.get_value("env_skips", env, 0)


func _get_next_level_path(current_path: String) -> String:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("get_next_level"):
		var nxt: String = gs.get_next_level(current_path)
		if nxt != "":
			return nxt

	if level_loader and level_loader.has_method("get_next_level_path"):
		return level_loader.get_next_level_path()

	return ""


func _on_skip_level_pressed() -> void:
	print("  [Skip] SKIP BUTTON PRESSED — loading next level")
	print("  [Skip] Current level: ", _current_level_path)
	_mark_level_skipped(_current_level_path)
	_hide_skip_button(true)

	var next_path := _get_next_level_path(_current_level_path)
	if next_path == "":
		_on_level_complete_menu_requested()
		return

	_on_next_level_requested(next_path)

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
	# Tab → toggle route view (Option A).
	# ui_focus_next is Tab by default; rename to "route_view" in Input Map if preferred.
	if event.is_action_pressed("ui_focus_next"):
		# Don't allow Tab-toggle during the auto-preview hold phase.
		# The return phase and normal FOLLOW_PLAYER allow it.
		if _preview_tween == null or not _preview_tween.is_valid():
			toggle_route_view()
		return

	if event.is_action_pressed("ui_cancel"):
		if pause_menu and not pause_menu.visible:
			_open_pause_menu()

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

	_reset_skip_state()

	# ── Route preview (Option B) ──────────────────────────────────────────────
	# Wait one more frame so the camera is positioned before the tween fires.
	await get_tree().process_frame
	start_route_preview()
	# ─────────────────────────────────────────────────────────────────────────

	print("  ✓ Level ready: ", path)

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

	if plyr.has_method("set_rope_system"):
		plyr.set_rope_system(rope_system)

	print("  ✓ Rope system ready at: ", belayer_pos)

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

	print("  ✓ Speed timer ready: ", time_limit, "s")

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
	print("🏃 Speed climb started!")

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

	_hide_skip_button(true)

	var completion_time := 0.0
	if current_discipline == ClimbingDiscipline.Type.SPEED and speed_timer:
		if speed_timer.has_method("get_time_remaining"):
			completion_time = speed_timer.get_time_remaining()

	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("record_level_completion"):
		game_state.record_level_completion(_current_level_path, completion_time)

	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)

	if level_complete_overlay:
		level_complete_overlay.show_overlay(_current_level_path)
	else:
		Transition.to("res://scenes/menus/level_completed.tscn")

func on_player_reset():
	# Manual reset (Escape/R key) — does NOT count toward skip threshold
	_do_player_reset()

func on_player_fell():
	# Fall detection — counts toward skip threshold
	print("  [Main] on_player_fell() called — counting toward skip")
	_increment_fall_count()
	_do_player_reset()

func _do_player_reset():
	if player and not player._grab_initialized:
		return

	position_player_at_spawn()
	camera_owned_by_main = false

	if player and player.has_method("reset_climb"):
		player.reset_climb()

	if current_discipline == ClimbingDiscipline.Type.SPEED and speed_timer:
		if speed_timer.has_method("stop_timer"):
			speed_timer.stop_timer()

func on_climb_start():
	print("🎬 Climb started!")

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
			_finish_preview()

	if current_discipline == ClimbingDiscipline.Type.SPEED:
		if speed_timer and speed_timer.has_method("start_timer"):
			speed_timer.start_timer()

	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("notify_climb_start"):
			hold.notify_climb_start()

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

	await LevelTransition.fade_out_only()

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

	await get_tree().create_timer(0.1).timeout

	await LevelTransition.fade_in_only()

	if pause_menu:
		pause_menu.pausing_enabled = true
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)

func _on_level_complete_menu_requested() -> void:
	cleanup_discipline_systems()
	Transition.to("res://scenes/menus/collections_select.tscn")

func _on_level_complete_restart_requested() -> void:
	print("Restarting: ", _current_level_path)

	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	if pause_menu:
		pause_menu.pausing_enabled = false

	await LevelTransition.fade_out_only()

	if player and player.has_method("reset_climb"):
		player.reset_climb()
	await get_tree().process_frame

	cleanup_discipline_systems()
	level_loader.unload_level()

	await _load_initial_level(_current_level_path)

	await get_tree().create_timer(0.1).timeout

	await LevelTransition.fade_in_only()

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

func _on_level_loaded():
	pass

# =============================================================================
#  INSTRUCTIONS / POPUP DISMISS
# =============================================================================

func _on_hide_instructions_pressed() -> void:
	if _active_popup_key != "":
		_mark_popup_seen(_active_popup_key)
		_active_popup_key = ""

	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	cfg.set_value(INSTRUCTIONS_SECTION, INSTRUCTIONS_KEY, true)
	cfg.save(INSTRUCTIONS_SAVE_PATH)

	if not instructions_root:
		instructions.hide()
		instructions.process_mode = PROCESS_MODE_DISABLED
		return

	var tween = create_tween()
	tween.tween_property(instructions_root, "modulate:a", 0.0, 0.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		instructions.hide()
		instructions.process_mode = PROCESS_MODE_DISABLED
	)
