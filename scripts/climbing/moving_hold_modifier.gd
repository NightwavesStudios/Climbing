class_name MovingHoldModifier
extends HoldModifierBase
## Moving Hold Modifier
##
## The hold shuttles back and forth in a straight line between two points
## (start_point and end_point) at a fixed speed, looping forever. The whole
## hold — collision and visuals — moves, so the climber has to time their
## grabs and can be carried along while holding on.
##
## Points are stored as ABSOLUTE world coordinates (the two points the user
## clicks in the level editor). During simulation the hold's visual root is
## placed on the straight line between them, ping-ponging end-to-end.

# ── Tunable parameters ────────────────────────────────────────────────────
## World-space point the hold starts at / returns to.
var start_point: Vector2 = Vector2(0, -64)
## World-space point the hold travels to.
var end_point: Vector2 = Vector2(0, 64)
## Movement speed in pixels per second.
var speed: float = 80.0
## If true, the hold pauses briefly at each end of the path.
var pause_at_ends: bool = false
## Seconds to pause at each end when pause_at_ends is true.
var pause_time: float = 0.5

# ── Internal state ────────────────────────────────────────────────────────
var _time: float = 0.0
var _visual_root_cache: Node2D = null
## -1 = unknown, 0 = standalone game, 1 = inside the level editor scene.
var _editor_context: int = -1

# Editor integration: when the level editor is live (not in the exported
# game), the editor toggles this flag so the hold only moves while the
# designer is testing the route, not while they are dragging/editing it.
static var simulate_in_editor: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	modifier_type = "moving"
	super._ready()

func _compute_visual_root() -> Node2D:
	if hold == null:
		return null
	var parent = hold.get_parent()
	if parent is Node2D and parent.get_script() == null:
		return parent as Node2D
	return hold

func _get_visual_root() -> Node2D:
	if _visual_root_cache != null and is_instance_valid(_visual_root_cache):
		return _visual_root_cache
	return hold

func on_hold_ready() -> void:
	_visual_root_cache = _compute_visual_root()
	# Snap the hold onto the path immediately so it doesn't sit at its spawn
	# position for a frame before the first on_process() tick. Gated on
	# simulation so attaching the modifier in the editor does NOT displace the
	# hold while the designer is still editing it.
	if hold != null and hold.is_inside_tree() and _should_simulate():
		_snap_to_start()

## Re-capture the visual root and snap the hold to the start point. Called by
## the level editor when entering test mode so the path reflects any dragging
## the designer did in edit mode.
func rebase() -> void:
	if hold == null or not is_instance_valid(hold):
		return
	_visual_root_cache = _compute_visual_root()
	_time = 0.0
	_snap_to_start()

# ── Per-frame ─────────────────────────────────────────────────────────────

func on_process(delta: float) -> void:
	if not _should_simulate():
		return
	_time += delta

	var span := end_point - start_point
	var dist := span.length()
	if dist <= 0.001:
		# Degenerate path — hold just sits on the start point.
		if _get_visual_root() != null:
			_get_visual_root().global_position = start_point
		return

	var travel_time := dist / maxf(speed, 0.001)

	if pause_at_ends:
		# One leg = dwell at one end + travel to the other end.
		var leg := travel_time + pause_time
		var phase := _time / leg
		var lt := fposmod(phase, 1.0)          # 0..1 within current leg
		var leg_idx := int(floor(phase))       # even leg → toward end, odd → toward start
		var t_in_leg := lt * leg               # 0..leg seconds within the leg
		var k_raw := clampf((t_in_leg - pause_time) / travel_time, 0.0, 1.0)
		var k: float = k_raw if leg_idx % 2 == 0 else 1.0 - k_raw
		_get_visual_root().global_position = start_point.lerp(end_point, k)
	else:
		var cycle := _time / travel_time
		var tri := fposmod(cycle, 2.0)
		var k := tri if tri <= 1.0 else 2.0 - tri
		_get_visual_root().global_position = start_point.lerp(end_point, k)

func _snap_to_start() -> void:
	if _get_visual_root() != null:
		_get_visual_root().global_position = start_point

# ── Simulation gating ─────────────────────────────────────────────────────

func _should_simulate() -> bool:
	if _editor_context == -1:
		var tree := get_tree()
		if tree == null:
			return false
		# If the level editor is present in the tree, we're in the editor
		# context and only move when the editor tells us it is testing.
		_editor_context = 1 if tree.root.find_child("LevelEditor", true, false) != null else 0
	if _editor_context == 1:
		return simulate_in_editor
	# Standalone game — always simulate.
	return true

# ── Reset hooks ───────────────────────────────────────────────────────────

func on_climb_reset() -> void:
	_time = 0.0
	_snap_to_start()

func on_caught_reset() -> void:
	_time = 0.0
	_snap_to_start()

# ── Serialization ─────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"type":       "moving",
		"start_x":    start_point.x,
		"start_y":    start_point.y,
		"end_x":      end_point.x,
		"end_y":      end_point.y,
		"speed":      speed,
		"pause":      pause_at_ends,
		"pause_time": pause_time,
	}

func deserialize(data: Dictionary) -> void:
	start_point = Vector2(
		float(data.get("start_x", start_point.x)),
		float(data.get("start_y", start_point.y)))
	end_point = Vector2(
		float(data.get("end_x", end_point.x)),
		float(data.get("end_y", end_point.y)))
	speed = float(data.get("speed", speed))
	pause_at_ends = bool(data.get("pause", pause_at_ends))
	pause_time = float(data.get("pause_time", pause_time))