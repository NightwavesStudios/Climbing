## MenuBackgroundManager
## Autoload that owns a single persistent MenuBackground instance.
## It lives at the root viewport so it survives all scene transitions.
## Menu scenes call  show()  in their _ready to ensure the shared
## background is visible behind their UI.
extends Node

# ─────────────────────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────────────────────

var _bg: MenuBackground = null
var _adding: bool = false  # guards against double creation while deferred

# ─────────────────────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_background()

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

## Make sure the shared background is visible.  Call from any menu's _ready.
## Resumes processing if it was paused by hide().
func show() -> void:
	_ensure_background()
	if _bg:
		_bg.visible = true
		_bg.process_mode = PROCESS_MODE_INHERIT

## Hide the shared background (e.g. when transitioning to gameplay).
## Also pauses processing so the background doesn't waste CPU.
func hide() -> void:
	if _bg and is_instance_valid(_bg):
		_bg.visible = false
		_bg.process_mode = PROCESS_MODE_DISABLED

## Returns true if the shared background is currently visible.
func is_showing() -> bool:
	return _bg != null and is_instance_valid(_bg) and _bg.visible

## Direct access to the background node, if needed.
func get_background() -> MenuBackground:
	return _bg

# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL
# ─────────────────────────────────────────────────────────────────────────────

func _on_bg_entered() -> void:
	_adding = false

func _ensure_background() -> void:
	# Already created and in the scene tree — good.
	if _bg != null and is_instance_valid(_bg) and _bg.is_inside_tree():
		return
	# Already created but deferred add_child hasn't run yet — skip.
	if _bg != null and _adding:
		return
	_bg = MenuBackground.new()
	_bg.name = "SharedMenuBackground"
	_bg.z_index = -100
	_adding = true
	# Defer so the root node is done setting up its children.
	_bg.tree_entered.connect(_on_bg_entered, CONNECT_ONE_SHOT)
	get_tree().root.add_child.call_deferred(_bg)
