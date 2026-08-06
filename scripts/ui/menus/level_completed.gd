extends CanvasLayer
## Overlay shown after completing a level.
##
## Weekly levels: full overlay showing best time, Retry, Share on Discord, Home.
## Normal levels:  simple layout with only a Next Climb button.

signal next_level_requested(next_level_path: String)
signal menu_requested
signal restart_requested
## Emitted when the player completes the last demo level (gym tutorial).
signal demo_finished

const DISCORD_URL  := "https://discord.gg/5JyxqfsAbq"

# ── Weekly overlay nodes (hidden for normal levels) ─────────────────────────
@onready var backdrop: ColorRect      = $Backdrop
@onready var box: Panel           = $Box
@onready var title_label: Label        = $Box/VBox/Title
@onready var time_label: Label         = $Box/VBox/TimeLabel
@onready var best_time_label: Label    = $Box/VBox/BestTimeLabel
@onready var restart_button: Button    = $Box/VBox/RestartButton
@onready var discord_button: Button    = $Box/VBox/DiscordButton
@onready var menu_button: Button       = $Box/VBox/MenuButton

# ── Leaderboard nodes ────────────────────────────────────────────────
@onready var leaderboard_title: Label      = $Box/VBox/LeaderboardTitle
@onready var leaderboard_entries: VBoxContainer = $Box/VBox/LeaderboardEntries
@onready var leaderboard_status: Label     = $Box/VBox/LeaderboardStatus

# ── Simple Next button (used for normal levels) ─────────────────────────────
@onready var next_button: Button       = $NextButton

## Last collection accessible in the demo — levels beyond this are gated.
const DEMO_END_COLLECTION := "intro-gym"

var _completed_level_path: String = ""
var _active_tweens: Array[Tween] = []
var _is_weekly := false
var _leaderboard_data_received := false  # Prevents timeout from overwriting loaded data
var _leaderboard_displayed := false  # True once rows have been shown (skip re-fade on name refresh)


func _ready() -> void:
	visible = false
	layer = 10
	_reset_all()
	# Make the weekly overlay buttons a uniform width, sized to the widest one.
	call_deferred(&"_equalize_button_widths")


## Give every weekly overlay button the same width (based on the longest label),
## so Retry / Share on Discord / Home line up as a cohesive column.
func _equalize_button_widths() -> void:
	UniversalButton.equalize_widths([restart_button, discord_button, menu_button])


func _exit_tree() -> void:
	# Disconnect from leaderboard signal when leaving the scene
	var wl := get_node_or_null("/root/WeeklyLeaderboard")
	if wl and wl.has_signal("leaderboard_ready") and wl.leaderboard_ready.is_connected(_on_leaderboard_ready):
		wl.leaderboard_ready.disconnect(_on_leaderboard_ready)


func _reset_all() -> void:
	_leaderboard_data_received = false
	_leaderboard_displayed = false
	# Weekly overlay group
	if backdrop:
		backdrop.modulate = Color(1, 1, 1, 0)
	if box:
		box.modulate = Color(1, 1, 1, 0)
		box.scale = Vector2(0.85, 0.85)
	for child in [title_label, time_label, best_time_label,
				  restart_button, discord_button, menu_button,
				  leaderboard_title, leaderboard_status]:
		if child:
			child.modulate = Color(1, 1, 1, 0)
	_reset_leaderboard()
	# Next button (simple layout)
	if next_button:
		next_button.modulate = Color(1, 1, 1, 0)
		next_button.modulate.a = 0.0


# =============================================================================
#  LEVEL NAVIGATION HELPERS
# =============================================================================

func _get_next_destination(level_path: String) -> String:
	var next_in_collection: String = GameState.get_next_level(level_path)
	if next_in_collection != "":
		return next_in_collection

	var current_col: String = GameState.get_current_collection()
	if current_col == DEMO_END_COLLECTION:
		return ""

	var collection_ids: Array = GameState.get_all_collection_ids()
	var current_col_index: int = collection_ids.find(current_col)

	for i in range(current_col_index + 1, collection_ids.size()):
		var candidate: String = collection_ids[i]
		if GameState.is_collection_unlocked(candidate):
			var data: Dictionary = GameState.get_collection_data(candidate)
			if not data.is_empty() and data.levels.size() > 0:
				return data.levels[0]

	return ""


func _is_last_in_collection(level_path: String) -> bool:
	return GameState.get_next_level(level_path) == ""


func _is_demo_end(level_path: String) -> bool:
	var current_col: String = GameState.get_current_collection()
	return current_col == DEMO_END_COLLECTION and GameState.get_next_level(level_path) == ""


# =============================================================================
#  SHOW OVERLAY (entry point)
# =============================================================================

func show_overlay(completed_level_path: String, completion_time: float = 0.0) -> void:
	_completed_level_path = completed_level_path
	_is_weekly = completed_level_path.begins_with("res://data/levels/weekly/")

	_reset_all()

	if _is_weekly:
		_show_weekly_overlay(completion_time)
	else:
		_show_normal_overlay()


# ── Weekly: full overlay with time, Retry, Discord, Home ───────────────────

func _show_weekly_overlay(completion_time: float) -> void:
	# Hide the simple Next button
	if next_button:
		next_button.visible = false

	# Title
	if title_label:
		title_label.text = "Route Complete!"

	# Time labels
	_show_completion_time(completion_time)

	# Show weekly buttons
	_set_button_visible(restart_button, true)
	_set_button_visible(discord_button, true)
	_set_button_visible(menu_button, true)

	# ── Leaderboard ────────────────────────────────────────────────────────
	_show_leaderboard_loading()

	# ── Animate in ─────────────────────────────────────────────────────────
	visible = true

	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_active_tweens.append(tween)
	tween.tween_property(backdrop, "modulate:a", 1.0, 0.4)
	tween.tween_property(box, "modulate:a", 1.0, 0.35)
	tween.tween_property(box, "scale", Vector2.ONE, 0.4)

	var children_to_fade: Array[Node] = [title_label]
	if time_label and time_label.visible:
		children_to_fade.append(time_label)
	if best_time_label and best_time_label.visible:
		children_to_fade.append(best_time_label)
	if restart_button and restart_button.visible:
		children_to_fade.append(restart_button)
	if discord_button and discord_button.visible:
		children_to_fade.append(discord_button)
	if menu_button and menu_button.visible:
		children_to_fade.append(menu_button)

	var delay := 0.15
	for child in children_to_fade:
		if child:
			var ct := create_tween()
			_active_tweens.append(ct)
			ct.tween_interval(delay)
			ct.tween_property(child, "modulate:a", 1.0, 0.35) \
				.set_ease(Tween.EASE_OUT) \
				.set_trans(Tween.TRANS_CUBIC)
			delay += 0.1

	call_deferred(&"_focus_overlay_button")


# ── Normal level: simple Next button ────────────────────────────────────────

func _show_normal_overlay() -> void:
	# Hide the weekly overlay group
	_set_weekly_group_visible(false)

	# Configure the Next button
	var next_dest: String = _get_next_destination(_completed_level_path)
	var is_demo_end := _is_demo_end(_completed_level_path)

	if next_button:
		if is_demo_end:
			next_button.visible = true
			next_button.disabled = false
			next_button.text = "Demo Complete"
		elif next_dest == "":
			next_button.visible = false
			next_button.disabled = true
		else:
			next_button.visible = true
			next_button.disabled = false
			if _is_last_in_collection(_completed_level_path):
				next_button.text = "Next Area"
			else:
				next_button.text = "Next Climb"

	# ── Simple fade-in ─────────────────────────────────────────────────────
	visible = true
	if next_button and next_button.visible:
		var tween := create_tween()
		_active_tweens.append(tween)
		next_button.modulate.a = 0.0
		tween.tween_property(next_button, "modulate:a", 1.0, 0.35) \
			.set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_CUBIC)

	call_deferred(&"_focus_overlay_button")


# =============================================================================
#  HELPERS
# =============================================================================

func _set_weekly_group_visible(do_show: bool) -> void:
	for node in [backdrop, box, title_label, time_label, best_time_label,
				 restart_button, discord_button, menu_button,
				 leaderboard_title, leaderboard_entries, leaderboard_status]:
		if node:
			node.visible = do_show


func _set_button_visible(button: Button, visible_flag: bool) -> void:
	if not button:
		return
	button.visible = visible_flag
	button.disabled = not visible_flag


func _show_completion_time(current_time: float) -> void:
	if time_label:
		time_label.visible = false
	if best_time_label:
		best_time_label.visible = false

	if current_time <= 0.0:
		return

	var fmt := WeeklyTimer._format_time(current_time)

	if time_label:
		time_label.visible = true
		time_label.text = fmt

	if best_time_label:
		var best_time := GameState.get_weekly_best_time(_completed_level_path)
		if best_time > 0.0:
			best_time_label.visible = true
			if current_time <= best_time:
				best_time_label.text = "New Personal Best!"
				best_time_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
			else:
				var diff := current_time - best_time
				best_time_label.text = "Best: %s (+%s)" % [WeeklyTimer._format_time(best_time), WeeklyTimer._format_time(diff)]
				best_time_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
		else:
			best_time_label.visible = true
			best_time_label.text = "Personal Best"
			best_time_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))


# =============================================================================
#  LEADERBOARD
# =============================================================================

func _show_leaderboard_loading() -> void:
	"""Show a loading indicator while waiting for Steam leaderboard data."""
	if leaderboard_title:
		leaderboard_title.visible = true
		leaderboard_title.modulate = Color(0.95, 0.85, 0.4, 0)
		# Fade in the title after the main overlay animation finishes
		var tween := create_tween()
		_active_tweens.append(tween)
		tween.tween_interval(0.5)
		tween.tween_property(leaderboard_title, "modulate:a", 1.0, 0.35) \
			.set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_CUBIC)

	if leaderboard_status:
		leaderboard_status.visible = true
		leaderboard_status.text = "Loading leaderboard..."
		leaderboard_status.modulate = Color(0.6, 0.6, 0.7, 0)
		# Fade in the status after the title
		var tween := create_tween()
		_active_tweens.append(tween)
		tween.tween_interval(0.65)
		tween.tween_property(leaderboard_status, "modulate:a", 0.6, 0.35) \
			.set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_CUBIC)

	if leaderboard_entries:
		leaderboard_entries.visible = false
		_reset_leaderboard()

	# Connect to the WeeklyLeaderboard singleton if it exists.
	# The upload_score() call in main_scene.gd already started the full chain:
	# findOrCreate → upload → download → emit leaderboard_ready.
	# We just need to listen for the result — no need to call download_entries_around_player() here.
	var wl := get_node_or_null("/root/WeeklyLeaderboard")
	if wl and wl.has_signal("leaderboard_ready") and not wl.leaderboard_ready.is_connected(_on_leaderboard_ready):
		wl.leaderboard_ready.connect(_on_leaderboard_ready)

	# Fallback: if Steam data never arrives (e.g., no Steam connection), show a message after 5s.
	var tree := get_tree()
	if tree:
		var timeout := tree.create_timer(5.0)
		timeout.timeout.connect(_on_leaderboard_timeout)

func _on_leaderboard_ready(entries: Array, player_rank: int, _player_time: float) -> void:
	"""Handle leaderboard data from Steam."""
	_leaderboard_data_received = true
	_reset_leaderboard()

	if entries.is_empty():
		# Title is already faded in by _show_leaderboard_loading(); just update the status
		if leaderboard_status:
			leaderboard_status.text = "No leaderboard data yet"
			leaderboard_status.modulate = Color(1, 1, 1, 0)
			var tween := create_tween()
			_active_tweens.append(tween)
			tween.tween_property(leaderboard_status, "modulate:a", 0.6, 0.35) \
				.set_ease(Tween.EASE_OUT) \
				.set_trans(Tween.TRANS_CUBIC)
		return

	# Hide the loading status now that we have real data
	if leaderboard_status:
		leaderboard_status.visible = false

	if leaderboard_entries:
		leaderboard_entries.visible = true

	# Create an entry row for each leaderboard entry
	for entry in entries:
		var row := _create_leaderboard_row(entry, player_rank)
		if row:
			leaderboard_entries.add_child(row)

	# Fade in the leaderboard entries only the first time data arrives
	# (later re-emissions are name refreshes from persona_state_change — don't flash).
	if leaderboard_entries and leaderboard_entries.get_child_count() > 0 and not _leaderboard_displayed:
		_leaderboard_displayed = true
		leaderboard_entries.modulate = Color(1, 1, 1, 0)
		var tween := create_tween()
		_active_tweens.append(tween)
		tween.tween_interval(0.5)
		tween.tween_property(leaderboard_entries, "modulate:a", 1.0, 0.35) \
			.set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_CUBIC)


func _on_leaderboard_timeout() -> void:
	"""Fallback if Steam leaderboard data never arrives."""
	if _leaderboard_data_received:
		return
	# Title is already faded in by _show_leaderboard_loading(); just update the status text
	if leaderboard_status and leaderboard_status.visible:
		leaderboard_status.text = "Leaderboard unavailable"
		leaderboard_status.modulate = Color(1, 1, 1, 0)
		var tween := create_tween()
		_active_tweens.append(tween)
		tween.tween_property(leaderboard_status, "modulate:a", 0.6, 0.35) \
			.set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_CUBIC)
func _create_leaderboard_row(entry: Dictionary, player_rank: int) -> HBoxContainer:
	"""Create a single leaderboard row (rank, name, time) for one entry."""
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	# Rank label
	var rank_label := Label.new()
	rank_label.text = "#" + str(entry["global_rank"])
	rank_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rank_label.add_theme_font_size_override("font_size", 14)
	rank_label.custom_minimum_size = Vector2(40, 0)

	# Player name label
	var name_label := Label.new()
	var display_name: String = str(entry.get("name", ""))
	if display_name == "" and entry.get("global_rank", 0) == player_rank and player_rank > 0:
		# This is the local player's row but the name didn't resolve — use the persona name directly.
		var wl := get_node_or_null("/root/WeeklyLeaderboard")
		if wl and wl.has_method("get_local_player_name"):
			display_name = wl.get_local_player_name()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 14)

	# Time label
	var row_time_label := Label.new()
	var time_seconds: float = entry["score"] / 1000.0
	row_time_label.text = WeeklyLeaderboard.format_time(time_seconds)
	row_time_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	row_time_label.add_theme_font_size_override("font_size", 14)
	row_time_label.custom_minimum_size = Vector2(80, 0)
	row_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Highlight the local player's row
	if entry["global_rank"] == player_rank and player_rank > 0:
		rank_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
		name_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
		row_time_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
	else:
		rank_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
		name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
		row_time_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))

	row.add_child(rank_label)
	row.add_child(name_label)
	row.add_child(row_time_label)
	return row


func _reset_leaderboard() -> void:
	"""Clear all dynamically created leaderboard entry rows."""
	if leaderboard_entries:
		for child in leaderboard_entries.get_children():
			leaderboard_entries.remove_child(child)
			child.queue_free()


# =============================================================================
#  TRANSITIONS
# =============================================================================

func _fade_out_all() -> void:
	_kill_active_tweens()
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_active_tweens.append(tween)

	var items: Array[Node] = [backdrop, box, title_label, time_label, best_time_label,
		restart_button, discord_button, menu_button, next_button,
		leaderboard_title, leaderboard_entries, leaderboard_status]

	var any_added := false
	for node in items:
		if node and node.visible:
			tween.tween_property(node, "modulate:a", 0.0, 0.2)
			any_added = true
	if any_added:
		await tween.finished
	else:
		tween.kill()
	visible = false


func _focus_overlay_button() -> void:
	if _is_weekly:
		for btn in [restart_button, discord_button, menu_button]:
			if btn and not btn.disabled and btn.visible:
				btn.grab_focus()
				return
	else:
		if next_button and not next_button.disabled and next_button.visible:
			next_button.grab_focus()
			return

func _kill_active_tweens() -> void:
	for t in _active_tweens:
		if t and is_instance_valid(t):
			t.kill()
	_active_tweens.clear()


# =============================================================================
#  BUTTON HANDLERS
# =============================================================================

func _on_next_button_pressed() -> void:
	var next_dest: String = _get_next_destination(_completed_level_path)
	if next_dest == "":
		if _is_demo_end(_completed_level_path):
			_kill_active_tweens()
			await _fade_out_all()
			demo_finished.emit()
			return
		if next_button:
			next_button.visible = false
			next_button.disabled = true
		return
	GameState.set_current_level(next_dest)
	_kill_active_tweens()
	await _fade_out_all()
	next_level_requested.emit(next_dest)


func _on_menu_button_pressed() -> void:
	_kill_active_tweens()
	await _fade_out_all()
	menu_requested.emit()


func _on_restart_button_pressed() -> void:
	_kill_active_tweens()
	await _fade_out_all()
	restart_requested.emit()


func _on_discord_button_pressed() -> void:
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
