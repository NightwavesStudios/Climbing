extends CanvasLayer
class_name SpeedTimer

## Minimal timer UI for speed climbing discipline

var time_limit: float = 30.0  # Default 30 seconds
var time_remaining: float = 30.0
var is_running: bool = false
var timer_started: bool = false

# UI elements
var timer_label: Label
var background_panel: PanelContainer

# Signals
signal time_expired
signal timer_started_signal
signal time_warning(seconds_remaining: float)

# ═══════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════

func _ready():
	layer = 100  # Ensure timer is above everything
	print("SpeedTimer: Setting up minimal UI")
	setup_ui()
	
	# Hide by default until explicitly shown
	visible = false

func _process(delta):
	if is_running:
		time_remaining -= delta
		
		if time_remaining <= 0:
			time_remaining = 0
			is_running = false
			time_expired.emit()
			print("SpeedTimer: TIME EXPIRED!")
		
		# Emit warnings at specific times
		var prev_time = time_remaining + delta
		
		if prev_time > 10.0 and time_remaining <= 10.0:
			time_warning.emit(10.0)
			print("SpeedTimer: 10 seconds warning")
		elif prev_time > 5.0 and time_remaining <= 5.0:
			time_warning.emit(5.0)
			print("SpeedTimer: 5 seconds warning!")
		
		update_display()

# ═══════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════

func setup_ui():
	"""Create minimal timer UI"""
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Simple background panel
	background_panel = PanelContainer.new()
	background_panel.position = Vector2((viewport_size.x - 200) / 2, 20)
	background_panel.custom_minimum_size = Vector2(200, 80)
	add_child(background_panel)
	
	# Clean, minimal background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	background_panel.add_theme_stylebox_override("panel", style)
	
	# Margin for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	background_panel.add_child(margin)
	
	# Timer label - clean and large
	timer_label = Label.new()
	timer_label.text = format_time(time_limit)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 48)
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	margin.add_child(timer_label)
	
	print("SpeedTimer: Minimal UI setup complete")
	update_display()

func set_time_limit(seconds: float):
	"""Set the time limit for speed climbing"""
	time_limit = seconds
	time_remaining = seconds
	
	print("SpeedTimer: Time limit set to ", seconds, " seconds")
	update_display()

# ═══════════════════════════════════════════════
# TIMER CONTROL
# ═══════════════════════════════════════════════

func start_timer():
	"""Start the countdown"""
	if not timer_started:
		is_running = true
		timer_started = true
		timer_started_signal.emit()
		print("SpeedTimer: STARTED - ", time_limit, " seconds")

func pause_timer():
	"""Pause the countdown"""
	is_running = false
	print("SpeedTimer: PAUSED at ", format_time(time_remaining))

func resume_timer():
	"""Resume the countdown"""
	if timer_started:
		is_running = true
		print("SpeedTimer: RESUMED")

func stop_timer():
	"""Stop and reset the timer"""
	is_running = false
	timer_started = false
	time_remaining = time_limit
	print("SpeedTimer: STOPPED and RESET")
	update_display()

func add_time(seconds: float):
	"""Add bonus time"""
	time_remaining += seconds
	time_remaining = min(time_remaining, time_limit * 1.5)
	print("➕ SpeedTimer: Added ", seconds, " seconds")
	update_display()

# ═══════════════════════════════════════════════
# DISPLAY
# ═══════════════════════════════════════════════

func update_display():
	"""Update timer display"""
	if not timer_label:
		return
	
	timer_label.text = format_time(time_remaining)

func format_time(seconds: float) -> String:
	"""Format time as MM:SS.mm"""
	var mins = int(seconds / 60)
	var secs = int(seconds) % 60
	var millis = int((seconds - int(seconds)) * 100)
	
	return "%02d:%02d.%02d" % [mins, secs, millis]

func get_time_remaining() -> float:
	"""Get remaining time in seconds"""
	return time_remaining

func get_elapsed_time() -> float:
	"""Get elapsed time since start"""
	return time_limit - time_remaining

func is_time_expired() -> bool:
	"""Check if time has run out"""
	return time_remaining <= 0

# ═══════════════════════════════════════════════
# VISIBILITY
# ═══════════════════════════════════════════════

func show_timer():
	"""Show the timer UI"""
	visible = true
	print("SpeedTimer: Shown")

func hide_timer():
	"""Hide the timer UI"""
	visible = false
	print("SpeedTimer: Hidden")

func cleanup():
	"""Clean up timer"""
	print("SpeedTimer: Cleaning up")
	queue_free()
