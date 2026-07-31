extends Node
## Autoload singleton for managing game state, collections, and progression

# Debug flags
var debug_unlock_all: bool = false  # Set to true to unlock all collections and levels

# Current gameplay state
var current_level: String = ""
var current_collection: String = ""
var last_completed_level: String = ""

# Progress tracking
var completed_levels: Dictionary = {}  # level_path: completion_time
var completed_collections: Array[String] = []

# Stats tracking
var total_falls: int = 0
var total_falling_holds: int = 0

# Weekly level best times: weekly_level_path -> best_time_seconds
var weekly_best_times: Dictionary = {}

# Climb metadata storage (name and grade for each level)
var climb_metadata: Dictionary = {}  # level_path: {name: String, grade: String}

# Collection definitions
const COLLECTIONS = {
	"intro-gym": {
		"name": "Gym",
		"description": "Learn the basics of climbing",
		"unlock_requirement": {"type": "always"},
		"levels": [
			"res://data/levels/tutorial/tutorial_01.json",
			"res://data/levels/tutorial/tutorial_02.json",
			"res://data/levels/tutorial/tutorial_03.json",
			"res://data/levels/tutorial/tutorial_04.json",
			"res://data/levels/tutorial/tutorial_05.json",
			"res://data/levels/tutorial/tutorial_06.json",
			"res://data/levels/tutorial/tutorial_07.json",
			"res://data/levels/tutorial/tutorial_08.json",
			"res://data/levels/tutorial/tutorial_09.json",
			"res://data/levels/tutorial/tutorial_10.json",
			"res://data/levels/tutorial/tutorial_11.json",
			"res://data/levels/tutorial/tutorial_12.json",
			"res://data/levels/tutorial/tutorial_13.json",
		]
	},
	"granite-crag": {
		"name": "Granite",
		"description": "",
		"unlock_requirement": {
			"type": "collection_complete",
			"collection": "intro-gym"
		},
		"levels": [
			"res://data/levels/granite_crag/granite_crag_01.json",
			"res://data/levels/granite_crag/granite_crag_02.json",
			"res://data/levels/granite_crag/granite_crag_03.json",
			"res://data/levels/granite_crag/granite_crag_04.json",
			"res://data/levels/granite_crag/granite_crag_05.json",
			"res://data/levels/granite_crag/granite_crag_06.json",
			"res://data/levels/granite_crag/granite_crag_07.json",
			"res://data/levels/granite_crag/granite_crag_08.json",
			"res://data/levels/granite_crag/granite_crag_09.json",
			"res://data/levels/granite_crag/granite_crag_10.json",
		]
	},
	"sandstone": {
	"name": "Sandstone",
	"description": "",
	"unlock_requirement": {
		"type": "collection_complete",
		"collection": "intro-gym"  # or whatever should gate it
	},
	"levels": [
		"res://data/levels/sandstone/sandstone_01.json",
		"res://data/levels/sandstone/sandstone_02.json",
		# etc.
	]
},
	"building": {
		"name": "Building",
		"description": "",
		"unlock_requirement": {
			"type": "collection_complete",
			"collection": "sandstone"
		},
		"levels": [
			"res://data/levels/building/building_01.json",
			"res://data/levels/building/building_02.json"
		]
	},
	"deep-water-solo": {
	"name": "Deep Water Solo",
	"description": "",
	"unlock_requirement": {
		"type": "collection_complete",
		"collection": "intro-gym"
	},
	"levels": [
		"res://data/levels/dws/dws_01.json",
		"res://data/levels/dws/dws_02.json",
	]
	},
	"ice": {
		"name": "Ice",
		"description": "",
		"unlock_requirement": {
			"type": "collection_complete",
			"collection": "intro-gym"
		},
		"levels": [
			"res://data/levels/ice/ice_01.json",
			"res://data/levels/ice/ice_02.json",
		]
	},
}

# =============================================================================
# READY
# =============================================================================

func _ready():
	current_level = ""
	current_collection = ""
	load_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Save game progress when the window is closed from anywhere
		save_game()

# =============================================================================
# LEVEL MANAGEMENT
# =============================================================================

func set_current_level(level_path: String) -> void:
	current_level = level_path
	_update_current_collection_from_level(level_path)
	print("GameState: Level set to " + level_path)

func get_current_level() -> String:
	return current_level

func get_last_completed_level() -> String:
	return last_completed_level

func record_level_completion(level_path: String, completion_time: float) -> void:
	last_completed_level = level_path
	_update_current_collection_from_level(level_path)

	var is_first_completion := level_path not in completed_levels

	if is_first_completion:
		completed_levels[level_path] = completion_time
		print("GameState: Completed " + level_path + " in " + str(completion_time) + "s")

		# ── Achievement: first-ever climb ──────────────────────────────────
		if completed_levels.size() == 1:
			if get_node_or_null("/root/Achievements") and Achievements.has_method("check_first_climb"):
				Achievements.check_first_climb()

		_check_collection_completion(level_path)
		save_game()
	else:
		if completion_time < completed_levels[level_path]:
			completed_levels[level_path] = completion_time
			print("GameState: New best time for " + level_path + ": " + str(completion_time) + "s")
			save_game()

func is_level_completed(level_path: String) -> bool:
	return level_path in completed_levels or is_level_skipped(level_path)

func record_level_skip(level_path: String) -> void:
	if level_path not in completed_levels:
		completed_levels[level_path] = -1.0 # Use -1.0 to indicate skipped
		_check_collection_completion(level_path)
		save_game()

func is_level_skipped(level_path: String) -> bool:
	return completed_levels.get(level_path, 0.0) == -1.0

func get_level_completion_time(level_path: String) -> float:
	return completed_levels.get(level_path, 0.0)

# =============================================================================
# CLIMB METADATA (Name & Grade)
# =============================================================================

func set_climb_metadata(level_path: String, climb_name: String, grade: String) -> void:
	"""Set the name and difficulty grade for a climb"""
	climb_metadata[level_path] = {
		"name": climb_name,
		"grade": grade
	}
	print("GameState: Set metadata for " + level_path + " - " + climb_name + " (" + grade + ")")

func get_climb_name(level_path: String) -> String:
	"""Get the name of a climb (returns empty string if not set)"""
	if level_path in climb_metadata:
		return climb_metadata[level_path].get("name", "")
	return ""

func get_climb_grade(level_path: String) -> String:
	"""Get the difficulty grade of a climb (returns empty string if not set)"""
	if level_path in climb_metadata:
		return climb_metadata[level_path].get("grade", "")
	return ""

func get_climb_metadata(level_path: String) -> Dictionary:
	"""Get full metadata for a climb"""
	return climb_metadata.get(level_path, {"name": "", "grade": ""})

# =============================================================================
# COLLECTION MANAGEMENT
# =============================================================================

func set_current_collection(collection_id: String) -> void:
	current_collection = collection_id
	print("GameState: Collection set to " + collection_id)

func get_current_collection() -> String:
	return current_collection

func get_collection_data(collection_id: String) -> Dictionary:
	return COLLECTIONS.get(collection_id, {})

func get_all_collection_ids() -> Array:
	return COLLECTIONS.keys()

func is_collection_unlocked(collection_id: String) -> bool:
	if debug_unlock_all:
		return true

	if collection_id not in COLLECTIONS:
		return false

	var req = COLLECTIONS[collection_id].unlock_requirement

	match req.type:
		"always":
			return true

		"collection_complete":
			return is_collection_completed(req.collection)

		"total_levels":
			return get_total_completed_levels() >= req.count

		"collections_complete":
			return completed_collections.size() >= req.count

		"specific_levels":
			for level in req.levels:
				if not is_level_completed(level):
					return false
			return true

	return false

func is_collection_completed(collection_id: String) -> bool:
	return collection_id in completed_collections

func get_collection_progress(collection_id: String) -> Dictionary:
	var data = get_collection_data(collection_id)
	if data.is_empty():
		return {"completed": 0, "total": 0, "percentage": 0.0}

	var levels = data.levels
	var completed_count = 0

	for level in levels:
		if is_level_completed(level):
			completed_count += 1

	return {
		"completed": completed_count,
		"total": levels.size(),
		"percentage": (float(completed_count) / float(levels.size())) * 100.0
	}

func _check_collection_completion(level_path: String) -> void:
	for collection_id in COLLECTIONS:
		var levels = COLLECTIONS[collection_id].levels
		if level_path not in levels:
			continue

		var all_complete = true
		for level in levels:
			if not is_level_completed(level):
				all_complete = false
				break

		if all_complete and collection_id not in completed_collections:
			completed_collections.append(collection_id)
			print("COLLECTION COMPLETE: " + COLLECTIONS[collection_id].name)

			# ── Achievement: collection-based checks ───────────────────────
			if get_node_or_null("/root/Achievements"):
				match collection_id:
					"intro-gym":
						Achievements.check_gym_rat()
					# "granite-crag" achievement (ON_REAL_ROCK) reserved for full game

func _update_current_collection_from_level(level_path: String) -> void:
	"""Find and set which collection this level belongs to"""
	# Check regular collections first
	for collection_id in COLLECTIONS:
		if level_path in COLLECTIONS[collection_id].levels:
			current_collection = collection_id
			print("GameState: Current collection set to " + collection_id)
			return
	
	# Check if this is a weekly level
	if level_path.begins_with("res://data/levels/weekly/"):
		current_collection = "weekly"
		print("GameState: Current collection set to weekly")

# =============================================================================
# LEVEL LOCKING (Within Collections)
# =============================================================================

func is_level_unlocked(collection_id: String, level_index: int) -> bool:
	if debug_unlock_all:
		return true

	var data = get_collection_data(collection_id)
	if data.is_empty():
		return false

	# Collection must be unlocked before any of its levels are accessible
	if not is_collection_unlocked(collection_id):
		return false

	# First two levels are always available once the collection is unlocked
	if level_index <= 1:
		return true

	# A level unlocks if either of the two levels before it has been completed.
	# e.g. level 4 (index 4) unlocks when index 2 or 3 is completed.
	# This means completing any level always unlocks up to 2 levels ahead,
	# and players can skip a level they're stuck on without being fully blocked.
	var levels = data.levels
	if level_index >= levels.size():
		return false

	for i in range(level_index - 2, level_index):
		if i >= 0 and is_level_completed(levels[i]):
			return true

	return false

func get_next_unlocked_level_in_collection(collection_id: String) -> String:
	"""Get the first uncompleted (but unlocked) level in a collection"""
	var data = get_collection_data(collection_id)
	if data.is_empty():
		return ""

	for i in range(data.levels.size()):
		var level = data.levels[i]
		if not is_level_completed(level) and is_level_unlocked(collection_id, i):
			return level

	return ""  # All levels complete

# =============================================================================
# PROGRESSION & STATS
# =============================================================================

func get_next_level(level_path: String) -> String:
	"""Get the next level in the same collection"""
	# Prefer current_collection for lookup to avoid ambiguity
	if current_collection != "":
		var data = get_collection_data(current_collection)
		if not data.is_empty():
			var index = data.levels.find(level_path)
			if index != -1:
				if index + 1 < data.levels.size():
					var next_level = data.levels[index + 1]
					print("GameState: Next level is " + next_level)
					return next_level
				else:
					print("GameState: Last level in collection '" + current_collection + "'")
					return ""

	# Fallback: search all collections
	for collection_id in COLLECTIONS:
		var levels = COLLECTIONS[collection_id].levels
		var index = levels.find(level_path)
		if index != -1:
			if index + 1 < levels.size():
				var next_level = levels[index + 1]
				print("GameState: Next level is " + next_level)
				return next_level
			else:
				print("GameState: Last level in collection '" + collection_id + "'")
				return ""

	print("GameState: Level not found in any collection: " + level_path)
	return ""

func has_next_level(level_path: String) -> bool:
	return get_next_level(level_path) != ""

func get_total_completed_levels() -> int:
	return completed_levels.size()

func get_total_levels_in_game() -> int:
	var total = 0
	for collection_id in COLLECTIONS:
		total += COLLECTIONS[collection_id].levels.size()
	return total

func get_overall_completion_percentage() -> float:
	var total = get_total_levels_in_game()
	if total == 0:
		return 0.0
	return (float(completed_levels.size()) / float(total)) * 100.0

# =============================================================================
# STATS
# =============================================================================

func record_fall() -> void:
	total_falls += 1
	save_game()

	# ── Achievement: gravity check ────────────────────────────────────────
	if get_node_or_null("/root/Achievements"):
		Achievements.check_gravity_check()


func record_falling_hold() -> void:
	total_falling_holds += 1
	save_game()

	# ── Achievement: loose rock ───────────────────────────────────────────
	if get_node_or_null("/root/Achievements"):
		Achievements.check_loose_rock()


func get_weekly_best_time(level_path: String) -> float:
	"""Get the player's best time for a weekly level. Returns 0.0 if none."""
	return weekly_best_times.get(level_path, 0.0)


func record_weekly_best_time(level_path: String, time_seconds: float) -> bool:
	"""Record a new weekly best time. Returns true if it's a new personal best."""
	var current_best: float = weekly_best_times.get(level_path, INF)
	if time_seconds > 0.0 and time_seconds < current_best:
		weekly_best_times[level_path] = time_seconds
		save_game()
		print("GameState: New weekly best for ", level_path, ": ", time_seconds, "s")
		return true
	return false


func get_total_falls() -> int:
	return total_falls


func get_total_falling_holds() -> int:
	return total_falling_holds


# =============================================================================
# SAVE / LOAD
# =============================================================================

const SAVE_PATH := "user://savegame.json"
const SAVE_TEMP_PATH := "user://savegame.json.tmp"

func save_game() -> void:
	# ── Atomic write: write to a temp file first, then rename ──
	# This prevents corruption if the game crashes mid-write.
	var file = FileAccess.open(SAVE_TEMP_PATH, FileAccess.WRITE)
	if not file:
		push_error("GameState: Could not open temp save file for writing: " + SAVE_TEMP_PATH)
		return
	file.store_string(JSON.stringify(get_save_data(), "\t"))
	file.close()

	# Rename temp → real (DirAccess.rename is atomic on most platforms)
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(SAVE_PATH.trim_prefix("user://"))
		dir.rename(SAVE_TEMP_PATH.trim_prefix("user://"), SAVE_PATH.trim_prefix("user://"))
	print("GameState: Game saved to " + SAVE_PATH)

func load_game() -> void:
	# Clean up any leftover temp file from a previous crash during save
	if FileAccess.file_exists(SAVE_TEMP_PATH):
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove(SAVE_TEMP_PATH.trim_prefix("user://"))
			print("GameState: Cleaned up stale temp save file")

	if not FileAccess.file_exists(SAVE_PATH):
		print("GameState: No save file found — starting fresh")
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("GameState: Could not open save file for reading")
		return

	var raw := file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(raw)

	if err != OK:
		# ── Delete the corrupt file so it doesn't cause repeated failures ──
		push_error("GameState: Save file JSON is corrupt — deleting and starting fresh")
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove(SAVE_PATH.trim_prefix("user://"))
		return

	load_save_data(json.data)
	print("GameState: Game loaded. Completed levels: " + str(completed_levels.size()))

func reset_progress() -> void:
	completed_levels.clear()
	completed_collections.clear()
	climb_metadata.clear()
	current_level = ""
	current_collection = ""
	last_completed_level = ""
	total_falls = 0
	total_falling_holds = 0
	weekly_best_times.clear()
	save_game()
	print("GameState: Progress reset")

func get_save_data() -> Dictionary:
	return {
		"completed_levels": completed_levels,
		"completed_collections": completed_collections,
		"climb_metadata": climb_metadata,
		"current_level": current_level,
		"current_collection": current_collection,
		"total_falls": total_falls,
		"total_falling_holds": total_falling_holds,
		"weekly_best_times": weekly_best_times,
	}

func load_save_data(data: Dictionary) -> void:
	completed_levels = data.get("completed_levels", {})
	completed_collections.assign(data.get("completed_collections", []))
	climb_metadata = data.get("climb_metadata", {})
	current_level = data.get("current_level", "")
	current_collection = data.get("current_collection", "")
	total_falls = data.get("total_falls", 0)
	total_falling_holds = data.get("total_falling_holds", 0)
	weekly_best_times = data.get("weekly_best_times", {})
