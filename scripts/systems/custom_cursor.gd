extends Node

@export var cursor_scale: float = 0.1

func _ready() -> void:
	var texture = load("res://assets/textures/cursor.png")
	if not texture:
		return
	
	var image = texture.get_image()
	image.resize(int(image.get_width() * cursor_scale), int(image.get_height() * cursor_scale))
	
	var scaled_texture = ImageTexture.create_from_image(image)
	
	Input.set_custom_mouse_cursor(scaled_texture, Input.CURSOR_ARROW, Vector2(0, 0))
