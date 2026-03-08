extends Node2D

# ═══════════════════════════════════════════════════════════════════════════
#  LEVEL EDITOR  —  redesigned UI/UX
#  Layout:
#    TOP BAR     (42px)  — name · grade · discipline · actions
#    LEFT PANEL  (72px wide) — hold type palette
#    CANVAS      — the climbing wall
#    PROPERTIES  (floating, contextual) — appears on right-click of a hold
#
#  FIXES:
#    1. Falling holds — modifiers are now instantiated + attached to hold
#       nodes at placement time AND after paste/undo.  The FallingHold
#       modifier component is looked up via HoldModifierRegistry and, if
#       the registry isn't present, a built-in fallback is used.
#    2. Rope / Belayer — belayer anchor now draws a visible rope line from
#       the anchor down to the player during test mode.  A RopeVisual node
#       is created and updated every frame.
#    3. Modified-hold outline — instead of a floating diamond glyph drawn
#       in _draw() (which is in world-space and never matched the hold),
#       a coloured outline is applied directly to the hold's Sprite2D child
#       using a per-hold CanvasItem material with a simple outline shader.
#       Falls back to a modulate tint if no Sprite2D is found.
# ═══════════════════════════════════════════════════════════════════════════

var camera: Camera2D
var holds_container: Node2D
var preview_container: Node2D
var crashpads_container: Node2D
var wall: Node2D

var ui_layer: CanvasLayer

# Top bar widgets
var climb_name_input: LineEdit
var grade_dropdown: OptionButton
var discipline_dropdown: OptionButton
var info_label: Label

# Left palette
var palette_panel: PanelContainer
var palette_buttons: Dictionary = {}   # type_key → Button

# Contextual properties panel
var props_panel: PanelContainer = null
var props_hold: Node2D = null

# Discipline extras
var speed_time_input: SpinBox
var belayer_placement_button: Button
var discipline_extras_panel: Control
var placing_belayer: bool = false
var belayer_marker: Node2D = null

var crashpad_button: Button

# Weather
var weather_dropdown: OptionButton
var weather_intensity_slider: HSlider
var weather_intensity_label: Label
var drawer_panel: ColorRect
var drawer_container: MarginContainer
var fold_button: Button
var ui_panel_collapsed: bool = true

# State
var selected_hold_type: String = ""
var preview_hold: Node2D = null
var dragging_hold: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO
var drag_start_position: Vector2 = Vector2.ZERO

var placing_crashpad: bool = false
var preview_crashpad: Node2D = null
var dragging_crashpad: Node2D = null
var crashpad_drag_start_position: Vector2 = Vector2.ZERO

var is_testing: bool = false
var preview_player_ref: Node2D = null
var _speed_timer_node: Node = null
var _speed_fail_pending: bool = false

# FIX 2: rope visual node shown during test mode
var _rope_visual: Line2D = null

var custom_spawn_hold: Node2D = null
var climb_name: String = ""
var climb_grade: String = "VB"
var current_discipline: String = "bouldering"
var speed_time_limit: float = 60.0
var belayer_position: Vector2 = Vector2.ZERO
var current_weather: int = 0
var current_weather_intensity: float = 1.0

var grid_enabled: bool = true
var grid_size: float = 32.0
var undo_stack: Array = []

var _hold_modifiers: Dictionary = {}

# ── Constants ──────────────────────────────────────────────────────────────
const WEATHER_NAMES := ["None", "Rain", "Night", "Snow", "Lightning", "Fog", "Hail"]
const V_GRADES   = ["VB","V0","V1","V2","V3","V4","V5","V6","V7","V8","V9","V10","V11","V12"]
const YDS_GRADES = ["5.5","5.6","5.7","5.8","5.9","5.10a","5.10b","5.10c","5.10d",
					"5.11a","5.11b","5.11c","5.11d","5.12a","5.12b","5.12c","5.12d","5.13a","5.13b"]
var HOLD_TYPES  = ["START","TOP","JUG","CRIMP","SLOPER","POCKET","FOOT","WINDOW","LEDGE"]
var HOLD_SCENES = {
	"START":  "res://scenes/holds/start.tscn",
	"TOP":    "res://scenes/holds/top_out.tscn",
	"JUG":    "res://scenes/holds/jug.tscn",
	"CRIMP":  "res://scenes/holds/crimp.tscn",
	"SLOPER": "res://scenes/holds/sloper.tscn",
	"POCKET": "res://scenes/holds/pocket.tscn",
	"FOOT":   "res://scenes/holds/foothold.tscn",
	"WINDOW": "res://scenes/holds/window.tscn",
	"LEDGE":  "res://scenes/holds/ledge.tscn",
}
const CRASHPAD_SCENE = "res://scenes/props/crashpad.tscn"
const MAX_START_HOLDS := 2
const MAX_TOP_HOLDS   := 1
const MIN_HOLD_DISTANCE := 40.0
const MAX_REACH_DISTANCE := 250.0
const ZOOM_SPEED := 0.15
const TRACKPAD_ZOOM_SPEED := 0.2
const PAN_SPEED := 1000.0
const MIN_ZOOM := 0.2
const MAX_ZOOM := 3.0
const CANVAS_MIN_X = -1500.0
const CANVAS_MAX_X =  2500.0
const CANVAS_MIN_Y = -3000.0
const CANVAS_MAX_Y =  2000.0
const WALL_PADDING_SIDES  = 100.0
const WALL_PADDING_TOP    = 100.0
const WALL_PADDING_BOTTOM = 150.0

# UI geometry
const TOP_BAR_H   := 52.0
const LEFT_PAL_W  := 80.0
const DRAWER_H    := 144.0

# Colours — chalk-board palette
const C_BG        := Color(0.08, 0.08, 0.09)
const C_SURFACE   := Color(0.12, 0.12, 0.14)
const C_BORDER    := Color(0.22, 0.22, 0.26)
const C_TEXT      := Color(0.88, 0.88, 0.90)
const C_MUTED     := Color(0.45, 0.45, 0.50)
const C_ACCENT    := Color(0.29, 0.62, 1.00)     # electric blue
const C_WARN      := Color(1.00, 0.42, 0.21)     # orange
const C_SUCCESS   := Color(0.27, 0.85, 0.50)     # green
const C_MODIFIER  := Color(0.60, 0.35, 1.00)     # purple

# FIX 3: outline shader source — draws a 1-pixel coloured border around
# the opaque region of the hold sprite by sampling 8 neighbours.
const OUTLINE_SHADER_SRC := """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.6, 0.35, 1.0, 1.0);
uniform float outline_width : hint_range(0.5, 8.0) = 2.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (col.a > 0.1) {
		COLOR = col;
		return;
	}
	vec2 px = outline_width / vec2(textureSize(TEXTURE, 0));
	float nb =
		texture(TEXTURE, UV + vec2( px.x,  0.0  )).a +
		texture(TEXTURE, UV + vec2(-px.x,  0.0  )).a +
		texture(TEXTURE, UV + vec2( 0.0,   px.y )).a +
		texture(TEXTURE, UV + vec2( 0.0,  -px.y )).a +
		texture(TEXTURE, UV + vec2( px.x,  px.y )).a +
		texture(TEXTURE, UV + vec2(-px.x,  px.y )).a +
		texture(TEXTURE, UV + vec2( px.x, -px.y )).a +
		texture(TEXTURE, UV + vec2(-px.x, -px.y )).a;
	if (nb > 0.0) {
		COLOR = outline_color;
	} else {
		COLOR = col;
	}
}
"""

# Hold type accent colours for palette buttons
var HOLD_COLORS := {
	"START":  Color(0.27, 0.85, 0.50),
	"TOP":    Color(0.29, 0.62, 1.00),
	"JUG":    Color(0.88, 0.88, 0.90),
	"CRIMP":  Color(1.00, 0.42, 0.21),
	"SLOPER": Color(1.00, 0.78, 0.20),
	"POCKET": Color(0.80, 0.40, 1.00),
	"FOOT":   Color(0.50, 0.80, 0.60),
	"WINDOW": Color(0.40, 0.85, 0.95),
	"LEDGE":  Color(0.90, 0.70, 0.50),
}

var loaded_scenes: Dictionary = {}
var crashpad_scene: PackedScene = null

@export_group("Audio")
@export var enable_editor_sounds: bool = true
@export var master_volume_db: float = -6.0

const CLICK_SOUND = preload("res://assets/audio/sfx/button-clicked.wav")
var _audio_player: AudioStreamPlayer

# FIX 3: cached outline shader so we compile it once
var _outline_shader: Shader = null


# ═══════════════════════════════════════════════════════════════════════════
#  READY
# ═══════════════════════════════════════════════════════════════════════════

func _ready():
	_setup_audio()
	_build_outline_shader()

	wall = get_node_or_null("Wall")
	if wall:
		if wall.has_method("set_editor_mode"): wall.set_editor_mode(true)
		if wall.has_method("_init_weather"):   wall._init_weather()

	if has_node("Camera2D"):
		camera = get_node("Camera2D")
	else:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = Vector2(0.5, 0.5)
		camera.position = Vector2(500, 0)
		add_child(camera)
	camera.make_current()
	if "position_smoothing_enabled" in camera: camera.position_smoothing_enabled = false
	if "drag_horizontal_enabled"    in camera:
		camera.drag_horizontal_enabled = false
		camera.drag_vertical_enabled   = false

	holds_container     = _get_or_create_node2d("Holds")
	crashpads_container = _get_or_create_node2d("Crashpads")
	preview_container   = _get_or_create_node2d("PreviewContainer")
	preview_container.z_index = 100

	for t in HOLD_SCENES:
		if ResourceLoader.exists(HOLD_SCENES[t]):
			loaded_scenes[t] = load(HOLD_SCENES[t])
	if ResourceLoader.exists(CRASHPAD_SCENE):
		crashpad_scene = load(CRASHPAD_SCENE)

	_build_ui()
	update_wall_bounds()

func _get_or_create_node2d(n: String) -> Node2D:
	if has_node(n): return get_node(n)
	var nd = Node2D.new(); nd.name = n; add_child(nd); return nd


# ═══════════════════════════════════════════════════════════════════════════
#  FIX 3 — OUTLINE SHADER
# ═══════════════════════════════════════════════════════════════════════════

func _build_outline_shader():
	_outline_shader = Shader.new()
	_outline_shader.code = OUTLINE_SHADER_SRC

## Apply or remove a purple outline on the hold's Sprite2D.
## Falls back to modulate tint if the hold has no Sprite2D child.
func _apply_hold_outline(hold: Node2D, active: bool):
	# Walk children looking for a Sprite2D or AnimatedSprite2D
	var sprite: Node2D = null
	for child in hold.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			sprite = child
			break
	# Also check the hold itself
	if sprite == null and (hold is Sprite2D or hold is AnimatedSprite2D):
		sprite = hold

	if sprite != null:
		if active:
			var mat = ShaderMaterial.new()
			mat.shader = _outline_shader
			mat.set_shader_parameter("outline_color", C_MODIFIER)
			mat.set_shader_parameter("outline_width", 2.5)
			sprite.material = mat
		else:
			sprite.material = null
		# Keep modulate neutral — the outline carries the visual signal
		hold.modulate = Color(1, 1, 1)
	else:
		# Fallback: tint the whole hold
		hold.modulate = C_MODIFIER if active else Color(1, 1, 1)

func _refresh_hold_tint(hold: Node2D):
	if hold == custom_spawn_hold:
		hold.modulate = Color(0.4, 1.0, 0.5)
		# Remove outline if it was set
		for child in hold.get_children():
			if child is Sprite2D or child is AnimatedSprite2D:
				child.material = null
		return
	var has_m = _hold_modifiers.has(hold) and not (_hold_modifiers[hold] as Array).is_empty()
	_apply_hold_outline(hold, has_m)


# ═══════════════════════════════════════════════════════════════════════════
#  AUDIO
# ═══════════════════════════════════════════════════════════════════════════

func _setup_audio():
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream    = CLICK_SOUND
	_audio_player.volume_db = master_volume_db
	add_child(_audio_player)

func _sfx(pitch: float = 1.0):
	if not enable_editor_sounds: return
	_audio_player.pitch_scale = pitch + randf_range(-0.04, 0.04)
	_audio_player.play()


# ═══════════════════════════════════════════════════════════════════════════
#  UI BUILD
# ═══════════════════════════════════════════════════════════════════════════

func _build_ui():
	ui_layer       = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	_build_top_bar()
	_build_drawer()
	_build_info_bar()


# ── TOP BAR ────────────────────────────────────────────────────────────────

func _build_top_bar():
	var bg = ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.size.y = TOP_BAR_H
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(bg)

	var line = ColorRect.new()
	line.color = C_BORDER
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.position.y = TOP_BAR_H - 1
	line.size.y = 1
	ui_layer.add_child(line)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.size.y = TOP_BAR_H
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 16 if "left" in s or "right" in s else 8)
	ui_layer.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(hbox)

	var logo = _label("EDITOR", 10, C_ACCENT)
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(logo)

	_bar_sep(hbox)

	climb_name_input = LineEdit.new()
	climb_name_input.placeholder_text = "Route name…"
	climb_name_input.custom_minimum_size = Vector2(160, 32)
	_style_line_edit(climb_name_input)
	climb_name_input.text_changed.connect(func(t): climb_name = t)
	hbox.add_child(climb_name_input)

	_bar_sep(hbox)

	discipline_dropdown = _make_option_button(110)
	discipline_dropdown.add_item("Boulder")
	discipline_dropdown.add_item("Roped")
	discipline_dropdown.add_item("Speed")
	discipline_dropdown.item_selected.connect(_on_discipline_changed)
	hbox.add_child(discipline_dropdown)

	grade_dropdown = _make_option_button(80)
	_populate_grade_dropdown()
	grade_dropdown.item_selected.connect(_on_grade_changed)
	hbox.add_child(grade_dropdown)

	_bar_sep(hbox)

	var hold_type_dropdown = OptionButton.new()
	hold_type_dropdown.custom_minimum_size = Vector2(110, 32)
	_style_option_button(hold_type_dropdown)
	hold_type_dropdown.add_item("-- Hold Type --")
	for ht in ["START", "TOP", "JUG", "CRIMP", "SLOPER", "POCKET", "FOOT", "WINDOW", "LEDGE"]:
		hold_type_dropdown.add_item(ht.capitalize())
		hold_type_dropdown.set_item_metadata(hold_type_dropdown.get_item_count() - 1, ht)
	hold_type_dropdown.item_selected.connect(func(idx):
		if idx == 0:
			selected_hold_type = ""
			placing_crashpad = false
			clear_preview()
			return
		var key: String = hold_type_dropdown.get_item_metadata(idx)
		_on_palette_type_selected(key)
	)
	hbox.add_child(hold_type_dropdown)

	_bar_sep(hbox)

	crashpad_button = _make_action_button("Crashpad", C_MUTED, func(): _on_place_crashpad_pressed())
	hbox.add_child(crashpad_button)

	discipline_extras_panel = HBoxContainer.new()
	discipline_extras_panel.add_theme_constant_override("separation", 4)
	discipline_extras_panel.visible = false
	hbox.add_child(discipline_extras_panel)

	var speed_lbl = _label("⏱", 12, C_MUTED)
	speed_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discipline_extras_panel.add_child(speed_lbl)

	speed_time_input = SpinBox.new()
	speed_time_input.min_value = 10; speed_time_input.max_value = 300
	speed_time_input.step = 5; speed_time_input.value = 60; speed_time_input.suffix = "s"
	speed_time_input.custom_minimum_size = Vector2(84, 30)
	speed_time_input.value_changed.connect(func(v): speed_time_limit = v)
	discipline_extras_panel.add_child(speed_time_input)

	belayer_placement_button = _make_action_button("Belayer", C_MUTED, func(): _on_place_belayer_pressed())
	discipline_extras_panel.add_child(belayer_placement_button)

	_bar_sep(hbox)

	hbox.add_child(_make_action_button("Copy JSON", C_MUTED,   func(): _on_copy_json()))
	hbox.add_child(_make_action_button("Paste JSON", C_MUTED,  func(): _on_paste_json()))

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	hbox.add_child(_make_action_button("Test", C_SUCCESS, func(): _on_preview()))

	_bar_sep(hbox)

	fold_button = _make_action_button("More ▼", C_MUTED, func(): _toggle_drawer())
	hbox.add_child(fold_button)


# ── DRAWER ─────────────────────────────────────────────────────────────────

func _build_drawer():
	drawer_panel       = ColorRect.new()
	drawer_panel.color = Color(C_BG.r, C_BG.g, C_BG.b, 0.97)
	drawer_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	drawer_panel.position.y   = TOP_BAR_H
	drawer_panel.size.y       = DRAWER_H
	drawer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer_panel.visible      = false
	ui_layer.add_child(drawer_panel)

	var border = ColorRect.new()
	border.color = C_BORDER
	border.set_anchors_preset(Control.PRESET_TOP_WIDE)
	border.position.y = TOP_BAR_H + DRAWER_H - 1
	border.size.y = 1
	border.visible = false
	ui_layer.add_child(border)
	drawer_panel.set_meta("border_rect", border)

	drawer_container = MarginContainer.new()
	drawer_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	drawer_container.position.y = TOP_BAR_H
	drawer_container.size.y     = DRAWER_H
	drawer_container.visible    = false
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		drawer_container.add_theme_constant_override(s, 24 if "left" in s or "right" in s else 14)
	ui_layer.add_child(drawer_container)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	drawer_container.add_child(hbox)

	var env_col = _drawer_col(hbox, "ENVIRONMENT")
	var env_row = _drawer_row(env_col, "Surface")
	var environment_dropdown = OptionButton.new()
	environment_dropdown.custom_minimum_size = Vector2(120, 26)
	_style_option_button(environment_dropdown)
	_populate_environment_dropdown(environment_dropdown)
	environment_dropdown.item_selected.connect(func(i): on_environment_changed(i, environment_dropdown))
	env_row.add_child(environment_dropdown)

	var wx_row = _drawer_row(env_col, "Weather")
	weather_dropdown = OptionButton.new()
	weather_dropdown.custom_minimum_size = Vector2(120, 26)
	_style_option_button(weather_dropdown)
	for n in WEATHER_NAMES: weather_dropdown.add_item(n)
	weather_dropdown.item_selected.connect(_on_weather_changed)
	wx_row.add_child(weather_dropdown)

	var int_row = _drawer_row(env_col, "Intensity")
	weather_intensity_slider = HSlider.new()
	weather_intensity_slider.min_value = 0.1; weather_intensity_slider.max_value = 1.0
	weather_intensity_slider.step = 0.05; weather_intensity_slider.value = 1.0
	weather_intensity_slider.custom_minimum_size = Vector2(90, 20)
	weather_intensity_slider.value_changed.connect(_on_weather_intensity_changed)
	int_row.add_child(weather_intensity_slider)
	weather_intensity_label = _label("100%", 10, C_MUTED)
	int_row.add_child(weather_intensity_label)
	int_row.visible = false
	weather_intensity_slider.set_meta("int_row", int_row)

	_drawer_vsep(hbox)

	var ed_col = _drawer_col(hbox, "EDITOR TOOLS")

	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	ed_col.add_child(row1)

	var grid_btn = _make_flat_button("Grid: ON", Vector2(80, 26))
	grid_btn.pressed.connect(func(): _toggle_grid(grid_btn))
	row1.add_child(grid_btn)

	var wall_btn = _make_flat_button("Edit Wall", Vector2(80, 26))
	wall_btn.pressed.connect(_on_toggle_wall_edit)
	row1.add_child(wall_btn)

	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	ed_col.add_child(row2)

	var clear_btn = _make_flat_button("Clear All", Vector2(80, 26))
	clear_btn.add_theme_color_override("font_color", C_WARN)
	clear_btn.pressed.connect(_on_clear)
	row2.add_child(clear_btn)

	var back_btn = _make_flat_button("← Back", Vector2(80, 26))
	back_btn.add_theme_color_override("font_color", C_WARN)
	back_btn.pressed.connect(_on_back_pressed)
	row2.add_child(back_btn)

	_drawer_vsep(hbox)

	var sc_col = _drawer_col(hbox, "SHORTCUTS")
	for pair in [
		["Click",         "Place hold"],
		["Right-click",   "Delete hold"],
		["Ctrl + Right",  "Hold properties"],
		["Shift + Right", "Set spawn"],
		["Ctrl + Z",      "Undo"],
		["W/A/S/D",       "Pan camera"],
		["Scroll",        "Zoom"],
	]:
		var r = HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		sc_col.add_child(r)
		var k = _label(pair[0], 9, C_ACCENT)
		k.custom_minimum_size = Vector2(94, 0)
		r.add_child(k)
		r.add_child(_label(pair[1], 9, C_MUTED))


func _on_palette_type_selected(type_key: String):
	if selected_hold_type == type_key:
		selected_hold_type = ""
		_deselect_all_palette()
		clear_preview()
		return
	_deselect_all_palette()
	selected_hold_type = type_key
	placing_crashpad   = false
	placing_belayer    = false
	clear_preview()
	_close_props_panel()
	_highlight_palette_button(type_key, true)
	_sfx(1.2)

func _deselect_all_palette():
	for key in palette_buttons:
		_highlight_palette_button(key, false)

func _highlight_palette_button(key: String, active: bool):
	var btn = palette_buttons.get(key)
	if btn == null: return
	var col: Color = HOLD_COLORS.get(key, C_MUTED) if key != "CRASHPAD" else C_MUTED
	var n = StyleBoxFlat.new()
	n.bg_color = Color(col.r, col.g, col.b, 0.28 if active else 0.06)
	if active:
		n.border_color = col
		n.set_border_width_all(0)
		n.border_width_left = 3
	n.set_corner_radius_all(0)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_color_override("font_color", col if active else Color(col.r,col.g,col.b,0.55))


# ── INFO BAR ──────────────────────────────────────────────────────────────

func _build_info_bar():
	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info_label.position   = Vector2(8, -24)
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", C_MUTED)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(info_label)


# ═══════════════════════════════════════════════════════════════════════════
#  PROPERTIES PANEL  (contextual, Ctrl+Right-click on hold)
# ═══════════════════════════════════════════════════════════════════════════

func _open_props_panel(hold: Node2D):
	_close_props_panel()
	props_hold  = hold
	props_panel = PanelContainer.new()
	props_panel.name = "PropsPanel"
	props_panel.custom_minimum_size = Vector2(240, 0)

	var screen_pos = _world_to_screen(hold.global_position) + Vector2(16, -32)
	screen_pos.x = clamp(screen_pos.x, 8.0, get_viewport_rect().size.x - 250)
	screen_pos.y = clamp(screen_pos.y, TOP_BAR_H + 4,  get_viewport_rect().size.y - 20)
	props_panel.position = screen_pos

	var sty = StyleBoxFlat.new()
	sty.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	sty.set_border_width_all(1)
	sty.border_color = C_BORDER
	sty.set_corner_radius_all(4)
	props_panel.add_theme_stylebox_override("panel", sty)

	var margin = MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 18 if "left" in s or "right" in s else 14)
	props_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var hdr = HBoxContainer.new()
	vbox.add_child(hdr)
	var ttl = _label("HOLD PROPERTIES", 11, C_ACCENT)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(ttl)
	var close_btn = _make_flat_button("X", Vector2(22, 22))
	close_btn.pressed.connect(_close_props_panel)
	hdr.add_child(close_btn)

	var sub = _label(get_hold_type(hold) + "  hold", 9, C_MUTED)
	vbox.add_child(sub)

	vbox.add_child(_hsep())

	var mod_list = VBoxContainer.new()
	mod_list.name = "ModList"
	mod_list.add_theme_constant_override("separation", 4)
	vbox.add_child(mod_list)
	_rebuild_mod_list(mod_list, hold)

	vbox.add_child(_hsep())

	var add_hbox = HBoxContainer.new()
	add_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(add_hbox)

	add_hbox.add_child(_label("Add:", 10, C_MUTED))

	var add_dd = OptionButton.new()
	add_dd.custom_minimum_size = Vector2(118, 26)
	_style_option_button(add_dd)
	var registry = get_node_or_null("/root/HoldModifierRegistry")
	if registry:
		for key in registry.get_all_modifier_types():
			add_dd.add_item(registry.get_display_name(key))
			add_dd.set_item_metadata(add_dd.get_item_count() - 1, key)
	else:
		add_dd.add_item("Falling"); add_dd.set_item_metadata(0, "falling")
	add_hbox.add_child(add_dd)

	var add_btn = _make_flat_button("＋", Vector2(28, 26))
	add_btn.add_theme_color_override("font_color", C_SUCCESS)
	add_btn.pressed.connect(func():
		var idx = add_dd.selected
		if idx < 0: return
		var key: String = add_dd.get_item_metadata(idx)
		_add_modifier(hold, key, mod_list)
	)
	add_hbox.add_child(add_btn)

	ui_layer.add_child(props_panel)
	_sfx(1.3)


func _rebuild_mod_list(list: VBoxContainer, hold: Node2D):
	for c in list.get_children(): c.queue_free()

	var mods: Array = _hold_modifiers.get(hold, [])
	if mods.is_empty():
		list.add_child(_label("  No modifiers", 10, C_MUTED))
		return

	var registry = get_node_or_null("/root/HoldModifierRegistry")

	for i in range(mods.size()):
		var md: Dictionary = mods[i]
		var mod_type: String = md.get("type", "?")

		var card = PanelContainer.new()
		var card_sty = StyleBoxFlat.new()
		card_sty.bg_color = Color(C_MODIFIER.r, C_MODIFIER.g, C_MODIFIER.b, 0.08)
		card_sty.set_border_width_all(1)
		card_sty.border_color = Color(C_MODIFIER.r, C_MODIFIER.g, C_MODIFIER.b, 0.30)
		card_sty.set_corner_radius_all(3)
		card.add_theme_stylebox_override("panel", card_sty)
		list.add_child(card)

		var card_margin = MarginContainer.new()
		for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
			card_margin.add_theme_constant_override(s, 10 if "left" in s or "right" in s else 8)
		card.add_child(card_margin)

		var card_vbox = VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)
		card_margin.add_child(card_vbox)

		var row = HBoxContainer.new()
		card_vbox.add_child(row)
		var display = registry.get_display_name(mod_type) if registry else mod_type.capitalize()
		var lbl = _label(display, 10, C_MODIFIER)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var rm = _make_flat_button("X", Vector2(20, 20))
		rm.add_theme_color_override("font_color", C_WARN)
		var ci = i
		rm.pressed.connect(func():
			save_undo_state()
			var cur: Array = _hold_modifiers.get(hold, [])
			if ci < cur.size(): cur.remove_at(ci)
			if cur.is_empty(): _hold_modifiers.erase(hold)
			else: _hold_modifiers[hold] = cur
			_rebuild_mod_list(list, hold)
			_refresh_hold_tint(hold)
			# FIX 1: detach runtime modifier component when removed
			_detach_modifier_component(hold, mod_type)
			_sfx(0.7)
		)
		row.add_child(rm)

		if mod_type == "falling":
			var fields_grid = GridContainer.new()
			fields_grid.columns = 2
			fields_grid.add_theme_constant_override("h_separation", 8)
			fields_grid.add_theme_constant_override("v_separation", 4)
			card_vbox.add_child(fields_grid)

			fields_grid.add_child(_label("Fall delay", 9, C_MUTED))
			var delay_spin = SpinBox.new()
			delay_spin.min_value = 0.5; delay_spin.max_value = 10.0
			delay_spin.step = 0.1; delay_spin.suffix = "s"
			delay_spin.value = float(md.get("fall_delay", 2.2))
			delay_spin.custom_minimum_size = Vector2(90, 22)
			var ci2 = i
			delay_spin.value_changed.connect(func(v):
				var cur: Array = _hold_modifiers.get(hold, [])
				if ci2 < cur.size():
					(cur[ci2] as Dictionary)["fall_delay"] = v
				_hold_modifiers[hold] = cur
				# FIX 1: live-update runtime component parameter
				_sync_modifier_component(hold, cur[ci2])
			)
			fields_grid.add_child(delay_spin)

			fields_grid.add_child(_label("Gravity", 9, C_MUTED))
			var grav_spin = SpinBox.new()
			grav_spin.min_value = 200.0; grav_spin.max_value = 4000.0
			grav_spin.step = 100.0; grav_spin.suffix = "px/s²"
			grav_spin.value = float(md.get("fall_gravity", 1800.0))
			grav_spin.custom_minimum_size = Vector2(90, 22)
			var ci3 = i
			grav_spin.value_changed.connect(func(v):
				var cur: Array = _hold_modifiers.get(hold, [])
				if ci3 < cur.size():
					(cur[ci3] as Dictionary)["fall_gravity"] = v
				_hold_modifiers[hold] = cur
				_sync_modifier_component(hold, cur[ci3])
			)
			fields_grid.add_child(grav_spin)


func _add_modifier(hold: Node2D, type_key: String, list: VBoxContainer):
	var existing: Array = _hold_modifiers.get(hold, [])
	for m in existing:
		if (m as Dictionary).get("type","") == type_key:
			_notify("Already has '%s' modifier" % type_key, true)
			_sfx(0.5)
			return
	save_undo_state()
	var registry = get_node_or_null("/root/HoldModifierRegistry")
	var default_data: Dictionary = {"type": type_key}
	if registry:
		var tmp = registry.create_modifier(type_key)
		if tmp and tmp.has_method("serialize"): default_data = tmp.serialize(); tmp.queue_free()
	# Ensure defaults for falling if registry didn't supply them
	if type_key == "falling":
		if not default_data.has("fall_delay"):   default_data["fall_delay"]   = 2.2
		if not default_data.has("fall_gravity"): default_data["fall_gravity"] = 1800.0
	if not _hold_modifiers.has(hold): _hold_modifiers[hold] = []
	(_hold_modifiers[hold] as Array).append(default_data)
	_rebuild_mod_list(list, hold)
	_refresh_hold_tint(hold)
	# FIX 1: attach runtime modifier component immediately
	_attach_modifier_component(hold, default_data)
	_sfx(1.2)
	_notify("Added '%s' modifier" % type_key)

func _close_props_panel():
	if props_panel and is_instance_valid(props_panel): props_panel.queue_free()
	props_panel = null; props_hold = null


# ═══════════════════════════════════════════════════════════════════════════
#  FIX 1 — FALLING HOLD MODIFIER  (runtime component management)
#
#  We attach a lightweight child node called "_FallingModifier" to each
#  hold that has the "falling" modifier.  This node drives the actual
#  physics: it waits for a grab signal (or auto-timer), then applies
#  gravity to the hold's position.  If the hold's scene already has its
#  own modifier system we defer to that; otherwise we use a built-in
#  fallback implemented here.
# ═══════════════════════════════════════════════════════════════════════════

const _FALLING_MOD_NODE_NAME := "_FallingModifier"

## Attach all serialised modifier components to a hold node.
func _attach_all_modifiers(hold: Node2D):
	var mods: Array = _hold_modifiers.get(hold, [])
	for md in mods:
		_attach_modifier_component(hold, md)

## Attach a single modifier component.
func _attach_modifier_component(hold: Node2D, data: Dictionary):
	var type_key: String = data.get("type", "")
	match type_key:
		"falling":
			_attach_falling_modifier(hold, data)
		_:
			# Delegate to registry if available
			var registry = get_node_or_null("/root/HoldModifierRegistry")
			if registry and registry.has_method("attach_modifier"):
				registry.attach_modifier(hold, data)

## Remove a modifier component by type.
func _detach_modifier_component(hold: Node2D, type_key: String):
	match type_key:
		"falling":
			var existing = hold.get_node_or_null(_FALLING_MOD_NODE_NAME)
			if existing: existing.queue_free()
		_:
			var registry = get_node_or_null("/root/HoldModifierRegistry")
			if registry and registry.has_method("detach_modifier"):
				registry.detach_modifier(hold, type_key)

## Update live parameters on an already-attached component.
func _sync_modifier_component(hold: Node2D, data: Dictionary):
	var type_key: String = data.get("type", "")
	if type_key == "falling":
		var comp = hold.get_node_or_null(_FALLING_MOD_NODE_NAME)
		if comp and "fall_delay"   in comp: comp.fall_delay   = float(data.get("fall_delay",   2.2))
		if comp and "fall_gravity" in comp: comp.fall_gravity = float(data.get("fall_gravity", 1800.0))

## Built-in falling hold component.
## Attach this as a child of the hold Node2D.
## It listens for the hold's "grabbed" signal (if present) or uses a
## countdown timer, then simulates a falling hold by moving position
## each physics tick.
func _attach_falling_modifier(hold: Node2D, data: Dictionary):
	# Remove stale component first
	var old = hold.get_node_or_null(_FALLING_MOD_NODE_NAME)
	if old: old.queue_free()

	# If the hold's own script already handles falling via registry, skip.
	if hold.has_method("apply_modifier") and hold.has_method("has_modifier"):
		if not hold.has_modifier("falling"):
			hold.apply_modifier(data)
		return

	# Build a tiny inline script for the component node
	var src := """
extends Node

var fall_delay   : float = 2.2
var fall_gravity : float = 1800.0

var _timer    : float = 0.0
var _falling  : bool  = false
var _vel_y    : float = 0.0
var _origin   : Vector2
var _grabbed  : bool  = false

func _ready():
	_origin = get_parent().global_position
	# Connect grab signal if the hold exposes one
	var p = get_parent()
	if p.has_signal("grabbed"):
		p.grabbed.connect(_on_grabbed)
	elif p.has_signal("hold_grabbed"):
		p.hold_grabbed.connect(_on_grabbed)
	_timer = fall_delay

func _on_grabbed():
	_grabbed = true

func reset():
	_falling = false
	_vel_y   = 0.0
	_timer   = fall_delay
	_grabbed = false
	get_parent().global_position = _origin

func _physics_process(delta: float):
	var p = get_parent()
	if not is_instance_valid(p): return
	if _falling:
		_vel_y += fall_gravity * delta
		p.global_position.y += _vel_y * delta
		# Respawn if fallen off screen
		if p.global_position.y > 3000.0:
			reset()
		return
	if _grabbed:
		_timer -= delta
		if _timer <= 0.0:
			_falling = true
"""

	var script = GDScript.new()
	script.source_code = src

	var comp = Node.new()
	comp.name = _FALLING_MOD_NODE_NAME
	comp.set_script(script)
	# We must set exported vars AFTER adding to scene tree so _ready runs
	hold.add_child(comp)
	# Now set parameters (script is running)
	if "fall_delay"   in comp: comp.fall_delay   = float(data.get("fall_delay",   2.2))
	if "fall_gravity" in comp: comp.fall_gravity = float(data.get("fall_gravity", 1800.0))


# ═══════════════════════════════════════════════════════════════════════════
#  FIX 2 — ROPE VISUAL
#
#  During test mode (roped/speed discipline) we draw a Line2D from the
#  belayer anchor down to the player's position each frame.  We also show
#  the anchor as a distinct visual marker even in non-test mode.
# ═══════════════════════════════════════════════════════════════════════════

func _create_rope_visual():
	_destroy_rope_visual()
	if belayer_position == Vector2.ZERO: return
	if current_discipline not in ["roped", "speed"]: return

	_rope_visual = Line2D.new()
	_rope_visual.name = "RopeVisual"
	_rope_visual.default_color = Color(0.85, 0.72, 0.40, 0.85)  # rope colour
	_rope_visual.width = 3.0
	_rope_visual.z_index = 50
	# Simple catenary-style look — we will update points each frame
	add_child(_rope_visual)

func _destroy_rope_visual():
	if _rope_visual and is_instance_valid(_rope_visual):
		_rope_visual.queue_free()
	_rope_visual = null

func _update_rope_visual():
	if not _rope_visual or not is_instance_valid(_rope_visual): return
	if belayer_position == Vector2.ZERO:
		_rope_visual.clear_points()
		return
	var anchor = belayer_position
	var end_pos: Vector2
	if is_instance_valid(preview_player_ref):
		end_pos = preview_player_ref.global_position
	else:
		end_pos = anchor + Vector2(0, 400)  # dangle down when no player

	# Build a simple catenary with 20 segments
	_rope_visual.clear_points()
	var seg := 20
	var sag = clamp(anchor.distance_to(end_pos) * 0.18, 20.0, 300.0)
	for i in range(seg + 1):
		var t := float(i) / float(seg)
		var pt = anchor.lerp(end_pos, t)
		# Parabolic sag
		pt.y += sag * 4.0 * t * (1.0 - t)
		_rope_visual.add_point(pt)


# ═══════════════════════════════════════════════════════════════════════════
#  PROCESS
# ═══════════════════════════════════════════════════════════════════════════

func _process(delta):
	update_camera(delta)
	_update_preview()
	_update_info_label()
	if is_testing and is_instance_valid(preview_player_ref):
		camera.position = camera.position.lerp(preview_player_ref.global_position, 8.0 * delta)
		# FIX 2: update rope every frame during test
		_update_rope_visual()
	queue_redraw()

func update_camera(delta):
	if is_testing: return
	var move = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if move.length() > 0:
		camera.position += move.normalized() * PAN_SPEED * delta / camera.zoom.x


# ═══════════════════════════════════════════════════════════════════════════
#  INPUT
# ═══════════════════════════════════════════════════════════════════════════

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed):
			if not is_testing: undo_last_action(); return
		match event.keycode:
			KEY_ESCAPE:
				if is_testing: _stop_testing(); return
				if props_panel and is_instance_valid(props_panel): _close_props_panel(); return
				selected_hold_type = ""; placing_crashpad = false; placing_belayer = false
				_deselect_all_palette(); clear_preview()
				dragging_hold = null; dragging_crashpad = null
			KEY_DELETE, KEY_BACKSPACE:
				if not is_testing:
					if dragging_hold:       _delete_hold(dragging_hold)
					elif dragging_crashpad: _delete_crashpad(dragging_crashpad)

	if is_testing: return
	if _is_mouse_over_ui(): return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if props_panel and is_instance_valid(props_panel): _close_props_panel()
				_handle_left_click()
			else:
				if dragging_hold and dragging_hold.global_position != drag_start_position:
					save_undo_state(); update_wall_bounds()
				elif dragging_crashpad and dragging_crashpad.global_position != crashpad_drag_start_position:
					save_undo_state()
				dragging_hold = null; dragging_crashpad = null

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var pos  = get_global_mouse_position()
			var hold = _get_hold_at(pos)
			if hold:
				if event.shift_pressed:    _set_custom_spawn(hold)
				elif event.ctrl_pressed:   _open_props_panel(hold)
				else:                      _delete_hold(hold)
			else:
				var cp = _get_crashpad_at(pos)
				if cp: _delete_crashpad(cp)

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * (1.0 + ZOOM_SPEED)).clamp(
				Vector2(MIN_ZOOM,MIN_ZOOM), Vector2(MAX_ZOOM,MAX_ZOOM))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom * (1.0 - ZOOM_SPEED)).clamp(
				Vector2(MIN_ZOOM,MIN_ZOOM), Vector2(MAX_ZOOM,MAX_ZOOM))

	elif event is InputEventMagnifyGesture:
		var z = (event.factor - 1.0) * TRACKPAD_ZOOM_SPEED
		camera.zoom = (camera.zoom * (1.0 + z)).clamp(
			Vector2(MIN_ZOOM,MIN_ZOOM), Vector2(MAX_ZOOM,MAX_ZOOM))

	elif event is InputEventPanGesture:
		camera.position += event.delta * 50.0 / camera.zoom.x

	elif event is InputEventMouseMotion:
		if dragging_hold:
			var p = _snap(get_global_mouse_position() + drag_offset)
			dragging_hold.global_position = p.clamp(
				Vector2(CANVAS_MIN_X, CANVAS_MIN_Y), Vector2(CANVAS_MAX_X, CANVAS_MAX_Y))
		elif dragging_crashpad:
			var p = _snap(get_global_mouse_position() + drag_offset)
			dragging_crashpad.global_position = p.clamp(
				Vector2(CANVAS_MIN_X, CANVAS_MIN_Y), Vector2(CANVAS_MAX_X, CANVAS_MAX_Y))

func _handle_left_click():
	var pos = get_global_mouse_position()
	if placing_belayer:
		save_undo_state(); _create_belayer_marker(_snap(pos))
		placing_belayer = false; _deselect_all_palette(); return

	if placing_crashpad and crashpad_scene:
		_place_crashpad(_snap(pos))
		return

	if selected_hold_type and selected_hold_type in loaded_scenes:
		_place_hold(_snap(pos))
		return

	var hold = _get_hold_at(pos)
	if hold:
		save_undo_state()
		dragging_hold = hold; drag_offset = hold.global_position - pos
		drag_start_position = hold.global_position
		return
	var cp = _get_crashpad_at(pos)
	if cp:
		save_undo_state()
		dragging_crashpad = cp; drag_offset = cp.global_position - pos
		crashpad_drag_start_position = cp.global_position

func _is_mouse_over_ui() -> bool:
	var mp = get_viewport().get_mouse_position()
	if mp.y < TOP_BAR_H:  return true
	if not ui_panel_collapsed and mp.y < TOP_BAR_H + DRAWER_H: return true
	if props_panel and is_instance_valid(props_panel):
		if Rect2(props_panel.position, props_panel.size).has_point(mp): return true
	return false


# ═══════════════════════════════════════════════════════════════════════════
#  HOLDS
# ═══════════════════════════════════════════════════════════════════════════

func _place_hold(pos: Vector2) -> bool:
	if not selected_hold_type or selected_hold_type not in loaded_scenes: return false
	pos = pos.clamp(Vector2(CANVAS_MIN_X,CANVAS_MIN_Y), Vector2(CANVAS_MAX_X,CANVAS_MAX_Y))
	if selected_hold_type == "START" and _count_type("START") >= MAX_START_HOLDS:
		_notify("Max %d START holds" % MAX_START_HOLDS, true); _sfx(0.5); return false
	if selected_hold_type == "TOP"   and _count_type("TOP")   >= MAX_TOP_HOLDS:
		_notify("Max %d TOP holds" % MAX_TOP_HOLDS, true); _sfx(0.5); return false
	if _too_close(pos, null):
		_notify("Too close to another hold", true); _sfx(0.5); return false
	if not _is_reachable(pos, null):
		_notify("Hold out of reach from route", true); _sfx(0.5); return false
	save_undo_state()
	var hold = loaded_scenes[selected_hold_type].instantiate()
	if hold.has_method("set_hold_type_from_string"): hold.set_hold_type_from_string(selected_hold_type)
	hold.global_position = pos
	holds_container.add_child(hold)
	hold.add_to_group("holds")
	hold.set_meta("editor_type", selected_hold_type)
	_sfx(1.2)
	update_wall_bounds()
	return true

func _delete_hold(hold: Node2D):
	_hold_modifiers.erase(hold)
	if props_hold == hold: _close_props_panel()
	save_undo_state()
	if hold == dragging_hold: dragging_hold = null
	if hold == custom_spawn_hold: custom_spawn_hold = null
	hold.queue_free(); _sfx(0.7)
	update_wall_bounds()

func _get_hold_at(pos: Vector2, max_dist: float = 44.0) -> Node2D:
	var closest: Node2D = null; var cd = max_dist
	for h in holds_container.get_children():
		var d = h.global_position.distance_to(pos)
		if d < cd: cd = d; closest = h
	return closest

func _place_crashpad(pos: Vector2) -> bool:
	if not crashpad_scene: _notify("Crashpad scene missing", true); return false
	pos = pos.clamp(Vector2(CANVAS_MIN_X,CANVAS_MIN_Y), Vector2(CANVAS_MAX_X,CANVAS_MAX_Y))
	save_undo_state()
	var cp = crashpad_scene.instantiate()
	cp.global_position = pos; crashpads_container.add_child(cp); cp.add_to_group("crashpads")
	_sfx(1.15); return true

func _delete_crashpad(cp: Node2D):
	save_undo_state()
	if cp == dragging_crashpad: dragging_crashpad = null
	cp.queue_free(); _sfx(0.7)

func _get_crashpad_at(pos: Vector2, max_dist: float = 60.0) -> Node2D:
	var closest: Node2D = null; var cd = max_dist
	for cp in crashpads_container.get_children():
		var d = cp.global_position.distance_to(pos)
		if d < cd: cd = d; closest = cp
	return closest

func get_hold_type(hold: Node2D) -> String:
	if hold.has_meta("editor_type"): return hold.get_meta("editor_type")
	if "hold_type" in hold:
		match hold.hold_type:
			0: return "JUG"
			1: return "START"
			2: return "TOP"
			3: return "CRIMP"
			4: return "SLOPER"
			5: return "FOOT"
			6: return "POCKET"
			7: return "WINDOW"
			8: return "LEDGE"
	return "JUG"

func _count_type(t: String) -> int:
	var n = 0
	for h in holds_container.get_children():
		if get_hold_type(h) == t: n += 1
	return n

func _too_close(pos: Vector2, ex: Node2D) -> bool:
	for h in holds_container.get_children():
		if h == ex: continue
		if h.global_position.distance_to(pos) < MIN_HOLD_DISTANCE: return true
	return false

func _is_reachable(pos: Vector2, ex: Node2D) -> bool:
	if selected_hold_type in ["START","FOOT","WINDOW","LEDGE"]: return true
	var non_start = 0
	for h in holds_container.get_children():
		if h != ex and get_hold_type(h) != "START": non_start += 1
	if non_start == 0: return true
	var nearest = INF
	for h in holds_container.get_children():
		if h == ex or get_hold_type(h) == "START": continue
		nearest = min(nearest, h.global_position.distance_to(pos))
	return nearest <= MAX_REACH_DISTANCE

func update_wall_bounds():
	if wall and wall.has_method("calculate_bounds_from_holds"):
		wall.calculate_bounds_from_holds(holds_container)
	queue_redraw()


# ═══════════════════════════════════════════════════════════════════════════
#  PREVIEW (ghost hold under cursor)
# ═══════════════════════════════════════════════════════════════════════════

func _update_preview():
	if placing_crashpad and crashpad_scene:
		if not preview_crashpad or not is_instance_valid(preview_crashpad):
			clear_preview()
			preview_crashpad = crashpad_scene.instantiate()
			preview_crashpad.modulate = Color(1,1,1,0.45)
			preview_crashpad.z_index  = 100
			preview_container.add_child(preview_crashpad)
		if _is_mouse_over_ui(): preview_crashpad.visible = false
		else:
			preview_crashpad.visible = true
			preview_crashpad.global_position = _snap(get_global_mouse_position()).clamp(
				Vector2(CANVAS_MIN_X,CANVAS_MIN_Y), Vector2(CANVAS_MAX_X,CANVAS_MAX_Y))
		return

	if not selected_hold_type or selected_hold_type not in loaded_scenes or _is_mouse_over_ui():
		clear_preview(); return

	if not preview_hold or not is_instance_valid(preview_hold):
		clear_preview()
		preview_hold = loaded_scenes[selected_hold_type].instantiate()
		preview_hold.z_index = 100
		preview_container.add_child(preview_hold)

	var sp = _snap(get_global_mouse_position()).clamp(
		Vector2(CANVAS_MIN_X,CANVAS_MIN_Y), Vector2(CANVAS_MAX_X,CANVAS_MAX_Y))
	var bad = _too_close(sp, null) or not _is_reachable(sp, null)
	preview_hold.modulate = Color(1, 0.3, 0.3, 0.5) if bad else Color(1,1,1,0.5)
	preview_hold.global_position = sp

func clear_preview():
	if preview_hold     and is_instance_valid(preview_hold):     preview_hold.queue_free()
	if preview_crashpad and is_instance_valid(preview_crashpad): preview_crashpad.queue_free()
	preview_hold = null; preview_crashpad = null


# ═══════════════════════════════════════════════════════════════════════════
#  INFO BAR
# ═══════════════════════════════════════════════════════════════════════════

func _update_info_label():
	var placing = "—"
	if placing_belayer:    placing = "Rope anchor"
	elif placing_crashpad: placing = "Crashpad"
	elif selected_hold_type: placing = selected_hold_type

	var disc_map = {"bouldering":"Boulder","roped":"Roped","speed":"Speed"}
	var parts = [
		"%s  %s" % [disc_map.get(current_discipline, current_discipline), climb_grade],
		"Holds: %d" % holds_container.get_child_count(),
		"Start: %d/%d  Top: %d/%d" % [_count_type("START"), MAX_START_HOLDS,
									   _count_type("TOP"),   MAX_TOP_HOLDS],
	]
	if current_discipline == "bouldering":
		parts.append("Pads: %d" % crashpads_container.get_child_count())
	var mod_count = 0
	for h in holds_container.get_children():
		if _hold_modifiers.has(h) and not (_hold_modifiers[h] as Array).is_empty(): mod_count += 1
	if mod_count > 0: parts.append("Modifiers: %d" % mod_count)
	if is_instance_valid(custom_spawn_hold): parts.append("Custom spawn set")
	if belayer_position != Vector2.ZERO: parts.append("Anchor set")
	parts.append("Placing: " + placing)
	info_label.text = "   ·   ".join(parts)


# ═══════════════════════════════════════════════════════════════════════════
#  CALLBACKS
# ═══════════════════════════════════════════════════════════════════════════

func _on_discipline_changed(index: int):
	match index:
		0:
			current_discipline = "bouldering"; climb_grade = "VB"
			discipline_extras_panel.visible = false
			crashpad_button.visible = true
			_clear_belayer_marker()
			_destroy_rope_visual()
		1:
			current_discipline = "roped"; climb_grade = "5.5"
			discipline_extras_panel.visible = true
			speed_time_input.visible = false
			belayer_placement_button.visible = true
			crashpad_button.visible = true
			_notify("Click Belayer to place belay point")
		2:
			current_discipline = "speed"; climb_grade = "5.5"
			discipline_extras_panel.visible = true
			speed_time_input.visible = true
			belayer_placement_button.visible = false
			crashpad_button.visible = true
			_clear_belayer_marker()
			_destroy_rope_visual()
	_populate_grade_dropdown()

func _on_grade_changed(index: int):
	var grades = V_GRADES if current_discipline == "bouldering" else YDS_GRADES
	if index >= 0 and index < grades.size(): climb_grade = grades[index]

func _populate_grade_dropdown():
	grade_dropdown.clear()
	var grades = V_GRADES if current_discipline == "bouldering" else YDS_GRADES
	for g in grades: grade_dropdown.add_item(g)
	grade_dropdown.select(0)

func _on_place_crashpad_pressed():
	_deselect_all_palette()
	placing_crashpad   = true; selected_hold_type = ""; placing_belayer = false
	clear_preview(); _close_props_panel()
	_highlight_palette_button("CRASHPAD", true)

func _on_place_belayer_pressed():
	placing_belayer = true; selected_hold_type = ""; placing_crashpad = false
	_deselect_all_palette(); clear_preview(); _close_props_panel()
	_notify("Click anywhere to place rope anchor")

func _create_belayer_marker(pos: Vector2):
	_clear_belayer_marker()
	belayer_marker = Node2D.new(); belayer_marker.name = "BelayerMarker"
	belayer_marker.z_index = 100; belayer_marker.global_position = pos
	belayer_position = pos

	# FIX 2: richer anchor visual — pulley bracket + rope lines
	var sp = Sprite2D.new()
	var img = Image.create(32, 48, false, Image.FORMAT_RGBA8); img.fill(Color.TRANSPARENT)
	for y in range(48):
		for x in range(32):
			if Vector2(x-16,y-8).length() < 6: img.set_pixel(x,y,Color.ORANGE)
			if x>=14 and x<=18 and y>=14 and y<=32: img.set_pixel(x,y,Color.ORANGE)
			if y>=18 and y<=22 and x>=8  and x<=24: img.set_pixel(x,y,Color.ORANGE)
			if y>=32 and y<=46 and ((x>=10 and x<=13) or (x>=19 and x<=22)): img.set_pixel(x,y,Color.ORANGE)
	sp.texture = ImageTexture.create_from_image(img)
	belayer_marker.add_child(sp)
	add_child(belayer_marker)
	_notify("Rope anchor placed")

func _clear_belayer_marker():
	if belayer_marker and is_instance_valid(belayer_marker): belayer_marker.queue_free()
	belayer_marker = null; belayer_position = Vector2.ZERO

func _toggle_drawer():
	ui_panel_collapsed = !ui_panel_collapsed
	drawer_panel.visible     = not ui_panel_collapsed
	drawer_container.visible = not ui_panel_collapsed
	if drawer_panel.has_meta("border_rect"):
		drawer_panel.get_meta("border_rect").visible = not ui_panel_collapsed
	fold_button.text = "Less ▲" if not ui_panel_collapsed else "More ▼"

func _toggle_grid(btn: Button):
	grid_enabled = !grid_enabled
	btn.text = "Grid: ON" if grid_enabled else "Grid: OFF"
	queue_redraw()

func _set_custom_spawn(hold: Node2D):
	if is_instance_valid(custom_spawn_hold) and custom_spawn_hold != hold:
		custom_spawn_hold.modulate = Color(1,1,1); _refresh_hold_tint(custom_spawn_hold)
	if custom_spawn_hold == hold:
		hold.modulate = Color(1,1,1); _refresh_hold_tint(hold)
		custom_spawn_hold = null; _notify("Spawn cleared"); _sfx(0.7); return
	custom_spawn_hold = hold; hold.modulate = Color(0.4,1.0,0.5)
	_notify("Spawn set on %s  (Shift+Right-click to clear)" % get_hold_type(hold)); _sfx(1.4)

func _populate_environment_dropdown(dd: OptionButton):
	dd.clear()
	var env = get_node_or_null("/root/EnvironmentConfig")
	if env:
		for t in env.get_all_environment_types():
			dd.add_item(env.get_environment_name(t))
		dd.select(env.get_current_environment())
	else:
		dd.add_item("Gym"); dd.add_item("Granite"); dd.select(0)

func on_environment_changed(index: int, dd: OptionButton):
	var env = get_node_or_null("/root/EnvironmentConfig")
	if not env: return
	var types = env.get_all_environment_types()
	if index < types.size(): env.set_environment(types[index])
	update_wall_bounds()
	for h in holds_container.get_children():
		if h.has_method("_update_sprite_for_environment"): h._update_sprite_for_environment()
	for cp in crashpads_container.get_children():
		if cp.has_method("_update_sprite_for_environment"): cp._update_sprite_for_environment()
	for h in holds_container.get_children(): _refresh_hold_tint(h)

func _on_weather_changed(index: int):
	current_weather = index
	if weather_intensity_slider.has_meta("int_row"):
		weather_intensity_slider.get_meta("int_row").visible = index > 0
	if wall and wall.has_method("set_weather"): wall.set_weather(index, current_weather_intensity)
	var is_night = index < WEATHER_NAMES.size() and WEATHER_NAMES[index] == "Night"
	for h in holds_container.get_children():
		h.modulate = Color(1.4,1.4,1.6) if is_night else Color(1,1,1)
		_refresh_hold_tint(h)
	_notify("Weather: " + (WEATHER_NAMES[index] if index < WEATHER_NAMES.size() else "?"))

func _on_weather_intensity_changed(v: float):
	current_weather_intensity = v
	weather_intensity_label.text = "%d%%" % int(v * 100)
	if wall and wall.has_method("set_weather"): wall.set_weather(current_weather, v)

func _on_toggle_wall_edit():
	if not wall: _notify("No wall found", true); return
	if not wall.has_method("enable_edit_mode"): _notify("Wall doesn't support editing", true); return
	var editing = wall.edit_mode if "edit_mode" in wall else false
	if not editing:
		save_undo_state(); selected_hold_type = ""; placing_crashpad = false
		placing_belayer = false; _deselect_all_palette(); clear_preview(); _close_props_panel()
	wall.enable_edit_mode(not editing)
	_notify("Wall edit %s" % ("ON — click line to add point, drag to move, right-click to delete" if not editing else "OFF"))
	if editing: save_undo_state()


# ═══════════════════════════════════════════════════════════════════════════
#  TEST MODE
# ═══════════════════════════════════════════════════════════════════════════

func _on_preview():
	if holds_container.get_child_count() == 0: _notify("No holds to test", true); _sfx(0.5); return
	var starts = []
	for h in holds_container.get_children():
		if get_hold_type(h) == "START": starts.append(h)
	if starts.is_empty() and not is_instance_valid(custom_spawn_hold):
		_notify("Need a START hold (or Shift+Right-click to set spawn)", true); _sfx(0.5); return
	var path = "res://scenes/player/character.tscn"
	if not ResourceLoader.exists(path): _notify("Player scene not found", true); return
	var old = get_node_or_null("PreviewPlayer")
	if old: old.queue_free()
	var player = load(path).instantiate()
	player.name = "PreviewPlayer"; add_child(player)
	_disable_player_cameras.call_deferred(player)
	preview_player_ref = player; is_testing = true; _speed_fail_pending = false
	_close_props_panel()
	var spawn = _get_spawn_pos()
	player.global_position = spawn; camera.position = spawn; camera.zoom = Vector2(1,1)
	camera.make_current()

	# FIX 1: attach all modifier components on all holds when entering test
	for h in holds_container.get_children():
		_attach_all_modifiers(h)

	# FIX 2: create rope visual for roped discipline
	if current_discipline in ["roped", "speed"]:
		_create_rope_visual()
		# Pass belayer position to player if it supports it
		if belayer_position != Vector2.ZERO:
			if player.has_method("set_belayer_position"):
				player.set_belayer_position(belayer_position)
			elif "belayer_position" in player:
				player.belayer_position = belayer_position

	if current_discipline == "speed": _setup_speed_timer()
	_sfx(1.2); _notify("Testing — press ESC to exit")

func _get_spawn_pos() -> Vector2:
	if is_instance_valid(custom_spawn_hold):
		var hp = custom_spawn_hold.get_node_or_null("HoldPoint")
		return (hp.global_position if hp else custom_spawn_hold.global_position) + Vector2(0,80)
	var starts = []
	for h in holds_container.get_children():
		if get_hold_type(h) == "START": starts.append(h)
	if starts.size() == 1:
		var hp = starts[0].get_node_or_null("HoldPoint")
		return (hp.global_position if hp else starts[0].global_position) + Vector2(0,80)
	elif starts.size() > 1:
		var s = Vector2.ZERO
		for h in starts:
			var hp = h.get_node_or_null("HoldPoint")
			s += hp.global_position if hp else h.global_position
		return s / starts.size() + Vector2(0,80)
	return Vector2.ZERO

func _setup_speed_timer():
	var old = get_node_or_null("TestSpeedTimer"); if old: old.queue_free()
	var sc = load("res://scripts/ui/speed_timer.gd")
	if not sc: return
	_speed_timer_node = sc.new(); _speed_timer_node.name = "TestSpeedTimer"; add_child(_speed_timer_node)
	_speed_timer_node.set_time_limit(speed_time_limit); _speed_timer_node.show_timer()
	_speed_timer_node.start_timer(); _speed_timer_node.time_expired.connect(_on_speed_expired)

func _on_speed_expired():
	if not is_testing or _speed_fail_pending: return
	_speed_fail_pending = true; _notify("TIME'S UP — resetting…", true); _sfx(0.5)
	var player = get_node_or_null("PreviewPlayer")
	if is_instance_valid(player):
		if   player.has_method("release_all_holds"): player.release_all_holds()
		elif player.has_method("fall"):              player.fall()
		else: if "can_grab" in player: player.can_grab = false
	await get_tree().create_timer(1.2).timeout
	if not is_testing: return
	_speed_fail_pending = false
	var spawn = _get_spawn_pos()
	var p2 = get_node_or_null("PreviewPlayer")
	if is_instance_valid(p2):
		p2.global_position = spawn; if "can_grab" in p2: p2.can_grab = true
		if "velocity" in p2: p2.velocity = Vector2.ZERO
	camera.position = spawn
	# FIX 1: reset all falling hold components on respawn
	for h in holds_container.get_children():
		var comp = h.get_node_or_null(_FALLING_MOD_NODE_NAME)
		if comp and comp.has_method("reset"): comp.reset()
	if is_instance_valid(_speed_timer_node): _speed_timer_node.stop_timer(); _speed_timer_node.start_timer()

func _disable_player_cameras(player: Node):
	for c in player.find_children("*","Camera2D",true,false): c.enabled = false; c.make_current()
	camera.make_current()

func _stop_testing():
	is_testing = false; _speed_fail_pending = false; preview_player_ref = null
	if is_instance_valid(_speed_timer_node): _speed_timer_node.queue_free()
	_speed_timer_node = null
	var pp = get_node_or_null("PreviewPlayer"); if pp: pp.queue_free()
	# FIX 1: detach all runtime modifier components when leaving test mode
	for h in holds_container.get_children():
		var comp = h.get_node_or_null(_FALLING_MOD_NODE_NAME)
		if comp: comp.queue_free()
		# Reset hold position if it drifted due to falling
		# (position is restored from undo state next time they edit)
	# FIX 2: destroy rope visual
	_destroy_rope_visual()
	camera.make_current()


# ═══════════════════════════════════════════════════════════════════════════
#  JSON COPY / PASTE
# ═══════════════════════════════════════════════════════════════════════════

func _on_copy_json():
	var env = get_node_or_null("/root/EnvironmentConfig")
	var env_name = env.get_current_environment_name().to_lower() if env else "gym"
	var data = {
		"name": climb_name if climb_name != "" else "Unnamed Route",
		"grade": climb_grade, "environment": env_name,
		"discipline": current_discipline, "weather": current_weather,
		"weather_intensity": current_weather_intensity,
		"speed_time_limit": speed_time_limit, "holds": [], "crashpads": []
	}
	if current_discipline == "roped" and belayer_position != Vector2.ZERO:
		data["belayer_position"] = {"x": belayer_position.x, "y": belayer_position.y}
	if wall and wall.has_method("get_polygon_data"):
		var pd = wall.get_polygon_data(); if pd: data["wall_polygon"] = pd
	for h in holds_container.get_children():
		var e = {"type": get_hold_type(h), "x": h.global_position.x, "y": h.global_position.y}
		var mods: Array = _hold_modifiers.get(h, [])
		if not mods.is_empty(): e["modifiers"] = mods.duplicate(true)
		if is_instance_valid(custom_spawn_hold) and h == custom_spawn_hold:
			e["custom_spawn"] = true
		data["holds"].append(e)
	for cp in crashpads_container.get_children():
		data["crashpads"].append({"x": cp.global_position.x, "y": cp.global_position.y})
	DisplayServer.clipboard_set(JSON.stringify(data, "\t"))
	_sfx(1.3); _notify("Route copied to clipboard")

func _on_paste_json():
	var clip = DisplayServer.clipboard_get()
	if clip.is_empty(): _notify("Clipboard empty", true); _sfx(0.5); return
	var json = JSON.new()
	if json.parse(clip) != OK: _notify("Invalid JSON in clipboard", true); _sfx(0.5); return
	var data = json.data
	if not "holds" in data: _notify("No holds data found", true); _sfx(0.5); return
	_on_clear()
	climb_name = data.get("name",""); if climb_name_input: climb_name_input.text = climb_name
	current_discipline = data.get("discipline","bouldering")
	speed_time_limit   = float(data.get("speed_time_limit", 60.0))
	if discipline_dropdown:
		match current_discipline:
			"bouldering": discipline_dropdown.select(0)
			"roped":      discipline_dropdown.select(1)
			"speed":      discipline_dropdown.select(2)
		_on_discipline_changed(discipline_dropdown.selected)
	var saved_grade = data.get("grade","VB")
	if grade_dropdown:
		var grades = V_GRADES if current_discipline == "bouldering" else YDS_GRADES
		var idx = grades.find(saved_grade); if idx >= 0: grade_dropdown.select(idx); _on_grade_changed(idx)
	if speed_time_input: speed_time_input.value = speed_time_limit
	if "belayer_position" in data and data["belayer_position"]:
		var bd = data["belayer_position"]
		_create_belayer_marker(Vector2(bd.get("x",0), bd.get("y",0)))
	var env = get_node_or_null("/root/EnvironmentConfig")
	if env:
		var en = data.get("environment","gym"); var types = env.get_all_environment_types(); var matched = false
		for i in range(types.size()):
			if env.get_environment_name(types[i]).to_lower() == en.to_lower():
				env.set_environment(types[i]); matched = true; break
		if not matched and not types.is_empty(): env.set_environment(types[0])
		update_wall_bounds()
	var lw = int(data.get("weather",0)); var li = float(data.get("weather_intensity",1.0))
	current_weather = lw; current_weather_intensity = li
	if weather_dropdown: weather_dropdown.select(clamp(lw,0,weather_dropdown.get_item_count()-1)); _on_weather_changed(lw)
	if weather_intensity_slider: weather_intensity_slider.value = li
	for hd in data["holds"]:
		var tn = hd.get("type","JUG")
		if tn not in loaded_scenes: continue
		var hold = loaded_scenes[tn].instantiate()
		if hold.has_method("set_hold_type_from_string"): hold.set_hold_type_from_string(tn)
		hold.global_position = Vector2(hd.get("x",0), hd.get("y",0))
		holds_container.add_child(hold); hold.add_to_group("holds"); hold.set_meta("editor_type", tn)
		if "modifiers" in hd and not (hd["modifiers"] as Array).is_empty():
			_hold_modifiers[hold] = (hd["modifiers"] as Array).duplicate(true)
			_refresh_hold_tint(hold)
			# FIX 1: modifiers are NOT attached here (editor mode); they
			# attach on Test press.  Outline is applied via _refresh_hold_tint.
		if hd.get("custom_spawn", false):
			custom_spawn_hold = hold
			hold.modulate = Color(0.4, 1.0, 0.5)
	if "crashpads" in data and crashpad_scene:
		for cpd in data["crashpads"]:
			var cp = crashpad_scene.instantiate()
			cp.global_position = Vector2(cpd.get("x",0), cpd.get("y",0))
			crashpads_container.add_child(cp); cp.add_to_group("crashpads")
	if "wall_polygon" in data and wall and wall.has_method("set_polygon_data"):
		wall.set_polygon_data(data["wall_polygon"])
	update_wall_bounds(); _sfx(1.25); _notify("Route loaded: " + climb_name)


# ═══════════════════════════════════════════════════════════════════════════
#  CLEAR / BACK
# ═══════════════════════════════════════════════════════════════════════════

func _on_clear():
	for h  in holds_container.get_children():    h.queue_free()
	for cp in crashpads_container.get_children(): cp.queue_free()
	if wall and wall.has_method("reset_polygon"): wall.reset_polygon()
	_hold_modifiers.clear(); _close_props_panel(); custom_spawn_hold = null
	current_discipline = "bouldering"; speed_time_limit = 60.0; _clear_belayer_marker()
	_destroy_rope_visual()
	placing_belayer = false
	if discipline_dropdown: discipline_dropdown.select(0); _on_discipline_changed(0)
	climb_name = ""; climb_grade = "VB"
	if climb_name_input: climb_name_input.text = ""
	_populate_grade_dropdown()
	current_weather = 0; current_weather_intensity = 1.0
	if weather_dropdown: weather_dropdown.select(0); _on_weather_changed(0)
	if weather_intensity_slider: weather_intensity_slider.value = 1.0
	update_wall_bounds(); undo_stack.clear(); _sfx(0.6); _notify("Editor cleared")

func _on_back_pressed():
	_stop_testing(); _close_props_panel()
	selected_hold_type = ""; placing_crashpad = false; placing_belayer = false
	_deselect_all_palette(); clear_preview()
	Transition.to("res://scenes/menus/main_menu.tscn")


# ═══════════════════════════════════════════════════════════════════════════
#  UNDO
# ═══════════════════════════════════════════════════════════════════════════

const MAX_UNDO = 50

func save_undo_state():
	var state = {
		"holds": [], "crashpads": [],
		"belayer_position": belayer_position, "wall_polygon": null,
		"weather": current_weather, "weather_intensity": current_weather_intensity,
	}
	for h in holds_container.get_children():
		state.holds.append({
			"type": get_hold_type(h), "x": h.global_position.x, "y": h.global_position.y,
			"modifiers": (_hold_modifiers.get(h, []) as Array).duplicate(true),
			"custom_spawn": (h == custom_spawn_hold)
		})
	for cp in crashpads_container.get_children():
		state.crashpads.append({"x": cp.global_position.x, "y": cp.global_position.y})
	if wall and wall.has_method("get_polygon_data"): state.wall_polygon = wall.get_polygon_data()
	undo_stack.append(state)
	if undo_stack.size() > MAX_UNDO: undo_stack.pop_front()

func undo_last_action():
	if undo_stack.is_empty(): _notify("Nothing to undo"); return
	var state = undo_stack.pop_back()
	for h  in holds_container.get_children():    h.queue_free()
	for cp in crashpads_container.get_children(): cp.queue_free()
	_hold_modifiers.clear(); _close_props_panel(); custom_spawn_hold = null
	for hd in state["holds"]:
		if hd["type"] not in loaded_scenes: continue
		var hold = loaded_scenes[hd["type"]].instantiate()
		if hold.has_method("set_hold_type_from_string"): hold.set_hold_type_from_string(hd["type"])
		hold.global_position = Vector2(hd["x"], hd["y"])
		holds_container.add_child(hold); hold.add_to_group("holds"); hold.set_meta("editor_type", hd["type"])
		if "modifiers" in hd and not (hd["modifiers"] as Array).is_empty():
			_hold_modifiers[hold] = (hd["modifiers"] as Array).duplicate(true)
			_refresh_hold_tint(hold)
		if hd.get("custom_spawn", false):
			custom_spawn_hold = hold
			hold.modulate = Color(0.4, 1.0, 0.5)
	if crashpad_scene:
		for cpd in state["crashpads"]:
			var cp = crashpad_scene.instantiate(); cp.global_position = Vector2(cpd["x"], cpd["y"])
			crashpads_container.add_child(cp); cp.add_to_group("crashpads")
	if state["belayer_position"] != Vector2.ZERO: _create_belayer_marker(state["belayer_position"])
	else: _clear_belayer_marker()
	if state["wall_polygon"] and wall and wall.has_method("set_polygon_data"):
		wall.set_polygon_data(state["wall_polygon"])
	if "weather" in state:
		current_weather = state["weather"]; current_weather_intensity = float(state.get("weather_intensity", 1.0))
		if weather_dropdown: weather_dropdown.select(clamp(current_weather,0,weather_dropdown.get_item_count()-1)); _on_weather_changed(current_weather)
		if weather_intensity_slider: weather_intensity_slider.value = current_weather_intensity
	update_wall_bounds(); _sfx(1.1); _notify("Undo")


# ═══════════════════════════════════════════════════════════════════════════
#  DRAW
# ═══════════════════════════════════════════════════════════════════════════

func _draw():
	var is_night = current_weather < WEATHER_NAMES.size() and WEATHER_NAMES[current_weather] == "Night"
	var grid_col  = Color(0.55,0.55,0.65,0.40) if is_night else Color(0.30,0.30,0.32,0.18)
	var bdr_col   = Color(0.55,0.75,1.00,0.65) if is_night else C_BORDER

	draw_rect(Rect2(CANVAS_MIN_X, CANVAS_MIN_Y,
		CANVAS_MAX_X-CANVAS_MIN_X, CANVAS_MAX_Y-CANVAS_MIN_Y), bdr_col, false, 2.0)

	var bounds = _get_route_bounds()
	if bounds.valid:
		draw_rect(Rect2(bounds.min, bounds.size), Color(0.30,0.50,0.80, 0.38 if is_night else 0.22), true)
		draw_rect(Rect2(bounds.min, bounds.size), Color(0.40,0.70,1.00, 0.75 if is_night else 0.55), false, 3.0)

	# FIX 2: draw rope anchor indicator in editor (non-test) mode
	if belayer_position != Vector2.ZERO and not is_testing:
		draw_circle(belayer_position, 15, Color(1,0.5,0,0.25))
		draw_arc(belayer_position, 20, 0, TAU, 32, Color.ORANGE, 2.0)
		# Draw a short dangling rope preview
		var dangle_end = belayer_position + Vector2(0, 120)
		draw_line(belayer_position, dangle_end, Color(0.85,0.72,0.40,0.55), 2.5)

	if is_instance_valid(custom_spawn_hold):
		var sp = custom_spawn_hold.global_position
		draw_circle(sp, 18, Color(0.3,1.0,0.4,0.15))
		draw_arc(sp, 22, 0, TAU, 36, Color(0.3,1.0,0.4,0.80), 2.0)

	# FIX 3: removed the non-functional diamond glyph — outline is now on
	# the sprite itself via _apply_hold_outline / shader material.
	# We keep a subtle label near modified holds so they are identifiable
	# even when zoomed out.
	for h in holds_container.get_children():
		if _hold_modifiers.has(h) and not (_hold_modifiers[h] as Array).is_empty():
			# Small "M" label above the hold
			draw_string(ThemeDB.fallback_font,
				h.global_position + Vector2(-5, -28),
				"M", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(C_MODIFIER.r, C_MODIFIER.g, C_MODIFIER.b, 0.85))

	if not grid_enabled: return

	var vr = get_viewport_rect()
	var half = vr.size / (2.0 * camera.zoom.x)
	var vmin = camera.position - half; var vmax = camera.position + half
	var dx = max(vmin.x, CANVAS_MIN_X); var ex = min(vmax.x, CANVAS_MAX_X)
	var dy = max(vmin.y, CANVAS_MIN_Y); var ey = min(vmax.y, CANVAS_MAX_Y)
	var sx = max(floor(dx/grid_size)*grid_size, CANVAS_MIN_X)
	var ex2 = min(ceil(ex/grid_size)*grid_size, CANVAS_MAX_X)
	var sy = max(floor(dy/grid_size)*grid_size, CANVAS_MIN_Y)
	var ey2 = min(ceil(ey/grid_size)*grid_size, CANVAS_MAX_Y)
	var x = sx
	while x <= ex2: draw_line(Vector2(x,dy), Vector2(x,ey), grid_col, 1.0); x += grid_size
	var y = sy
	while y <= ey2: draw_line(Vector2(dx,y), Vector2(ex,y), grid_col, 1.0); y += grid_size

func _get_route_bounds() -> Dictionary:
	if holds_container.get_child_count() == 0:
		return {"min":Vector2.ZERO,"max":Vector2.ZERO,"valid":false}
	var mn_x=INF; var mx_x=-INF; var mn_y=INF; var mx_y=-INF
	for h in holds_container.get_children():
		mn_x=min(mn_x,h.global_position.x); mx_x=max(mx_x,h.global_position.x)
		mn_y=min(mn_y,h.global_position.y); mx_y=max(mx_y,h.global_position.y)
	var wmin=Vector2(mn_x-WALL_PADDING_SIDES, mn_y-WALL_PADDING_TOP)
	var wmax=Vector2(mx_x+WALL_PADDING_SIDES, mx_y+WALL_PADDING_BOTTOM)
	return {"min":wmin,"max":wmax,"center":(wmin+wmax)/2.0,"size":wmax-wmin,"valid":true}


# ═══════════════════════════════════════════════════════════════════════════
#  NOTIFICATION TOAST
# ═══════════════════════════════════════════════════════════════════════════

func _notify(text: String, is_error: bool = false):
	var old = ui_layer.get_node_or_null("Toast"); if old: old.queue_free()
	var ui_bottom = TOP_BAR_H + (DRAWER_H if not ui_panel_collapsed else 0.0) + 8.0

	var toast = ColorRect.new(); toast.name = "Toast"
	toast.size    = Vector2(380, 38)
	toast.position = Vector2(get_viewport_rect().size.x/2.0 - 190.0, ui_bottom)
	toast.color   = Color(0.55,0.12,0.12,0.94) if is_error else Color(0.10,0.38,0.20,0.94)

	var lbl = Label.new(); lbl.text = text
	lbl.size = toast.size
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1,1,1))
	toast.add_child(lbl); ui_layer.add_child(toast)

	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(toast): toast.queue_free()


# ═══════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _snap(pos: Vector2) -> Vector2:
	if not grid_enabled: return pos
	return Vector2(round(pos.x/grid_size)*grid_size, round(pos.y/grid_size)*grid_size)

func _world_to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - camera.global_position) * camera.zoom + get_viewport_rect().size * 0.5


# ── Widget helpers ──────────────────────────────────────────────────────────

func _label(text: String, size: int, color: Color) -> Label:
	var l = Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _hsep() -> HSeparator:
	var s = HSeparator.new()
	s.add_theme_color_override("color", C_BORDER)
	return s

func _bar_sep(parent: HBoxContainer):
	var s = ColorRect.new(); s.color = C_BORDER
	s.custom_minimum_size = Vector2(1, 22); parent.add_child(s)

func _style_line_edit(le: LineEdit):
	var n = StyleBoxFlat.new()
	n.bg_color = C_SURFACE; n.set_border_width_all(1); n.border_color = C_BORDER
	n.set_corner_radius_all(3)
	le.add_theme_stylebox_override("normal", n)
	le.add_theme_font_size_override("font_size", 11)
	le.add_theme_color_override("font_color", C_TEXT)

func _make_option_button(min_w: int) -> OptionButton:
	var ob = OptionButton.new(); ob.custom_minimum_size = Vector2(min_w, 30)
	_style_option_button(ob); return ob

func _style_option_button(ob: OptionButton):
	ob.add_theme_font_size_override("font_size", 11)
	ob.add_theme_color_override("font_color", C_TEXT)
	var n = StyleBoxFlat.new()
	n.bg_color = C_SURFACE; n.set_border_width_all(1); n.border_color = C_BORDER
	n.set_corner_radius_all(3); ob.add_theme_stylebox_override("normal", n)

func _make_action_button(text: String, color: Color, cb: Callable) -> Button:
	var btn = Button.new(); btn.text = text; btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", color)
	var n = StyleBoxFlat.new(); n.bg_color = C_SURFACE
	n.set_border_width_all(1); n.border_color = C_BORDER; n.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", n)
	var h = StyleBoxFlat.new(); h.bg_color = Color(C_SURFACE.r+0.06,C_SURFACE.g+0.06,C_SURFACE.b+0.06)
	h.set_border_width_all(1); h.border_color = color; h.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", h)
	btn.pressed.connect(cb); return btn

func _make_flat_button(text: String, min_size: Vector2) -> Button:
	var btn = Button.new(); btn.text = text; btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE; btn.add_theme_font_size_override("font_size", 11)
	var n = StyleBoxFlat.new(); n.bg_color = C_SURFACE
	n.set_border_width_all(1); n.border_color = C_BORDER; n.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", n)
	var h = StyleBoxFlat.new(); h.bg_color = Color(C_SURFACE.r+0.06,C_SURFACE.g+0.06,C_SURFACE.b+0.06)
	h.set_border_width_all(1); h.border_color = C_ACCENT; h.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", h); return btn

func _drawer_col(parent: HBoxContainer, title: String) -> VBoxContainer:
	var col = VBoxContainer.new(); col.add_theme_constant_override("separation", 8); parent.add_child(col)
	var t = _label(title, 9, C_MUTED); col.add_child(t); return col

func _drawer_row(parent: VBoxContainer, lbl_text: String) -> HBoxContainer:
	var hb = HBoxContainer.new(); hb.add_theme_constant_override("separation", 10); parent.add_child(hb)
	var l = _label(lbl_text + ":", 10, C_MUTED); l.custom_minimum_size = Vector2(60, 0); hb.add_child(l)
	return hb

func _drawer_vsep(parent: HBoxContainer):
	var s = ColorRect.new(); s.color = C_BORDER
	s.custom_minimum_size = Vector2(1, 110); parent.add_child(s)
