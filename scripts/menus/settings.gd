extends Control

const MASTER_BUS := 0
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUME := 0.5

@onready var volume_slider: HSlider = $MarginContainer/VBoxContainer/Volume
@onready var window_mode_option: OptionButton = $MarginContainer/VBoxContainer/WindowMode
@onready var vsync_toggle: CheckBox = $MarginContainer/VBoxContainer/VSync
@onready var fps_cap_option: OptionButton = $MarginContainer/VBoxContainer/FPSCap

func _ready() -> void:
	if volume_slider.value_changed.is_connected(_on_volume_value_changed):
		volume_slider.value_changed.disconnect(_on_volume_value_changed)

	AudioServer.set_bus_mute(MASTER_BUS, false)
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(DEFAULT_VOLUME))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60

	load_settings()

	volume_slider.value_changed.connect(_on_volume_value_changed)

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

func _on_save_pressed() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("audio", "master_volume_db", AudioServer.get_bus_volume_db(MASTER_BUS))
	cfg.set_value("audio", "muted", AudioServer.is_bus_mute(MASTER_BUS))

	cfg.set_value("video", "window_mode_index", window_mode_option.selected)
	cfg.set_value("video", "vsync_enabled", vsync_toggle.button_pressed)
	cfg.set_value("performance", "fps_cap_index", fps_cap_option.selected)

	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("Settings save FAILED: %d" % err)
	else:
		print("Settings saved to: ", SETTINGS_PATH)

func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/main_menu.tscn")

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		print("No settings file, using defaults.")
		# Default to fullscreen
		window_mode_option.select(1)
		_on_window_mode_item_selected(1)
		return

	if cfg.has_section_key("audio", "master_volume_db"):
		AudioServer.set_bus_volume_db(MASTER_BUS, cfg.get_value("audio", "master_volume_db"))
	if cfg.has_section_key("audio", "muted"):
		AudioServer.set_bus_mute(MASTER_BUS, cfg.get_value("audio", "muted"))

	# Sync slider UI to loaded audio state
	var linear_vol := db_to_linear(AudioServer.get_bus_volume_db(MASTER_BUS))
	volume_slider.set_value_no_signal(clampf(linear_vol, 0.0, 1.0))

	# Load index → set UI → apply to system via the handler
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
