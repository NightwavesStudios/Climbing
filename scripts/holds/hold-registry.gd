extends Node
## HoldRegistry - Centralized hold discovery and registration system
## Just add a .tscn file to res://scenes/holds/ and it auto-registers!

# Singleton pattern - access via HoldRegistry from anywhere
var hold_scenes: Dictionary = {}
var hold_metadata: Dictionary = {}

const HOLD_FOLDER = "res://scenes/holds/"

func _ready():
	name = "HoldRegistry"
	discover_holds()

# =============================================================================
# AUTO-DISCOVERY
# =============================================================================

func discover_holds():
	"""Automatically find all .tscn files in the holds folder"""
	hold_scenes.clear()
	hold_metadata.clear()
	
	var dir = DirAccess.open(HOLD_FOLDER)
	if not dir:
		push_error("Cannot open holds folder: " + HOLD_FOLDER)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tscn"):
			var hold_path = HOLD_FOLDER + file_name
			var hold_type = _extract_type_from_filename(file_name)
			
			# Load and register
			if ResourceLoader.exists(hold_path):
				hold_scenes[hold_type] = load(hold_path)
				hold_metadata[hold_type] = {
					"path": hold_path,
					"filename": file_name,
					"display_name": _format_display_name(hold_type)
				}
				print("✓ Registered hold: ", hold_type, " -> ", file_name)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	print("\n═══════════════════════════════════════")
	print("HoldRegistry: ", hold_scenes.size(), " holds registered")
	print("═══════════════════════════════════════\n")

# =============================================================================
# TYPE EXTRACTION
# =============================================================================

func _extract_type_from_filename(filename: String) -> String:
	"""Extract hold type from filename - smart detection"""
	var base_name = filename.get_basename().to_upper()
	
	# Remove common prefixes/suffixes
	base_name = base_name.replace("HOLD_", "")
	base_name = base_name.replace("_HOLD", "")
	
	# Special cases
	if "START" in base_name:
		return "START"
	elif "TOP" in base_name or "TOPOUT" in base_name:
		return "TOP"
	elif "CRIMP" in base_name:
		return "CRIMP"
	elif "SLOPER" in base_name or "SLOP" in base_name:
		return "SLOPER"
	elif "POCKET" in base_name:
		return "POCKET"
	elif "FOOT" in base_name:
		return "FOOT"
	elif "JUG" in base_name:
		return "JUG"
	elif "PINCH" in base_name:
		return "PINCH"
	elif "UNDERCLING" in base_name:
		return "UNDERCLING"
	elif "SIDEPULL" in base_name:
		return "SIDEPULL"
	
	# Default: use cleaned filename
	return base_name

func _format_display_name(type_name: String) -> String:
	"""Format type name for UI display"""
	return type_name.capitalize()

# =============================================================================
# PUBLIC API
# =============================================================================

func get_hold_scene(type_name: String) -> PackedScene:
	"""Get hold scene by type name (case insensitive)"""
	var key = type_name.to_upper()
	return hold_scenes.get(key, null)

func get_all_hold_types() -> Array:
	"""Get list of all registered hold types"""
	return hold_scenes.keys()

func get_hold_display_name(type_name: String) -> String:
	"""Get formatted display name for a hold type"""
	var key = type_name.to_upper()
	if key in hold_metadata:
		return hold_metadata[key].display_name
	return type_name.capitalize()

func has_hold_type(type_name: String) -> bool:
	"""Check if hold type is registered"""
	return type_name.to_upper() in hold_scenes

func get_hold_count() -> int:
	"""Get total number of registered holds"""
	return hold_scenes.size()

func refresh():
	"""Re-scan holds folder (call after adding new holds at runtime)"""
	discover_holds()
