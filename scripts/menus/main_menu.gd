## main_menu.gd  –  attach to your MainMenu Control node.
## The scene must have a RandomBackground node (or a Control with
## random_background.gd attached) as a child, referenced below.

extends Control

@onready var buttons:    VBoxContainer      = $CanvasLayer/Buttons
@onready var music_player: AudioStreamPlayer = $MainMenuTheme
@onready var background: RandomBackground   = $RandomBackground   # ← your new node

# 🎵 Loop timestamps (seconds)
const MUSIC_LOOP_START := 57.6
const MUSIC_LOOP_END   := 115.2

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	music_player.play()
	# The RandomBackground node handles its own fade-in, so nothing else needed.


func _process(_delta: float) -> void:
	if music_player.playing and music_player.get_playback_position() >= MUSIC_LOOP_END:
		music_player.seek(MUSIC_LOOP_START)

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
	
