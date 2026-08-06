extends Node
## Autoload singleton for weekly level rotation.
##
## Picks a level from the weekly folder based on the current week number.
## The rotation uses the Unix epoch week (weeks since Jan 1, 1970),
## so each week a different level is selected, and the cycle repeats
## after all levels have been shown.

const WEEKLY_DIR := "res://data/levels/weekly/"
const WEEKLY_FOLDER_NAME := "weekly"

## All weekly level file paths, scanned once at startup.
var weekly_level_paths: Array[String] = []

## How many weeks the whole cycle takes before repeating.
var total_weeks: int:
	get: return weekly_level_paths.size()


func _ready() -> void:
	_refresh_weekly_levels()


## Scan the weekly directory for all level files.
func _refresh_weekly_levels() -> void:
	weekly_level_paths.clear()
	
	var dir := DirAccess.open(WEEKLY_DIR)
	if not dir:
		push_error("WeeklyRotation: Could not open weekly directory: ", WEEKLY_DIR)
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".climb") or file_name.ends_with(".json")):
			weekly_level_paths.append(WEEKLY_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	weekly_level_paths.sort()
	print("WeeklyRotation: Found ", weekly_level_paths.size(), " weekly levels")


## Returns the current week number (weeks since Unix epoch).
## This is deterministic and the same for all players.
@warning_ignore("integer_division")
func get_current_week_number() -> int:
	var unix_now := int(Time.get_unix_time_from_system())
	# Week number = seconds since epoch / seconds per week
	return unix_now / (7 * 86400)


## Returns the index into weekly_level_paths for the current week.
func get_current_week_index() -> int:
	if total_weeks == 0:
		return -1
	
	var week_num := get_current_week_number()
	return week_num % total_weeks


## Returns the res:// path of the level for this week.
func get_current_weekly_level_path() -> String:
	if weekly_level_paths.is_empty():
		push_error("WeeklyRotation: No weekly levels available!")
		return ""
	
	var idx := get_current_week_index()
	if idx < 0 or idx >= weekly_level_paths.size():
		return ""
	
	return weekly_level_paths[idx]


## Returns a human-readable label for the current week, e.g. "Week 3"
func get_week_label() -> String:
	var week_num := get_current_week_number()
	if total_weeks > 0:
		var cycle_week := (week_num % total_weeks) + 1
		return "Week %d" % cycle_week
	return "Week %d" % week_num


## Opens the weekly level directory in the system file manager for debugging.
func open_weekly_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(WEEKLY_DIR))
