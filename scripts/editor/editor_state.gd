extends Node

# =============================================================================
# EDITOR STATE - Manages level editor state
# Autoload singleton to pass level information to editor
# =============================================================================

var level_to_load: String = ""

func set_level_to_load(path: String):
	level_to_load = path

func get_level_to_load() -> String:
	var path = level_to_load
	level_to_load = ""  # Clear after retrieving
	return path

func has_level_to_load() -> bool:
	return not level_to_load.is_empty()
