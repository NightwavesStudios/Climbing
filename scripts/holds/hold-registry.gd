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
#
# wall_types: [] = available on ALL wall types (default)
# wall_types: ["building"] = ONLY available on building walls
# Add as many wall type strings as needed per hold.
# =============================================================================
const HOLD_CONFIGS = {
	"JUG": {
		"difficulty": 0.0,
		"rest_value": 50.0,
		"snap_to_point": true,
		"is_pocket": false,
		"is_foothold": false,
		"is_start": false,
		"is_top_out": false,
		"display_name": "Jug",
		"sloper_drain": false,
		"wall_types": [],
		"max_limbs": 2, 
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
		"wall_types": [],
		"max_limbs": 2, 
	},
	"TOP": {
		"difficulty": 0.0,
		"rest_value": 100.0,
		"snap_to_point": true,
		"is_pocket": false,
		"is_foothold": false,
		"is_start": false,
		"is_top_out": true,
		"display_name": "Top Out",
		"sloper_drain": false,
		"wall_types": [],
		"max_limbs": 2, 
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
		"wall_types": [],
		"max_limbs": 2, 
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
		"wall_types": [],
		"max_limbs": 2, 
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
		"wall_types": [],
		"max_limbs": 1, 
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
		"wall_types": [],
		"max_limbs": 2, 
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
		"wall_types": [],
		"max_limbs": 2, 
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
		"wall_types": [],
	},
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
		"wall_types": ["building"],  # building walls only — not gym, granite, or sandstone
		"max_limbs": 4,    
	},
}

# Default config used when a hold type has no explicit entry
const DEFAULT_CONFIG = {
	"difficulty": 0.0,
	"rest_value": 0.0,
	"snap_to_point": true,
	"is_pocket": false,
	"is_foothold": false,
	"is_start": false,
	"is_top_out": false,
	"display_name": "",
	"sloper_drain": false,
	"wall_types": [],   # empty = allowed on all wall types
	"max_limbs": 2,    
}

func _ready():
	name = "HoldRegistry"
	_register_all_holds()

# =============================================================================
# AUTO-DISCOVERY
# =============================================================================
func _register_all_holds() -> void:
	hold_scenes.clear()
	hold_metadata.clear()
	
	var holds_to_register = {
		"JUG":    "res://scenes/holds/jug.tscn",
		"START":  "res://scenes/holds/start.tscn",
		"TOP":    "res://scenes/holds/top_out.tscn",
		"CRIMP":  "res://scenes/holds/crimp.tscn",
		"SLOPER": "res://scenes/holds/sloper.tscn",
		"POCKET": "res://scenes/holds/pocket.tscn",
		"FOOT":   "res://scenes/holds/foothold.tscn",
		"WINDOW": "res://scenes/holds/window.tscn",
		"LEDGE":  "res://scenes/holds/ledge.tscn",
	}
	
	for hold_type in holds_to_register:
		var hold_path = holds_to_register[hold_type]
		if ResourceLoader.exists(hold_path):
			hold_scenes[hold_type] = load(hold_path)
			var config = get_hold_config(hold_type)
			hold_metadata[hold_type] = {
				"path": hold_path,
				"filename": hold_path.get_file(),
				"display_name": config.get("display_name", _format_display_name(hold_type)),
				"config": config
			}
			print("✓ Registered hold: ", hold_type, " -> ", hold_path.get_file())
		else:
			push_error("Hold scene not found: " + hold_path)
	
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
# WALL TYPE FILTERING
# =============================================================================
func get_holds_for_wall_type(wall_type: String) -> Array:
	"""Return all hold type keys valid for the given wall type.
	Holds with empty wall_types are allowed everywhere."""
	var valid = []
	var wt = wall_type.to_lower()
	for hold_type in hold_scenes.keys():
		var config = get_hold_config(hold_type)
		var allowed: Array = config.get("wall_types", [])
		if allowed.is_empty() or wt in allowed:
			valid.append(hold_type)
	return valid

func is_hold_valid_for_wall(hold_type: String, wall_type: String) -> bool:
	"""Returns true if the hold type is allowed on the given wall type."""
	var config = get_hold_config(hold_type)
	var allowed: Array = config.get("wall_types", [])
	return allowed.is_empty() or wall_type.to_lower() in allowed

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
	_register_all_holds()
