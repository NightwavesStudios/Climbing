extends Node2D
class_name RopeSystem

## Top-rope climbing system — visual rope + fall catch
## Designed specifically for character.gd which uses com_velocity / com_position.

@export var rope_color     := Color.BLACK
@export var rope_thickness := 2.5

# ── Rope visual simulation ─────────────────────────────────────────────────
const ROPE_SEGMENTS  := 25
const ROPE_STIFFNESS := 0.95
const GRAVITY        := 50.0
const SEGMENT_DRAG   := 0.95

# ── Fall catch config ──────────────────────────────────────────────────────
@export var fall_trigger_velocity : float = 150.0
@export var rope_stretch_distance : float = 60.0
@export var catch_decel_rate      : float = 12.0
@export var lower_speed           : float = 60.0

# ── Catch state machine ────────────────────────────────────────────────────
enum CatchState { IDLE, FALLING, STRETCHING, HELD }
var catch_state   : CatchState = CatchState.IDLE
var fall_origin_y : float = 0.0
var taut_y        : float = 0.0
var held_y        : float = 0.0
var fall_vel      : float = 0.0

signal player_caught

# ── Belayer body constants (scaled up ~25%) ───────────────────────────────
const LEG_UPPER_LENGTH      := 38.0
const LEG_LOWER_LENGTH      := 35.0
const HIP_DOWN              := 22.0
const HEAD_OFFSET           := -24.0
const LEG_NATURAL_SPLAY_DEG := 12.0

var b_left_hand_joint  := Vector2.ZERO
var b_right_hand_joint := Vector2.ZERO
var b_left_foot_joint  := Vector2.ZERO
var b_right_foot_joint := Vector2.ZERO
var b_left_hand        := Vector2.ZERO
var b_right_hand       := Vector2.ZERO
var b_left_foot        := Vector2.ZERO
var b_right_foot       := Vector2.ZERO

# belayer_facing: smoothed float (+1 = right, -1 = left).
var belayer_facing_right := true
var belayer_facing       : float = 1.0
const FACING_LERP_SPEED  := 5.0

var belayer_lean : float = 0.0
const LEAN_ATTACK := 10.0
const LEAN_DECAY  := 2.5

# ── Lowering animation ─────────────────────────────────────────────────────
var lower_anim_phase : float = 0.0
const LOWER_ANIM_SPEED := 1.8
var _is_lowering       : bool  = false

# ── Idle slack burst system ────────────────────────────────────────────────
var guide_hand_pull      : float = 0.0
var slack_burst_timer    : float = 0.0
var slack_burst_active   : bool  = false
var slack_burst_intensity: float = 0.0
var slack_between_bursts : float = 1.0
const BURST_INTERVAL_MIN := 1.4
const BURST_INTERVAL_MAX := 3.2
const BURST_DURATION     := 0.38
const BURST_MAGNITUDE    := 16.0
const ARM_RETURN_SPEED   := 4.0

# ── Rope state ─────────────────────────────────────────────────────────────
var belayer_position : Vector2 = Vector2.ZERO
var anchor_position  : Vector2 = Vector2.ZERO
var rope_points      : Array[Vector2] = []
var rope_velocities  : Array[Vector2] = []
var is_setup         : bool = false

var player               : Node2D = null
var player_attach_offset : Vector2 = Vector2(0, -10)
var rope_line            : Line2D = null
var rope_line_lower      : Line2D = null   # anchor → climber, drawn BEHIND character

# ── Hold accessors ────────────────────────────────────────────────────────

func _left_hand_hold() -> Area2D:
	if not is_instance_valid(player):
		return null
	var h = player.lh.hold
	if h != null and not is_instance_valid(h):
		player.lh.hold = null
		return null
	return h

func _right_hand_hold() -> Area2D:
	if not is_instance_valid(player):
		return null
	var h = player.rh.hold
	if h != null and not is_instance_valid(h):
		player.rh.hold = null
		return null
	return h

func _has_hand_hold() -> bool:
	return _left_hand_hold() != null or _right_hand_hold() != null

# ═══════════════════════════════════════════════════════════════════════════

func _ready():
	global_position  = Vector2.ZERO
	z_index          = 50

	# Upper rope: belayer hand → anchor (in front of most things)
	rope_line                = Line2D.new()
	rope_line.width          = rope_thickness
	rope_line.default_color  = rope_color
	rope_line.z_index        = 49
	rope_line.top_level      = true
	rope_line.antialiased    = true
	rope_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rope_line.end_cap_mode   = Line2D.LINE_CAP_ROUND
	rope_line.joint_mode     = Line2D.LINE_JOINT_ROUND
	add_child(rope_line)

	# Lower rope: anchor → climber chest (behind the character figure)
	rope_line_lower                  = Line2D.new()
	rope_line_lower.width            = rope_thickness
	rope_line_lower.default_color    = rope_color
	rope_line_lower.z_index          = -1
	rope_line_lower.top_level        = true
	rope_line_lower.antialiased      = true
	rope_line_lower.begin_cap_mode   = Line2D.LINE_CAP_ROUND
	rope_line_lower.end_cap_mode     = Line2D.LINE_CAP_ROUND
	rope_line_lower.joint_mode       = Line2D.LINE_JOINT_ROUND
	add_child(rope_line_lower)

	set_process(true)


func _process(delta):
	if not is_setup or not is_instance_valid(player):
		is_setup = false
		return
	_update_catch(delta)
	update_belayer_animation(delta)
	update_belayer_joints()
	simulate_rope_physics(delta)
	update_rope_visual()
	queue_redraw()

# ═══════════════════════════════════════════════════════════════════════════
## Public setup
# ═══════════════════════════════════════════════════════════════════════════

func setup_rope(belayer_pos: Vector2, player_node: Node2D, anchor_pos: Vector2 = Vector2.ZERO):
	belayer_position = belayer_pos
	player           = player_node
	anchor_position  = anchor_pos if anchor_pos != Vector2.ZERO else find_top_anchor()

	belayer_facing_right = get_player_chest_position().x > anchor_position.x
	belayer_facing       = 1.0 if belayer_facing_right else -1.0
	update_belayer_joints()
	_init_rope_points(get_belayer_guide_hand_world(), anchor_position, get_player_chest_position())

	is_setup          = true
	visible           = true
	if is_instance_valid(rope_line):
		rope_line.visible = true
	if is_instance_valid(rope_line_lower):
		rope_line_lower.visible = true
	catch_state       = CatchState.IDLE

# ═══════════════════════════════════════════════════════════════════════════
## Fall / catch state machine
# ═══════════════════════════════════════════════════════════════════════════

func _update_catch(delta: float):
	if not is_instance_valid(player):
		return
	if not "com_velocity" in player or not "com_position" in player:
		return

	match catch_state:

		CatchState.IDLE:
			if not _has_hand_hold() and player.com_velocity.y >= fall_trigger_velocity:
				catch_state   = CatchState.FALLING
				fall_origin_y = player.com_position.y
				fall_vel      = player.com_velocity.y
				belayer_lean  = 0.0

		CatchState.FALLING:
			var fallen = player.com_position.y - fall_origin_y
			fall_vel    = player.com_velocity.y

			if fallen >= rope_stretch_distance * 0.5 and fall_vel >= fall_trigger_velocity:
				catch_state  = CatchState.STRETCHING
				taut_y       = player.com_position.y
				fall_vel     = player.com_velocity.y
				belayer_lean = 1.0
				emit_signal("player_caught")

			if _has_hand_hold():
				catch_state = CatchState.IDLE

		CatchState.STRETCHING:
			fall_vel = move_toward(fall_vel, 0.0, catch_decel_rate * fall_vel * delta + 40.0 * delta)

			player.com_position.y  += fall_vel * delta
			player.com_velocity     = Vector2.ZERO
			player.body_velocity    = Vector2.ZERO
			player.global_position  = player.com_position + Vector2(0, -player.COM_OFFSET_Y)

			if fall_vel <= 2.0:
				fall_vel    = 0.0
				held_y      = player.com_position.y
				catch_state = CatchState.HELD

		CatchState.HELD:
			if _has_hand_hold():
				catch_state = CatchState.IDLE
				return

			player.com_velocity.y  = minf(player.com_velocity.y, 0.0)
			player.body_velocity.y = minf(player.body_velocity.y, 0.0)

			if Input.is_action_pressed("ui_accept"):
				held_y += lower_speed * delta

			held_y                 = player.com_position.y
			player.com_position.y  = held_y
			player.global_position = player.com_position + Vector2(0, -player.COM_OFFSET_Y)

# ═══════════════════════════════════════════════════════════════════════════
## Belayer animation — lean, facing, lowering phase
# ═══════════════════════════════════════════════════════════════════════════

func update_belayer_animation(delta: float):
	# ── Lean ──────────────────────────────────────────────────────────────────
	var lean_target := 1.0 if catch_state in [CatchState.STRETCHING, CatchState.HELD] else 0.0
	belayer_lean = move_toward(belayer_lean, lean_target,
		(LEAN_ATTACK if lean_target > belayer_lean else LEAN_DECAY) * delta)

	# ── Idle slack bursts ─────────────────────────────────────────────────────
	if catch_state == CatchState.IDLE:
		if not slack_burst_active:
			slack_between_bursts -= delta
			guide_hand_pull = lerp(guide_hand_pull, 0.0, ARM_RETURN_SPEED * delta)
			if slack_between_bursts <= 0.0:
				slack_burst_active    = true
				slack_burst_timer     = BURST_DURATION
				slack_burst_intensity = randf_range(0.55, 1.0)
		else:
			slack_burst_timer -= delta
			guide_hand_pull    = (-sin((1.0 - slack_burst_timer / BURST_DURATION) * PI)
								  * BURST_MAGNITUDE * slack_burst_intensity)
			if slack_burst_timer <= 0.0:
				slack_burst_active   = false
				slack_between_bursts = randf_range(BURST_INTERVAL_MIN, BURST_INTERVAL_MAX)
	else:
		guide_hand_pull = lerp(guide_hand_pull, -BURST_MAGNITUDE * 1.8, 10.0 * delta)

	# ── Smooth facing ─────────────────────────────────────────────────────────
	if is_instance_valid(player):
		belayer_facing_right = get_player_chest_position().x > anchor_position.x
		var target := 1.0 if belayer_facing_right else -1.0
		belayer_facing = lerp(belayer_facing, target, FACING_LERP_SPEED * delta)

	# ── Lowering animation phase ───────────────────────────────────────────────
	_is_lowering = (catch_state == CatchState.HELD
		and Input.is_action_pressed("ui_accept"))
	if _is_lowering:
		lower_anim_phase = fmod(lower_anim_phase + LOWER_ANIM_SPEED * delta, 1.0)
	else:
		lower_anim_phase = lerp(lower_anim_phase, 0.0, 5.0 * delta)

# ═══════════════════════════════════════════════════════════════════════════
## Belayer joints
# ═══════════════════════════════════════════════════════════════════════════

func update_belayer_joints():
	var sm     := belayer_facing
	var lean_y := -belayer_lean * 8.0
	var b      := belayer_position + Vector2(0, lean_y)
	var b_base := belayer_position

	var near_shoulder := b      + Vector2( sm * 10.0, 0.0)
	var far_shoulder  := b      + Vector2(-sm * 10.0, 0.0)
	var near_hip      := b_base + Vector2( sm *  8.0, HIP_DOWN)
	var far_hip       := b_base + Vector2(-sm *  8.0, HIP_DOWN)

	# ── Guide hand ───────────────────────────────────────────────────────────
	var lower_guide_y := 0.0
	var lower_guide_x := 0.0
	if lower_anim_phase > 0.005:
		var cycle     := sin(lower_anim_phase * TAU)
		lower_guide_y  = cycle * 20.0
		lower_guide_x  = abs(cycle) * sm * 5.0

	var pull_offset    := Vector2(lower_guide_x, guide_hand_pull + lower_guide_y)
	b_right_hand_joint  = near_shoulder + Vector2( sm * 10.0, -10.0) + pull_offset * 0.4
	b_right_hand        = near_shoulder + Vector2( sm * 14.0, -26.0) + pull_offset

	# ── Brake hand ───────────────────────────────────────────────────────────
	var lower_brake_y := 0.0
	if lower_anim_phase > 0.005:
		var brake_cycle := sin(lower_anim_phase * TAU + PI)
		lower_brake_y    = brake_cycle * 11.0

	var brake_pull := belayer_lean * 18.0 + lower_brake_y
	b_left_hand_joint  = far_shoulder + Vector2(-sm * 6.0, 14.0 + brake_pull * 0.4)
	b_left_hand        = far_shoulder + Vector2(-sm * 8.0, 28.0 + brake_pull)

	# ── Feet ──────────────────────────────────────────────────────────────────
	var lr := deg_to_rad(LEG_NATURAL_SPLAY_DEG)
	b_right_foot_joint = near_hip + Vector2( sm * LEG_UPPER_LENGTH * sin(lr),        LEG_UPPER_LENGTH * cos(lr))
	b_right_foot       = b_right_foot_joint + Vector2(0, LEG_LOWER_LENGTH)
	b_left_foot_joint  = far_hip  + Vector2(-sm * LEG_UPPER_LENGTH * sin(lr) * 0.7,  LEG_UPPER_LENGTH * cos(lr))
	b_left_foot        = b_left_foot_joint  + Vector2(0, LEG_LOWER_LENGTH)


func get_belayer_guide_hand_world() -> Vector2:
	return b_right_hand

# ═══════════════════════════════════════════════════════════════════════════
## Rope physics
# ═══════════════════════════════════════════════════════════════════════════

func simulate_rope_physics(delta: float):
	if rope_points.size() < 3 or not is_instance_valid(player):
		return

	var belayer_hand := get_belayer_guide_hand_world()
	var player_chest := get_player_chest_position()

	for i in range(1, rope_points.size() - 1):
		rope_velocities[i].y += GRAVITY * delta
		rope_velocities[i]   *= SEGMENT_DRAG
		rope_points[i]       += rope_velocities[i] * delta

	if catch_state == CatchState.FALLING:
		for i in range(1, rope_points.size() - 1):
			rope_velocities[i].y += fall_vel * delta * 0.15
	elif catch_state == CatchState.STRETCHING:
		for i in range(1, rope_points.size() - 1):
			rope_velocities[i].y += fall_vel * delta * 0.25

	for _iter in range(15):
		rope_points[0]                      = belayer_hand
		rope_points[rope_points.size() - 1] = player_chest

		var anchor_index := 0
		var min_dist     := rope_points[0].distance_to(anchor_position)
		for i in range(1, rope_points.size()):
			var d := rope_points[i].distance_to(anchor_position)
			if d < min_dist:
				min_dist     = d
				anchor_index = i
		rope_points[anchor_index] = anchor_position

		var up_seg = belayer_hand.distance_to(anchor_position) / max(1.0, float(anchor_index))
		var dn_seg = anchor_position.distance_to(player_chest) / max(1.0, float(rope_points.size() - anchor_index - 1))

		for i in range(anchor_index):
			var dv := rope_points[i + 1] - rope_points[i]
			var d  := dv.length()
			if d < 0.1:
				continue
			var cv = dv.normalized() * (d - up_seg) * ROPE_STIFFNESS * 0.5
			if i > 0:
				rope_points[i] += cv
			if i + 1 < rope_points.size() - 1 and i + 1 != anchor_index:
				rope_points[i + 1] -= cv

		for i in range(anchor_index, rope_points.size() - 1):
			var dv := rope_points[i + 1] - rope_points[i]
			var d  := dv.length()
			if d < 0.1:
				continue
			var cv = dv.normalized() * (d - dn_seg) * ROPE_STIFFNESS * 0.5
			if i != anchor_index:
				rope_points[i] += cv
			if i + 1 < rope_points.size() - 1:
				rope_points[i + 1] -= cv

	_smooth_rope()


func _smooth_rope():
	if rope_points.size() < 3:
		return
	for i in range(1, rope_points.size() - 1):
		if rope_points[i].distance_to(anchor_position) >= 5.0:
			rope_points[i] = (rope_points[i - 1] * 0.2
							+ rope_points[i]       * 0.6
							+ rope_points[i + 1]   * 0.2)

# ═══════════════════════════════════════════════════════════════════════════
## Rope visual — split at anchor: upper segment in front, lower behind character
# ═══════════════════════════════════════════════════════════════════════════

func update_rope_visual():
	if not is_instance_valid(rope_line) or rope_points.size() < 2:
		return

	# Find the anchor index (same logic as simulate_rope_physics)
	var anchor_index := 0
	var min_dist     := rope_points[0].distance_to(anchor_position)
	for i in range(1, rope_points.size()):
		var d := rope_points[i].distance_to(anchor_position)
		if d < min_dist:
			min_dist     = d
			anchor_index = i

	# Upper segment: belayer hand → anchor  (z_index 49, in front of wall/most things)
	var upper_pts := PackedVector2Array()
	for i in range(anchor_index + 1):
		upper_pts.append(rope_points[i])
	rope_line.points = upper_pts

	# Lower segment: anchor → climber chest  (z_index -1, behind character figure)
	if is_instance_valid(rope_line_lower):
		var lower_pts := PackedVector2Array()
		for i in range(anchor_index, rope_points.size()):
			lower_pts.append(rope_points[i])
		rope_line_lower.points = lower_pts

	# Tint / width based on catch state — applied to both lines
	if catch_state == CatchState.STRETCHING:
		var t = clamp(fall_vel / 400.0, 0.0, 1.0)
		var w = rope_thickness + t * 2.0
		var c := rope_color.darkened(t * 0.35)
		rope_line.width             = w;  rope_line.default_color  = c
		if is_instance_valid(rope_line_lower):
			rope_line_lower.width        = w;  rope_line_lower.default_color = c
	elif catch_state == CatchState.HELD:
		var w := rope_thickness + 0.5
		var c := rope_color.darkened(0.15)
		rope_line.width             = w;  rope_line.default_color  = c
		if is_instance_valid(rope_line_lower):
			rope_line_lower.width        = w;  rope_line_lower.default_color = c
	else:
		rope_line.width             = rope_thickness
		rope_line.default_color     = rope_color
		if is_instance_valid(rope_line_lower):
			rope_line_lower.width        = rope_thickness
			rope_line_lower.default_color = rope_color

# ═══════════════════════════════════════════════════════════════════════════
## Draw
# ═══════════════════════════════════════════════════════════════════════════

func _draw():
	if not is_setup:
		return
	_draw_anchor()
	_draw_belayer_figure()


func _draw_anchor():
	var al := to_local(anchor_position)
	draw_circle(al, 10, Color(0.18, 0.18, 0.18))
	draw_circle(al,  8, Color(0.72, 0.72, 0.72))
	draw_circle(al,  5, Color(0.18, 0.18, 0.18))
	draw_circle(al,  3, Color(0.85, 0.85, 0.85))

# ═══════════════════════════════════════════════════════════════════════════
## Tonal outline helper — mirrors character.gd's _outline_color() exactly
# ═══════════════════════════════════════════════════════════════════════════

func _belayer_outline_color(col: Color) -> Color:
	var lum := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	var r   = lerp(col.r, lum, 0.3 * 0.3)
	var g   = lerp(col.g, lum, 0.3 * 0.3)
	var b   = lerp(col.b, lum, 0.3 * 0.3)
	r = lerp(r, 0.0, 0.25)
	g = lerp(g, 0.0, 0.25)
	b = lerp(b, 0.0, 0.25)
	return Color(r, g, b, 1.0)


func _draw_belayer_figure():
	# ── Palette — matches character.gd exactly ────────────────────────────────
	var skin_color    := Color("#C68642")
	var shirt_color   := Color("#2E4A6B")
	var pants_color   := Color("#1A1A2E")
	var shoe_color    := Color("#d89418ff")
	var harness_color := Color("#E8A020")

	const OW := 5.5   # outline extra width, matching character.gd figure_outline_width

	var sm := belayer_facing

	# ── Local body landmarks ──────────────────────────────────────────────────
	var lean_y      := -belayer_lean * 8.0
	var b           := to_local(belayer_position + Vector2(0, lean_y))
	var b_base      := to_local(belayer_position)

	var head_center := b      + Vector2(0, HEAD_OFFSET)
	var neck        := b      + Vector2(0, HEAD_OFFSET + 16.0)
	var hips        := b_base + Vector2(0, HIP_DOWN)

	var near_shoulder := neck + Vector2( sm * 12.0, 4.0)
	var far_shoulder  := neck + Vector2(-sm * 12.0, 4.0)
	var near_hip      := hips + Vector2( sm *  9.0, 0.0)
	var far_hip       := hips + Vector2(-sm *  9.0, 0.0)

	var lhj := to_local(b_left_hand_joint)
	var lh  := to_local(b_left_hand)
	var rhj := to_local(b_right_hand_joint)
	var rh  := to_local(b_right_hand)
	var lfj := to_local(b_left_foot_joint)
	var lf  := to_local(b_left_foot)
	var rfj := to_local(b_right_foot_joint)
	var rf  := to_local(b_right_foot)

	# Sleeve transition points — matches character.gd's left_sl / right_sl (0.35 lerp)
	var near_sl := near_shoulder.lerp(rhj, 0.35)
	var far_sl  := far_shoulder.lerp(lhj, 0.35)

	# ── Lowering hand highlights ──────────────────────────────────────────────
	var guide_bright := 0.0
	var brake_bright := 0.0
	if lower_anim_phase > 0.005:
		guide_bright = clamp(sin(lower_anim_phase * TAU),       0.0, 1.0)
		brake_bright = clamp(sin(lower_anim_phase * TAU + PI),  0.0, 1.0)

	var rope_hand_color  := skin_color.lerp(harness_color, guide_bright * 0.55)
	var brake_hand_color := skin_color.lerp(harness_color, brake_bright * 0.55)

	# Pre-compute tonal outline colors
	var oc_pants   := _belayer_outline_color(pants_color)
	var oc_shoe    := _belayer_outline_color(shoe_color)
	var oc_shirt   := _belayer_outline_color(shirt_color)
	var oc_harness := _belayer_outline_color(harness_color)
	var oc_skin    := _belayer_outline_color(skin_color)

	# ══════════════════════════════════════════════════════════════════════════
	# PASS 1 — tonal outline (behind fill)
	# ══════════════════════════════════════════════════════════════════════════

	# Far leg
	draw_line(far_hip,  lfj, oc_pants, 12.0 + OW)
	draw_circle(lfj, 5.0 + OW * 0.5, oc_pants)
	draw_line(lfj,      lf,  oc_pants, 11.0 + OW)
	draw_circle(lf,  9.0 + OW * 0.5, oc_shoe)

	# Near leg
	draw_line(near_hip, rfj, oc_pants, 12.0 + OW)
	draw_circle(rfj, 5.0 + OW * 0.5, oc_pants)
	draw_line(rfj,      rf,  oc_pants, 11.0 + OW)
	draw_circle(rf,  9.0 + OW * 0.5, oc_shoe)

	# Torso — hip span + harness strip + shirt body
	draw_line(far_hip,  near_hip,        oc_pants,   17.0 + OW)
	draw_line(far_hip,  near_hip,        oc_harness,  4.0 + OW * 0.5)
	draw_line(hips,     b,               oc_shirt,   19.0 + OW)
	draw_line(b,        neck,            oc_shirt,   17.0 + OW)

	# Far arm (brake hand) — shirt sleeve → skin forearm
	draw_circle(far_shoulder,  5.0 + OW * 0.5, oc_shirt)
	draw_line(far_shoulder,  far_sl,  oc_shirt, 12.0 + OW)
	draw_line(far_sl,        lhj,     oc_skin,  12.0 + OW)
	draw_circle(lhj, 5.0 + OW * 0.5, oc_skin)
	draw_line(lhj,   lh,  oc_skin,   10.0 + OW)
	draw_circle(lh,  8.0 + OW * 0.5, _belayer_outline_color(brake_hand_color))

	# Near arm (rope/guide hand) — shirt sleeve → skin forearm
	draw_circle(near_shoulder, 5.0 + OW * 0.5, oc_shirt)
	draw_line(near_shoulder, near_sl, oc_shirt, 12.0 + OW)
	draw_line(near_sl,       rhj,     oc_skin,  12.0 + OW)
	draw_circle(rhj, 5.0 + OW * 0.5, oc_skin)
	draw_line(rhj,   rh,  oc_skin,   10.0 + OW)
	draw_circle(rh,  8.0 + OW * 0.5, _belayer_outline_color(rope_hand_color))

	# Head + neck connector
	draw_line(head_center + Vector2(0, 14.0), head_center + Vector2(0, 4.0), oc_skin, 10.0 + OW)
	draw_circle(head_center, 16.0 + OW * 0.5, oc_skin)

	# ══════════════════════════════════════════════════════════════════════════
	# PASS 2 — color fill (on top)
	# ══════════════════════════════════════════════════════════════════════════

	# Far leg
	draw_line(far_hip,  lfj, pants_color, 12.0)
	draw_circle(lfj,    5.0, pants_color)
	draw_line(lfj,      lf,  pants_color, 11.0)
	draw_circle(lf,     9.0, shoe_color)

	# Near leg
	draw_line(near_hip, rfj, pants_color, 12.0)
	draw_circle(rfj,    5.0, pants_color)
	draw_line(rfj,      rf,  pants_color, 11.0)
	draw_circle(rf,     9.0, shoe_color)

	# Torso — hip harness strip + shirt body
	draw_line(far_hip,  near_hip,  pants_color,   17.0)
	draw_line(far_hip,  near_hip,  harness_color,  4.0)
	draw_line(hips,     b,         shirt_color,   19.0)
	draw_line(b,        neck,      shirt_color,   17.0)

	# Far arm (brake hand) — shirt sleeve → skin forearm
	draw_circle(far_shoulder, 5, shirt_color)
	draw_line(far_shoulder, far_sl,  shirt_color, 12.0)
	draw_line(far_sl,       lhj,     skin_color,  12.0)
	draw_circle(lhj, 5, skin_color)
	draw_line(lhj,   lh,  skin_color,  10.0)
	draw_circle(lh,  8, brake_hand_color)

	# Near arm (rope/guide hand) — shirt sleeve → skin forearm
	draw_circle(near_shoulder, 5, shirt_color)
	draw_line(near_shoulder, near_sl, shirt_color, 12.0)
	draw_line(near_sl,       rhj,     skin_color,  12.0)
	draw_circle(rhj, 5, skin_color)
	draw_line(rhj,   rh,  skin_color,  10.0)
	draw_circle(rh,  8, rope_hand_color)

	# Head + neck connector
	draw_line(head_center + Vector2(0, 14.0), head_center + Vector2(0, 4.0), skin_color, 10.0)
	draw_circle(head_center, 16, skin_color)

# ═══════════════════════════════════════════════════════════════════════════
## Anchor lookup
# ═══════════════════════════════════════════════════════════════════════════

func find_top_anchor() -> Vector2:
	var anchor_x := player.global_position.x if is_instance_valid(player) else 0.0
	for wall in get_tree().get_nodes_in_group("environment_walls"):
		if wall.has_method("get_anchor_position_for_x"):
			return wall.get_anchor_position_for_x(anchor_x)
	return _find_highest_hold_anchor()


func _find_highest_hold_anchor() -> Vector2:
	var best_y   := INF
	var best_pos := (belayer_position + Vector2(0, -200.0)) if belayer_position != Vector2.ZERO \
				 else Vector2(0.0, -200.0)
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.global_position.y < best_y:
			best_y   = hold.global_position.y
			best_pos = hold.global_position
	return best_pos + Vector2(0, -30.0)

# ═══════════════════════════════════════════════════════════════════════════

func get_player_chest_position() -> Vector2:
	if is_instance_valid(player):
		return player.global_position + player_attach_offset
	return belayer_position + Vector2(0, 100)


func _init_rope_points(from: Vector2, mid: Vector2, to: Vector2):
	rope_points.clear()
	rope_velocities.clear()
	var path      := [from, mid, to]
	var total_len := 0.0
	for i in range(path.size() - 1):
		total_len += path[i].distance_to(path[i + 1])
	var seg_len := total_len / float(ROPE_SEGMENTS - 1)
	var cs  := 0
	var dis := 0.0
	var ss  = path[0]
	var se  = path[1]
	var sl  = ss.distance_to(se)
	for i in range(ROPE_SEGMENTS):
		var td := i * seg_len
		while td > dis + sl and cs < path.size() - 2:
			dis += sl
			cs  += 1
			ss   = path[cs]
			se   = path[cs + 1]
			sl   = ss.distance_to(se)
		var t = (td - dis) / sl if sl > 0.0 else 0.0
		rope_points.append(ss.lerp(se, t))
		rope_velocities.append(Vector2.ZERO)


func cleanup():
	is_setup = false
	set_process(false)
	set_physics_process(false)
	# Free the Line2D children we own — but do NOT free ourselves.
	# The parent (main_scene) is responsible for removing us from the tree
	# and calling .free() directly, which avoids the deferred-free race.
	if is_instance_valid(rope_line):
		rope_line.queue_free()
		rope_line = null
	if is_instance_valid(rope_line_lower):
		rope_line_lower.queue_free()
		rope_line_lower = null
