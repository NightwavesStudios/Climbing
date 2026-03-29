extends Node2D
## Main game scene with dynamic wall integration and climbing disciplines

@export var default_level_path: String = "res://scenes/levels/tutorial/ladder.json"

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
var current_discipline: int = 0

var level_complete_overlay: CanvasLayer = null

const INSTRUCTIONS_SAVE_PATH := "user://prefs.cfg"
const INSTRUCTIONS_SECTION  := "instructions"
const INSTRUCTIONS_KEY      := "shown"

# =============================================================================
# POPUP SYSTEM
# =============================================================================
# Each entry describes one popup condition.
# Fields:
#   image_path  – texture loaded onto the Sprite2D (or TextureRect)
#   condition   – callable that returns true when this popup should show;
#                 it receives the level path as its only argument.
#   save_key    – unique key written to prefs.cfg so the popup only fires once.
#   priority    – higher wins when multiple conditions match simultaneously.
#
# Add new popups inside _build_popup_configs() — no changes needed anywhere else.
# ─────────────────────────────────────────────────────────────────────────────
var POPUP_CONFIGS: Array = []

func _build_popup_configs() -> void:
	POPUP_CONFIGS = [
		{
			"image_path": "res://assets/images/popups/tutorial_popup.png",
			"condition":  _popup_cond_first_launch,
			"save_key":   "tutorial_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/topping_out.png",
			"condition":  _popup_cond_first_granite,
			"save_key":   "granite_topping_out_popup",
			"priority":   10,
		},
		# ── Add more popups below ─────────────────────────────────────────────
		# {
		#     "image_path": "res://assets/images/popups/speed_tips.png",
		#     "condition":  _popup_cond_first_speed,
		#     "save_key":   "speed_tips_popup",
		#     "priority":   5,
		# },
	]

# ── Condition callables ───────────────────────────────────────────────────────

## Tutorial popup — always a valid trigger; once-only gating is handled
## entirely by save_key inside _resolve_popup, not here.
static func _popup_cond_first_launch(_level_path: String) -> bool:
	return true

## Granite topping-out popup — fires whenever a granite_crag level loads.
## _resolve_popup skips it automatically after the first dismissal.
static func _popup_cond_first_granite(level_path: String) -> bool:
	return "granite_crag" in level_path

# ─────────────────────────────────────────────────────────────────────────────

## Returns the highest-priority popup config that should fire for *level_path*,
## or an empty Dictionary if none applies.
func _resolve_popup(level_path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)   # OK to fail — missing keys default to false

	var best: Dictionary = {}
	for entry in POPUP_CONFIGS:
		var key: String = entry["save_key"]
		if cfg.get_value("popups", key, false):
			continue   # already shown
		if entry["condition"].call(level_path):
			if best.is_empty() or entry["priority"] > best["priority"]:
				best = entry
	return best

## Swap the Sprite2D texture and fade the overlay in.
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

	# Fade in
	instructions_root.modulate.a = 0.0
	instructions.show()
	instructions_root.show()

	var tween = create_tween()
	tween.tween_property(instructions_root, "modulate:a", 1.0, 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

## Mark a popup's save_key as seen so it never fires again.
func _mark_popup_seen(save_key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	cfg.set_value("popups", save_key, true)
	cfg.save(INSTRUCTIONS_SAVE_PATH)

# =============================================================================
# PATH CHECK (dev helper)
# =============================================================================

func _check_paths() -> void:
	var paths = [
		"res://scenes/levels/tutorial/ladder.json",
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
		"res://scripts/holds/dynamic_wall.gd",
		"res://scripts/holds/hold_modifiers.gd",
		"res://scripts/levels/weather_modifier.gd",
		"res://scripts/systems/rope_system.gd",
		"res://scripts/levels/speed_timer.gd",
		"res://scenes/levels/granite_crag/granite_crag_01.json",
	]
	for path in paths:
		print("EXISTS ", path, ": ", FileAccess.file_exists(path) or ResourceLoader.exists(path))

# =============================================================================
# READY
# =============================================================================

func _ready():
	print("=== MAIN SCENE READY ===")

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

	_setup_level_complete_overlay()
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
# POPUP ENTRY POINT
# =============================================================================

## Called after every level load. Resolves which popup (if any) to show,
## swaps the image, and fades it in.
func _show_popup_for_level(level_path: String) -> void:
	var entry = _resolve_popup(level_path)
	if entry.is_empty():
		print("  [Popup] No popup for this level/state")
		return

	print("  [Popup] Showing: ", entry["image_path"], " (key: ", entry["save_key"], ")")
	show_popup_image(entry["image_path"])

	# Store the active key so _on_hide_instructions_pressed knows what to mark.
	_active_popup_key = entry["save_key"]

var _active_popup_key: String = ""

# =============================================================================
# PAUSE MENU
# =============================================================================

func _setup_pause_menu() -> void:
	if not pause_menu:
		push_error("PauseMenu node not found — add it to the scene tree")
		return

	pause_menu.resumed.connect(_on_pause_resumed)
	pause_menu.visible = false

func _unhandled_input(event: InputEvent) -> void:
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
# LEVEL COMPLETE OVERLAY
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

# =============================================================================
# LEVEL LOADING
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

	print("  ✓ Level ready: ", path)

# =============================================================================
# DISCIPLINE SYSTEM SETUP
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

	var RopeSystemScript = load("res://scripts/systems/rope_system.gd")
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
# SPEED CALLBACKS
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
# PLAYER SPAWN
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
# CAMERA
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
# TOP-OUT DETECTION
# =============================================================================

func check_player_top_out() -> bool:
	if not player or not dynamic_wall:
		return false
	if not dynamic_wall.has_method("get_top_edge_y"):
		return false

	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if not env_config or env_config.get_current_environment() != 1:
		return false

	return player.global_position.y < (dynamic_wall.get_top_edge_y() + 50.0)

func _process(_delta):
	if check_player_top_out():
		pass

# =============================================================================
# PUBLIC API
# =============================================================================

func get_current_level_path() -> String:
	return _current_level_path

func set_current_level_path(path: String) -> void:
	_current_level_path = path

# =============================================================================
# LEVEL EVENTS
# =============================================================================

func on_level_complete():
	print("=== LEVEL COMPLETE ===")

	if _current_level_path == "":
		push_error("_current_level_path is empty!")
		return

	if pause_menu and pause_menu.visible:
		pause_menu.hide_pause_menu()

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
	if player and not player._grab_initialized:
		return

	position_player_at_spawn()
	center_camera_on_route()

	if player and player.has_method("reset_climb"):
		player.reset_climb()

	if current_discipline == ClimbingDiscipline.Type.SPEED and speed_timer:
		if speed_timer.has_method("stop_timer"):
			speed_timer.stop_timer()

func on_climb_start():
	print("🎬 Climb started!")

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
# OVERLAY SIGNAL HANDLERS
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

	# ── Show popup for the new level (if any) ────────────────────────────────
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
# DISCIPLINE CLEANUP
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
# MESSAGES
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
# TRANSITION CALLBACKS
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
# INSTRUCTIONS / POPUP DISMISS
# =============================================================================

func _on_hide_instructions_pressed() -> void:
	# Mark whichever popup is currently showing as seen
	if _active_popup_key != "":
		_mark_popup_seen(_active_popup_key)
		_active_popup_key = ""

	# Also mark the legacy "shown" flag for backwards-compat
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	cfg.set_value(INSTRUCTIONS_SECTION, INSTRUCTIONS_KEY, true)
	cfg.save(INSTRUCTIONS_SAVE_PATH)

	if not instructions_root:
		instructions.hide()
		return

	var tween = create_tween()
	tween.tween_property(instructions_root, "modulate:a", 0.0, 0.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		instructions.hide()
	)
