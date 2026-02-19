extends Node
## HoldRegistry - Centralized hold discovery, registration, and behavior config.
## Just add a .tscn file to res://scenes/holds/ and it auto-registers!
## Hold behavior (difficulty, rest, snap mode, etc.) is defined here — not in ClimbingHold.

const HOLD_FOLDER = "res://scenes/holds/"

var hold_scenes: Dictionary = {}     # type_name -> PackedScene
var hold_metadata: Dictionary = {}   # type_name -> { path, filename, display_name, config }

# =============================================================================
# HOLD BEHAVIOR CONFIG
# Define all hold behavior here. Adding a new hold type = add one entry below.
# ClimbingHold reads this at runtime - no code changes needed there.
# =============================================================================
const HOLD_CONFIGS = {
	"JUG": {
		"difficulty": 0.0,
		"rest_value": 50.0,
		"snap_to_point": true,
		"is_pocket": false,       # pocket = only one limb at a time
		"is_foothold": false,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Jug",
		"sloper_drain": false,    # slopers drain extra when held
	},
	"START": {
		"difficulty": 0.0,
		"rest_value": 50.0,
		"snap_to_point": true,
		"is_pocket": false,
		"is_foothold": false,
		"is_start": true,
		"is_top_out": false,
		"display_name": "Start",
		"sloper_drain": false,
	},
	"TOP": {
		"difficulty": 0.0,
		"rest_value": 10.0,
		"snap_to_point": true,
		"is_pocket": false,
		"is_foothold": false,
		"is_start": false,
		"is_top_out": true,
		"display_name": "Top Out",
		"sloper_drain": false,
	},
	"CRIMP": {
		"difficulty": 3.0,
		"rest_value": 0.0,
		"snap_to_point": false,
		"is_pocket": false,
		"is_foothold": false,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Crimp",
		"sloper_drain": false,
	},
	"SLOPER": {
		"difficulty": 2.5,
		"rest_value": 0.0,
		"snap_to_point": false,
		"is_pocket": false,
		"is_foothold": false,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Sloper",
		"sloper_drain": true,
	},
	"POCKET": {
		"difficulty": 1.2,
		"rest_value": 0.0,
		"snap_to_point": true,
		"is_pocket": true,
		"is_foothold": false,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Pocket",
		"sloper_drain": false,
	},
	"FOOT": {
		"difficulty": 1.0,
		"rest_value": 0.0,
		"snap_to_point": true,
		"is_pocket": false,
		"is_foothold": true,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Foothold",
		"sloper_drain": false,
	},
	"PINCH": {
		"difficulty": 2.0,
		"rest_value": 0.0,
		"snap_to_point": false,
		"is_pocket": false,
		"is_foothold": false,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Pinch",
		"sloper_drain": false,
	},
	"UNDERCLING": {
		"difficulty": 2.2,
		"rest_value": 0.0,
		"snap_to_point": true,
		"is_pocket": false,
		"is_foothold": false,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Undercling",
		"sloper_drain": false,
	},
	# WINDOW hold: two-handed, both hands can grab simultaneously at separate points
	"WINDOW": {
		"difficulty": 1.5,
		"rest_value": 5.0,
		"snap_to_point": false,   # free placement - each hand grabs its own spot
		"is_pocket": false,       # NOT a pocket - multiple limbs allowed
		"is_foothold": false,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Window",
		"sloper_drain": false,
	},
}

# Default config used when a hold type has no explicit entry
const DEFAULT_CONFIG = {
	"difficulty": 1.0,
	"rest_value": 0.0,
	"snap_to_point": true,
	"is_pocket": false,
	"is_foothold": false,
	"is_start": false,
	"is_top_out": false,
	"display_name": "",
	"sloper_drain": false,
}

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

			if ResourceLoader.exists(hold_path):
				hold_scenes[hold_type] = load(hold_path)
				var config = get_hold_config(hold_type)
				hold_metadata[hold_type] = {
					"path": hold_path,
					"filename": file_name,
					"display_name": config.get("display_name", "") if config.get("display_name", "") != "" else _format_display_name(hold_type),
					"config": config
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
	"""Extract hold type from filename"""
	var base_name = filename.get_basename().to_upper()

	base_name = base_name.replace("HOLD_", "")
	base_name = base_name.replace("_HOLD", "")

	# Check against all known config keys first (most accurate)
	for key in HOLD_CONFIGS.keys():
		if key in base_name:
			return key

	# Fallbacks for special naming
	if "TOP" in base_name or "TOPOUT" in base_name or "TOP_OUT" in base_name:
		return "TOP"
	if "FOOT" in base_name:
		return "FOOT"
	if "SLOP" in base_name:
		return "SLOPER"

	return base_name

func _format_display_name(type_name: String) -> String:
	return type_name.capitalize()

# =============================================================================
# CONFIG API
# =============================================================================
func get_hold_config(type_name: String) -> Dictionary:
	"""Get the behavior config for a hold type. Returns default if not found."""
	var key = type_name.to_upper()
	if key in HOLD_CONFIGS:
		return HOLD_CONFIGS[key]
	# Return a copy of default with display_name filled in
	var default = DEFAULT_CONFIG.duplicate()
	default["display_name"] = _format_display_name(type_name)
	return default

func get_config_value(type_name: String, property: String, fallback = null):
	"""Get a single property from a hold's config."""
	var config = get_hold_config(type_name)
	return config.get(property, fallback)

# =============================================================================
# PUBLIC API
# =============================================================================
func get_hold_scene(type_name: String) -> PackedScene:
	var key = type_name.to_upper()
	return hold_scenes.get(key, null)

func get_all_hold_types() -> Array:
	return hold_scenes.keys()

func get_hold_display_name(type_name: String) -> String:
	var key = type_name.to_upper()
	if key in hold_metadata:
		return hold_metadata[key].display_name
	return _format_display_name(type_name)

func has_hold_type(type_name: String) -> bool:
	return type_name.to_upper() in hold_scenes

func get_hold_count() -> int:
	return hold_scenes.size()

func refresh():
	"""Re-scan holds folder (call after adding new holds at runtime)"""
	discover_holds()
