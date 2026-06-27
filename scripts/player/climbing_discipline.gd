extends RefCounted
class_name ClimbingDiscipline

## Defines the different climbing disciplines available in the game

enum Type {
	BOULDERING,    # No rope, short routes, completion by reaching top holds
	ROPED,         # Rope attached, belayer at bottom, completion by reaching top
	SPEED          # Time limit, race to the top
}

## Convert discipline enum to string
static func type_to_string(discipline: Type) -> String:
	match discipline:
		Type.BOULDERING:
			return "bouldering"
		Type.ROPED:
			return "roped"
		Type.SPEED:
			return "speed"
	return "bouldering"

## Convert string to discipline enum
static func from_string(discipline_str: String) -> Type:
	match discipline_str.to_lower():
		"bouldering":
			return Type.BOULDERING
		"roped":
			return Type.ROPED
		"speed":
			return Type.SPEED
	return Type.BOULDERING

## Get display name for discipline
static func get_display_name(discipline: Type) -> String:
	match discipline:
		Type.BOULDERING:
			return "Bouldering"
		Type.ROPED:
			return "Roped Climbing"
		Type.SPEED:
			return "Speed Climbing"
	return "Bouldering"

## Get description for discipline
static func get_description(discipline: Type) -> String:
	match discipline:
		Type.BOULDERING:
			return "Climb without ropes to reach the top holds"
		Type.ROPED:
			return "Climb with a rope and belayer for safety"
		Type.SPEED:
			return "Race against the clock to reach the top"
	return ""
