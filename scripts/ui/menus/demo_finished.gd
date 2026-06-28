extends CanvasLayer
## Demo finished overlay shown after completing the final demo level (granite_crag_10).
## Displays social buttons (Wishlist, Feedback, Discord) and a Back to Menu option.

signal menu_requested

const WISHLIST_URL  := "https://store.steampowered.com/app/4440890/Climbing_Simplified/"
const DISCORD_URL   := "https://discord.gg/5JyxqfsAbq"

@onready var backdrop: ColorRect    = $Backdrop
@onready var box: ColorRect         = $Box
@onready var title_label: Label     = $Box/VBox/Title
@onready var subtitle_label: Label  = $Box/VBox/Subtitle
@onready var wishlist_btn: Button   = $Box/VBox/WishlistButton
@onready var feedback_btn: Button   = $Box/VBox/FeedbackButton
@onready var discord_btn: Button    = $Box/VBox/DiscordButton
@onready var menu_btn: Button       = $Box/VBox/MenuButton

var _active_tweens: Array[Tween] = []


func _ready() -> void:
	visible = false
	layer = 10
	_reset_alpha()


func _reset_alpha() -> void:
	backdrop.modulate = Color(1, 1, 1, 0)
	box.modulate = Color(1, 1, 1, 0)
	box.scale = Vector2(0.85, 0.85)
	for child in [title_label, subtitle_label, wishlist_btn, feedback_btn, discord_btn, menu_btn]:
		if child:
			child.modulate = Color(1, 1, 1, 0)


func show_overlay() -> void:
	_reset_alpha()
	visible = true

	# Animate in
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_active_tweens.append(tween)
	tween.tween_property(backdrop, "modulate:a", 1.0, 0.4)
	tween.tween_property(box, "modulate:a", 1.0, 0.35)
	tween.tween_property(box, "scale", Vector2.ONE, 0.4)

	# Stagger the children
	var delay := 0.2
	for child in [title_label, subtitle_label, wishlist_btn, feedback_btn, discord_btn, menu_btn]:
		if child:
			var ct := create_tween()
			_active_tweens.append(ct)
			ct.tween_interval(delay)
			ct.tween_property(child, "modulate:a", 1.0, 0.3)
			delay += 0.1


func _hide_and_emit() -> void:
	# Fade out then emit menu signal
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_active_tweens.append(tween)
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.25)
	tween.tween_property(box, "modulate:a", 0.0, 0.2)
	tween.tween_property(box, "scale", Vector2(0.92, 0.92), 0.25)
	tween.finished.connect(func():
		visible = false
		menu_requested.emit()
	, CONNECT_ONE_SHOT)


func _on_wishlist_pressed() -> void:
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("""
			var a = document.createElement('a');
			a.href = '""" + WISHLIST_URL + """';
			a.target = '_blank';
			a.rel = 'noopener noreferrer';
			document.body.appendChild(a);
			a.click();
			document.body.removeChild(a);
		""", true)
	else:
		OS.shell_open(WISHLIST_URL)


func _on_feedback_pressed() -> void:
	# Open Discord for feedback
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("""
			var a = document.createElement('a');
			a.href = '""" + DISCORD_URL + """';
			a.target = '_blank';
			a.rel = 'noopener noreferrer';
			document.body.appendChild(a);
			a.click();
			document.body.removeChild(a);
		""", true)
	else:
		OS.shell_open(DISCORD_URL)


func _on_discord_pressed() -> void:
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("""
			var a = document.createElement('a');
			a.href = '""" + DISCORD_URL + """';
			a.target = '_blank';
			a.rel = 'noopener noreferrer';
			document.body.appendChild(a);
			a.click();
			document.body.removeChild(a);
		""", true)
	else:
		OS.shell_open(DISCORD_URL)


func _on_menu_pressed() -> void:
	_kill_tweens()
	_hide_and_emit()


func _kill_tweens() -> void:
	for t in _active_tweens:
		if t and is_instance_valid(t):
			t.kill()
	_active_tweens.clear()
