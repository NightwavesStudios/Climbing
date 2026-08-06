## test_level_editor.gd
## Headless verification of the revamped level editor.
## NOTE: the Ziva test runner calls test_*() methods during SceneTree._initialize
## before any frame is pumped, so nodes can't enter the tree (no _ready, no await).
## Strategy: build the editor UI directly, drive its pure functions manually, and
## validate the environment→palette rule via the live HoldRegistry autoload.
extends Node

var _checks: int = 0
var _failures: int = 0
var _log: String = ""

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		_log += "PASS: " + msg + "\n"
	else:
		_failures += 1
		_log += "FAIL: " + msg + "\n"

func test_editor_core() -> void:
	var st := _tree()
	var packed: PackedScene = load("res://scenes/editor/level_editor.tscn")
	_check(packed != null, "editor scene loads")
	if packed == null:
		return

	var editor: Node2D = packed.instantiate()
	editor.wall = editor.get_node_or_null("Wall")
	editor.holds_container = editor.get_node_or_null("Holds")
	editor.crashpads_container = editor._get_or_create_node2d("Crashpads")
	editor.preview_container = editor._get_or_create_node2d("PreviewContainer")
	editor._setup_audio()

	# Simulate the hold-scene loading that normally happens in _ready().
	for t in editor.HOLD_SCENES:
		if ResourceLoader.exists(editor.HOLD_SCENES[t]):
			editor.loaded_scenes[t] = load(editor.HOLD_SCENES[t])

	# ── 1. UI construction ─────────────────────────────────────────────
	editor._build_ui()
	_check(editor.ui_layer != null, "UI CanvasLayer built")
	_check(editor.palette_panel != null and editor.palette_panel.visible, "palette panel exists and visible")
	_check(editor.info_label != null, "info bar label exists")
	_check(editor.fold_button != null, "More drawer button exists")
	_check(editor.palette_buttons.has("JUG"), "palette has JUG button")
	_check(editor.palette_buttons.has("CRASHPAD"), "palette has CRASHPAD button")
	_check(editor.palette_buttons.has("BELAYER"), "palette has BELAYER button")
	_check(editor.crashpad_button != null and editor.belayer_placement_button != null,
		"crashpad + belayer buttons exist")

	# Top bar contents (Back button must be present and prominent).
	var back_found: bool = false
	var margin: MarginContainer = editor.ui_layer.get_child(2) as MarginContainer
	if margin:
		var top_hbox: HBoxContainer = margin.get_child(0) as HBoxContainer
		if top_hbox:
			for c in top_hbox.get_children():
				if c is Button and (c as Button).text.contains("Back"):
					back_found = true
	_check(back_found, "top bar has a visible ← Back button (not hidden in drawer)")

	# ── 2. Environment → palette rule (via live HoldRegistry autoload) ─
	var reg: Node = st.root.get_node_or_null("HoldRegistry")
	if reg:
		_check(not reg.is_hold_valid_for_wall("WINDOW", "gym"), "WINDOW invalid on gym wall (hidden from palette)")
		_check(reg.is_hold_valid_for_wall("JUG", "gym"), "JUG valid on gym wall")
		_check(reg.is_hold_valid_for_wall("WINDOW", "building"), "WINDOW valid on building wall (shown)")
		_check(not reg.is_hold_valid_for_wall("WINDOW", "ice"), "WINDOW invalid on ice wall (hidden)")
	else:
		_check(false, "HoldRegistry autoload present")

	# ── 3. Palette selection + styling ─────────────────────────────────
	editor._on_palette_type_selected("JUG")
	_check(editor.selected_hold_type == "JUG", "palette click selects JUG")
	var jug_btn: Button = editor.palette_buttons["JUG"]
	var jug_stripe := jug_btn.get_node_or_null("Stripe") as ColorRect
	var highlighted: bool = jug_stripe != null and jug_stripe.color.a > 0.8
	_check(highlighted, "JUG button highlighted when selected")

	# ── 4. Hold placement + wall render ────────────────────────────────
	var before: int = editor.holds_container.get_child_count()
	var placed: bool = editor._place_hold(editor._snap(Vector2(600.0, 300.0)))
	var after: int = editor.holds_container.get_child_count()
	_check(placed, "placing a hold returns true")
	_check(after == before + 1, "placing a hold adds one node (before=" + str(before) + ", after=" + str(after) + ")")
	editor.update_wall_bounds()
	_check(editor.wall.wall_valid == true, "wall becomes valid (renders) after holds placed")
	editor._update_info_label()
	_check(editor.info_label.text.contains("Holds: 1"), "info bar shows Holds: 1 (text: " + editor.info_label.text + ")")

	# ── 5. Deletion ────────────────────────────────────────────────────
	if after > before:
		var last: Node = editor.holds_container.get_child(editor.holds_container.get_child_count() - 1)
		editor._delete_hold(last)
		# queue_free() only completes at end of frame, which this harness never
		# pumps — simulate frame-end removal so the count reflects deletion.
		if is_instance_valid(last) and last.get_parent() == editor.holds_container:
			editor.holds_container.remove_child(last)
		editor.update_wall_bounds()
		_check(editor.holds_container.get_child_count() == before, "deleting hold restores count")
		_check(editor.wall.wall_valid == false, "wall invalid again with 0 holds")

	# ── 6. Info bar content sanity ─────────────────────────────────────
	var txt: String = editor.info_label.text.to_lower()
	_check(txt.contains("env:"), "info bar mentions environment (text: '" + editor.info_label.text + "')")

	_log += "RESULT: " + str(_checks - _failures) + "/" + str(_checks) + " checks passed, " + str(_failures) + " failed"
	print("==============================================")
	print(_log)
	assert(_failures == 0, "LEDITOR_TESTLOG: " + _log.replace("\n", " | "))
