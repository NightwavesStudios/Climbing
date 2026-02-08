extends Node
## Autoload singleton for managing game state across scenes

var current_level: String = ""
var completed_levels: Array[String] = []

# Level progression mapping - UPDATED PATHS
const LEVEL_PROGRESSION = {
	"res://scenes/levels/tutorial.json": "res://scenes/levels/level_1.json",
	"res://scenes/levels/level_1.json": "res://scenes/levels/level_2.json",
	"res://scenes/levels/level_2.json": "res://scenes/levels/level_3.json",
	# Add more levels as needed
}

func _ready():
	# Default starting level - UPDATED PATH
	current_level = "res://scenes/levels/tutorial.json"

## Set which level should be loaded when entering game scene
func set_current_level(level_path: String) -> void:
	current_level = level_path
	print("GameState: Level set to " + level_path)

## Get the level that should be loaded
func get_current_level() -> String:
	return current_level

## Record when a level is completed
func record_level_completion(level_path: String, completion_time: float) -> void:
	if level_path not in completed_levels:
		completed_levels.append(level_path)
		print("GameState: Completed " + level_path + " in " + str(completion_time) + "s")
	
	# Auto-progress to next level
	if level_path in LEVEL_PROGRESSION:
		current_level = LEVEL_PROGRESSION[level_path]
		print("GameState: Next level set to " + current_level)

## Check if a level has been completed
func is_level_completed(level_path: String) -> bool:
	return level_path in completed_levels

## Get the next level after the given one
func get_next_level(level_path: String) -> String:
	if level_path in LEVEL_PROGRESSION:
		return LEVEL_PROGRESSION[level_path]
	return ""

## Reset progress (for testing or new game)
func reset_progress() -> void:
	completed_levels.clear()
	current_level = "res://scenes/levels/tutorial.json"
	print("GameState: Progress reset")
