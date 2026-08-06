extends Control

# ─────────────────────────────────────────────
#  CONSTANTS
# ─────────────────────────────────────────────
const MASTER_BUS        := 0
const SETTINGS_PATH     := "user://settings.cfg"
const PREFS_PATH        := "user://prefs.cfg"
const DEFAULT_VOLUME    := 0.5

const MAIN_MENU_SCENE   := "res://scenes/menus/main_menu.tscn"

## Where the "Back" button should return to. Set by the pause menu when
## settings is opened mid-level so Back returns to gameplay instead of the
## main menu. Empty means the default (main menu).
static var return_scene: String = ""

const REBINDABLE_ACTIONS: Array[String] = [
	"select_left",
	"select_right",
	"select_left_foot",
	"select_right_foot",
	"restart",
	"project_mode",
	"route_view",
	"ui_cancel",
]

# Maps OptionButton index → Engine.max_fps value (0 = unlimited)
const FPS_CAP_VALUES: Array[int] = [0, 30, 60, 120, 144]

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
@onready var vsync_toggle:        CheckBox         = $MarginContainer/VBoxContainer/VSyncRow/VSync
@onready var fps_cap_option:      OptionButton     = $MarginContainer/VBoxContainer/FPSCapRow/FPSCap
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
	call_deferred(&"_focus_first_setting")

func _focus_first_setting() -> void:
	if volume_slider:
		volume_slider.grab_focus()

func _exit_tree() -> void:
	# Safety net: auto-save settings if the scene is destroyed
	# (e.g. window closed, abrupt scene change) without going through Back.
	_on_save_pressed()

# ─────────────────────────────────────────────
#  KEYBIND UI
# ─────────────────────────────────────────────
func _build_keybind_ui() -> void:
	for action in REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var lbl := Label.new()
		lbl.text = InputHelper.get_action_label(action)
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
	# Use InputHelper to get the best label for the current input method
	return InputHelper.get_action_key_name(action)

func _get_event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		return event.as_text_physical_keycode()
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:            return "Mouse Left"
			MOUSE_BUTTON_RIGHT:           return "Mouse Right"
			MOUSE_BUTTON_MIDDLE:          return "Mouse Middle"
			MOUSE_BUTTON_WHEEL_UP:        return "Mouse Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:      return "Mouse Wheel Down"
			MOUSE_BUTTON_WHEEL_LEFT:      return "Mouse Wheel Left"
			MOUSE_BUTTON_WHEEL_RIGHT:     return "Mouse Wheel Right"
			_:                             return "Mouse Button %d" % event.button_index
	elif event is InputEventJoypadButton:
		# e.g. "Joypad Button 0 (PS Cross)" — keep it compact
		var raw := event.as_text()
		# Strip the "Joypad " prefix Godot adds so it reads "Button 0 (PS Cross)"
		if raw.begins_with("Joypad "):
			return raw.trim_prefix("Joypad ")
		return raw
	elif event is InputEventJoypadMotion:
		var dir := "+" if event.axis_value > 0 else "-"
		return "Axis %d %s" % [event.axis, dir]
	return "(unknown)"

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
	# Defer so the mouse click that triggered this button isn't captured as the new bind
	call_deferred("set_process_input", true)

func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return

	# Ignore events that don't have a pressed state (mouse motion, etc.)
	if not "pressed" in event or not event.pressed:
		return

	# ── Keyboard ─────────────────────────────────────────────────────────
	if event is InputEventKey:

		if event.physical_keycode == KEY_ESCAPE:
			_action_buttons[_listening_action].text = _get_action_key_label(_listening_action)
			_stop_listening()
			get_viewport().set_input_as_handled()
			return

		# Ignore modifier-only presses (Shift, Ctrl, Alt, Meta held alone)
		if event.physical_keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return

		var new_event := InputEventKey.new()
		new_event.physical_keycode = event.physical_keycode
		InputMap.action_erase_events(_listening_action)
		InputMap.action_add_event(_listening_action, new_event)
		_action_buttons[_listening_action].text = _get_event_label(new_event)
		_stop_listening()
		get_viewport().set_input_as_handled()

	# ── Mouse button ─────────────────────────────────────────────────────
	elif event is InputEventMouseButton:
		# Ignore wheel events (not useful as action triggers)
		if event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT,
		]:
			return

		var new_event := InputEventMouseButton.new()
		new_event.button_index = event.button_index
		InputMap.action_erase_events(_listening_action)
		InputMap.action_add_event(_listening_action, new_event)
		_action_buttons[_listening_action].text = _get_event_label(new_event)
		_stop_listening()
		get_viewport().set_input_as_handled()

	# ── Joypad button ────────────────────────────────────────────────────
	elif event is InputEventJoypadButton:
		var new_event := InputEventJoypadButton.new()
		new_event.button_index = event.button_index
		InputMap.action_erase_events(_listening_action)
		InputMap.action_add_event(_listening_action, new_event)
		_action_buttons[_listening_action].text = _get_event_label(new_event)
		_stop_listening()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()

func _stop_listening() -> void:
	_listening_action = ""
	set_process_input(false)

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
			cfg.set_value("keybinds", action, var_to_str(e))
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
		_apply_vsync(true)
		vsync_toggle.set_pressed_no_signal(true)
		# VSync is on by default → FPS cap forced to None and dropdown disabled
		fps_cap_option.select(0)
		_apply_fps_cap(0)
		_sync_fps_cap_disabled(true)
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
	var fps_idx: int = cfg.get_value("performance", "fps_cap_index", 0)
	fps_cap_option.select(fps_idx)
	_apply_fps_cap(fps_idx)

	# Sync the FPS cap disabled state with VSync state
	_sync_fps_cap_disabled(vsync_on)

	# --- Keybinds ---
	for action in REBINDABLE_ACTIONS:
		if cfg.has_section_key("keybinds", action):
			var val = cfg.get_value("keybinds", action)
			var ev: InputEvent
			if val is int:
				# Backward compat: old format stored physical_keycode as int
				ev = InputEventKey.new()
				ev.physical_keycode = val as Key
			elif val is String:
				ev = str_to_var(val) as InputEvent

			if ev:
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

# Disable/enable the FPS cap dropdown to match VSync state.
func _sync_fps_cap_disabled(vsync_on: bool) -> void:
	fps_cap_option.disabled = vsync_on
	# When VSync is active, the concept of a "cap" doesn't apply,
	# so show a subtitle-style hint on the label.
	var label: Label = $MarginContainer/VBoxContainer/FPSCapRow/FPSCapLabel
	if vsync_on:
		label.text = "Frame Rate Cap  —  managed by VSync"
		fps_cap_option.select(0)
		_apply_fps_cap(0)
	else:
		label.text = "Frame Rate Cap"

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
	_sync_fps_cap_disabled(toggled_on)

func _on_fps_cap_item_selected(index: int) -> void:
	_apply_fps_cap(index)

func _on_back_pressed() -> void:
	# Auto-save before leaving — the user expects changes to stick
	_on_save_pressed()
	var target := MAIN_MENU_SCENE if return_scene.is_empty() else return_scene
	return_scene = ""
	Transition.to(target)

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
	prefs.set_value("popups",       "demo_notice_seen",          false)
	prefs.set_value("popups",       "controls_popup",            false)
	prefs.set_value("popups",       "stamina_popup",             false)
	prefs.set_value("popups",       "zoom_popup",                false)
	prefs.set_value("popups",       "roped_popup",               false)
	prefs.set_value("popups",       "falling_holds_popup",       false)
	prefs.set_value("popups",       "granite_topping_out_popup", false)
	prefs.set_value("popups",       "weather_popup",             false)
	prefs.set_value("popups",       "pockets_popup",             false)
	prefs.save(PREFS_PATH)

	print("Settings: all progress data reset.")
	reset_btn.text = "Data Reset!"
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(reset_btn):
		reset_btn.text = "Reset Data"
