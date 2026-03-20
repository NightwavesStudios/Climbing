extends Node2D
## Main game scene with dynamic wall integration and climbing disciplines

@export var default_level_path: String = "res://scenes/levels/tutorial/ladder.json"

@onready var level_loader: LevelLoader = $LevelLoader
@onready var player: CharacterBody2D = $Character
@onready var camera: Camera2D = $Camera2D
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var instructions: CanvasLayer = $Instructions
@onready var instructions_root: ColorRect = $Instructions/ColorRect

var _current_level_path: String = ""
var dynamic_wall: Node2D = null

var rope_system: Node2D = null
var speed_timer: CanvasLayer = null
var current_discipline: int = 0

var level_complete_overlay: CanvasLayer = null

const INSTRUCTIONS_SAVE_PATH := "user://prefs.cfg"
const INSTRUCTIONS_SECTION := "instructions"
const INSTRUCTIONS_KEY := "shown"

func _ready():
	print("=== MAIN SCENE READY ===")

	add_to_group("main_scene")

	# TEMPORARY: Reset instructions so they always show for testing
	var cfg_reset := ConfigFile.new()
	cfg_reset.set_value(INSTRUCTIONS_SECTION, INSTRUCTIONS_KEY, false)
	cfg_reset.save(INSTRUCTIONS_SAVE_PATH)
	print("  [DEBUG] Instructions pref reset")

	if instructions_root:
		instructions_root.modulate.a = 0.0

	_setup_level_complete_overlay()
	_setup_pause_menu()

	if has_node("/root/LevelTransition"):
		var lt = get_node("/root/LevelTransition")
		lt.transition_started.connect(_on_transition_started)
		lt.level_loaded.connect(_on_level_loaded)
		lt.transition_finished.connect(_on_transition_finished)

	var initial_level = _get_initial_level()
	print("Initial level to load: ", initial_level)

	await _load_initial_level(initial_level)

	await get_tree().process_frame
	_show_instructions_if_needed()

	print("=== MAIN SCENE READY COMPLETE ===")

# =============================================================================
# INSTRUCTIONS
# =============================================================================

func _show_instructions_if_needed() -> void:
	print("=== INSTRUCTIONS DEBUG ===")
	print("  instructions: ", instructions)
	print("  instructions_root: ", instructions_root)

	if not instructions or not instructions_root:
		push_error("Instructions nodes are null!")
		return

	print("  instructions.visible: ", instructions.visible)
	print("  instructions_root.visible: ", instructions_root.visible)
	print("  instructions_root.modulate: ", instructions_root.modulate)

	var cfg := ConfigFile.new()
	if cfg.load(INSTRUCTIONS_SAVE_PATH) == OK:
		var already_shown = cfg.get_value(INSTRUCTIONS_SECTION, INSTRUCTIONS_KEY, false)
		print("  already_shown: ", already_shown)
		if already_shown:
			print("  SKIPPING — already shown before")
			return
	else:
		print("  No prefs file found — first time")

	instructions_root.modulate.a = 0.0
	instructions.show()
	instructions_root.show()

	print("  instructions.visible after show(): ", instructions.visible)
	print("  instructions_root.visible after show(): ", instructions_root.visible)

	var tween = create_tween()
	tween.tween_property(instructions_root, "modulate:a", 1.0, 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	print("  Tween created — should fade in now")
	print("=========================")

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

	# ── Always create a fresh RopeSystem — never reuse a stale one ───────────
	# cleanup_discipline_systems() calls queue_free() which is deferred,
	# so is_instance_valid() can still return true in the same frame.
	# We null-check the variable instead and always construct a new instance.
	if rope_system != null:
		push_warning("setup_roped_climbing: rope_system was not null — forcing cleanup")
		if is_instance_valid(rope_system):
			rope_system.set_process(false)
			rope_system.queue_free()
		rope_system = null
		# Wait one frame so queue_free actually lands before we add the new node
		await get_tree().process_frame

	var RopeSystemScript = load("res://scripts/systems/rope_system.gd")
	if not RopeSystemScript:
		print("  ERROR: Could not load rope_system.gd!")
		return

	rope_system = RopeSystemScript.new()
	rope_system.name = "RopeSystem"
	add_child(rope_system)
	await get_tree().process_frame   # let _ready() run

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

	# ── Tear down discipline systems and wait for queue_free to land ──────────
	# cleanup_discipline_systems() calls queue_free() on rope_system, which is
	# deferred. Without the extra frame here, setup_roped_climbing() would see
	# is_instance_valid(rope_system) == true and skip creating a new one, then
	# call setup_rope() on a node that's mid-free → "freed instance" crash.
	cleanup_discipline_systems()
	await get_tree().process_frame   # let queue_free land before loading next

	level_loader.unload_level()

	await _load_initial_level(next_level_path)

	await get_tree().process_frame
	await get_tree().process_frame
	if player and player.has_method("reset_climb"):
		player.reset_climb()

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

	cleanup_discipline_systems()
	await get_tree().process_frame   # same fix — let queue_free land

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

func cleanup_discipline_systems():
	if rope_system and is_instance_valid(rope_system):
		if rope_system.has_method("cleanup"):
			rope_system.cleanup()   # sets is_setup=false, set_process(false), queue_free()
		else:
			rope_system.queue_free()
	rope_system = null   # null immediately — don't wait for queue_free

	if speed_timer and is_instance_valid(speed_timer):
		if speed_timer.has_method("cleanup"):
			speed_timer.cleanup()
		else:
			speed_timer.queue_free()
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
# INSTRUCTIONS
# =============================================================================

func _on_hide_instructions_pressed() -> void:
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
