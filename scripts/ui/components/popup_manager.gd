class_name PopupManager
extends RefCounted
## Manages tutorial popup display logic for the main scene.
## Encapsulates popup configs, level-conditional logic, and display/dismiss.

const INSTRUCTIONS_SAVE_PATH := "user://prefs.cfg"

var _instructions: CanvasLayer
var _instructions_root: ColorRect
var _popup_sprite: Sprite2D
var _active_popup_key: String = ""
var _popup_queue: Array[Dictionary] = []

var POPUP_CONFIGS: Array = []

func _init(instructions: CanvasLayer, instructions_root: ColorRect, popup_sprite: Sprite2D) -> void:
	_instructions = instructions
	_instructions_root = instructions_root
	_popup_sprite = popup_sprite
	_build_popup_configs()

func _build_popup_configs() -> void:
	POPUP_CONFIGS = [
		{
			"image_path": "res://assets/images/popups/tutorial_popup.png",
			"condition":  _popup_cond_controls,
			"save_key":   "controls_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/pockets.png",
			"condition":  _popup_cond_tutorial_03_pockets,
			"save_key":   "tutorial_03_pockets_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/stamina.png",
			"condition":  _popup_cond_stamina,
			"save_key":   "stamina_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/crimps_slopers.png",
			"condition":  _popup_cond_zoom,
			"save_key":   "zoom_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/roped.png",
			"condition":  _popup_cond_roped,
			"save_key":   "roped_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/falling-holds.png",
			"condition":  _popup_cond_falling_holds,
			"save_key":   "falling_holds_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/topping_out.png",
			"condition":  _popup_cond_granite_topping_out,
			"save_key":   "granite_topping_out_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/weather.png",
			"condition":  _popup_cond_weather,
			"save_key":   "weather_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/pockets.png",
			"condition":  _popup_cond_pockets,
			"save_key":   "pockets_popup",
			"priority":   0,
		},
		{
			"image_path": "res://assets/images/popups/project.png",
			"condition":  _popup_cond_project,
			"save_key":   "project_popup",
			"priority":   0,
		},
	]

# ── Level-specific popup conditions ──────────────────────────────────────
static func _popup_cond_controls(level_path: String) -> bool:
	return level_path.ends_with("tutorial_01.json")

static func _popup_cond_tutorial_03_pockets(level_path: String) -> bool:
	return level_path.ends_with("tutorial_03.json")

static func _popup_cond_stamina(level_path: String) -> bool:
	return level_path.ends_with("tutorial_03.json")

static func _popup_cond_zoom(level_path: String) -> bool:
	return level_path.ends_with("tutorial_04.json")

static func _popup_cond_roped(level_path: String) -> bool:
	return level_path.ends_with("tutorial_05.json")

static func _popup_cond_falling_holds(level_path: String) -> bool:
	return level_path.ends_with("tutorial_08.json")

static func _popup_cond_granite_topping_out(level_path: String) -> bool:
	return level_path.ends_with("granite_crag_01.json")

static func _popup_cond_weather(level_path: String) -> bool:
	return level_path.ends_with("granite_crag_02.json")

static func _popup_cond_pockets(level_path: String) -> bool:
	return level_path.ends_with("granite_crag_03.json")

static func _popup_cond_project(level_path: String) -> bool:
	return level_path.ends_with("tutorial_11.json")

# ── Public API ───────────────────────────────────────────────────────────

func show_popup_for_level(level_path: String) -> void:
	_popup_queue = _resolve_all_popups(level_path)
	if _popup_queue.is_empty():
		print("  [Popup] No popup for this level/state")
		return
	_show_next_queued_popup()


func _show_next_queued_popup() -> void:
	if _popup_queue.is_empty():
		return
	var entry = _popup_queue.pop_front()
	print("  [Popup] Showing: ", entry["image_path"], " (key: ", entry["save_key"], ")")
	_show_popup_image(entry["image_path"])
	_active_popup_key = entry["save_key"]

func try_dismiss() -> void:
	if _active_popup_key != "":
		_mark_popup_seen(_active_popup_key)
		_active_popup_key = ""

	# If there are more popups in the queue, show the next one
	if not _popup_queue.is_empty():
		_show_next_queued_popup()
		return

	# Otherwise hide the instructions
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	cfg.set_value("instructions", "shown", true)
	cfg.save(INSTRUCTIONS_SAVE_PATH)

	if not _instructions_root:
		_instructions.hide()
		_instructions.process_mode = Node.PROCESS_MODE_DISABLED
		return

	var tween = _instructions.create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_instructions_root, "modulate:a", 0.0, 0.3)
	tween.tween_property(_instructions_root, "scale", Vector2(0.94, 0.94), 0.25)
	tween.tween_callback(func():
		_instructions_root.scale = Vector2.ONE
		_instructions.hide()
		_instructions.process_mode = Node.PROCESS_MODE_DISABLED
	)

func has_active_popup() -> bool:
	return _active_popup_key != ""

func get_active_popup_key() -> String:
	return _active_popup_key

# ── Internal helpers ─────────────────────────────────────────────────────

func _resolve_all_popups(level_path: String) -> Array[Dictionary]:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)

	var result: Array[Dictionary] = []
	for entry in POPUP_CONFIGS:
		var key: String = entry["save_key"]
		if cfg.get_value("popups", key, false):
			continue
		if entry["condition"].call(level_path):
			result.append(entry)
	return result

func _show_popup_image(image_path: String) -> void:
	if not _instructions or not _instructions_root:
		push_error("show_popup_image: Instructions nodes are null!")
		return

	if _popup_sprite == null:
		push_error("show_popup_image: popup_sprite is null")
	else:
		var tex = load(image_path) as Texture2D
		if tex:
			_popup_sprite.texture = tex
			print("  [Popup] Sprite2D texture set to: ", image_path)
		else:
			push_error("show_popup_image: Failed to load texture: " + image_path)

	_instructions.process_mode = Node.PROCESS_MODE_INHERIT
	_instructions_root.modulate.a = 0.0
	_instructions_root.scale = Vector2(0.92, 0.92)
	_instructions.show()
	_instructions_root.show()

	var tween = _instructions.create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_instructions_root, "modulate:a", 1.0, 0.45)
	tween.tween_property(_instructions_root, "scale", Vector2.ONE, 0.4)

func _mark_popup_seen(save_key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(INSTRUCTIONS_SAVE_PATH)
	cfg.set_value("popups", save_key, true)
	cfg.save(INSTRUCTIONS_SAVE_PATH)
