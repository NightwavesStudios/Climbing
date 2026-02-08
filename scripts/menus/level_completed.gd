extends Control
## Level Complete Screen

@onready var next_button: Button = $NextButton if has_node("NextButton") else null

var _completed_level_path: String = ""

func _ready():
	# Get the completed level from GameState
	_completed_level_path = GameState.get_last_completed_level()
	
	# Check if there's a next level
	var next_level = GameState.get_next_level(_completed_level_path)
	
	# Hide "Next" button if this was the last level
	if next_button:
		if next_level == "":
			next_button.visible = false
			# Maybe show a "You beat all levels!" message instead

func _on_next_button_pressed() -> void:
	# Get next level from GameState
	var next_level = GameState.get_next_level(_completed_level_path)
	
	if next_level != "":
		print("Loading next level: " + next_level)
		# Set it in GameState so game scene knows what to load
		GameState.set_current_level(next_level)
		# Go back to game scene, it will load the level GameState says
		Transition.to("res://scenes/main/main_scene.tscn")
	else:
		print("No more levels! Returning to menu...")
		Transition.to("res://scenes/menus/main_menu.tscn")

func _on_menu_button_pressed() -> void:
	# Return to main menu
	Transition.to("res://scenes/menus/main_menu.tscn")

func _on_restart_button_pressed() -> void:
	# Restart the level we just completed
	GameState.set_current_level(_completed_level_path)
	Transition.to("res://scenes/main/main_scene.tscn")
