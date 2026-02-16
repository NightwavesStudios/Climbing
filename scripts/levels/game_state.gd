extends Node
## Autoload singleton for managing game state, collections, and progression

# Current gameplay state
var current_level: String = ""
var current_collection: String = ""
var last_completed_level: String = ""

# Progress tracking
var completed_levels: Dictionary = {}  # level_path: completion_time
var completed_collections: Array[String] = []

# Climb metadata storage (name and grade for each level)
var climb_metadata: Dictionary = {}  # level_path: {name: String, grade: String}

# Collection definitions
const COLLECTIONS = {
	"tutorial": {
		"name": "Intro Gym",
		"description": "Learn the basics of climbing",
		"unlock_requirement": {"type": "always"},
		"levels": [
			"res://scenes/levels/tutorial/ladder.json",
			"res://scenes/levels/tutorial/pockets.json",
			"res://scenes/levels/tutorial/first-roped.json",
			"res://scenes/levels/tutorial/far-reach.json",
			"res://scenes/levels/tutorial/long-way-up.json",
			"res://scenes/levels/tutorial/first-speed.json",
			"res://scenes/levels/tutorial/crimp.json",
		]
	},
	#"flow": {
		#"name": "Flow State",
		#"description": "Smooth, continuous climbing",
		#"unlock_requirement": {"type": "always"},  # Also unlocked from start
		#"levels": [
			#"res://scenes/levels/flow/gentle_start.json",
			#"res://scenes/levels/flow/rhythm.json",
			#"res://scenes/levels/flow/momentum.json",
			#"res://scenes/levels/flow/cascade.json",
			#"res://scenes/levels/flow/waterfall.json",
		#]
	#},
	#"precision": {
		#"name": "Precision",
		#"description": "Exact movements and careful planning",
		#"unlock_requirement": {
			#"type": "collection_complete",
			#"collection": "tutorial"
		#},
		#"levels": [
			#"res://scenes/levels/precision/careful_steps.json",
			#"res://scenes/levels/precision/finger_lock.json",
			#"res://scenes/levels/precision/crimp_master.json",
			#"res://scenes/levels/precision/micro_holds.json",
			#"res://scenes/levels/precision/perfect_balance.json",
		#]
	#},
	#"instability": {
		#"name": "Instability",
		#"description": "Dynamic movement and balance",
		#"unlock_requirement": {
			#"type": "total_levels",
			#"count": 15  # Complete 15 levels total
		#},
		#"levels": [
			#"res://scenes/levels/instability/wobble.json",
			#"res://scenes/levels/instability/dyno_intro.json",
			#"res://scenes/levels/instability/swing.json",
			#"res://scenes/levels/instability/campus.json",
			#"res://scenes/levels/instability/chaos.json",
		#]
	#},
	#"long_haul": {
		#"name": "Long Haul",
		#"description": "Endurance and stamina challenges",
		#"unlock_requirement": {
			#"type": "collections_complete",
			#"count": 2  # Complete any 2 collections
		#},
		#"levels": [
			#"res://scenes/levels/long_haul/marathon_wall.json",
			#"res://scenes/levels/long_haul/endurance_test.json",
			#"res://scenes/levels/long_haul/no_rest.json",
			#"res://scenes/levels/long_haul/final_push.json",
			#"res://scenes/levels/long_haul/everest.json",
		#]
	#},
}

func _ready():
	current_level = ""
	current_collection = ""

# =============================================================================
# LEVEL MANAGEMENT
# =============================================================================

func set_current_level(level_path: String) -> void:
	current_level = level_path
	# Also update current_collection when setting a level
	_update_current_collection_from_level(level_path)
	print("GameState: Level set to " + level_path)

func get_current_level() -> String:
	return current_level

func get_last_completed_level() -> String:
	return last_completed_level

func record_level_completion(level_path: String, completion_time: float) -> void:
	last_completed_level = level_path
	
	# Make sure we track which collection this level belongs to
	_update_current_collection_from_level(level_path)
	
	if level_path not in completed_levels:
		completed_levels[level_path] = completion_time
		print("GameState: Completed " + level_path + " in " + str(completion_time) + "s")
		
		# Check if this completed a collection
		_check_collection_completion(level_path)
	else:
		# Update if faster time
		if completion_time < completed_levels[level_path]:
			completed_levels[level_path] = completion_time
			print("GameState: New best time for " + level_path + ": " + str(completion_time) + "s")

func is_level_completed(level_path: String) -> bool:
	return level_path in completed_levels

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
	if collection_id not in COLLECTIONS:
		return false
	
	var req = COLLECTIONS[collection_id].unlock_requirement
	
	match req.type:
		"always":
			return true
		
		"collection_complete":
			var required_collection = req.collection
			return is_collection_completed(required_collection)
		
		"total_levels":
			var required_count = req.count
			return get_total_completed_levels() >= required_count
		
		"collections_complete":
			var required_count = req.count
			return completed_collections.size() >= required_count
		
		"specific_levels":
			# Check if specific levels are completed
			var required_levels = req.levels
			for level in required_levels:
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

func _check_collection_completion(level_path: String):
	# Find which collection this level belongs to
	for collection_id in COLLECTIONS:
		var levels = COLLECTIONS[collection_id].levels
		if level_path in levels:
			# Check if all levels in this collection are now complete
			var all_complete = true
			for level in levels:
				if not is_level_completed(level):
					all_complete = false
					break
			
			if all_complete and collection_id not in completed_collections:
				completed_collections.append(collection_id)
				print("🎉 COLLECTION COMPLETE: " + COLLECTIONS[collection_id].name)

func _update_current_collection_from_level(level_path: String) -> void:
	"""Find and set which collection this level belongs to"""
	for collection_id in COLLECTIONS:
		var levels = COLLECTIONS[collection_id].levels
		if level_path in levels:
			current_collection = collection_id
			print("GameState: Current collection set to " + collection_id)
			return

# =============================================================================
# LEVEL LOCKING (Within Collections)
# =============================================================================

func is_level_unlocked(collection_id: String, level_index: int) -> bool:
	var data = get_collection_data(collection_id)
	if data.is_empty():
		return false
	
	# First level is always unlocked (if collection is unlocked)
	if level_index == 0:
		return is_collection_unlocked(collection_id)
	
	# Other levels require previous level to be completed
	var levels = data.levels
	if level_index >= levels.size():
		return false
	
	var previous_level = levels[level_index - 1]
	return is_level_completed(previous_level)

func get_next_unlocked_level_in_collection(collection_id: String) -> String:
	"""Get the first uncompleted level in a collection"""
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
	"""Get next level in the same collection"""
	# First try to find in current collection (if set)
	if current_collection != "":
		var data = get_collection_data(current_collection)
		if not data.is_empty():
			var levels = data.levels
			var index = levels.find(level_path)
			
			if index != -1:
				# Found the level in current collection
				if index + 1 < levels.size():
					var next_level = levels[index + 1]
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
			# Found the level, check if there's a next one
			if index + 1 < levels.size():
				var next_level = levels[index + 1]
				print("GameState: Next level is " + next_level)
				return next_level
			else:
				print("GameState: Last level in collection '" + collection_id + "'")
				return ""  # Last level in collection
	
	print("GameState: Level not found in any collection: " + level_path)
	return ""  # Level not found

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
# SAVE/LOAD (for future persistence)
# =============================================================================

func reset_progress() -> void:
	completed_levels.clear()
	completed_collections.clear()
	climb_metadata.clear()
	current_level = ""
	current_collection = ""
	last_completed_level = ""
	print("GameState: Progress reset")

func get_save_data() -> Dictionary:
	return {
		"completed_levels": completed_levels,
		"completed_collections": completed_collections,
		"climb_metadata": climb_metadata,
		"current_level": current_level,
		"current_collection": current_collection,
	}

func load_save_data(data: Dictionary) -> void:
	completed_levels = data.get("completed_levels", {})
	completed_collections = data.get("completed_collections", [])
	climb_metadata = data.get("climb_metadata", {})
	current_level = data.get("current_level", "")
	current_collection = data.get("current_collection", "")
