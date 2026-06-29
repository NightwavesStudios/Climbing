## CustomCursor
## Software-rendered cursor that hides the OS cursor entirely, avoiding macOS
## cursor-rectangle issues that cause flickering after scene transitions.
extends Node

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

const CURSOR_SIZE        := 72
const OUTER_RADIUS       := 13.0
const OUTER_THICKNESS    := 2.5
const INNER_RADIUS_NORMAL := 7.0
const INNER_RADIUS_PRESSED := 4.0
const ANIM_DURATION_PRESS   := 0.08
const ANIM_DURATION_RELEASE := 0.14
const SHADOW_OFFSET     := 1.5

# ─────────────────────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────────────────────

var _inner_radius: float = INNER_RADIUS_NORMAL
var _tween: Tween
var _image: Image
var _cursor_layer: CanvasLayer
var _cursor_sprite: TextureRect


# ─────────────────────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Keep processing input even when the game is paused so the cursor stays alive.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Hide the OS cursor entirely — no more flicker from macOS cursor rectangles.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	# A high-layer CanvasLayer guarantees the cursor renders above everything.
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.name = "CursorLayer"
	_cursor_layer.layer = 128
	add_child(_cursor_layer)

	# Create a TextureRect that serves as our software cursor.
	_cursor_sprite = TextureRect.new()
	_cursor_sprite.name = "CursorSprite"
	_cursor_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_sprite.size = Vector2(CURSOR_SIZE, CURSOR_SIZE)
	_cursor_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_cursor_layer.add_child(_cursor_sprite)

	_image = Image.create(CURSOR_SIZE, CURSOR_SIZE, false, Image.FORMAT_RGBA8)
	_update_cursor()

	var root := get_tree().root as Window
	root.connect("focus_entered", _on_window_focus_entered)
	root.connect("focus_exited", _on_window_focus_exited)


func _update_cursor_position() -> void:
	if _cursor_sprite and get_viewport():
		var mp: Vector2 = get_viewport().get_mouse_position()
		_cursor_sprite.position = mp - Vector2(CURSOR_SIZE, CURSOR_SIZE) * 0.5

# Fallback in case no mouse event fires after the cursor is created (e.g. first frame).
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		_update_cursor_position()


# ─────────────────────────────────────────────────────────────────────────────
# TEXTURE GENERATION  (unchanged — produces the ring + dot)
# ─────────────────────────────────────────────────────────────────────────────

static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var val: float = (x - edge0) / (edge1 - edge0)
	var t: float = val if val < 0.0 else (1.0 if val > 1.0 else val)
	return t * t * (3.0 - 2.0 * t)


func _generate_texture(inner_radius: float) -> ImageTexture:
	_image.fill(Color.TRANSPARENT)

	var cx: float = CURSOR_SIZE / 2.0 - 0.5
	var cy: float = CURSOR_SIZE / 2.0 - 0.5
	var half_thick: float = OUTER_THICKNESS / 2.0
	var aa: float = 0.65

	var fill_color: Color = Color(1.0, 1.0, 1.0, 0.92)

	for y in range(CURSOR_SIZE):
		for x in range(CURSOR_SIZE):
			var dx: float = x - cx
			var dy: float = y - cy
			var dist: float = sqrt(dx * dx + dy * dy)

			# Drop shadow (offset down-right)
			var shad_dx: float = dx - SHADOW_OFFSET
			var shad_dy: float = dy - SHADOW_OFFSET
			var shad_dist: float = sqrt(shad_dx * shad_dx + shad_dy * shad_dy)

			var shad_inner: float = 1.0 - _smoothstep(inner_radius - aa, inner_radius + aa, shad_dist)
			var shad_ring: float = 1.0 - _smoothstep(half_thick - aa, half_thick + aa, abs(shad_dist - OUTER_RADIUS))
			var shad_alpha: float = shad_inner if shad_inner > shad_ring else shad_ring
			shad_alpha *= 0.25

			# Inner dot
			var inner_alpha: float = 1.0 - _smoothstep(inner_radius - aa, inner_radius + aa, dist)

			# Outer ring
			var ring_alpha: float = 1.0 - _smoothstep(half_thick - aa, half_thick + aa, abs(dist - OUTER_RADIUS))

			# Composite
			var final_color: Color = Color(fill_color.r, fill_color.g, fill_color.b, 0.0)
			var final_alpha: float = 0.0

			if shad_alpha > 0.001:
				final_color = Color(0.0, 0.0, 0.0, 0.0)
				final_alpha = shad_alpha

			if inner_alpha > 0.001:
				final_color = fill_color
				final_alpha = inner_alpha
			elif ring_alpha > 0.001:
				final_color = fill_color
				final_alpha = ring_alpha

			if final_alpha > 0.001:
				_image.set_pixel(x, y, Color(final_color.r, final_color.g, final_color.b, final_alpha))

	return ImageTexture.create_from_image(_image)


func _update_cursor() -> void:
	var tex: ImageTexture = _generate_texture(_inner_radius)
	if _cursor_sprite:
		_cursor_sprite.texture = tex


func _animate_inner_radius(target_radius: float, duration: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_method(_on_tween_update, _inner_radius, target_radius, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.finished.connect(func(): _inner_radius = target_radius, CONNECT_ONE_SHOT)


func _on_tween_update(value: float) -> void:
	var tex: ImageTexture = _generate_texture(value)
	if _cursor_sprite:
		_cursor_sprite.texture = tex


func _input(event: InputEvent) -> void:
	# Update cursor position on any mouse event
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_update_cursor_position()

	# Animate inner dot on click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_animate_inner_radius(INNER_RADIUS_PRESSED, ANIM_DURATION_PRESS)
		else:
			_animate_inner_radius(INNER_RADIUS_NORMAL, ANIM_DURATION_RELEASE)


# ─────────────────────────────────────────────────────────────────────────────
# WINDOW FOCUS
# ─────────────────────────────────────────────────────────────────────────────

func _on_window_focus_entered() -> void:
	# Re-hide the OS cursor (macOS shows it when switching back to the window).
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_inner_radius = INNER_RADIUS_NORMAL
	_update_cursor()


func _on_window_focus_exited() -> void:
	# Show the OS cursor so the user can interact with other apps normally.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
