extends Node

# =============================================================================
# GAME STATE - Global state management
# Autoload singleton to track current level, player progress, etc.
# =============================================================================

var current_level_path: String = ""
var player_stats: Dictionary = {}

func _ready():
	# Load player stats if they exist
	load_player_stats()

func set_current_level(path: String):
	current_level_path = path

func get_current_level() -> String:
	return current_level_path

func load_player_stats():
	var file = FileAccess.open("user://player_stats.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()
		
		if error == OK:
			player_stats = json.data
		else:
			player_stats = {}
	else:
		player_stats = {}

func save_player_stats():
	var file = FileAccess.open("user://player_stats.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(player_stats, "\t"))
		file.close()

func record_level_completion(level_path: String, time: float):
	if not "completed_levels" in player_stats:
		player_stats["completed_levels"] = {}
	
	if not level_path in player_stats.completed_levels:
		player_stats.completed_levels[level_path] = {
			"best_time": time,
			"attempts": 1,
			"first_completed": Time.get_datetime_string_from_system()
		}
	else:
		var stats = player_stats.completed_levels[level_path]
		stats.attempts += 1
		if time < stats.best_time:
			stats.best_time = time
	
	save_player_stats()
