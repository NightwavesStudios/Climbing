## main_menu.gd – attach to your MainMenu Control node.
extends Control

@onready var buttons: VBoxContainer = $CanvasLayer/Buttons
@onready var demo_notice: CanvasLayer = $DemoNotice

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Show the shared persistent menu background
	MenuBackgroundManager.show()
	
	# Force the sunset menu theme
	EnvironmentConfig.set_environment(EnvironmentConfig.EnvironmentType.MENU_SUNSET)

	# Show demo notice popup on every launch
	_show_demo_notice()

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

func _show_demo_notice() -> void:
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
