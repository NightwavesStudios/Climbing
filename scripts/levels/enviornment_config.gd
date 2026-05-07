extends Node
## Autoload singleton for managing climbing environments.
## To add a new environment: add it to EnvironmentType enum AND add its config
## to ENVIRONMENTS dict. Everything else (wall rendering, editor dropdown,
## hold sprites) picks it up automatically.

enum EnvironmentType { GYM, GRANITE, SANDSTONE, BUILDING, ICE }

var current_environment: EnvironmentType = EnvironmentType.GYM

const ENVIRONMENTS = {
	EnvironmentType.GYM: {
		"name": "Gym",
		"wall_color": Color(0.82, 0.75, 0.62),
		"background_color": Color(0.53, 0.81, 0.92),
		"show_bolt_holes": true,
		"show_granite_texture": false,
		"sprite_suffix": "Gym"
	},
	EnvironmentType.GRANITE: {
		"name": "Granite",
		"wall_color": Color(0.607, 0.607, 0.655, 1.0),
		"background_color": Color(0.53, 0.81, 0.92),
		"show_bolt_holes": false,
		"show_granite_texture": true,
		"sprite_suffix": "Granite"
	},
	EnvironmentType.SANDSTONE: {
		"name": "Sandstone",
		"wall_color": Color(0.76, 0.60, 0.42, 1.0),
		"background_color": Color(0.85, 0.75, 0.55, 1.0),
		"show_bolt_holes": false,
		"show_granite_texture": false,
		"sprite_suffix": "Sandstone"
	},
	EnvironmentType.BUILDING: {
		"name": "Building",
		"wall_color": Color(0.52, 0.52, 0.54, 1.0),
		"background_color": Color(0.16, 0.38, 0.70, 1.0),
		"show_bolt_holes": false,
		"show_granite_texture": false,
		"sprite_suffix": "Sandstone"
	},
	# ── ICE — frozen alpine face ───────────────────────────────────────────────
	EnvironmentType.ICE: {
		"name": "Ice",
		"wall_color": Color(0.72, 0.88, 0.96, 1.0),   # pale glacial blue
		"background_color": Color(0.62, 0.80, 0.92, 1.0),
		"show_bolt_holes": false,
		"show_granite_texture": false,
		"sprite_suffix": "Granite"  # reuse until Ice-specific art exists
	},
}

func _ready() -> void:
	print("EnvironmentConfig initialized with environment: " + get_current_environment_name())

func set_environment(env_type: EnvironmentType) -> void:
	current_environment = env_type
	print("Environment set to: " + get_current_environment_name())
	get_tree().call_group("holds",             "_update_sprite_for_environment")
	get_tree().call_group("environment_walls", "update_environment_settings")

func get_current_environment() -> EnvironmentType:
	return current_environment

func get_current_environment_name() -> String:
	return ENVIRONMENTS[current_environment].name

func get_environment_data(env_type: EnvironmentType = current_environment) -> Dictionary:
	return ENVIRONMENTS.get(env_type, {})

func get_wall_color() -> Color:
	return ENVIRONMENTS[current_environment].get("wall_color", Color(0.82, 0.75, 0.62))

func get_background_color() -> Color:
	return ENVIRONMENTS[current_environment].get("background_color", Color(0.53, 0.81, 0.92))

func has_screw_holes() -> bool:
	return ENVIRONMENTS[current_environment].get("show_bolt_holes", false)

func get_sprite_suffix() -> String:
	return ENVIRONMENTS[current_environment].get("sprite_suffix", "Gym")

func get_all_environment_types() -> Array:
	return ENVIRONMENTS.keys()

func get_environment_name(env_type: EnvironmentType) -> String:
	return ENVIRONMENTS.get(env_type, {}).get("name", "Unknown")
