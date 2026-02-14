extends CanvasLayer
class_name SpeedTimer

## Timer UI for speed climbing discipline

var time_limit: float = 30.0  # Default 30 seconds
var time_remaining: float = 30.0
var is_running: bool = false
var timer_started: bool = false

# UI elements
var timer_label: Label
var background_panel: PanelContainer
var time_bar: ProgressBar
var title_label: Label

# Colors
const COLOR_NORMAL := Color(0.2, 0.9, 0.3)
const COLOR_WARNING := Color(0.95, 0.75, 0.2)
const COLOR_CRITICAL := Color(0.95, 0.2, 0.2)

# Signals
signal time_expired
signal timer_started_signal
signal time_warning(seconds_remaining: float)

# ═══════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════

func _ready():
	layer = 100  # Ensure timer is above everything
	print("SpeedTimer: Setting up UI")
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
			print("⏰ SpeedTimer: TIME EXPIRED!")
		
		# Emit warnings at specific times
		var prev_time = time_remaining + delta
		
		if prev_time > 10.0 and time_remaining <= 10.0:
			time_warning.emit(10.0)
			print("⚠️ SpeedTimer: 10 seconds warning")
		elif prev_time > 5.0 and time_remaining <= 5.0:
			time_warning.emit(5.0)
			print("⚠️ SpeedTimer: 5 seconds warning!")
		
		update_display()

# ═══════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════

func setup_ui():
	"""Create timer UI elements at top center of screen"""
	
	# Get viewport size for positioning
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Background panel (centered at top)
	background_panel = PanelContainer.new()
	background_panel.position = Vector2((viewport_size.x - 250) / 2, 20)
	background_panel.custom_minimum_size = Vector2(250, 100)
	background_panel.modulate = Color(1, 1, 1, 0.95)
	add_child(background_panel)
	
	# Add outline
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	background_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	background_panel.add_child(vbox)
	
	# Add some padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	vbox.add_child(margin)
	
	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 5)
	margin.add_child(inner_vbox)
	
	# Title label
	title_label = Label.new()
	title_label.text = "⏱️ TIME REMAINING"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	title_label.add_theme_constant_override("outline_size", 2)
	inner_vbox.add_child(title_label)
	
	# Timer label (LARGE and prominent)
	timer_label = Label.new()
	timer_label.text = format_time(time_limit)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 42)
	timer_label.add_theme_color_override("font_color", COLOR_NORMAL)
	timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	timer_label.add_theme_constant_override("outline_size", 4)
	inner_vbox.add_child(timer_label)
	
	# Progress bar
	time_bar = ProgressBar.new()
	time_bar.custom_minimum_size = Vector2(220, 15)
	time_bar.max_value = time_limit
	time_bar.value = time_limit
	time_bar.show_percentage = false
	
	# Style the progress bar
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = COLOR_NORMAL
	bar_style.corner_radius_top_left = 5
	bar_style.corner_radius_top_right = 5
	bar_style.corner_radius_bottom_left = 5
	bar_style.corner_radius_bottom_right = 5
	time_bar.add_theme_stylebox_override("fill", bar_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.25)
	bg_style.corner_radius_top_left = 5
	bg_style.corner_radius_top_right = 5
	bg_style.corner_radius_bottom_left = 5
	bg_style.corner_radius_bottom_right = 5
	time_bar.add_theme_stylebox_override("background", bg_style)
	
	inner_vbox.add_child(time_bar)
	
	print("SpeedTimer: UI setup complete")
	update_display()

func set_time_limit(seconds: float):
	"""Set the time limit for speed climbing"""
	time_limit = seconds
	time_remaining = seconds
	
	if time_bar:
		time_bar.max_value = time_limit
		time_bar.value = time_remaining
	
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
		print("🏃 SpeedTimer: STARTED - ", time_limit, " seconds")
		
		# Flash effect on start
		if title_label:
			title_label.text = "⏱️ CLIMB STARTED!"
			await get_tree().create_timer(1.0).timeout
			if is_instance_valid(title_label):
				title_label.text = "⏱️ TIME REMAINING"

func pause_timer():
	"""Pause the countdown"""
	is_running = false
	print("⏸️ SpeedTimer: PAUSED at ", format_time(time_remaining))

func resume_timer():
	"""Resume the countdown"""
	if timer_started:
		is_running = true
		print("▶️ SpeedTimer: RESUMED")

func stop_timer():
	"""Stop and reset the timer"""
	is_running = false
	timer_started = false
	time_remaining = time_limit
	print("⏹️ SpeedTimer: STOPPED and RESET")
	update_display()

func add_time(seconds: float):
	"""Add bonus time (e.g., for hitting checkpoints)"""
	time_remaining += seconds
	time_remaining = min(time_remaining, time_limit * 1.5)  # Cap at 150% of original
	print("➕ SpeedTimer: Added ", seconds, " seconds")
	
	# Show bonus message
	if title_label:
		var old_text = title_label.text
		title_label.text = "+%.1f SECONDS!" % seconds
		await get_tree().create_timer(1.5).timeout
		if is_instance_valid(title_label):
			title_label.text = old_text
	
	update_display()

# ═══════════════════════════════════════════════
# DISPLAY
# ═══════════════════════════════════════════════

func update_display():
	"""Update timer display"""
	if not timer_label:
		return
	
	timer_label.text = format_time(time_remaining)
	
	# Update color based on remaining time
	var time_ratio = time_remaining / time_limit
	
	var current_color: Color
	if time_ratio > 0.33:
		current_color = COLOR_NORMAL
	elif time_ratio > 0.16:
		current_color = COLOR_WARNING
	else:
		current_color = COLOR_CRITICAL
		
		# Pulse effect when critical
		if is_running:
			var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.15
			timer_label.scale = Vector2(pulse, pulse)
		else:
			timer_label.scale = Vector2.ONE
	
	# Apply color to label
	timer_label.add_theme_color_override("font_color", current_color)
	
	# Update progress bar
	if time_bar:
		time_bar.value = time_remaining
		
		# Update progress bar color
		var bar_style = StyleBoxFlat.new()
		bar_style.bg_color = current_color
		bar_style.corner_radius_top_left = 5
		bar_style.corner_radius_top_right = 5
		bar_style.corner_radius_bottom_left = 5
		bar_style.corner_radius_bottom_right = 5
		time_bar.add_theme_stylebox_override("fill", bar_style)

func format_time(seconds: float) -> String:
	"""Format time as MM:SS.mm"""
	var mins = int(seconds / 60)
	var secs = int(seconds) % 60
	var millis = int((seconds - int(seconds)) * 100)
	
	return "%02d:%02d.%02d" % [mins, secs, millis]

func get_time_remaining() -> float:
	"""Get remaining time in seconds"""
	return time_remaining

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
