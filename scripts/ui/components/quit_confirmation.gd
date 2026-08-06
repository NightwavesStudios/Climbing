extends CanvasLayer
class_name QuitConfirmation

## Quit confirmation popup shown when the player clicks Quit.
## Displays "Thanks for playing!" along with Wishlist/Discord/Exit/Cancel options.

signal dismissed

const WISHLIST_URL := "https://store.steampowered.com/app/4484650/Climbing_Simplified/"
const DISCORD_URL  := "https://discord.gg/5JyxqfsAbq"

@onready var backdrop: ColorRect       = $Backdrop
@onready var box: Panel            = $Box
@onready var title_label: Label        = $Box/VBox/TitleLabel
@onready var wishlist_btn: Button      = $Box/VBox/WishlistButton
@onready var discord_btn: Button       = $Box/VBox/DiscordButton
@onready var exit_btn: Button          = $Box/VBox/ExitButton
@onready var cancel_btn: Button        = $Box/VBox/CancelButton


func _ready() -> void:
	visible = false
	layer = 10
	_reset_alpha()
	# Make all popup buttons a uniform width, sized to the widest one.
	call_deferred(&"_equalize_button_widths")


## Give every button in the popup the same width (based on the longest label),
## so Wishlist / Discord / Exit / Cancel line up as a cohesive column.
func _equalize_button_widths() -> void:
	UniversalButton.equalize_widths([wishlist_btn, discord_btn, exit_btn, cancel_btn])


func _reset_alpha() -> void:
	backdrop.modulate = Color(1, 1, 1, 0)
	box.modulate = Color(1, 1, 1, 0)
	box.scale = Vector2(0.88, 0.88)
	for child in [title_label, wishlist_btn, discord_btn, exit_btn, cancel_btn]:
		if child:
			child.modulate = Color(1, 1, 1, 0)


## Show the popup with a quick fade-in animation.
func show_popup() -> void:
	_reset_alpha()
	visible = true

	# Fast parallel animation — no staggers, no delays
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(backdrop, "modulate:a", 1.0, 0.2)
	tween.tween_property(box, "modulate:a", 1.0, 0.18)
	tween.tween_property(box, "scale", Vector2.ONE, 0.2)

	for child in [title_label, wishlist_btn, discord_btn, exit_btn, cancel_btn]:
		if child:
			tween.tween_property(child, "modulate:a", 1.0, 0.18)

	# Focus the Cancel button so controller navigation works immediately
	call_deferred(&"_focus_popup_button")

func _focus_popup_button() -> void:
	if cancel_btn and not cancel_btn.disabled:
		cancel_btn.grab_focus()
	elif exit_btn and not exit_btn.disabled:
		exit_btn.grab_focus()


## Dismiss the popup with a quick fade-out animation.
func dismiss_popup() -> void:
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.15)
	tween.tween_property(box, "modulate:a", 0.0, 0.12)
	tween.tween_property(box, "scale", Vector2(0.92, 0.92), 0.15)

	for child in [title_label, wishlist_btn, discord_btn, exit_btn, cancel_btn]:
		if child:
			tween.tween_property(child, "modulate:a", 0.0, 0.1)

	tween.finished.connect(func():
		visible = false
		dismissed.emit()
	, CONNECT_ONE_SHOT)


# ── Button callbacks ──────────────────────────────────────────────────────────

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


func _on_exit_pressed() -> void:
	# Save game state before quitting
	if has_node("/root/GameState"):
		get_node("/root/GameState").save_game()
	get_tree().quit()


func _on_cancel_pressed() -> void:
	dismiss_popup()
