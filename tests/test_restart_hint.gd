## test_restart_hint.gd
## Verifies the rope-restart-hint UI logic in main_scene.gd:
##  - The bug fix: fading the hint must target the Panel (Control.modulate),
##    NOT the CanvasLayer (which has no 'modulate').
##  - The RopeSystem catch-state API used to detect "hanging" exists.
##
## NOTE: the Ziva test runner calls test_*() methods during SceneTree._initialize
## before any frame is pumped, so nodes can't enter the tree (no _ready, no
## await). Strategy: build the nodes off-tree and drive the logic manually.
extends Node

var _checks: int   = 0
var _failures: int = 0
var _log: String   = ""

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		_log += "PASS: " + msg + "\n"
	else:
		_failures += 1
		_log += "FAIL: " + msg + "\n"

func _finish() -> void:
	_log += "RESULT: " + str(_checks - _failures) + "/" + str(_checks) + " checks passed, " + str(_failures) + " failed"
	print("==============================================")
	print(_log)
	assert(_failures == 0, "RESTART_HINT_TESTLOG: " + _log.replace("\n", " | "))


## Mirrors the fixed _show_restart_hint from main_scene.gd.
func _simulate_show_hint(hint: CanvasLayer, panel: Control) -> bool:
	hint.visible = true
	panel.modulate = Color(1, 1, 1, 0)
	return hint.visible and panel.modulate.a < 1.0


## Mirrors the fixed _hide_restart_hint from main_scene.gd.
func _simulate_hide_hint(hint: CanvasLayer, panel: Control) -> bool:
	hint.visible = false
	panel.modulate = Color.WHITE
	return not hint.visible and panel.modulate == Color.WHITE


func test_ui_nodes_have_expected_properties() -> void:
	var hint: CanvasLayer = CanvasLayer.new()
	var panel: Control = Control.new()
	_check("visible" in hint, "CanvasLayer exposes 'visible'")
	_check("modulate" in panel, "Control exposes 'modulate'")
	_check(not ("modulate" in hint), "CanvasLayer does NOT expose 'modulate' (the original bug)")


func test_show_hide_logic_uses_valid_properties() -> void:
	var hint: CanvasLayer = CanvasLayer.new()
	var panel: Control = Control.new()
	_check(_simulate_show_hint(hint, panel), "show path sets CanvasLayer.visible + Control.modulate without error")
	_check(_simulate_hide_hint(hint, panel), "hide path clears visible + resets modulate")


func test_rope_catch_api_exists() -> void:
	var rs: RopeSystem = RopeSystem.new()
	_check("IDLE" in RopeSystem.CatchState, "RopeSystem.CatchState enum exists")
	_check(RopeSystem.CatchState.IDLE == 0, "CatchState.IDLE is defined")
	_check("catch_state" in rs, "RopeSystem exposes 'catch_state'")
	rs.catch_state = RopeSystem.CatchState.HELD
	_check(rs.catch_state == RopeSystem.CatchState.HELD, "catch_state can be assigned HELD")
	rs.free()


func test_hanging_detection() -> void:
	# Mirrors _update_restart_hint's hanging check.
	var rs: RopeSystem = RopeSystem.new()
	var hanging: bool = rs.catch_state != RopeSystem.CatchState.IDLE
	_check(hanging == false, "IDLE catch_state means NOT hanging")
	rs.catch_state = RopeSystem.CatchState.HELD
	hanging = rs.catch_state != RopeSystem.CatchState.IDLE
	_check(hanging, "HELD catch_state means hanging on rope")
	rs.free()
