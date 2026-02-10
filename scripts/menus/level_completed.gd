# level_complete.gd
extends Control
## Level Complete Screen

@onready var next_button: Button = get_node_or_null("NextButton")
@onready var menu_button: Button = get_node_or_null("MenuButton")
@onready var restart_button: Button = get_node_or_null("RestartButton")

var _completed_level_path: String = ""

func _ready() -> void:
	# Get the completed level from GameState
	_completed_level_path = GameState.get_last_completed_level()
	
	print("=== LEVEL COMPLETE SCREEN ===")
	print("Completed level: ", _completed_level_path)
	print("Current collection: ", GameState.get_current_collection())
	
	# Determine next level
	var next_level: String = GameState.get_next_level(_completed_level_path)
	
	print("Next level found: ", next_level)
	print("=============================")
	
	# Handle "Next" button state safely
	if next_button:
		if next_level == "":
			next_button.visible = false
			next_button.disabled = true
		else:
			next_button.visible = true
			next_button.disabled = false

func _on_next_button_pressed() -> void:
	print("=== NEXT BUTTON PRESSED ===")
	print("Completed level was: ", _completed_level_path)
	
	var next_level: String = GameState.get_next_level(_completed_level_path)
	
	print("Next level retrieved: ", next_level)
	
	if next_level == "":
		print("ERROR: No next level found!")
		if next_button:
			next_button.visible = false
			next_button.disabled = true
		return
	
	print("Setting current level to: ", next_level)
	GameState.set_current_level(next_level)
	
	print("Current level is now: ", GameState.get_current_level())
	print("Transitioning to next level...")
	print("===========================")
	
	# Use Transition autoload
	Transition.to("res://scenes/main/main_scene.tscn")

func _on_menu_button_pressed() -> void:
	# Return to collection select
	Transition.to("res://scenes/menus/collections_select.tscn")

func _on_restart_button_pressed() -> void:
	# Restart the level just completed
	GameState.set_current_level(_completed_level_path)
	Transition.to("res://scenes/main/main_scene.tscn")
