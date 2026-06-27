extends Control

const MASTER_BUS := 0
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUME := 0.5

# --- existing refs ---
@onready var volume_slider: HSlider         = $MarginContainer/VBoxContainer/Volume
@onready var window_mode_option: OptionButton = $MarginContainer/VBoxContainer/WindowMode
@onready var vsync_toggle: CheckBox         = $MarginContainer/VBoxContainer/VSync
@onready var fps_cap_option: OptionButton   = $MarginContainer/VBoxContainer/FPSCap

# --- keybind refs ---
@onready var keybinds_container: VBoxContainer = $MarginContainer/VBoxContainer/KeybindsContainer

# --- reset data refs ---
@onready var reset_data_dialog: ConfirmationDialog = $ResetDataDialog

# Which actions to expose for rebinding (must match your Input Map exactly)
const REBINDABLE_ACTIONS := [
	"select_left",
	"select_right",
	"select_left_foot",
	"select_right_foot",
]

var _listening_action: String = ""   # action currently waiting for a new key
var _action_buttons: Dictionary = {} # action_name -> Button

# ─────────────────────────────────────────────
func _ready() -> void:
	# Show the shared persistent menu background
	MenuBackgroundManager.show()
	
	if volume_slider.value_changed.is_connected(_on_volume_value_changed):
		volume_slider.value_changed.disconnect(_on_volume_value_changed)

	AudioServer.set_bus_mute(MASTER_BUS, false)
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(DEFAULT_VOLUME))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60

	_build_keybind_ui()
	load_settings()

	volume_slider.value_changed.connect(_on_volume_value_changed)

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
	var events := InputMap.action_get_events(action)
	for e in events:
		if e is InputEventKey:
			return e.as_text_physical_keycode()
	return "(none)"

# ─────────────────────────────────────────────
#  REBIND LOGIC
# ─────────────────────────────────────────────
func _on_rebind_button_pressed(action: String, btn: Button) -> void:
	if _listening_action != "":
		# Cancel the previous listen
		var old_btn: Button = _action_buttons.get(_listening_action)
		if old_btn:
			old_btn.text = _get_action_key_label(_listening_action)

	_listening_action = action
	btn.text = "Press a key…"
	set_process_unhandled_key_input(true)

func _unhandled_key_input(event: InputEvent) -> void:
	if _listening_action == "" or not event is InputEventKey:
		return
	if not event.pressed:
		return

	# Escape cancels
	if event.physical_keycode == KEY_ESCAPE:
		var btn: Button = _action_buttons.get(_listening_action)
		if btn:
			btn.text = _get_action_key_label(_listening_action)
		_listening_action = ""
		set_process_unhandled_key_input(false)
		get_viewport().set_input_as_handled()
		return

	# Apply the new binding
	var new_event := InputEventKey.new()
	new_event.physical_keycode = event.physical_keycode

	InputMap.action_erase_events(_listening_action)
	InputMap.action_add_event(_listening_action, new_event)

	var btn: Button = _action_buttons.get(_listening_action)
	if btn:
		btn.text = new_event.as_text_physical_keycode()

	_listening_action = ""
	set_process_unhandled_key_input(false)
	get_viewport().set_input_as_handled()

# ─────────────────────────────────────────────
#  SAVE / LOAD
# ─────────────────────────────────────────────
func _on_save_pressed() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("audio",       "master_volume_db", AudioServer.get_bus_volume_db(MASTER_BUS))
	cfg.set_value("audio",       "muted",            AudioServer.is_bus_mute(MASTER_BUS))
	cfg.set_value("video",       "window_mode_index", window_mode_option.selected)
	cfg.set_value("video",       "vsync_enabled",     vsync_toggle.button_pressed)
	cfg.set_value("performance", "fps_cap_index",     fps_cap_option.selected)

	# Save keybinds
	for action in REBINDABLE_ACTIONS:
		var events := InputMap.action_get_events(action)
		for e in events:
			if e is InputEventKey:
				cfg.set_value("keybinds", action, e.physical_keycode)
				break

	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("Settings save FAILED: %d" % err)
	else:
		print("Settings saved to: ", SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		print("No settings file, using defaults.")
		window_mode_option.select(1)
		_on_window_mode_item_selected(1)
		return

	if cfg.has_section_key("audio", "master_volume_db"):
		AudioServer.set_bus_volume_db(MASTER_BUS, cfg.get_value("audio", "master_volume_db"))
	if cfg.has_section_key("audio", "muted"):
		AudioServer.set_bus_mute(MASTER_BUS, cfg.get_value("audio", "muted"))

	var linear_vol := db_to_linear(AudioServer.get_bus_volume_db(MASTER_BUS))
	volume_slider.set_value_no_signal(clampf(linear_vol, 0.0, 1.0))

	if cfg.has_section_key("video", "window_mode_index"):
		var idx: int = cfg.get_value("video", "window_mode_index")
		window_mode_option.select(idx)
		_on_window_mode_item_selected(idx)
	else:
		window_mode_option.select(1)
		_on_window_mode_item_selected(1)

	if cfg.has_section_key("video", "vsync_enabled"):
		var vsync_on: bool = cfg.get_value("video", "vsync_enabled")
		vsync_toggle.set_pressed_no_signal(vsync_on)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED
		)

	if cfg.has_section_key("performance", "fps_cap_index"):
		var idx: int = cfg.get_value("performance", "fps_cap_index")
		fps_cap_option.select(idx)
		_on_fps_cap_item_selected(idx)

	# Load keybinds
	for action in REBINDABLE_ACTIONS:
		if cfg.has_section_key("keybinds", action):
			var keycode: int = cfg.get_value("keybinds", action)
			var new_event := InputEventKey.new()
			new_event.physical_keycode = keycode
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, new_event)

		# Refresh button label whether loaded or default
		var btn: Button = _action_buttons.get(action)
		if btn:
			btn.text = _get_action_key_label(action)

# ─────────────────────────────────────────────
#  EXISTING HANDLERS (unchanged)
# ─────────────────────────────────────────────
func _on_volume_value_changed(value: float) -> void:
	if value <= 0.01:
		AudioServer.set_bus_mute(MASTER_BUS, true)
	else:
		AudioServer.set_bus_mute(MASTER_BUS, false)
		AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(value))

func _on_window_mode_item_selected(index: int) -> void:
	match index:
		0: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _on_vsync_toggled(toggled_on: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if toggled_on else DisplayServer.VSYNC_DISABLED
	)

func _on_fps_cap_item_selected(index: int) -> void:
	match index:
		0: Engine.max_fps = 0
		1: Engine.max_fps = 60
		2: Engine.max_fps = 120
		3: Engine.max_fps = 144

func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/main_menu.tscn")

# ─────────────────────────────────────────────
#  RESET DATA
# ─────────────────────────────────────────────

const INSTRUCTIONS_SAVE_PATH := "user://prefs.cfg"

func _on_reset_data_pressed() -> void:
	"""Show confirmation dialog before resetting"""
	reset_data_dialog.popup_centered()

func _on_reset_data_dialog_confirmed() -> void:
	"""Reset all progress data"""
	# Reset game progress (completed levels, collections, metadata)
	if has_node("/root/GameState"):
		var gs: Node = get_node("/root/GameState")
		if gs.has_method("reset_progress"):
			gs.reset_progress()

	# Reset popup/instruction seen-flags so tutorials replay
	var prefs_cfg := ConfigFile.new()
	prefs_cfg.set_value("instructions", "shown", false)
	prefs_cfg.set_value("popups", "tutorial_popup", false)
	prefs_cfg.set_value("popups", "granite_topping_out_popup", false)
	prefs_cfg.save(INSTRUCTIONS_SAVE_PATH)

	print("Settings: All progress data reset")

	# Visual feedback — briefly change the button text
	var reset_btn: Button = $MarginContainer/VBoxContainer/ResetData
	if reset_btn:
		reset_btn.text = "✓ Data Reset!"
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(reset_btn):
			reset_btn.text = "Reset Data"
