extends Control

@onready var buttons: VBoxContainer = $CanvasLayer/Buttons
@onready var level_loader: LevelLoader = $LevelLoader
@onready var player: CharacterBody2D = $Character
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	# Hide everything initially
	modulate = Color(1, 1, 1, 0)
	
	_setup_background_level()

# --------------------------
# BACKGROUND LEVEL SETUP
# --------------------------
func _setup_background_level() -> void:
	# Load the tutorial level
	await get_tree().process_frame
	await level_loader.load_level("res://scenes/levels/menu.json")
	
	# Wait for everything to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Position player at spawn
	var spawn_pos = level_loader.get_player_spawn_position()
	player.global_position = spawn_pos
	if player.has_method("set_spawn_position"):
		player.set_spawn_position(spawn_pos)
	
	# Center camera on the route
	_center_camera_on_route()
	
	# Give physics one more frame, then trigger initial grab
	await get_tree().process_frame
	call_deferred("_initial_grab")
	
	# Wait for initial grab to complete
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Fade in the menu
	_fade_in_menu()

func _initial_grab() -> void:
	"""Ensure player properly grabs start holds"""
	if player.has_method("initial_grab"):
		player.initial_grab()

func _fade_in_menu() -> void:
	"""Fade in the entire menu once everything is loaded"""
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.5)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

func _center_camera_on_route() -> void:
	var bounds = level_loader.get_wall_bounds()
	if bounds.valid:
		var wall_center_x = (bounds.min.x + bounds.max.x) / 2.0
		var wall_center_y = (bounds.min.y + bounds.max.y) / 2.0
		camera.position = Vector2(wall_center_x, wall_center_y)
		
		# Calculate zoom to fit nicely
		var wall_height = bounds.max.y - bounds.min.y
		var viewport_height = get_viewport_rect().size.y
		
		if wall_height > viewport_height * 0.7:
			var zoom_factor = viewport_height / (wall_height * 1.2)
			camera.zoom = Vector2(zoom_factor, zoom_factor)
		else:
			camera.zoom = Vector2(1.0, 1.0)

# --------------------------
# BUTTON CALLBACKS
# --------------------------
func _on_play_pressed() -> void:
	Transition.to("res://scenes/menus/collections_select.tscn")

func _on_level_maker_pressed() -> void:
	Transition.to("res://scenes/editor/level_editor.tscn")

func _on_settings_pressed() -> void:
	Transition.to("res://scenes/menus/settings.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
