extends Control

const MASTER_BUS := 0
const SETTINGS_PATH := "user://settings.cfg"

const DEFAULT_VOLUME := 0.5
const DEFAULT_FPS_CAP := 60

func _ready() -> void:
	AudioServer.set_bus_mute(MASTER_BUS, false)
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(DEFAULT_VOLUME))

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

	Engine.max_fps = DEFAULT_FPS_CAP

	load_settings()


func _on_volume_value_changed(value: float) -> void:
	if value <= 0.01:
		AudioServer.set_bus_mute(MASTER_BUS, true)
	else:
		AudioServer.set_bus_mute(MASTER_BUS, false)
		AudioServer.set_bus_volume_db(
			MASTER_BUS,
			linear_to_db(value)
		)


func _on_window_mode_item_selected(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _on_vsync_toggled(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)


func _on_fps_cap_item_selected(index: int) -> void:
	match index:
		0: Engine.max_fps = 0
		1: Engine.max_fps = 60
		2: Engine.max_fps = 120
		3: Engine.max_fps = 144


func _on_save_pressed() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("audio", "master_volume",
		AudioServer.get_bus_volume_db(MASTER_BUS)
	)
	cfg.set_value("audio", "muted",
		AudioServer.is_bus_mute(MASTER_BUS)
	)

	cfg.set_value("video", "window_mode",
		DisplayServer.window_get_mode()
	)
	cfg.set_value("video", "vsync",
		DisplayServer.window_get_vsync_mode()
	)

	cfg.set_value("performance", "fps_cap",
		Engine.max_fps
	)

	cfg.save(SETTINGS_PATH)


func _on_back_pressed() -> void:
	Transition.to("res://scenes/menus/main_menu.tscn")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return

	if cfg.has_section_key("audio", "master_volume"):
		AudioServer.set_bus_volume_db(
			MASTER_BUS,
			cfg.get_value("audio", "master_volume")
		)

	if cfg.has_section_key("audio", "muted"):
		AudioServer.set_bus_mute(
			MASTER_BUS,
			cfg.get_value("audio", "muted")
		)

	if cfg.has_section_key("video", "window_mode"):
		DisplayServer.window_set_mode(
			cfg.get_value("video", "window_mode")
		)

	if cfg.has_section_key("video", "vsync"):
		DisplayServer.window_set_vsync_mode(
			cfg.get_value("video", "vsync")
		)

	if cfg.has_section_key("performance", "fps_cap"):
		Engine.max_fps = cfg.get_value(
			"performance", "fps_cap"
		)
