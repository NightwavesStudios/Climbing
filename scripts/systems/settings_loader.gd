extends Node
## Autoload that loads and applies saved settings on game startup.
## Settings are persisted to user://settings.cfg by the Settings UI scene.
## Without this loader, settings like volume, window mode, vsync, and keybinds
## would not take effect until the player opens the Settings menu.

const SETTINGS_PATH := "user://settings.cfg"

const REBINDABLE_ACTIONS: Array[String] = [
	"select_left",
	"select_right",
	"select_left_foot",
	"select_right_foot",
]

const FPS_CAP_VALUES: Array[int] = [0, 30, 60, 120, 144]

const WINDOW_MODES: Array[int] = [
	DisplayServer.WINDOW_MODE_WINDOWED,
	DisplayServer.WINDOW_MODE_FULLSCREEN,
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
]

func _ready() -> void:
	_load_and_apply()


func _load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		print("SettingsLoader: No saved settings to apply — using defaults")
		return

	# ── Audio ──────────────────────────────────────────────────────────────
	if cfg.has_section_key("audio", "master_volume_db"):
		AudioServer.set_bus_volume_db(0, cfg.get_value("audio", "master_volume_db"))
	if cfg.has_section_key("audio", "muted"):
		AudioServer.set_bus_mute(0, cfg.get_value("audio", "muted"))

	# ── Window mode ────────────────────────────────────────────────────────
	var wm_idx: int = cfg.get_value("video", "window_mode_index", 1)
	if wm_idx >= 0 and wm_idx < WINDOW_MODES.size():
		DisplayServer.window_set_mode(WINDOW_MODES[wm_idx])

	# ── VSync ──────────────────────────────────────────────────────────────
	var vsync_on: bool = cfg.get_value("video", "vsync_enabled", true)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED
	)

	# ── FPS cap (only meaningful when VSync is off) ────────────────────────
	if vsync_on:
		Engine.max_fps = 0
	else:
		var fps_idx: int = cfg.get_value("performance", "fps_cap_index", 0)
		if fps_idx >= 0 and fps_idx < FPS_CAP_VALUES.size():
			Engine.max_fps = FPS_CAP_VALUES[fps_idx]

	# ── Keybinds ───────────────────────────────────────────────────────────
	for action in REBINDABLE_ACTIONS:
		if cfg.has_section_key("keybinds", action):
			var kc: int = cfg.get_value("keybinds", action)
			var ev := InputEventKey.new()
			ev.physical_keycode = kc as Key
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, ev)

	print("SettingsLoader: Applied saved settings from ", SETTINGS_PATH)
