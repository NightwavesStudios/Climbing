extends CanvasLayer
class_name WeeklyTimer
## Count-up timer for weekly levels. Shows elapsed time so players can
## compete for the best time each week.

var elapsed_time: float = 0.0
var is_running: bool = false
var _started: bool = false

var timer_label: Label
var background_panel: PanelContainer


func _ready() -> void:
	layer = 100
	_setup_ui()
	visible = false


func _process(delta: float) -> void:
	if is_running:
		elapsed_time += delta
		_update_display()


func _setup_ui() -> void:
	# Guard: only set up if in scene tree
	if not is_inside_tree():
		return

	var viewport_size := get_viewport().get_visible_rect().size

	background_panel = PanelContainer.new()
	background_panel.position = Vector2((viewport_size.x - 180) / 2, 20)
	background_panel.custom_minimum_size = Vector2(180, 60)
	add_child(background_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	background_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	background_panel.add_child(margin)

	timer_label = Label.new()
	timer_label.text = _format_time(0.0)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 36)
	timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	margin.add_child(timer_label)

	_update_display()


func start_timer() -> void:
	if not _started:
		elapsed_time = 0.0
		is_running = true
		_started = true
		visible = true
		_update_display()
		print("WeeklyTimer: Started")


func stop_timer() -> float:
	is_running = false
	print("WeeklyTimer: Stopped at ", _format_time(elapsed_time))
	return elapsed_time


func pause_timer() -> void:
	is_running = false
	print("WeeklyTimer: Paused")


func resume_timer() -> void:
	if _started:
		is_running = true
		print("WeeklyTimer: Resumed")


func reset_timer() -> void:
	is_running = false
	_started = false
	elapsed_time = 0.0
	_update_display()
	visible = false
	print("WeeklyTimer: Reset")


func hide_timer() -> void:
	## Hide the timer display (e.g. while the level-complete summary is showing,
	## since the summary already shows the time). The timer reappears on the
	## next climb via start_timer().
	visible = false
	print("WeeklyTimer: Hidden")


func get_elapsed_time() -> float:
	return elapsed_time


func _update_display() -> void:
	if timer_label:
		timer_label.text = _format_time(elapsed_time)


static func _format_time(seconds: float) -> String:
	var mins := int(seconds / 60)
	var secs := int(seconds) % 60
	var millis := int((seconds - int(seconds)) * 100)
	return "%02d:%02d.%02d" % [mins, secs, millis]


static func format_seconds(seconds: float) -> String:
	return _format_time(seconds)


func cleanup() -> void:
	queue_free()
