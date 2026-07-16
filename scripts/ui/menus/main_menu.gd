## main_menu.gd – attach to your MainMenu Control node.
extends Control

const PREFS_PATH        := "user://prefs.cfg"
const DEMO_NOTICE_KEY   := "demo_notice_seen"

const ENTRY_DURATION    := 0.45  # duration of each element's tween

@onready var buttons: VBoxContainer = $CanvasLayer/Buttons
@onready var demo_notice: CanvasLayer = $DemoNotice
@onready var title_sprite: Sprite2D = $"Climbing(14)"
@onready var discord_btn: Button = $Discord

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Show the shared persistent menu background
	MenuBackgroundManager.show()
	
	# No FPS cap on the menu — it causes visual stutter/glitching
	Engine.max_fps = 0
	
	# Force the sunset menu theme
	EnvironmentConfig.set_environment(EnvironmentConfig.EnvironmentType.MENU_SUNSET)

	# Animate menu elements in with a staggered reveal
	_play_entry_animation()

	# Show demo notice popup only once
	_show_demo_notice_if_needed()


# ── Entry animation ──────────────────────────────────────────────────────────

## Staggered fade-and-slide-in for title, buttons, and Discord button so
## the menu feels polished when revealed after the splash-transition fade-in.
func _play_entry_animation() -> void:
	var title_y := title_sprite.position.y
	var buttons_y := buttons.position.y
	var discord_pos := discord_btn.position

	# Set initial states: invisible + slightly offset
	title_sprite.modulate = Color(1, 1, 1, 0.0)
	title_sprite.position.y = title_y - 20.0

	buttons.modulate = Color(1, 1, 1, 0.0)
	buttons.position.y = buttons_y + 30.0

	discord_btn.modulate = Color(1, 1, 1, 0.0)
	discord_btn.position.y = discord_pos.y + 20.0

	# Staggered reveal: title first, then buttons, then discord
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 1. Title drops in and fades up
	tween.tween_interval(0.05)
	var t := tween.parallel()
	t.tween_property(title_sprite, "modulate:a", 1.0, ENTRY_DURATION * 1.2)
	t.tween_property(title_sprite, "position:y", title_y, ENTRY_DURATION * 1.2)

	# 2. Buttons slide up in their container (animate the container)
	tween.tween_interval(0.12)
	var b := tween.parallel()
	b.tween_property(buttons, "modulate:a", 1.0, ENTRY_DURATION)
	b.tween_property(buttons, "position:y", buttons_y, ENTRY_DURATION)

	# 3. Discord button fades in last
	tween.tween_interval(0.08)
	var d := tween.parallel()
	d.tween_property(discord_btn, "modulate:a", 1.0, ENTRY_DURATION * 0.8)
	d.tween_property(discord_btn, "position:y", discord_pos.y, ENTRY_DURATION * 0.8)


# ── Button callbacks ─────────────────────────────────────────────────────────
func _on_play_pressed() -> void:
	Transition.to("res://scenes/menus/collections_select.tscn")

func _on_level_maker_pressed() -> void:
	Transition.to("res://scenes/editor/level_editor.tscn")

func _on_settings_pressed() -> void:
	Transition.to("res://scenes/menus/settings.tscn")

func _on_quit_pressed() -> void:
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()

func _on_button_pressed() -> void:
	var url = "https://docs.google.com/document/d/1N6-leO-syXynmaG4eIWHm48-PhJm5FvxIoEAVukUTqs/edit?usp=sharing"
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("""
			var a = document.createElement('a');
			a.href = '""" + url + """';
			a.target = '_blank';
			a.rel = 'noopener noreferrer';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
		""", true)
	else:
		OS.shell_open(url)

func _show_demo_notice_if_needed() -> void:
	# Check if already dismissed — only show once.
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)
	if cfg.get_value("popups", DEMO_NOTICE_KEY, false):
		return

	if not demo_notice or not is_instance_valid(demo_notice):
		return

	var backdrop := $DemoNotice/Backdrop as ColorRect
	var box := $DemoNotice/Box as ColorRect

	demo_notice.process_mode = PROCESS_MODE_INHERIT
	demo_notice.show()

	# Start from invisible — modulate with Color.WHITE so it acts as pure alpha
	if backdrop:
		backdrop.modulate = Color(1, 1, 1, 0)
	if box:
		box.modulate = Color(1, 1, 1, 0)
		box.scale = Vector2(0.85, 0.85)

	# Animate in: backdrop fades, box scales+fades with slight bounce
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if backdrop:
		tween.tween_property(backdrop, "modulate:a", 1.0, 0.4)
	if box:
		tween.tween_property(box, "modulate:a", 1.0, 0.35)
		tween.tween_property(box, "scale", Vector2.ONE, 0.4)

	var labels := demo_notice.find_children("", "Label", true, false)
	for label in labels:
		var l := label as Label
		if l:
			l.modulate = Color(1, 1, 1, 0)
			tween.tween_property(l, "modulate:a", 1.0, 0.4)

	var btns := demo_notice.find_children("", "Button", true, false)
	for button in btns:
		var b := button as Button
		if b:
			b.modulate = Color(1, 1, 1, 0)
			tween.tween_property(b, "modulate:a", 1.0, 0.4)


func _on_demo_notice_dismissed() -> void:
	# Mark as seen so it never shows again.
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)
	cfg.set_value("popups", DEMO_NOTICE_KEY, true)
	cfg.save(PREFS_PATH)

	if not demo_notice or not is_instance_valid(demo_notice):
		return

	var backdrop := $DemoNotice/Backdrop as ColorRect
	var box := $DemoNotice/Box as ColorRect

	# Animate out
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	if backdrop:
		tween.tween_property(backdrop, "modulate:a", 0.0, 0.25)
	if box:
		tween.tween_property(box, "modulate:a", 0.0, 0.2)
		tween.tween_property(box, "scale", Vector2(0.92, 0.92), 0.25)

	var labels := demo_notice.find_children("", "Label", true, false)
	for label in labels:
		var l := label as Label
		if l:
			tween.tween_property(l, "modulate:a", 0.0, 0.15)

	var btns := demo_notice.find_children("", "Button", true, false)
	for btn in btns:
		var b := btn as Button
		if b:
			tween.tween_property(b, "modulate:a", 0.0, 0.15)

	tween.finished.connect(func():
		demo_notice.hide()
		demo_notice.process_mode = PROCESS_MODE_DISABLED
	, CONNECT_ONE_SHOT)


func _on_discord_pressed() -> void:
	OS.shell_open("https://discord.gg/5JyxqfsAbq")
