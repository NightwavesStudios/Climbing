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
#    4. Wall-type filtering — hold palette buttons are shown/hidden based on
#       the current environment. Holds with wall_types:[] are universal;
#       holds with specific wall_types (e.g. WINDOW = ["building"]) only
#       appear on matching environments. Placement is also guarded.
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
var palette_list: VBoxContainer
var palette_buttons: Dictionary = {}   # type_key → Button

# Contextual properties panel
var props_panel: PanelContainer = null
var props_hold: Node2D = null
var _props_mod_list: VBoxContainer = null

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
var time_of_day_dropdown: OptionButton
var drawer_panel: PanelContainer
var drawer_container: MarginContainer
var fold_button: Button
var ui_panel_collapsed: bool = true

# Top‑bar file‑operation UI (set in _build_top_bar)
var _file_label: Label
var _btn_new: Button
var _btn_open: Button
var _btn_save: Button

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
var current_time_of_day: int = -1  # -1=random, 0=day, 1=dusk, 2=night
const TIME_OF_DAY_NAMES := ["Random", "Day", "Dusk", "Night"]

# FIX 4: track current environment for hold palette filtering
var current_environment: String = "gym"

var grid_enabled: bool = true
var grid_size: float = 32.0
var undo_stack: Array = []

# ── File persistence ──────────────────────────────────────────────────────────
var current_file_path: String = ""       # "user://levels/<name>.climb"
var current_file_name: String = ""       # display name (without path)
var is_dirty: bool = false               # true when unsaved changes exist
var _suppress_dirty: bool = false        # prevent re‑entrant dirty signals

var _hold_modifiers: Dictionary = {}

# ── Moving-hold modifier point placement state ──────────────────────────────
var _place_move_hold: Node2D = null   # hold whose point is being set
var _place_move_idx: int = -1         # index of the modifier in _hold_modifiers[hold]
var _place_move_key: String = ""      # "start" or "end" while waiting for a world click

# ── Constants ──────────────────────────────────────────────────────────────
const WEATHER_NAMES := ["None", "Rain", "Night", "Snow", "Lightning", "Fog", "Hail", "Sandstorm", "Wind"]
const V_GRADES: Array[String] = ["VB","V0","V1","V2","V3","V4","V5","V6","V7","V8","V9","V10","V11","V12"]
const YDS_GRADES: Array[String] = ["5.5","5.6","5.7","5.8","5.9","5.10a","5.10b","5.10c","5.10d",
					"5.11a","5.11b","5.11c","5.11d","5.12a","5.12b","5.12c","5.12d","5.13a","5.13b"]
var HOLD_TYPES  = ["START","TOP","JUG","CRIMP","SLOPER","POCKET","FOOT","UNDERCLING","WINDOW","LEDGE"]
var HOLD_SCENES = {
	"START":  "res://scenes/holds/start.tscn",
	"TOP":    "res://scenes/holds/top_out.tscn",
	"JUG":    "res://scenes/holds/jug.tscn",
	"CRIMP":  "res://scenes/holds/crimp.tscn",
	"SLOPER": "res://scenes/holds/sloper.tscn",
	"POCKET": "res://scenes/holds/pocket.tscn",
	"FOOT":   "res://scenes/holds/foothold.tscn",
	"UNDERCLING": "res://scenes/holds/undercling.tscn",
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
const LEFT_PAL_W  := 118.0
const DRAWER_H    := 144.0

# Colours — chalk-board palette
const C_BG        := Color(0.08, 0.08, 0.09)
const C_SURFACE   := Color(0.12, 0.12, 0.14)
const C_BORDER    := Color(0.30, 0.30, 0.36)
const C_TEXT      := Color(0.88, 0.88, 0.90)
const C_MUTED     := Color(0.45, 0.45, 0.50)
const C_ACCENT    := Color(0.90, 0.72, 0.35)     # soft gold (matches new UI style)
const C_WARN      := Color(1.00, 0.42, 0.21)     # orange
const C_SUCCESS   := Color(0.27, 0.85, 0.50)     # green
const C_MODIFIER  := Color(0.62, 0.52, 0.88)     # soft violet
const CRASHPAD_COLOR := Color(0.45, 0.72, 0.95)  # padded blue

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
	} else {
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
}
"""

# Hold type accent colours — muted to fit the chalk-board aesthetic
# (less rainbow, more cohesive). Only used as thin accent stripes on
# the palette buttons; the buttons themselves stay near-white.
var HOLD_COLORS := {
	"START":  Color(0.40, 0.72, 0.50),   # muted green
	"TOP":    Color(0.48, 0.62, 0.92),   # muted blue
	"JUG":    Color(0.78, 0.78, 0.82),   # neutral
	"CRIMP":  Color(0.92, 0.58, 0.38),   # muted orange
	"SLOPER": Color(0.86, 0.66, 0.34),   # muted amber
	"POCKET": Color(0.70, 0.58, 0.92),   # muted purple
	"FOOT":   Color(0.48, 0.74, 0.64),   # muted teal
	"UNDERCLING": Color(0.86, 0.56, 0.60), # muted rose
	"WINDOW": Color(0.50, 0.74, 0.86),   # muted cyan
	"LEDGE":  Color(0.76, 0.62, 0.44),   # muted tan
}

# Short descriptions shown as tooltips on the palette buttons.
var HOLD_TOOLTIPS := {
	"START":  "Start hold — the route must begin here. Max 2.",
	"TOP":    "Top hold — the finish of the route.",
	"JUG":    "Easiest grip, any 2 limbs can hold it.",
	"CRIMP":  "Small edge — fingertips only, but strong.",
	"SLOPER": "Open rounded hold — needs a good hand position.",
	"POCKET": "A pocket for one or two fingers.",
	"FOOT":   "Foothold — feet only, can't be gripped.",
	"UNDERCLING": "Grip from below, palms up.",
	"WINDOW": "Hole through the wall (building walls).",
	"LEDGE":  "Wide shelf — easy to stand on.",
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

	# Sync our environment with the shared EnvironmentConfig so the palette
	# filtering matches what the wall actually shows (e.g. MENU_SUNSET after
	# coming from the main menu).
	var env_autoload := get_node_or_null("/root/EnvironmentConfig")
	if env_autoload:
		current_environment = env_autoload.get_current_environment_name().to_lower()

	# The shared menu background (animated sunset sky) is an autoload that
	# persists across scenes — hide it here so it doesn't clutter the canvas.
	var menu_bg := get_node_or_null("/root/MenuBackgroundManager")
	if menu_bg and menu_bg.has_method("hide"):
		menu_bg.hide()

	_build_ui()
	_refresh_hold_palette_for_environment()
	update_wall_bounds()
	# Set initial window title
	_update_title_bar()

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
	_build_palette()
	_build_drawer()
	_build_info_bar()


# ── TOP BAR ────────────────────────────────────────────────────────────────

func _build_top_bar():
	var bg = ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.offset_bottom = TOP_BAR_H
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(bg)

	var line = ColorRect.new()
	line.color = C_BORDER
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_top = TOP_BAR_H - 1
	line.offset_bottom = TOP_BAR_H
	ui_layer.add_child(line)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.offset_bottom = TOP_BAR_H
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 10 if "left" in s or "right" in s else 6)
	ui_layer.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(hbox)

	# ── Back to main menu (kept visible & obvious — NOT hidden in the drawer) ──
	var back_btn = _make_action_button("← Back", C_TEXT, func(): _on_back_pressed())
	back_btn.tooltip_text = "Return to the main menu"
	hbox.add_child(back_btn)
	_bar_sep(hbox)

	var logo = _label("EDITOR", 12, C_TEXT)
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(logo)

	_bar_sep(hbox)

	# ── File operations ────────────────────────────────────────────────────
	_btn_new  = _make_action_button("New",  C_TEXT,   _on_new_level)
	_btn_open = _make_action_button("Open", C_TEXT,   _on_open_level_browser)
	_btn_save = _make_action_button("Save", C_SUCCESS, _on_save)
	_btn_new.tooltip_text  = "Start a new route (discards unsaved changes)"
	_btn_open.tooltip_text = "Open a previously saved route"
	_btn_save.tooltip_text = "Save the current route"
	hbox.add_child(_btn_new)
	hbox.add_child(_btn_open)
	hbox.add_child(_btn_save)

	_bar_sep(hbox)

	climb_name_input = LineEdit.new()
	climb_name_input.placeholder_text = "Route name…"
	climb_name_input.custom_minimum_size = Vector2(170, 30)
	_style_line_edit(climb_name_input)
	climb_name_input.text_changed.connect(func(t): climb_name = t)
	hbox.add_child(climb_name_input)

	_bar_sep(hbox)

	discipline_dropdown = _make_option_button(104)
	discipline_dropdown.add_item("Boulder")
	discipline_dropdown.add_item("Roped")
	discipline_dropdown.add_item("Speed")
	discipline_dropdown.item_selected.connect(_on_discipline_changed)
	hbox.add_child(discipline_dropdown)

	grade_dropdown = _make_option_button(76)
	_populate_grade_dropdown()
	grade_dropdown.item_selected.connect(_on_grade_changed)
	hbox.add_child(grade_dropdown)

	# Speed time-limit spinbox (only shown for the Speed discipline).
	# The Belayer button lives in the left palette now.
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
	speed_time_input.custom_minimum_size = Vector2(84, 28)
	speed_time_input.value_changed.connect(func(v): speed_time_limit = v)
	discipline_extras_panel.add_child(speed_time_input)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var export_btn = _make_action_button("Export", C_TEXT, func(): _on_copy_json())
	export_btn.tooltip_text = "Copy the level as JSON to the clipboard"
	hbox.add_child(export_btn)
	var import_btn = _make_action_button("Import", C_TEXT, func(): _on_paste_json())
	import_btn.tooltip_text = "Load a level from JSON on the clipboard"
	hbox.add_child(import_btn)

	_bar_sep(hbox)

	var test_btn = _make_action_button("Test", C_SUCCESS, func(): _on_preview())
	test_btn.tooltip_text = "Playtest the current route"
	hbox.add_child(test_btn)

	_bar_sep(hbox)

	fold_button = _make_action_button("More ▼", C_TEXT, func(): _toggle_drawer())
	fold_button.tooltip_text = "Environment, editor tools and shortcuts"
	hbox.add_child(fold_button)


# ── LEFT PALETTE ────────────────────────────────────────────────────────────
# The palette is the primary hold picker. It only ever shows hold types that
# are valid for the current environment (see _refresh_hold_palette_for_environment).

func _build_palette():
	palette_panel = PanelContainer.new()
	palette_panel.name = "PalettePanel"
	palette_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	palette_panel.offset_left   = 6
	palette_panel.offset_right  = LEFT_PAL_W
	palette_panel.offset_top    = TOP_BAR_H + 6
	palette_panel.offset_bottom = -28
	var sty = StyleBoxFlat.new()
	sty.bg_color = Color(C_SURFACE.r, C_SURFACE.g, C_SURFACE.b, 0.94)
	sty.set_border_width_all(1)
	sty.border_color = C_BORDER
	sty.set_corner_radius_all(6)
	sty.content_margin_left   = 8
	sty.content_margin_right  = 8
	sty.content_margin_top    = 8
	sty.content_margin_bottom = 8
	palette_panel.add_theme_stylebox_override("panel", sty)
	ui_layer.add_child(palette_panel)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	palette_panel.add_child(outer)

	var title = _label("HOLDS", 9, C_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	# All entries live in one list so widths stay consistent and there is no
	# dead space between the holds and the utility entries.
	palette_list = VBoxContainer.new()
	palette_list.add_theme_constant_override("separation", 4)
	palette_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(palette_list)

	# Hold type buttons — grouped for clarity; visibility is still filtered
	# by environment in _refresh_hold_palette_for_environment().
	var registry = get_node_or_null("/root/HoldRegistry")
	var hold_groups: Array[Array] = [
		["START & TOP", ["START", "TOP"]],
		["GRIPS", ["JUG", "CRIMP", "SLOPER", "POCKET", "UNDERCLING", "LEDGE"]],
		["FEET", ["FOOT"]],
		["WALL FEATURES", ["WINDOW"]],
	]
	for group in hold_groups:
		var group_title: String = group[0]
		var group_lbl = _label(group_title, 8, C_MUTED)
		group_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		palette_list.add_child(group_lbl)
		for type_key in (group[1] as Array):
			var display: String = type_key.capitalize()
			if registry:
				display = registry.get_hold_display_name(type_key)
			var btn = _make_palette_button(display, HOLD_COLORS.get(type_key, C_MUTED), HOLD_TOOLTIPS.get(type_key, ""))
			btn.pressed.connect(func(): _on_palette_type_selected(type_key))
			palette_list.add_child(btn)
			palette_buttons[type_key] = btn

	# ── Utility entries (crashpad / belayer) ─────────────────────────────
	var other = _label("OTHER", 8, C_MUTED)
	other.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	palette_list.add_child(other)
	var sep = HSeparator.new()
	sep.add_theme_color_override("color", C_BORDER)
	palette_list.add_child(sep)

	crashpad_button = _make_palette_button("Crashpad", CRASHPAD_COLOR)
	crashpad_button.pressed.connect(func(): _on_place_crashpad_pressed())
	palette_list.add_child(crashpad_button)
	palette_buttons["CRASHPAD"] = crashpad_button

	belayer_placement_button = _make_palette_button("Belayer", C_WARN)
	belayer_placement_button.pressed.connect(func(): _on_place_belayer_pressed())
	belayer_placement_button.visible = false
	palette_list.add_child(belayer_placement_button)
	palette_buttons["BELAYER"] = belayer_placement_button

	# Default selection: none.
	_deselect_all_palette()


# ── DRAWER ─────────────────────────────────────────────────────────────────

func _build_drawer():
	# Floating rounded panel, centered under the top bar — matches the
	# project's card/popup style instead of a full-width strip.
	drawer_panel       = PanelContainer.new()
	drawer_panel.name  = "DrawerPanel"
	drawer_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	drawer_panel.offset_left   = -470
	drawer_panel.offset_right  = 470
	drawer_panel.offset_top    = TOP_BAR_H + 8
	drawer_panel.offset_bottom = TOP_BAR_H + 8 + DRAWER_H
	drawer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer_panel.visible      = false
	var sty = StyleBoxFlat.new()
	sty.bg_color = Color(0.06, 0.06, 0.08, 0.98)
	sty.set_border_width_all(1)
	sty.border_color = Color(1, 1, 1, 0.09)
	sty.set_corner_radius_all(12)
	sty.shadow_color = Color(0, 0, 0, 0.4)
	sty.shadow_size  = 10
	drawer_panel.add_theme_stylebox_override("panel", sty)
	ui_layer.add_child(drawer_panel)

	drawer_container = MarginContainer.new()
	drawer_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	drawer_container.visible    = false
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		drawer_container.add_theme_constant_override(s, 24 if "left" in s or "right" in s else 14)
	drawer_panel.add_child(drawer_container)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	drawer_container.add_child(hbox)

	var env_col = _drawer_col(hbox, "ENVIRONMENT")
	var env_row = _drawer_row(env_col, "Surface")
	var environment_dropdown = OptionButton.new()
	environment_dropdown.custom_minimum_size = Vector2(120, 26)
	_style_option_button(environment_dropdown)
	_populate_environment_dropdown(environment_dropdown)
	environment_dropdown.item_selected.connect(func(i): on_environment_changed(i))
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

	var tod_row = _drawer_row(env_col, "Time of Day")
	time_of_day_dropdown = OptionButton.new()
	time_of_day_dropdown.custom_minimum_size = Vector2(120, 26)
	_style_option_button(time_of_day_dropdown)
	for n in TIME_OF_DAY_NAMES: time_of_day_dropdown.add_item(n)
	time_of_day_dropdown.select(0)  # "Random"
	time_of_day_dropdown.item_selected.connect(_on_time_of_day_changed)
	tod_row.add_child(time_of_day_dropdown)

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

	var save_as_btn = _make_flat_button("Save As", Vector2(80, 26))
	save_as_btn.add_theme_color_override("font_color", C_SUCCESS)
	save_as_btn.pressed.connect(_on_save_as)
	row2.add_child(save_as_btn)

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
	var col: Color = HOLD_COLORS.get(key, C_MUTED)
	if key == "CRASHPAD": col = CRASHPAD_COLOR
	elif key == "BELAYER": col = C_WARN
	_style_palette_button(btn, col, active)


## Build a palette entry button (full width, hold-colour coded).
## tooltip: optional help text shown on hover.
func _make_palette_button(text: String, col: Color, tooltip: String = "") -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 30)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)
	btn.clip_text = true
	if tooltip != "":
		btn.tooltip_text = tooltip
	# Thin coloured accent stripe on the left edge (kept inset so it sits
	# inside the 1px border / rounded corner).
	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_left = 1.0
	stripe.offset_right = 4.0
	stripe.offset_top = 1.0
	stripe.offset_bottom = -1.0
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(stripe)
	_style_palette_button(btn, col, false)
	return btn


## Apply the selected/unselected style to a palette button.
## Clean minimal look: near-white label with a thin coloured accent stripe
## on the left edge (matches the project's flat UI style).
func _style_palette_button(btn: Button, col: Color, active: bool):
	var n = StyleBoxFlat.new()
	n.bg_color = Color(col.r, col.g, col.b, 0.10 if active else 0.045)
	n.set_border_width_all(1)
	n.border_color = Color(col.r, col.g, col.b, 0.25)
	n.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", n)
	var h = StyleBoxFlat.new()
	h.bg_color = Color(col.r, col.g, col.b, 0.18 if active else 0.13)
	h.set_border_width_all(1)
	h.border_color = Color(col.r, col.g, col.b, 0.5)
	h.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", h)
	var p = h.duplicate()
	p.bg_color = Color(col.r, col.g, col.b, 0.22)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_color_override("font_color", Color(1, 1, 1) if active else C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	# Accent stripe brightens when the button is selected.
	var stripe := btn.get_node_or_null("Stripe")
	if stripe is ColorRect:
		stripe.color = Color(col.r, col.g, col.b, 0.95 if active else 0.65)


# ── FIX 4: PALETTE WALL-TYPE FILTERING ────────────────────────────────────

func _refresh_hold_palette_for_environment():
	"""Show/hide palette buttons based on what's valid for the current wall type.
	Also clears the active selection if it's no longer valid."""
	var registry = get_node_or_null("/root/HoldRegistry")
	for type_key in HOLD_TYPES:
		var btn = palette_buttons.get(type_key)
		if btn == null:
			continue
		var valid = true
		if registry:
			valid = registry.is_hold_valid_for_wall(type_key, current_environment)
		btn.visible = valid
		# If the currently selected type is no longer valid, deselect it
		if not valid and selected_hold_type == type_key:
			selected_hold_type = ""
			clear_preview()
			_deselect_all_palette()
			_notify("'%s' hold not available on %s walls" % [type_key, current_environment], true)


# ── INFO BAR ──────────────────────────────────────────────────────────────

func _build_info_bar():
	# A slim status strip along the bottom edge, consistent with the top bar.
	var strip = ColorRect.new()
	strip.color = Color(C_BG.r, C_BG.g, C_BG.b, 0.92)
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -28
	strip.offset_bottom = 0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(strip)

	var line = ColorRect.new()
	line.color = C_BORDER
	line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	line.offset_top = -28
	line.offset_bottom = -27
	ui_layer.add_child(line)

	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info_label.offset_left = 12
	info_label.offset_top = -27
	info_label.offset_bottom = -2
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84))
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	_props_mod_list = mod_list
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

		if mod_type == "soft_hold":
			var soft_grid = GridContainer.new()
			soft_grid.columns = 2
			soft_grid.add_theme_constant_override("h_separation", 8)
			soft_grid.add_theme_constant_override("v_separation", 4)
			card_vbox.add_child(soft_grid)

			soft_grid.add_child(_label("Max uses", 9, C_MUTED))
			var uses_spin = SpinBox.new()
			uses_spin.min_value = 1; uses_spin.max_value = 20
			uses_spin.step = 1; uses_spin.suffix = " grabs"
			uses_spin.value = float(int(md.get("max_uses", 4)))
			uses_spin.custom_minimum_size = Vector2(90, 22)
			var ci4 = i
			uses_spin.value_changed.connect(func(v):
				var cur: Array = _hold_modifiers.get(hold, [])
				if ci4 < cur.size():
					(cur[ci4] as Dictionary)["max_uses"] = int(v)
				_hold_modifiers[hold] = cur
				_sync_modifier_component(hold, cur[ci4])
			)
			soft_grid.add_child(uses_spin)

		if mod_type == "moving":
			var move_vbox = VBoxContainer.new()
			move_vbox.add_theme_constant_override("separation", 4)
			card_vbox.add_child(move_vbox)

			move_vbox.add_child(_label("Click a button, then click the wall to place that point.", 8, C_MUTED))

			var pt_row = HBoxContainer.new()
			pt_row.add_theme_constant_override("separation", 6)
			move_vbox.add_child(pt_row)

			var mi = i
			var set_start_btn = _make_flat_button("Set Start", Vector2(95, 24))
			set_start_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			set_start_btn.pressed.connect(func(): _begin_move_point_placement(hold, mi, "start"))
			pt_row.add_child(set_start_btn)

			var set_end_btn = _make_flat_button("Set End", Vector2(95, 24))
			set_end_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
			set_end_btn.pressed.connect(func(): _begin_move_point_placement(hold, mi, "end"))
			pt_row.add_child(set_end_btn)

			# Live readouts so the designer sees the currently-set points.
			var ro = _label("", 8, C_MUTED)
			ro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ro.custom_minimum_size = Vector2(0, 26)
			move_vbox.add_child(ro)
			_show_move_points(ro, md)

			var spd_row = GridContainer.new()
			spd_row.columns = 2
			spd_row.add_theme_constant_override("h_separation", 8)
			spd_row.add_theme_constant_override("v_separation", 4)
			move_vbox.add_child(spd_row)

			spd_row.add_child(_label("Speed", 9, C_MUTED))
			var speed_spin = SpinBox.new()
			speed_spin.min_value = 10.0; speed_spin.max_value = 600.0
			speed_spin.step = 5.0; speed_spin.suffix = " px/s"
			speed_spin.value = float(md.get("speed", 80.0))
			speed_spin.custom_minimum_size = Vector2(90, 22)
			var ci5 = i
			speed_spin.value_changed.connect(func(v):
				var cur: Array = _hold_modifiers.get(hold, [])
				if ci5 < cur.size():
					(cur[ci5] as Dictionary)["speed"] = v
				_hold_modifiers[hold] = cur
				_sync_modifier_component(hold, cur[ci5])
			)
			spd_row.add_child(speed_spin)


# ── Moving-hold modifier: click-to-place points ────────────────────────────

func _begin_move_point_placement(hold: Node2D, idx: int, key: String):
	if is_testing: return
	_place_move_hold = hold
	_place_move_idx  = idx
	_place_move_key  = key
	_notify("Click on the wall to set the %s point (ESC cancels)" % key)
	_sfx(1.0)

func _cancel_move_point_placement():
	_place_move_hold = null
	_place_move_idx  = -1
	_place_move_key  = ""

func _place_move_point():
	var hold: Node2D = _place_move_hold
	var key: String  = _place_move_key
	if hold == null or not is_instance_valid(hold):
		_cancel_move_point_placement(); queue_redraw(); return

	var pos := _snap(get_global_mouse_position())
	var cur: Array = _hold_modifiers.get(hold, [])
	if _place_move_idx >= 0 and _place_move_idx < cur.size():
		var md: Dictionary = cur[_place_move_idx]
		if key == "start":
			md["start_x"] = pos.x
			md["start_y"] = pos.y
		else:
			md["end_x"] = pos.x
			md["end_y"] = pos.y
		cur[_place_move_idx] = md
		_hold_modifiers[hold] = cur
		_sync_modifier_component(hold, md)
	_cancel_move_point_placement()
	if _props_mod_list and is_instance_valid(_props_mod_list):
		_rebuild_mod_list(_props_mod_list, hold)
	queue_redraw()
	_sfx(1.2)
	_notify("Set %s point" % key)

func _show_move_points(ro: Label, md: Dictionary):
	var sx := float(md.get("start_x", 0.0))
	var sy := float(md.get("start_y", 0.0))
	var ex := float(md.get("end_x", 0.0))
	var ey := float(md.get("end_y", 0.0))
	ro.text = "Start (%d, %d)  →  End (%d, %d)" % [sx, sy, ex, ey]


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
	# Ensure defaults for soft hold if registry didn't supply them
	if type_key == "soft_hold":
		if not default_data.has("max_uses"): default_data["max_uses"] = 4
	# Ensure defaults for moving hold: span a vertical path around the hold.
	# The modifier's serialize() defaults are arbitrary (origin-based), so the
	# start/end points are always anchored to the hold's current position.
	if type_key == "moving":
		if not default_data.has("speed"): default_data["speed"] = 80.0
		if not default_data.has("pause"): default_data["pause"] = false
		if not default_data.has("pause_time"): default_data["pause_time"] = 0.5
		default_data["start_x"] = hold.global_position.x
		default_data["start_y"] = hold.global_position.y - 64.0
		default_data["end_x"]   = hold.global_position.x
		default_data["end_y"]   = hold.global_position.y + 64.0
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
	_props_mod_list = null
	_cancel_move_point_placement()


# ═══════════════════════════════════════════════════════════════════════════
#  FIX 1 — FALLING HOLD MODIFIER  (runtime component management)
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
	if type_key == "soft_hold":
		var registry = get_node_or_null("/root/HoldModifierRegistry")
		if registry:
			var comp = registry.find_modifier(hold, "soft_hold")
			if comp and "max_uses" in comp: comp.max_uses = int(data.get("max_uses", 4))
	if type_key == "moving":
		var registry = get_node_or_null("/root/HoldModifierRegistry")
		if registry:
			var comp = registry.find_modifier(hold, "moving")
			if comp:
				if "start_point" in comp:
					comp.start_point = Vector2(float(data.get("start_x", 0.0)), float(data.get("start_y", 0.0)))
				if "end_point" in comp:
					comp.end_point = Vector2(float(data.get("end_x", 0.0)), float(data.get("end_y", 0.0)))
				if "speed" in comp: comp.speed = float(data.get("speed", 80.0))
				if "pause_at_ends" in comp: comp.pause_at_ends = bool(data.get("pause", false))
				if "pause_time" in comp: comp.pause_time = float(data.get("pause_time", 0.5))

func _attach_falling_modifier(hold: Node2D, data: Dictionary):
	# Remove stale component first
	var old = hold.get_node_or_null(_FALLING_MOD_NODE_NAME)
	if old:
		old.queue_free()

	# If the hold's own script already handles falling via registry, skip.
	if hold.has_method("apply_modifier") and hold.has_method("has_modifier"):
		if not hold.has_modifier("falling"):
			hold.apply_modifier(data)
		return

	var script = load("res://scripts/editor/editor_falling_modifier.gd")
	if script == null:
		push_error("level_editor: Could not load editor_falling_modifier.gd")
		return

	var comp = Node.new()
	comp.name = _FALLING_MOD_NODE_NAME
	comp.set_script(script)
	hold.add_child(comp)
	comp.fall_delay   = float(data.get("fall_delay",   2.2))
	comp.fall_gravity = float(data.get("fall_gravity", 1800.0))


# ═══════════════════════════════════════════════════════════════════════════
#  FIX 2 — ROPE VISUAL
# ═══════════════════════════════════════════════════════════════════════════

func _create_rope_visual():
	_destroy_rope_visual()
	if belayer_position == Vector2.ZERO: return
	if current_discipline not in ["roped", "speed"]: return

	_rope_visual = Line2D.new()
	_rope_visual.name = "RopeVisual"
	_rope_visual.default_color = Color(0.85, 0.72, 0.40, 0.85)
	_rope_visual.width = 3.0
	_rope_visual.z_index = 50
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
		end_pos = anchor + Vector2(0, 400)

	_rope_visual.clear_points()
	var seg := 20
	var sag = clamp(anchor.distance_to(end_pos) * 0.18, 20.0, 300.0)
	for i in range(seg + 1):
		var t := float(i) / float(seg)
		var pt = anchor.lerp(end_pos, t)
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
				if _place_move_key != "":
					_cancel_move_point_placement(); _notify("Point placement cancelled"); return
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
				if _place_move_key != "":
					_place_move_point()
					return
				if props_panel and is_instance_valid(props_panel): _close_props_panel()
				_handle_left_click()
			else:
				if dragging_hold and dragging_hold.global_position != drag_start_position:
					save_undo_state(); update_wall_bounds()
				elif dragging_crashpad and dragging_crashpad.global_position != crashpad_drag_start_position:
					save_undo_state()
				dragging_hold = null; dragging_crashpad = null

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _place_move_key != "":
				_cancel_move_point_placement(); _notify("Point placement cancelled")
				return
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
	if palette_panel and palette_panel.visible:
		if Rect2(palette_panel.global_position, palette_panel.size).has_point(mp): return true
	if props_panel and is_instance_valid(props_panel):
		if Rect2(props_panel.position, props_panel.size).has_point(mp): return true
	return false


# ═══════════════════════════════════════════════════════════════════════════
#  HOLDS
# ═══════════════════════════════════════════════════════════════════════════

func _place_hold(pos: Vector2) -> bool:
	if not selected_hold_type or selected_hold_type not in loaded_scenes: return false

	# FIX 4: hard guard — block placement if hold isn't valid for this wall type
	var registry = get_node_or_null("/root/HoldRegistry")
	if registry and not registry.is_hold_valid_for_wall(selected_hold_type, current_environment):
		_notify("'%s' hold not available on %s walls" % [selected_hold_type, current_environment], true)
		_sfx(0.5)
		return false

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

# ── Dirty tracking ───────────────────────────────────────────────────────────
func _mark_dirty():
	if _suppress_dirty: return
	is_dirty = true
	_update_title_bar()

func _update_title_bar():
	"""Update the editor title / window text to show dirty state."""
	var tag = ("* " if is_dirty else "") + (current_file_name if current_file_name else "New Route")
	DisplayServer.window_set_title("Climbing Simplified – Level Editor: " + tag)
	# Also update the top‑bar filename label if it exists
	if is_instance_valid(_file_label):
		_file_label.text = tag


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
		"Env: %s" % current_environment.capitalize(),
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
			belayer_placement_button.visible = false
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
	_highlight_palette_button("BELAYER", true)
	_notify("Click anywhere to place rope anchor")

func _create_belayer_marker(pos: Vector2):
	_clear_belayer_marker()
	belayer_marker = Node2D.new(); belayer_marker.name = "BelayerMarker"
	belayer_marker.z_index = 100; belayer_marker.global_position = pos
	belayer_position = pos

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

func on_environment_changed(index: int):
	var env = get_node_or_null("/root/EnvironmentConfig")
	if not env: return
	var types = env.get_all_environment_types()
	if index < types.size():
		env.set_environment(types[index])
		# FIX 4: sync current_environment and refresh palette
		current_environment = env.get_environment_name(types[index]).to_lower()
	update_wall_bounds()
	_refresh_hold_palette_for_environment()
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

func _on_time_of_day_changed(index: int):
	# index 0 = Random (-1), 1 = Day (0), 2 = Dusk (1), 3 = Night (2)
	current_time_of_day = index - 1
	# If no wall yet (e.g. during _on_level_open before wall is ready), defer
	if wall and wall.has_method("set_time_of_day"):
		wall.set_time_of_day(current_time_of_day)
	elif is_inside_tree():
		# Try finding a DynamicWall child
		var found_wall = get_node_or_null("Wall")
		if found_wall and found_wall.has_method("set_time_of_day"):
			found_wall.set_time_of_day(current_time_of_day)
	_notify("Time of day: " + TIME_OF_DAY_NAMES[index])

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
		# Moving modifiers: re-capture the base so the path reflects any
		# dragging done in edit mode, then enable simulation.
		var reg := get_node_or_null("/root/HoldModifierRegistry")
		if reg:
			var mcomp = reg.find_modifier(h, "moving")
			if mcomp and mcomp.has_method("rebase"):
				mcomp.rebase()
	MovingHoldModifier.simulate_in_editor = true

	# FIX 2: create rope visual for roped discipline
	if current_discipline in ["roped", "speed"]:
		_create_rope_visual()
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
	for h in holds_container.get_children():
		var comp = h.get_node_or_null(_FALLING_MOD_NODE_NAME)
		if comp and comp.has_method("reset"): comp.reset()
	if is_instance_valid(_speed_timer_node): _speed_timer_node.stop_timer(); _speed_timer_node.start_timer()

func _disable_player_cameras(player: Node):
	for c in player.find_children("*","Camera2D",true,false): c.enabled = false; c.make_current()
	camera.make_current()

func _stop_testing():
	is_testing = false; _speed_fail_pending = false; preview_player_ref = null
	MovingHoldModifier.simulate_in_editor = false
	if is_instance_valid(_speed_timer_node): _speed_timer_node.queue_free()
	_speed_timer_node = null
	var pp = get_node_or_null("PreviewPlayer"); if pp: pp.queue_free()
	for h in holds_container.get_children():
		var comp = h.get_node_or_null(_FALLING_MOD_NODE_NAME)
		if comp: comp.queue_free()
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
		"time_of_day": current_time_of_day,
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
	var saved_grade: String = data.get("grade","VB")
	if grade_dropdown:
		var grades: Array[String] = V_GRADES if current_discipline == "bouldering" else YDS_GRADES
		var idx: int = grades.find(saved_grade); if idx >= 0: grade_dropdown.select(idx); _on_grade_changed(idx)
	if speed_time_input: speed_time_input.value = speed_time_limit
	if "belayer_position" in data and data["belayer_position"]:
		var bd: Dictionary = data["belayer_position"]
		_create_belayer_marker(Vector2(bd.get("x",0), bd.get("y",0)))
	var env: Node = get_node_or_null("/root/EnvironmentConfig")
	if is_instance_valid(env):
		var en: String = data.get("environment","gym")
		var types: Array = env.get_all_environment_types()
		var matched: bool = false
		for i in range(types.size()):
			if env.get_environment_name(types[i]).to_lower() == en.to_lower():
				env.set_environment(types[i])
				current_environment = en   # FIX 4: sync env on paste
				matched = true; break
		if not matched and not types.is_empty():
			env.set_environment(types[0])
			current_environment = env.get_environment_name(types[0]).to_lower()
		_refresh_hold_palette_for_environment()
		update_wall_bounds()
	var lw: int = int(data.get("weather",0)); var li: float = float(data.get("weather_intensity",1.0))
	current_weather = lw; current_weather_intensity = li
	if weather_dropdown: weather_dropdown.select(clamp(lw,0,weather_dropdown.get_item_count()-1)); _on_weather_changed(lw)
	if weather_intensity_slider: weather_intensity_slider.value = li

	# ── Time of day ──────────────────────────────────────────────────────────
	var tod: int = int(data.get("time_of_day", -1))
	current_time_of_day = tod
	if time_of_day_dropdown:
		time_of_day_dropdown.select(tod + 1)
	_on_time_of_day_changed(tod + 1)

	for hd in data["holds"]:
		var tn: String = hd.get("type","JUG")
		if tn not in loaded_scenes: continue
		var hold: Node2D = loaded_scenes[tn].instantiate()
		if hold.has_method("set_hold_type_from_string"): hold.set_hold_type_from_string(tn)
		hold.global_position = Vector2(hd.get("x",0), hd.get("y",0))
		holds_container.add_child(hold); hold.add_to_group("holds"); hold.set_meta("editor_type", tn)
		if "modifiers" in hd and not (hd["modifiers"] as Array).is_empty():
			_hold_modifiers[hold] = (hd["modifiers"] as Array).duplicate(true)
			_refresh_hold_tint(hold)
		if hd.get("custom_spawn", false):
			custom_spawn_hold = hold
			hold.modulate = Color(0.4, 1.0, 0.5)
	if "crashpads" in data and crashpad_scene:
		for cpd in data["crashpads"]:
			var cp: Node2D = crashpad_scene.instantiate()
			cp.global_position = Vector2(cpd.get("x",0), cpd.get("y",0))
			crashpads_container.add_child(cp); cp.add_to_group("crashpads")
	if "wall_polygon" in data and wall and wall.has_method("set_polygon_data"):
		wall.set_polygon_data(data["wall_polygon"])
	update_wall_bounds(); _sfx(1.25); _notify("Route loaded: " + climb_name)


# ═══════════════════════════════════════════════════════════════════════════
#  SAVE / LOAD / NEW
# ═══════════════════════════════════════════════════════════════════════════

func _on_new_level():
	"""Start a fresh empty level — with unsaved‑changes guard."""
	if is_dirty:
		_show_confirm_dialog("Discard unsaved changes and start a new level?", _do_new_level)
	else:
		_do_new_level()

func _do_new_level():
	_on_clear()
	current_file_path = ""
	current_file_name = ""
	is_dirty = false
	_update_title_bar()
	_notify("New level — ready to create!")

func _on_save():
	"""Save.  If never saved, prompt for a name."""
	if current_file_path and not current_file_path.is_empty():
		_save_to_path(current_file_path)
	else:
		_show_save_dialog()

func _on_save_as():
	_show_save_dialog()

func _save_to_path(path: String):
	var data = _build_save_data()
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		_notify("Failed to save level — check permissions", true)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	current_file_path = path
	current_file_name = path.get_file().get_basename()
	is_dirty = false
	_update_title_bar()
	# Refresh level list so the new file appears immediately
	var lm := get_node_or_null("/root/LevelManager")
	if lm: lm.refresh_levels()
	_sfx(1.2)
	_notify("Saved: " + current_file_name)

func _build_save_data() -> Dictionary:
	"""Build the full level dictionary for saving (same structure as clipboard export)."""
	var env_name := "gym"
	var env := get_node_or_null("/root/EnvironmentConfig")
	if env:
		env_name = env.get_current_environment_name().to_lower()
	var data := {
		"name":              climb_name if climb_name != "" else "Unnamed Route",
		"grade":             climb_grade,
		"environment":       env_name,
		"discipline":        current_discipline,
		"weather":           current_weather,
		"weather_intensity": current_weather_intensity,
		"time_of_day":       current_time_of_day,
		"speed_time_limit":  speed_time_limit,
		"holds":             [],
		"crashpads":         [],
		"metadata":          {
			"editor_version": "2.0",
			"creator":        "Level Editor",
		},
	}
	if current_discipline == "roped" and belayer_position != Vector2.ZERO:
		data["belayer_position"] = {"x": belayer_position.x, "y": belayer_position.y}
	if wall and wall.has_method("get_polygon_data"):
		var pd = wall.get_polygon_data()
		if pd: data["wall_polygon"] = pd
	for h in holds_container.get_children():
		var e := {
			"type": get_hold_type(h),
			"x": h.global_position.x,
			"y": h.global_position.y,
		}
		var mods: Array = _hold_modifiers.get(h, [])
		if not mods.is_empty():
			e["modifiers"] = mods.duplicate(true)
		if is_instance_valid(custom_spawn_hold) and h == custom_spawn_hold:
			e["custom_spawn"] = true
		data["holds"].append(e)
	for cp in crashpads_container.get_children():
		data["crashpads"].append({"x": cp.global_position.x, "y": cp.global_position.y})
	return data

func _show_save_dialog():
	"""A small inline dialog that asks for a level name, then saves."""
	_close_level_browser()
	var dim := ColorRect.new()
	dim.name = "SaveDialogDim"
	dim.color = Color(0, 0, 0, 0.50)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_dialog("SaveDialogDim")
	)
	ui_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "SaveDialogPanel"
	panel.custom_minimum_size = Vector2(360, 200)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-180, -100)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	sty.set_border_width_all(1); sty.border_color = C_BORDER
	sty.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sty)
	ui_layer.add_child(panel)

	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	vbox.add_child(_label("SAVE LEVEL", 14, C_TEXT))
	vbox.add_child(_label("Give your route a name:", 11, C_MUTED))

	var name_input := LineEdit.new()
	_style_line_edit(name_input)
	name_input.placeholder_text = "My Awesome Route"
	name_input.text = climb_name if climb_name != "" else ""
	name_input.custom_minimum_size.y = 32
	vbox.add_child(name_input)

	# Overwrite warning
	var warn_label := _label("", 10, C_WARN)
	warn_label.visible = false
	vbox.add_child(warn_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn_row)

	var cancel_btn := _make_flat_button("Cancel", Vector2(90, 30))
	btn_row.add_child(cancel_btn)

	var save_btn := _make_action_button("Save", C_SUCCESS, func(): pass)
	btn_row.add_child(save_btn)

	cancel_btn.pressed.connect(func(): _close_dialog("SaveDialogDim"); _close_dialog("SaveDialogPanel"))

	save_btn.pressed.connect(func():
		var raw := name_input.text.strip_edges()
		if raw.is_empty():
			warn_label.text = "Please enter a name"
			warn_label.visible = true
			return
		# Sanitise filename: keep only safe characters
		var safe_name := ""
		for ch in raw:
			safe_name += ch if ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-" else "_"
		safe_name = safe_name.strip_edges()
		if safe_name.is_empty():
			safe_name = "Unnamed"
		var path := "user://levels/" + safe_name + ".climb"

		# Check overwrite
		if FileAccess.file_exists(path) and path != current_file_path:
			warn_label.text = "Level \"" + safe_name + "\" already exists!\nPress Save again to overwrite it."
			warn_label.visible = true
			# On second press, force overwrite
			save_btn.pressed.connect(func():
				_close_dialog("SaveDialogDim"); _close_dialog("SaveDialogPanel")
				_save_to_path(path)
			, CONNECT_ONE_SHOT)
			return

		_close_dialog("SaveDialogDim"); _close_dialog("SaveDialogPanel")
		_save_to_path(path)
	)

	name_input.focus()
	# Focus the input
	await get_tree().process_frame
	name_input.grab_focus()


func _on_open_level_browser():
	"""Open the level‑browser popup — with unsaved‑changes guard."""
	if is_dirty:
		_show_confirm_dialog("Discard unsaved changes and open a different level?", _open_level_browser_inner)
	else:
		_open_level_browser_inner()

func _open_level_browser_inner():
	_build_level_browser()


# ── Level‑browser popup ──────────────────────────────────────────────────────

var _browser_nodes: Array[Node] = []

func _build_level_browser():
	"""Build a modal level‑browser overlay listing both user and built‑in levels."""
	_close_level_browser()

	var dim := ColorRect.new()
	dim.name = "LbDim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_level_browser()
	)
	ui_layer.add_child(dim)
	_browser_nodes.append(dim)

	var panel := PanelContainer.new()
	panel.name = "LbPanel"
	panel.custom_minimum_size = Vector2(560, 420)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-280, -210)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	sty.set_border_width_all(1); sty.border_color = C_BORDER
	sty.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sty)
	ui_layer.add_child(panel)
	_browser_nodes.append(panel)

	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# ── Header ──────────────────────────────────────────────────────────────
	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)
	var title := _label("OPEN LEVEL", 14, C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var close_btn := _make_flat_button("X", Vector2(28, 28))
	close_btn.pressed.connect(_close_level_browser)
	hdr.add_child(close_btn)

	# ── Tab bar ─────────────────────────────────────────────────────────────
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vbox.add_child(tabs)

	var user_tab := _make_flat_button("My Levels",  Vector2(120, 28))
	var builtin_tab := _make_flat_button("Built‑in", Vector2(120, 28))
	tabs.add_child(user_tab)
	tabs.add_child(builtin_tab)

	# ── Scrollable list ─────────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	vbox.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 4)
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	# ── Populate helper ─────────────────────────────────────────────────────

	var populate_callable := func(which: String):
		for c in list_vbox.get_children(): c.queue_free()
		var lm := get_node_or_null("/root/LevelManager")
		if not lm:
			list_vbox.add_child(_label("LevelManager not available", 11, C_WARN))
			return
		var levels: Array
		if which == "user":
			levels = lm.get_user_levels()
		else:
			levels = lm.get_builtin_levels()
		if levels.is_empty():
			var msg := "You haven't saved any levels yet!" if which == "user" else "No built‑in levels found"
			list_vbox.add_child(_label(msg, 11, C_MUTED))
			if which == "user":
				var hint := _label("  Create a route, then press Save", 10, C_MUTED)
				hint.add_theme_color_override("font_color", Color(C_MUTED.r, C_MUTED.g, C_MUTED.b, 0.6))
				list_vbox.add_child(hint)
			return
		for lvl in levels:
			var row := _build_level_row(lvl, which == "user")
			list_vbox.add_child(row)

	user_tab.pressed.connect(func():
		user_tab.add_theme_color_override("font_color", C_ACCENT)
		builtin_tab.add_theme_color_override("font_color", Color(1,1,1))
		populate_callable.call("user")
	)
	builtin_tab.pressed.connect(func():
		builtin_tab.add_theme_color_override("font_color", C_ACCENT)
		user_tab.add_theme_color_override("font_color", Color(1,1,1))
		populate_callable.call("builtin")
	)

	# Show user levels first
	user_tab.add_theme_color_override("font_color", C_ACCENT)
	populate_callable.call("user")


func _build_level_row(lvl, is_user: bool) -> PanelContainer:
	"""One row in the level browser list."""
	var card := PanelContainer.new()
	var csty := StyleBoxFlat.new()
	csty.bg_color = Color(C_SURFACE.r, C_SURFACE.g, C_SURFACE.b, 0.40)
	csty.set_border_width_all(1); csty.border_color = C_BORDER
	csty.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", csty)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	var mrg := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		mrg.add_theme_constant_override(s, 8)
	card.add_child(mrg)
	mrg.add_child(hbox)

	# Try loading metadata
	var name_str: String = lvl.name
	var grade_str: String = "—"
	var disc_str: String = ""
	var env_str: String = ""
	if lvl.path and FileAccess.file_exists(lvl.path):
		var file := FileAccess.open(lvl.path, FileAccess.READ)
		if file:
			var j := JSON.new()
			if j.parse(file.get_as_text()) == OK:
				var d: Dictionary = j.data
				name_str = d.get("name", lvl.name) as String
				grade_str = d.get("grade", "—") as String
				disc_str = d.get("discipline", "") as String
				env_str = d.get("environment", "") as String

	# Info column
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_lbl := _label(name_str, 12, C_TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(name_lbl)

	var meta_parts: Array[String] = []
	meta_parts.append("Grade: " + grade_str)
	if disc_str:  meta_parts.append(disc_str.capitalize())
	if env_str:   meta_parts.append(env_str.capitalize())
	meta_parts.append(str(lvl.hold_count) + " holds")
	var meta_lbl := _label("   ·   ".join(meta_parts), 9, C_MUTED)
	info_vbox.add_child(meta_lbl)

	# Badge for user levels
	if is_user:
		var badge := _label("user", 8, Color(0.40, 0.70, 0.40, 0.70))
		info_vbox.add_child(badge)

	# Action buttons
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 4)
	btn_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(btn_vbox)

	var open_btn := _make_flat_button("Open", Vector2(64, 24))
	var path_copy = lvl.path
	open_btn.pressed.connect(func():
		_close_level_browser()
		_load_level_from_file(path_copy)
	)
	btn_vbox.add_child(open_btn)

	if is_user:
		var del_btn := _make_flat_button("Del", Vector2(64, 24))
		del_btn.add_theme_color_override("font_color", C_WARN)
		del_btn.add_theme_color_override("font_hover_color", C_WARN)
		var path_copy2 = lvl.path
		del_btn.pressed.connect(func():
			_close_level_browser()
			_show_confirm_dialog("Delete \"" + name_str + "\"? This cannot be undone.", func():
				var lm := get_node_or_null("/root/LevelManager")
				if lm and lm.has_method("delete_user_level"):
					var lvi = lm.get_level_by_path(path_copy2)
					if lvi: lm.delete_user_level(lvi)
					# If this was the current level, reset
					if current_file_path == path_copy2:
						current_file_path = ""
						current_file_name = ""
					_notify("Deleted: " + name_str)
					_sfx(0.6)
			)
		)
		btn_vbox.add_child(del_btn)

	return card


func _close_level_browser():
	"""Remove level‑browser overlay nodes."""
	for n in _browser_nodes:
		if is_instance_valid(n): n.queue_free()
	_browser_nodes.clear()


func _load_level_from_file(path: String) -> bool:
	"""Load a .climb file into the editor (reuses the paste‑logic)."""
	if not FileAccess.file_exists(path):
		_notify("File not found: " + path, true)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		_notify("Could not open file", true)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_notify("Invalid level file", true)
		return false
	file.close()
	var data: Dictionary = json.data
	if not "holds" in data:
		_notify("No holds in level file", true)
		return false

	# ── Clear and load ─────────────────────────────────────────────────────
	_suppress_dirty = true   # prevent dirty spamming during load
	_on_clear()

	climb_name = data.get("name", "")
	if climb_name_input: climb_name_input.text = climb_name

	current_discipline = data.get("discipline", "bouldering")
	speed_time_limit = float(data.get("speed_time_limit", 60.0))
	if discipline_dropdown:
		match current_discipline:
			"bouldering": discipline_dropdown.select(0)
			"roped":      discipline_dropdown.select(1)
			"speed":      discipline_dropdown.select(2)
		_on_discipline_changed(discipline_dropdown.selected)
	var saved_grade: String = data.get("grade", "VB")
	if grade_dropdown:
		var grades: Array[String] = V_GRADES if current_discipline == "bouldering" else YDS_GRADES
		var idx: int = grades.find(saved_grade)
		if idx >= 0: grade_dropdown.select(idx); _on_grade_changed(idx)
	if speed_time_input: speed_time_input.value = speed_time_limit

	if "belayer_position" in data and data["belayer_position"]:
		var bd: Dictionary = data["belayer_position"]
		_create_belayer_marker(Vector2(bd.get("x",0), bd.get("y",0)))

	var env: Node = get_node_or_null("/root/EnvironmentConfig")
	if is_instance_valid(env):
		var en: String = data.get("environment", "gym")
		var types: Array = env.get_all_environment_types()
		var matched: bool = false
		for i in types.size():
			if env.get_environment_name(types[i]).to_lower() == en.to_lower():
				env.set_environment(types[i])
				current_environment = en
				matched = true; break
		if not matched and not types.is_empty():
			env.set_environment(types[0])
			current_environment = env.get_environment_name(types[0]).to_lower()
		_refresh_hold_palette_for_environment()
		update_wall_bounds()

	var lw: int = int(data.get("weather", 0))
	var li: float = float(data.get("weather_intensity", 1.0))
	current_weather = lw; current_weather_intensity = li
	if weather_dropdown:
		weather_dropdown.select(clamp(lw, 0, weather_dropdown.get_item_count() - 1))
		_on_weather_changed(lw)
	if weather_intensity_slider: weather_intensity_slider.value = li

	# ── Time of day ──────────────────────────────────────────────────────────
	var tod: int = int(data.get("time_of_day", -1))
	current_time_of_day = tod
	if time_of_day_dropdown:
		time_of_day_dropdown.select(tod + 1)
	_on_time_of_day_changed(tod + 1)

	for hd in data["holds"]:
		var tn: String = hd.get("type", "JUG")
		if tn not in loaded_scenes: continue
		var hold: Node2D = loaded_scenes[tn].instantiate()
		if hold.has_method("set_hold_type_from_string"):
			hold.set_hold_type_from_string(tn)
		hold.global_position = Vector2(hd.get("x",0), hd.get("y",0))
		holds_container.add_child(hold)
		hold.add_to_group("holds")
		hold.set_meta("editor_type", tn)
		if "modifiers" in hd and not (hd["modifiers"] as Array).is_empty():
			_hold_modifiers[hold] = (hd["modifiers"] as Array).duplicate(true)
			_refresh_hold_tint(hold)
		if hd.get("custom_spawn", false):
			custom_spawn_hold = hold
			hold.modulate = Color(0.4, 1.0, 0.5)

	if "crashpads" in data and crashpad_scene:
		for cpd in data["crashpads"]:
			var cp: Node2D = crashpad_scene.instantiate()
			cp.global_position = Vector2(cpd.get("x",0), cpd.get("y",0))
			crashpads_container.add_child(cp)
			cp.add_to_group("crashpads")

	if "wall_polygon" in data and wall and wall.has_method("set_polygon_data"):
		wall.set_polygon_data(data["wall_polygon"])

	current_file_path = path
	current_file_name = path.get_file().get_basename()
	_suppress_dirty = false
	is_dirty = false
	update_wall_bounds()
	_update_title_bar()
	_sfx(1.25)
	_notify("Loaded: " + current_file_name)
	return true


# ── Confirmation dialog ──────────────────────────────────────────────────────

func _show_confirm_dialog(msg: String, on_confirm: Callable):
	"""A simple yes/no confirmation overlay."""
	_close_confirm_dialog()

	var dim := ColorRect.new()
	dim.name = "ConfirmDim"
	dim.color = Color(0, 0, 0, 0.50)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "ConfirmPanel"
	panel.custom_minimum_size = Vector2(380, 160)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-190, -80)
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	sty.set_border_width_all(1); sty.border_color = C_BORDER
	sty.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sty)
	ui_layer.add_child(panel)

	var margin := MarginContainer.new()
	for s in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(s, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var msg_lbl := _label(msg, 11, C_TEXT)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(btn_row)

	var cancel_btn := _make_flat_button("Cancel", Vector2(100, 30))
	btn_row.add_child(cancel_btn)

	var confirm_btn := _make_action_button("Confirm", C_WARN, func():
		_close_confirm_dialog()
		on_confirm.call()
	)
	btn_row.add_child(confirm_btn)

	cancel_btn.pressed.connect(_close_confirm_dialog)


func _close_confirm_dialog():
	for name in ["ConfirmDim", "ConfirmPanel"]:
		var n := ui_layer.get_node_or_null(name)
		if n and is_instance_valid(n): n.queue_free()


func _close_dialog(name: String):
	var n := ui_layer.get_node_or_null(name)
	if n and is_instance_valid(n): n.queue_free()


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
	_mark_dirty()
	is_dirty = false    # clean — brand new or just cleared
	_update_title_bar()

func _on_back_pressed():
	if is_dirty:
		_show_confirm_dialog("Discard unsaved changes and go back?", func():
			_do_go_back()
		)
	else:
		_do_go_back()

func _do_go_back():
	_stop_testing(); _close_props_panel(); _close_level_browser(); _close_confirm_dialog()
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
	_mark_dirty()

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
	var grid_col  = Color(0.60,0.60,0.70,0.50) if is_night else Color(0.42,0.42,0.48,0.30)
	var major_col = Color(0.62,0.66,0.76,0.55) if is_night else Color(0.46,0.47,0.55,0.38)
	var bdr_col   = Color(0.55,0.75,1.00,0.65) if is_night else C_BORDER

	draw_rect(Rect2(CANVAS_MIN_X, CANVAS_MIN_Y,
		CANVAS_MAX_X-CANVAS_MIN_X, CANVAS_MAX_Y-CANVAS_MIN_Y), bdr_col, false, 2.0)

	var bounds = _get_route_bounds()
	if bounds.valid:
		draw_rect(Rect2(bounds.min, bounds.size), Color(0.30,0.50,0.80, 0.38 if is_night else 0.22), true)
		draw_rect(Rect2(bounds.min, bounds.size), Color(0.40,0.70,1.00, 0.75 if is_night else 0.55), false, 3.0)

	if belayer_position != Vector2.ZERO and not is_testing:
		draw_circle(belayer_position, 15, Color(1,0.5,0,0.25))
		draw_arc(belayer_position, 20, 0, TAU, 32, Color.ORANGE, 2.0)
		var dangle_end = belayer_position + Vector2(0, 120)
		draw_line(belayer_position, dangle_end, Color(0.85,0.72,0.40,0.55), 2.5)

	if is_instance_valid(custom_spawn_hold):
		var sp = custom_spawn_hold.global_position
		draw_circle(sp, 18, Color(0.3,1.0,0.4,0.15))
		draw_arc(sp, 22, 0, TAU, 36, Color(0.3,1.0,0.4,0.80), 2.0)

	for h in holds_container.get_children():
		if _hold_modifiers.has(h) and not (_hold_modifiers[h] as Array).is_empty():
			# Motion path for moving modifiers: line + green start marker + red end marker.
			for md in (_hold_modifiers[h] as Array):
				if (md as Dictionary).get("type", "") == "moving":
					var sp := Vector2(float(md.get("start_x", 0.0)), float(md.get("start_y", 0.0)))
					var ep := Vector2(float(md.get("end_x",   0.0)), float(md.get("end_y",   0.0)))
					draw_line(sp, ep, Color(C_MODIFIER.r, C_MODIFIER.g, C_MODIFIER.b, 0.55), 2.0)
					draw_circle(sp, 6, Color(0.3, 1.0, 0.45, 0.55))
					draw_arc(sp, 9, 0, TAU, 24, Color(0.3, 1.0, 0.45, 0.9), 2.0)
					draw_circle(ep, 6, Color(1.0, 0.4, 0.3, 0.55))
					draw_arc(ep, 9, 0, TAU, 24, Color(1.0, 0.4, 0.3, 0.9), 2.0)
					# Small arrows indicate travel direction.
					var dir := (ep - sp).normalized()
					var mid := sp.lerp(ep, 0.5)
					draw_line(mid, mid + dir * 14.0, Color(1.0, 1.0, 1.0, 0.6), 2.0)
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

	# Major grid lines every 128px (4 cells) for orientation.
	var major_step := grid_size * 4.0
	var mx = sx
	while mx <= ex2: draw_line(Vector2(mx,dy), Vector2(mx,ey), major_col, 1.5); mx += major_step
	var my = sy
	while my <= ey2: draw_line(Vector2(dx,my), Vector2(ex,my), major_col, 1.5); my += major_step

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

	# Minimal card-style toast: dark translucent panel, coloured edge/text only.
	var toast = PanelContainer.new(); toast.name = "Toast"
	toast.custom_minimum_size = Vector2(380, 40)
	toast.position = Vector2(get_viewport_rect().size.x/2.0 - 190.0, ui_bottom)
	var sty = StyleBoxFlat.new()
	sty.bg_color = Color(0.16, 0.09, 0.09, 0.97) if is_error else Color(0.07, 0.11, 0.08, 0.97)
	sty.set_border_width_all(1)
	sty.border_color = Color(1.0, 0.45, 0.4, 0.45) if is_error else Color(0.55, 0.85, 0.62, 0.4)
	sty.set_corner_radius_all(8)
	sty.shadow_color = Color(0, 0, 0, 0.35)
	sty.shadow_size  = 6
	toast.add_theme_stylebox_override("panel", sty)

	var margin = MarginContainer.new()
	for m in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(m, 12)
	toast.add_child(margin)

	var lbl = Label.new(); lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.68) if is_error else Color(0.82, 0.95, 0.85))
	margin.add_child(lbl)
	ui_layer.add_child(toast)

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
	le.add_theme_color_override("placeholder_font_color", Color(0.50, 0.50, 0.56))

func _make_option_button(min_w: int) -> OptionButton:
	var ob = OptionButton.new(); ob.custom_minimum_size = Vector2(min_w, 30)
	_style_option_button(ob); return ob

func _style_option_button(ob: OptionButton):
	ob.add_theme_font_size_override("font_size", 11)
	ob.add_theme_constant_override("arrow_margin", 6)
	ob.add_theme_color_override("font_color", C_TEXT)
	var n = StyleBoxFlat.new()
	n.bg_color = C_SURFACE; n.set_border_width_all(1); n.border_color = C_BORDER
	n.set_corner_radius_all(3); ob.add_theme_stylebox_override("normal", n)

func _make_action_button(text: String, color: Color, cb: Callable) -> Button:
	var btn = Button.new(); btn.text = text; btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", color.lightened(0.25))
	var n = StyleBoxFlat.new(); n.bg_color = C_SURFACE
	n.set_border_width_all(1); n.border_color = C_BORDER; n.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", n)
	var h = StyleBoxFlat.new(); h.bg_color = Color(C_SURFACE.r+0.07,C_SURFACE.g+0.07,C_SURFACE.b+0.07)
	h.set_border_width_all(1); h.border_color = color; h.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", h)
	var p = h.duplicate(); p.bg_color = Color(C_SURFACE.r+0.03,C_SURFACE.g+0.03,C_SURFACE.b+0.03)
	btn.add_theme_stylebox_override("pressed", p)
	btn.pressed.connect(cb); return btn

func _make_flat_button(text: String, min_size: Vector2) -> Button:
	var btn = Button.new(); btn.text = text; btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE; btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_hover_color", C_ACCENT.lightened(0.3))
	var n = StyleBoxFlat.new(); n.bg_color = C_SURFACE
	n.set_border_width_all(1); n.border_color = C_BORDER; n.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", n)
	var h = StyleBoxFlat.new(); h.bg_color = Color(C_SURFACE.r+0.07,C_SURFACE.g+0.07,C_SURFACE.b+0.07)
	h.set_border_width_all(1); h.border_color = C_ACCENT; h.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", h)
	var p = h.duplicate(); p.bg_color = Color(C_SURFACE.r+0.03,C_SURFACE.g+0.03,C_SURFACE.b+0.03)
	btn.add_theme_stylebox_override("pressed", p)
	return btn

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
