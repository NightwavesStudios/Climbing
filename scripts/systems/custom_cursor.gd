extends Node

@export var cursor_scale: float = 0.1

var _cursor_texture: ImageTexture

func _ready() -> void:
	_load_cursor()
	get_tree().root.connect("focus_entered", _on_window_focus_entered)

func _load_cursor() -> void:
	var texture := load("res://assets/textures/cursor.png") as Texture2D
	if not texture:
		push_warning("Cursor texture not found.")
		return
	
	if not _cursor_texture:
		var image := texture.get_image()
		image.resize(
			int(image.get_width() * cursor_scale),
			int(image.get_height() * cursor_scale),
			Image.INTERPOLATE_BILINEAR
		)
		_cursor_texture = ImageTexture.create_from_image(image)
	
	Input.set_custom_mouse_cursor(_cursor_texture, Input.CURSOR_ARROW, Vector2.ZERO)

func _on_window_focus_entered() -> void:
	if _cursor_texture:
		Input.set_custom_mouse_cursor(_cursor_texture, Input.CURSOR_ARROW, Vector2.ZERO)
