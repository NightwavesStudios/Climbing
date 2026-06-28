extends Node

# =============================================================================
# LEVEL MANAGER - Handles level storage, loading, and selection
# =============================================================================

# signal level_selected(level_path: String) # Unused signal
signal levels_refreshed()

# Level storage paths
const BUILTIN_LEVELS_DIR = "res://data/levels/"
const USER_LEVELS_DIR = "user://levels/"

# Level metadata
class LevelInfo:
	var name: String
	var path: String
	var is_builtin: bool
	var difficulty: String
	var hold_count: int
	var creator: String
	
	func _init(p_name: String, p_path: String, p_builtin: bool):
		name = p_name
		path = p_path
		is_builtin = p_builtin
		difficulty = "Unknown"
		hold_count = 0
		creator = "Unknown"

var available_levels: Array[LevelInfo] = []
var current_level: LevelInfo = null

func _ready():
	ensure_user_directory()
	refresh_levels()

# =============================================================================
# DIRECTORY MANAGEMENT
# =============================================================================

func ensure_user_directory():
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("levels"):
		dir.make_dir("levels")

# =============================================================================
# LEVEL DISCOVERY
# =============================================================================

func refresh_levels():
	available_levels.clear()
	
	# Load built-in levels
	scan_directory(BUILTIN_LEVELS_DIR, true)
	
	# Load user levels
	scan_directory(USER_LEVELS_DIR, false)
	
	# Sort by difficulty/name
	available_levels.sort_custom(func(a, b): return a.name < b.name)
	
	levels_refreshed.emit()

func scan_directory(dir_path: String, is_builtin: bool):
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".climb") or file_name.ends_with(".json")):
			var full_path = dir_path + file_name
			var level_name = file_name.get_basename()
			var level_info = LevelInfo.new(level_name, full_path, is_builtin)
			
			# Try to load metadata
			load_level_metadata(level_info)
			
			available_levels.append(level_info)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func load_level_metadata(level_info: LevelInfo):
	var file = FileAccess.open(level_info.path, FileAccess.READ)
	if not file:
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		return
	
	var data = json.data
	
	# Extract metadata
	if "holds" in data:
		level_info.hold_count = data.holds.size()
	
	if "metadata" in data:
		var metadata = data.metadata
		if "difficulty" in metadata:
			level_info.difficulty = metadata.difficulty
		if "creator" in metadata:
			level_info.creator = metadata.creator

# =============================================================================
# LEVEL OPERATIONS
# =============================================================================

func get_level_by_name(level_name: String) -> LevelInfo:
	for level in available_levels:
		if level.name == level_name:
			return level
	return null

func get_level_by_path(level_path: String) -> LevelInfo:
	for level in available_levels:
		if level.path == level_path:
			return level
	return null

func load_level_data(level_info: LevelInfo) -> Dictionary:
	var file = FileAccess.open(level_info.path, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		return {}
	
	return json.data

func save_user_level(level_name: String, level_data: Dictionary) -> bool:
	var file_path = USER_LEVELS_DIR + level_name + ".climb"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if not file:
		return false
	
	file.store_string(JSON.stringify(level_data, "\t"))
	file.close()
	
	refresh_levels()
	return true

func delete_user_level(level_info: LevelInfo) -> bool:
	if level_info.is_builtin:
		return false
	
	var dir = DirAccess.open("user://")
	if dir.file_exists(level_info.path):
		dir.remove(level_info.path)
		refresh_levels()
		return true
	
	return false

func import_level(source_path: String) -> bool:
	var file = FileAccess.open(source_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	# Validate it's a proper level file
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		return false
	
	# Save to user directory
	var file_name = source_path.get_file()
	var dest_path = USER_LEVELS_DIR + file_name
	
	var dest_file = FileAccess.open(dest_path, FileAccess.WRITE)
	if not dest_file:
		return false
	
	dest_file.store_string(content)
	dest_file.close()
	
	refresh_levels()
	return true

# =============================================================================
# GETTERS
# =============================================================================

func get_all_levels() -> Array[LevelInfo]:
	return available_levels

func get_builtin_levels() -> Array[LevelInfo]:
	return available_levels.filter(func(level): return level.is_builtin)

func get_user_levels() -> Array[LevelInfo]:
	return available_levels.filter(func(level): return not level.is_builtin)

func get_level_count() -> int:
	return available_levels.size()
