extends Node2D
class_name LevelLoader

# Hold scenes mapping
const HOLD_SCENES = {
	"START":  "res://scenes/holds/start.tscn",
	"TOP":    "res://scenes/holds/top_out.tscn",
	"JUG":    "res://scenes/holds/jug.tscn",
	"CRIMP":  "res://scenes/holds/crimp.tscn",
	"SLOPER": "res://scenes/holds/sloper.tscn",
	"POCKET": "res://scenes/holds/pocket.tscn",
	"FOOT":   "res://scenes/holds/foothold.tscn"
}

const CRASHPAD_SCENE = "res://scenes/props/crashpad.tscn"

var loaded_scenes: Dictionary = {}
var holds_container: Node2D
var crashpads_container: Node2D
var dynamic_wall = null

# Current level metadata
var current_level_name: String        = ""
var current_level_grade: String       = ""
var current_level_environment: String = "gym"

# Discipline metadata
var current_level_discipline: String  = "bouldering"
var speed_time_limit: float           = 60.0
var rope_belayer_position: Vector2    = Vector2.ZERO

# =============================================================================
# READY
# =============================================================================
func _ready():
	for type_name in HOLD_SCENES:
		if ResourceLoader.exists(HOLD_SCENES[type_name]):
			loaded_scenes[type_name] = load(HOLD_SCENES[type_name])
		else:
			print("WARNING: Hold scene not found: " + HOLD_SCENES[type_name])

	if not has_node("Holds"):
		holds_container = Node2D.new()
		holds_container.name = "Holds"
		add_child(holds_container)
	else:
		holds_container = get_node("Holds")

	if not has_node("Crashpads"):
		crashpads_container = Node2D.new()
		crashpads_container.name = "Crashpads"
		add_child(crashpads_container)
	else:
		crashpads_container = get_node("Crashpads")

	call_deferred("_create_dynamic_wall")

# =============================================================================
# DYNAMIC WALL
# =============================================================================
func _create_dynamic_wall():
	var wall_script = preload("res://scripts/holds/dynamic_wall.gd")
	dynamic_wall = wall_script.new()
	assert(dynamic_wall != null, "dynamic_wall.gd must extend Node2D")
	dynamic_wall.name    = "DynamicWall"
	dynamic_wall.z_index = -10
	get_parent().add_child(dynamic_wall)

func update_wall_bounds():
	if dynamic_wall:
		dynamic_wall.calculate_bounds_from_holds(holds_container)

func get_wall_bounds() -> Dictionary:
	if dynamic_wall and dynamic_wall.has_method("get_bounds"):
		return dynamic_wall.get_bounds()
	return {"min": Vector2.ZERO, "max": Vector2.ZERO, "valid": false}

func get_dynamic_wall() -> Node2D:
	return dynamic_wall

# =============================================================================
# LEVEL LOADING
# =============================================================================
func load_level(path: String) -> bool:
	clear_holds()
	clear_crashpads()

	if not FileAccess.file_exists(path):
		print("ERROR: Level file not found: " + path)
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("ERROR: Could not open: " + path)
		return false

	var json_string = file.get_as_text()
	file.close()

	var json  = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		print("ERROR: Invalid JSON in: " + path)
		return false

	var level_data = json.data
	if not "holds" in level_data:
		print("ERROR: No 'holds' array in: " + path)
		return false

	# ── Metadata ──────────────────────────────────────────────────────────────
	current_level_name        = level_data.get("name",        "")
	current_level_grade       = level_data.get("grade",       "")
	current_level_environment = level_data.get("environment", "gym")
	current_level_discipline  = level_data.get("discipline",  "bouldering")

	speed_time_limit = float(level_data.get("speed_time_limit", 60.0))
	print("LevelLoader: speed_time_limit = ", speed_time_limit, " s  (discipline: ", current_level_discipline, ")")

	if "belayer_position" in level_data:
		var bd = level_data.belayer_position
		rope_belayer_position = Vector2(bd.get("x", 0), bd.get("y", 0))
	else:
		rope_belayer_position = Vector2.ZERO

	print("Setting environment to: " + current_level_environment)
	set_environment_from_string(current_level_environment)

	print("Discipline: " + current_level_discipline)
	if current_level_discipline == "speed":
		print("  Time limit: " + str(speed_time_limit) + " seconds")
	elif current_level_discipline == "roped":
		print("  Belayer position: " + str(rope_belayer_position))

	await get_tree().process_frame

	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("set_climb_metadata"):
		game_state.set_climb_metadata(path, current_level_name, current_level_grade)

	print("\n=== SPAWNING HOLDS ===")
	for hold_data in level_data.holds:
		spawn_hold(hold_data)
		await get_tree().process_frame

	await get_tree().process_frame
	await get_tree().process_frame

	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.has_method("_update_sprite_for_environment"):
			hold._update_sprite_for_environment()

	load_crashpads(level_data)

	# ── Wall polygon ──────────────────────────────────────────────────────────
	var has_custom_polygon = false
	if "wall_polygon" in level_data and dynamic_wall:
		if dynamic_wall.has_method("set_polygon_data"):
			await get_tree().process_frame
			dynamic_wall.set_polygon_data(level_data.wall_polygon)
			has_custom_polygon = true
			print("  ✓ Loaded wall polygon with ",
				  level_data.wall_polygon.get("points", []).size(), " points")
			if "top_edge_indices" in level_data.wall_polygon:
				print("  ✓ Polygon has top edge indices: ",
					  level_data.wall_polygon.top_edge_indices)

	update_wall_bounds()

	if has_custom_polygon and dynamic_wall:
		await get_tree().process_frame
		await get_tree().process_frame
		if dynamic_wall.has_method("_create_top_edge_holds"):
			print("  Creating top edge holds...")
			dynamic_wall._create_top_edge_holds()
			var top_hold_count = 0
			for child in dynamic_wall.get_children():
				if child.has_meta("is_top_edge_hold"):
					top_hold_count += 1
					print("    - Created top hold at: ", child.global_position)
			if top_hold_count > 0:
				print("  ✓ Created ", top_hold_count, " top edge holds")
			elif "top_edge_indices" in dynamic_wall and not dynamic_wall.top_edge_indices.is_empty():
				print("  ⚠ WARNING: top_edge_indices exist but no holds created!")
				print("    Indices: ", dynamic_wall.top_edge_indices)

	# ── Weather ───────────────────────────────────────────────────────────────
	var weather_type      := int(level_data.get("weather",           0))
	var weather_intensity := float(level_data.get("weather_intensity", 1.0))
	if dynamic_wall and dynamic_wall.has_method("set_weather"):
		dynamic_wall.set_weather(weather_type, weather_intensity)
		if weather_type > 0:
			print("  ✓ Weather set: type=", weather_type,
				  " intensity=", weather_intensity)
		else:
			print("  Weather: none")

	print("\n═══════════════════════════════════════")
	print("✓ LEVEL LOADED: " + path)
	if current_level_name != "":
		print("  Name: " + current_level_name + " (" + current_level_grade + ")")
	print("  Environment: " + current_level_environment)
	print("  Discipline:  " + current_level_discipline)
	if current_level_discipline == "speed":
		print("    Time limit: " + str(speed_time_limit) + "s")
	elif current_level_discipline == "roped":
		print("    Belayer at: " + str(rope_belayer_position))
	print("  Holds: " + str(level_data.holds.size()))
	if "crashpads" in level_data:
		print("  Crashpads: " + str(level_data.crashpads.size()))
	if "wall_polygon" in level_data:
		print("  Wall: Custom polygon shape")
		if "top_edge_indices" in level_data.wall_polygon:
			print("  Top edges: " + str(level_data.wall_polygon.top_edge_indices))
	if weather_type > 0:
		print("  Weather: type=", weather_type, " intensity=", weather_intensity)
	print("═══════════════════════════════════════\n")

	return true

# =============================================================================
# ENVIRONMENT
# =============================================================================
func set_environment_from_string(env_name: String):
	if not has_node("/root/EnvironmentConfig"):
		print("WARNING: EnvironmentConfig not available")
		return

	var env_config = get_node("/root/EnvironmentConfig")
	var matched    = false

	for env_type in env_config.get_all_environment_types():
		if env_config.get_environment_name(env_type).to_lower() == env_name.to_lower():
			env_config.set_environment(env_type)
			print("Level environment set to: " +
				  env_config.get_environment_name(env_type).to_upper())
			matched = true
			break

	if not matched:
		print("WARNING: Unknown environment '" + env_name +
			  "', defaulting to first registered environment")
		var all_types = env_config.get_all_environment_types()
		if not all_types.is_empty():
			env_config.set_environment(all_types[0])

	if dynamic_wall and dynamic_wall.has_method("update_environment_settings"):
		dynamic_wall.update_environment_settings()

# =============================================================================
# HOLDS
# =============================================================================
func spawn_hold(hold_data: Dictionary) -> Node2D:
	var type_name = hold_data.get("type", "JUG")
	if type_name not in loaded_scenes:
		print("WARNING: Unknown hold type: " + type_name)
		return null

	var hold = loaded_scenes[type_name].instantiate()
	hold.global_position = Vector2(hold_data.get("x", 0.0), hold_data.get("y", 0.0))

	if "hold_type" in hold:
		hold.hold_type = type_name
		print("  Spawned %s hold at (%.1f, %.1f)" % [
			type_name, hold.global_position.x, hold.global_position.y])
	else:
		print("  WARNING: Hold at (%.1f, %.1f) missing 'hold_type' property!" % [
			hold.global_position.x, hold.global_position.y])

	if hold.has_method("set_hold_type_from_string"):
		hold.set_hold_type_from_string(type_name)

	holds_container.add_child(hold)
	hold.add_to_group("holds")

	# ── Attach modifiers ──────────────────────────────────────────────────────
	var modifiers_data: Array = hold_data.get("modifiers", [])
	if not modifiers_data.is_empty():
		_attach_modifiers_to_hold(hold, modifiers_data)

	return hold

func _attach_modifiers_to_hold(hold: Node2D, modifiers_data: Array) -> void:
	var registry := get_node_or_null("/root/HoldModifierRegistry")
	if registry == null:
		push_warning("LevelLoader: HoldModifierRegistry autoload not found — modifiers skipped.")
		return

	for mod_data in modifiers_data:
		if not mod_data is Dictionary:
			continue

		var modifier = registry.create_modifier_from_data(mod_data)
		if modifier == null:
			push_warning("LevelLoader: could not create modifier '%s'" % mod_data.get("type", "?"))
			continue

		# Set the hold reference before adding to tree so on_hold_ready() fires correctly
		if "hold" in modifier:
			modifier.hold = hold

		hold.add_child(modifier)

		# Fire on_hold_ready() now that the modifier is fully in the scene tree
		if modifier.has_method("on_hold_ready"):
			modifier.on_hold_ready()

		print("  ✓ Attached '%s' modifier to %s hold" % [
			mod_data.get("type", "?"),
			hold.get("hold_type") if "hold_type" in hold else "?"])

func clear_holds():
	if holds_container:
		for child in holds_container.get_children():
			child.queue_free()

func get_hold_count() -> int:
	return holds_container.get_child_count() if holds_container else 0

func get_start_holds() -> Array[Node2D]:
	var starts: Array[Node2D] = []
	if holds_container:
		for hold in holds_container.get_children():
			if hold.has_method("is_start_hold") and hold.is_start_hold():
				starts.append(hold)
	return starts

func get_top_holds() -> Array[Node2D]:
	var tops: Array[Node2D] = []
	if holds_container:
		for hold in holds_container.get_children():
			if hold.has_method("is_top_out") and hold.is_top_out():
				tops.append(hold)
	if dynamic_wall:
		for child in dynamic_wall.get_children():
			if child.has_meta("is_top_edge_hold"):
				tops.append(child)
	return tops

func get_player_spawn_position() -> Vector2:
	print("GET_PLAYER_SPAWN_POSITION called")
	print("\n=== GET_PLAYER_SPAWN_POSITION ===")
	var starts = get_start_holds()
	print("Found %d START holds" % starts.size())

	if starts.size() == 0:
		print("⚠️  WARNING: No START holds found!")
		if holds_container:
			for i in min(10, holds_container.get_child_count()):
				var hold        = holds_container.get_child(i)
				var has_method  = hold.has_method("is_start_hold")
				var is_start    = has_method and hold.is_start_hold()
				var hold_type   = hold.get("hold_type") if "hold_type" in hold else "NO_TYPE"
				print("  [%d] hold_type='%s', has_method=%s, is_start=%s, pos=(%.1f, %.1f)" % [
					i, hold_type, has_method, is_start,
					hold.global_position.x, hold.global_position.y])
		return Vector2.ZERO

	if starts.size() == 1:
		var hold_point = starts[0].get_node_or_null("HoldPoint")
		var spawn_pos  = (hold_point.global_position if hold_point
						  else starts[0].global_position) + Vector2(0, 80)
		print("Single start hold spawn: (%.1f, %.1f)" % [spawn_pos.x, spawn_pos.y])
		return spawn_pos

	var sum = Vector2.ZERO
	for hold in starts:
		var hold_point = hold.get_node_or_null("HoldPoint")
		if hold_point:
			sum += hold_point.global_position
			print("  Start hold (HoldPoint) at: (%.1f, %.1f)" % [
				hold_point.global_position.x, hold_point.global_position.y])
		else:
			sum += hold.global_position
			print("  Start hold at: (%.1f, %.1f)" % [
				hold.global_position.x, hold.global_position.y])

	var spawn_pos = sum / starts.size() + Vector2(0, 80)
	print("Average spawn position: (%.1f, %.1f)" % [spawn_pos.x, spawn_pos.y])
	print("===============================\n")
	return spawn_pos

func validate_level() -> Dictionary:
	var result = {
		"valid":       false,
		"has_start":   false,
		"has_top":     false,
		"start_count": 0,
		"top_count":   0,
		"total_holds": 0,
		"errors":      []
	}
	result.total_holds = get_hold_count()
	if result.total_holds == 0:
		result.errors.append("No holds in level")
		return result

	var starts = get_start_holds()
	var tops   = get_top_holds()
	result.start_count = starts.size()
	result.top_count   = tops.size()
	result.has_start   = result.start_count > 0
	result.has_top     = result.top_count   > 0

	if not result.has_start: result.errors.append("No START holds")
	if not result.has_top:   result.errors.append("No TOP holds")

	result.valid = result.has_start and result.has_top
	return result

# =============================================================================
# CRASHPADS
# =============================================================================
func load_crashpads(level_data: Dictionary) -> void:
	if not "crashpads" in level_data:
		print("  No crashpads in level data")
		return

	if not crashpads_container:
		crashpads_container = Node2D.new()
		crashpads_container.name = "Crashpads"
		add_child(crashpads_container)

	if not ResourceLoader.exists(CRASHPAD_SCENE):
		push_error("Crashpad scene not found at: " + CRASHPAD_SCENE)
		return

	var crashpad_scene = load(CRASHPAD_SCENE)
	var crashpad_count = 0

	var belayer_exclusion_radius = 120.0
	var has_belayer = (current_level_discipline == "roped"
					   and rope_belayer_position != Vector2.ZERO)

	print("\n=== SPAWNING CRASHPADS ===")
	if has_belayer:
		print("  Roped mode — excluding crashpads near belayer at: ",
			  rope_belayer_position)

	for crashpad_data in level_data.crashpads:
		var crashpad_pos = Vector2(crashpad_data.get("x", 0),
								   crashpad_data.get("y", 0))
		if has_belayer and crashpad_pos.distance_to(rope_belayer_position) \
				< belayer_exclusion_radius:
			print("  Skipped crashpad at: ", crashpad_pos,
				  " (too close to belayer)")
			continue

		var crashpad = crashpad_scene.instantiate()
		crashpad.global_position = crashpad_pos
		crashpads_container.add_child(crashpad)
		crashpad.add_to_group("crashpads")
		crashpad_count += 1
		print("  Spawned crashpad at: " + str(crashpad.global_position))

	await get_tree().process_frame

	for crashpad in get_tree().get_nodes_in_group("crashpads"):
		if crashpad.has_method("_update_sprite_for_environment"):
			crashpad._update_sprite_for_environment()

	print("  Loaded " + str(crashpad_count) + " crashpads")

func clear_crashpads():
	if crashpads_container:
		for child in crashpads_container.get_children():
			child.queue_free()

func get_crashpad_count() -> int:
	return crashpads_container.get_child_count() if crashpads_container else 0

# =============================================================================
# DISCIPLINE GETTERS
# =============================================================================

func get_discipline() -> String:
	return current_level_discipline

func get_speed_time_limit() -> float:
	return speed_time_limit

func get_belayer_position() -> Vector2:
	return rope_belayer_position

func is_bouldering() -> bool:
	return current_level_discipline == "bouldering"

func is_roped() -> bool:
	return current_level_discipline == "roped"

func is_speed() -> bool:
	return current_level_discipline == "speed"

func unload_level() -> void:
	var holds = get_node_or_null("Holds")
	if holds:
		for child in holds.get_children():
			child.queue_free()
	print("LevelLoader: level unloaded")
