extends Control

# ─────────────────────────────────────────────
#  CONSTANTS
# ─────────────────────────────────────────────
const MASTER_BUS        := 0
const SETTINGS_PATH     := "user://settings.cfg"
const PREFS_PATH        := "user://prefs.cfg"
const DEFAULT_VOLUME    := 0.5

const REBINDABLE_ACTIONS: Array[String] = [
	"select_left",
	"select_right",
	"select_left_foot",
	"select_right_foot",
]

# Maps OptionButton index → Engine.max_fps value (0 = unlimited)
const FPS_CAP_VALUES: Array[int] = [0, 60, 120]

# Maps OptionButton index → DisplayServer window mode
const WINDOW_MODES: Array[int] = [
	DisplayServer.WINDOW_MODE_WINDOWED,
	DisplayServer.WINDOW_MODE_FULLSCREEN,
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
]

# ─────────────────────────────────────────────
#  NODE REFS
# ─────────────────────────────────────────────
@onready var volume_slider:       HSlider          = $MarginContainer/VBoxContainer/Volume
@onready var window_mode_option:  OptionButton     = $MarginContainer/VBoxContainer/WindowMode
@onready var vsync_toggle:        CheckBox         = $MarginContainer/VBoxContainer/VSync
@onready var fps_cap_option:      OptionButton     = $MarginContainer/VBoxContainer/FPSCap
@onready var keybinds_container:  VBoxContainer    = $MarginContainer/VBoxContainer/KeybindsContainer
@onready var reset_data_dialog:   ConfirmationDialog = $ResetDataDialog
@onready var reset_btn:           Button           = $MarginContainer/VBoxContainer/ResetData

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _listening_action: String   = ""
var _action_buttons:   Dictionary = {}

# ─────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	MenuBackgroundManager.show()
	_build_keybind_ui()
	load_settings()
	# Already connected in the scene file

# ─────────────────────────────────────────────
#  KEYBIND UI
# ─────────────────────────────────────────────
func _build_keybind_ui() -> void:
	for action in REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var lbl := Label.new()
		lbl.text = action.capitalize().replace("_", " ")
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(140, 0)
		btn.text = _get_action_key_label(action)
		btn.pressed.connect(_on_rebind_button_pressed.bind(action, btn))
		row.add_child(btn)

		keybinds_container.add_child(row)
		_action_buttons[action] = btn

func _get_action_key_label(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e.as_text_physical_keycode()
	return "(none)"

# ─────────────────────────────────────────────
#  REBIND LOGIC
# ─────────────────────────────────────────────
func _on_rebind_button_pressed(action: String, btn: Button) -> void:
	if _listening_action != "":
		# Cancel the previous pending rebind
		var old_btn: Button = _action_buttons.get(_listening_action)
		if old_btn:
			old_btn.text = _get_action_key_label(_listening_action)

	_listening_action = action
	btn.text = "Press a key…"
	set_process_unhandled_key_input(true)

func _unhandled_key_input(event: InputEvent) -> void:
	if _listening_action == "" or not event is InputEventKey or not event.pressed:
		return

	if event.physical_keycode == KEY_ESCAPE:
		_action_buttons[_listening_action].text = _get_action_key_label(_listening_action)
		_stop_listening()
		get_viewport().set_input_as_handled()
		return

	var new_event := InputEventKey.new()
	new_event.physical_keycode = event.physical_keycode
	InputMap.action_erase_events(_listening_action)
	InputMap.action_add_event(_listening_action, new_event)
	_action_buttons[_listening_action].text = new_event.as_text_physical_keycode()

	_stop_listening()
	get_viewport().set_input_as_handled()

func _stop_listening() -> void:
	_listening_action = ""
	set_process_unhandled_key_input(false)

# ─────────────────────────────────────────────
#  SAVE / LOAD
# ─────────────────────────────────────────────
func _on_save_pressed() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("audio",       "master_volume_db", AudioServer.get_bus_volume_db(MASTER_BUS))
	cfg.set_value("audio",       "muted",            AudioServer.is_bus_mute(MASTER_BUS))
	cfg.set_value("video",       "window_mode_index", window_mode_option.selected)
	cfg.set_value("video",       "vsync_enabled",    vsync_toggle.button_pressed)
	cfg.set_value("performance", "fps_cap_index",    fps_cap_option.selected)

	for action in REBINDABLE_ACTIONS:
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				cfg.set_value("keybinds", action, e.physical_keycode)
				break

	if cfg.save(SETTINGS_PATH) != OK:
		push_error("Settings save failed: %s" % SETTINGS_PATH)
	else:
		print("Settings saved: ", SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		print("No settings file — applying defaults.")
		_apply_window_mode(1)
		window_mode_option.select(1)
		_apply_fps_cap(2)          # default: index 2 = 60 fps
		fps_cap_option.select(2)
		volume_slider.set_value_no_signal(DEFAULT_VOLUME)
		AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(DEFAULT_VOLUME))
		return

	# --- Audio ---
	if cfg.has_section_key("audio", "master_volume_db"):
		AudioServer.set_bus_volume_db(MASTER_BUS, cfg.get_value("audio", "master_volume_db"))
	if cfg.has_section_key("audio", "muted"):
		AudioServer.set_bus_mute(MASTER_BUS, cfg.get_value("audio", "muted"))
	volume_slider.set_value_no_signal(
		clampf(db_to_linear(AudioServer.get_bus_volume_db(MASTER_BUS)), 0.0, 1.0)
	)

	# --- Video ---
	var wm_idx: int = cfg.get_value("video", "window_mode_index", 1)
	window_mode_option.select(wm_idx)
	_apply_window_mode(wm_idx)

	var vsync_on: bool = cfg.get_value("video", "vsync_enabled", true)
	vsync_toggle.set_pressed_no_signal(vsync_on)
	_apply_vsync(vsync_on)

	# --- Performance ---
	var fps_idx: int = cfg.get_value("performance", "fps_cap_index", 2)
	fps_cap_option.select(fps_idx)
	_apply_fps_cap(fps_idx)

	# --- Keybinds ---
	for action in REBINDABLE_ACTIONS:
		if cfg.has_section_key("keybinds", action):
			var kc: int = cfg.get_value("keybinds", action)
			var ev := InputEventKey.new()
			ev.physical_keycode = kc as Key
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, ev)

		var btn: Button = _action_buttons.get(action)
		if btn:
			btn.text = _get_action_key_label(action)

# ─────────────────────────────────────────────
#  APPLY HELPERS  (single source of truth)
# ─────────────────────────────────────────────
func _apply_window_mode(index: int) -> void:
	if index >= 0 and index < WINDOW_MODES.size():
		DisplayServer.window_set_mode(WINDOW_MODES[index])
	else:
		push_warning("Invalid window mode index: %d" % index)

func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)

func _apply_fps_cap(index: int) -> void:
	if index >= 0 and index < FPS_CAP_VALUES.size():
		Engine.max_fps = FPS_CAP_VALUES[index]
	else:
		push_warning("Invalid FPS cap index: %d" % index)

# ─────────────────────────────────────────────
#  UI SIGNAL HANDLERS
# ─────────────────────────────────────────────
func _on_volume_value_changed(value: float) -> void:
	if value <= 0.01:
		AudioServer.set_bus_mute(MASTER_BUS, true)
	else:
		AudioServer.set_bus_mute(MASTER_BUS, false)
		AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(value))

func _on_window_mode_item_selected(index: int) -> void:
	_apply_window_mode(index)

func _on_vsync_toggled(toggled_on: bool) -> void:
	_apply_vsync(toggled_on)

func _on_fps_cap_item_selected(index: int) -> void:
	_apply_fps_cap(index)

func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/main_menu.tscn")

# ─────────────────────────────────────────────
#  RESET DATA
# ─────────────────────────────────────────────
func _on_reset_data_pressed() -> void:
	reset_data_dialog.popup_centered()

func _on_reset_data_dialog_confirmed() -> void:
	if has_node("/root/GameState"):
		var gs := get_node("/root/GameState")
		if gs.has_method("reset_progress"):
			gs.reset_progress()

	var prefs := ConfigFile.new()
	prefs.set_value("instructions", "shown",                    false)
	prefs.set_value("popups",       "tutorial_popup",            false)
	prefs.set_value("popups",       "granite_topping_out_popup", false)
	prefs.save(PREFS_PATH)

	print("Settings: all progress data reset.")
	reset_btn.text = "✓ Data Reset!"
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(reset_btn):
		reset_btn.text = "Reset Data"
