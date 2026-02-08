extends Node
## Autoload singleton for managing climbing environments

enum EnvironmentType { GYM, GRANITE }

# Current environment
var current_environment: EnvironmentType = EnvironmentType.GYM

# Environment definitions
const ENVIRONMENTS = {
	EnvironmentType.GYM: {
		"name": "Gym",
		"wall_color": Color(0.85, 0.85, 0.9),  # Light gray
		"has_screw_holes": true,
		"sprite_suffix": "Gym"
	},
	EnvironmentType.GRANITE: {
		"name": "Granite",
		"wall_color": Color(0.5, 0.5, 0.55),  # Darker gray
		"has_screw_holes": false,
		"sprite_suffix": "Granite"
	}
}

func _ready():
	print("EnvironmentConfig initialized with environment: " + get_current_environment_name())

func set_environment(env_type: EnvironmentType):
	current_environment = env_type
	print("Environment set to: " + get_current_environment_name())
	
	# Notify all holds to update their sprites
	get_tree().call_group("holds", "_update_sprite_for_environment")
	
	# Notify walls to update their appearance
	get_tree().call_group("environment_walls", "update_environment_settings")

func get_current_environment() -> EnvironmentType:
	return current_environment

func get_current_environment_name() -> String:
	return ENVIRONMENTS[current_environment].name

func get_environment_data(env_type: EnvironmentType = current_environment) -> Dictionary:
	return ENVIRONMENTS.get(env_type, {})

func get_wall_color() -> Color:
	return ENVIRONMENTS[current_environment].wall_color

func has_screw_holes() -> bool:
	return ENVIRONMENTS[current_environment].has_screw_holes

func get_sprite_suffix() -> String:
	return ENVIRONMENTS[current_environment].sprite_suffix

func get_all_environment_types() -> Array:
	return ENVIRONMENTS.keys()

func get_environment_name(env_type: EnvironmentType) -> String:
	return ENVIRONMENTS.get(env_type, {}).get("name", "Unknown")
