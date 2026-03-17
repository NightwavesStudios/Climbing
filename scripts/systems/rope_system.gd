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
## Downward com_velocity (px/s) that triggers fall tracking (hands off holds)
@export var fall_trigger_velocity : float = 150.0
## Extra pixels player travels downward after rope goes taut before stopping
@export var rope_stretch_distance : float = 60.0
## How quickly the player decelerates once rope is taut (lower = more gradual)
@export var catch_decel_rate      : float = 12.0
## Speed (px/s) at which the player lowers themselves when holding Space
@export var lower_speed           : float = 60.0

# ── Catch state machine ────────────────────────────────────────────────────
# IDLE      → climbing normally, no fall
# FALLING   → hands off, tracking downward travel, waiting for rope to go taut
# STRETCHING→ rope taut, player still moving down but decelerating
# HELD      → fully stopped, locked in place forever until reset

enum CatchState { IDLE, FALLING, STRETCHING, HELD }
var catch_state     : CatchState = CatchState.IDLE
var fall_origin_y   : float = 0.0   # com_position.y when hands first left holds
var taut_y          : float = 0.0   # com_position.y when rope went taut
var held_y          : float = 0.0   # final locked com_position.y
var fall_vel        : float = 0.0   # current downward velocity during fall/stretch

signal player_caught

# ── Belayer body constants ─────────────────────────────────────────────────
const LEG_UPPER_LENGTH      := 30.0
const LEG_LOWER_LENGTH      := 28.0
const HIP_DOWN              := 18.0
const HEAD_OFFSET           := -18.0
const LEG_NATURAL_SPLAY_DEG := 12.0

var b_left_hand_joint  := Vector2.ZERO
var b_right_hand_joint := Vector2.ZERO
var b_left_foot_joint  := Vector2.ZERO
var b_right_foot_joint := Vector2.ZERO
var b_left_hand        := Vector2.ZERO
var b_right_hand       := Vector2.ZERO
var b_left_foot        := Vector2.ZERO
var b_right_foot       := Vector2.ZERO

var belayer_facing_right := true
var belayer_lean         : float = 0.0
const LEAN_ATTACK := 10.0
const LEAN_DECAY  := 2.5

# ── Slack burst system ─────────────────────────────────────────────────────
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

# ═══════════════════════════════════════════════════════════════════════════
func _ready():
	global_position = Vector2.ZERO
	z_index = 50

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
	set_process(true)

func _process(delta):
	if not is_setup or not player:
		return
	_update_catch(delta)
	update_belayer_joints()
	simulate_rope_physics(delta)
	update_rope_visual()
	update_belayer_animation(delta)
	queue_redraw()

# ═══════════════════════════════════════════════════════════════════════════
## Public setup
# ═══════════════════════════════════════════════════════════════════════════

func setup_rope(belayer_pos: Vector2, player_node: Node2D, anchor_pos: Vector2 = Vector2.ZERO):
	belayer_position = belayer_pos
	player           = player_node
	anchor_position  = anchor_pos if anchor_pos != Vector2.ZERO else find_top_anchor()

	belayer_facing_right = get_player_chest_position().x > anchor_position.x
	update_belayer_joints()
	_init_rope_points(get_belayer_guide_hand_world(), anchor_position, get_player_chest_position())

	is_setup          = true
	visible           = true
	rope_line.visible = true
	catch_state       = CatchState.IDLE

# ═══════════════════════════════════════════════════════════════════════════
## Fall / catch state machine
# ═══════════════════════════════════════════════════════════════════════════

func _update_catch(delta: float):
	if not "com_velocity" in player or not "com_position" in player:
		return

	match catch_state:

		CatchState.IDLE:
			# Both hands must be off holds AND player falling fast enough
			var no_hands : bool = (player.left_hand_hold == null and player.right_hand_hold == null)
			if no_hands and player.com_velocity.y >= fall_trigger_velocity:
				catch_state  = CatchState.FALLING
				fall_origin_y = player.com_position.y
				fall_vel     = player.com_velocity.y
				belayer_lean = 0.0

		CatchState.FALLING:
			# Player is in freefall — let character.gd drive physics normally.
			# We just watch com_velocity and wait for it to peak (rope going taut).
			# The rope "goes taut" when the player has fallen a meaningful distance.
			var fallen = player.com_position.y - fall_origin_y
			fall_vel   = player.com_velocity.y

			# Rope goes taut once the player has fallen enough downward distance
			# and is still moving fast — gives the visual of slack paying out first.
			if fallen >= rope_stretch_distance * 0.5 and fall_vel >= fall_trigger_velocity:
				catch_state  = CatchState.STRETCHING
				taut_y       = player.com_position.y
				fall_vel     = player.com_velocity.y
				belayer_lean = 1.0
				emit_signal("player_caught")

			# Safety: if player somehow re-grabbed, reset
			if player.left_hand_hold != null or player.right_hand_hold != null:
				catch_state = CatchState.IDLE

		CatchState.STRETCHING:
			# Rope is taut — we take over player movement and decelerate them.
			# Player continues moving down by fall_vel but it bleeds off fast.
			fall_vel = move_toward(fall_vel, 0.0, catch_decel_rate * fall_vel * delta + 40.0 * delta)

			# Move com_position down by remaining velocity
			player.com_position.y  += fall_vel * delta
			player.com_velocity     = Vector2.ZERO
			player.body_velocity    = Vector2.ZERO
			player.global_position  = player.com_position + Vector2(0, -player.COM_OFFSET_Y)

			# Once velocity is basically zero, lock permanently
			if fall_vel <= 2.0:
				fall_vel    = 0.0
				held_y      = player.com_position.y
				catch_state = CatchState.HELD

		CatchState.HELD:
			# Allow normal limb movement and body pull from holds —
			# only suppress free gravity fall, not intentional climbing movement.
			# If the player has grabbed holds, let character.gd pull the body up normally.
			var has_hold = (player.left_hand_hold != null or player.right_hand_hold != null)
			if has_hold:
				# Let character.gd fully take over — exit held state so body can move
				catch_state = CatchState.IDLE
				return

			# No holds — clamp downward velocity only (allow upward, block falling further)
			player.com_velocity.y  = minf(player.com_velocity.y, 0.0)
			player.body_velocity.y = minf(player.body_velocity.y, 0.0)

			# Lowering: hold Space (or your preferred key) to slowly lower down the rope
			if Input.is_action_pressed("ui_accept"):
				held_y += lower_speed * delta
			# Keep held_y current so re-entering HELD after a micro-movement doesn't snap
			held_y = player.com_position.y
			player.com_position.y  = held_y
			player.global_position = player.com_position + Vector2(0, -player.COM_OFFSET_Y)

# ═══════════════════════════════════════════════════════════════════════════
## Belayer joints
# ═══════════════════════════════════════════════════════════════════════════

func update_belayer_joints():
	var sm     = 1.0 if belayer_facing_right else -1.0
	var lean_y = -belayer_lean * 8.0
	var b      = belayer_position + Vector2(0, lean_y)
	var b_base = belayer_position

	var near_shoulder = b      + Vector2( sm * 8.0, 0.0)
	var far_shoulder  = b      + Vector2(-sm * 8.0, 0.0)
	var near_hip      = b_base + Vector2( sm * 6.0, HIP_DOWN)
	var far_hip       = b_base + Vector2(-sm * 6.0, HIP_DOWN)

	var pull_offset    = Vector2(0.0, guide_hand_pull)
	b_right_hand_joint = near_shoulder + Vector2( sm * 8.0,  -8.0)  + pull_offset * 0.4
	b_right_hand       = near_shoulder + Vector2( sm * 12.0, -22.0) + pull_offset

	var brake_pull    = belayer_lean * 18.0
	b_left_hand_joint = far_shoulder + Vector2(-sm * 5.0, 14.0 + brake_pull * 0.4)
	b_left_hand       = far_shoulder + Vector2(-sm * 7.0, 26.0 + brake_pull)

	var lr = deg_to_rad(LEG_NATURAL_SPLAY_DEG)
	b_right_foot_joint = near_hip + Vector2( sm * LEG_UPPER_LENGTH * sin(lr),        LEG_UPPER_LENGTH * cos(lr))
	b_right_foot       = b_right_foot_joint + Vector2(0, LEG_LOWER_LENGTH)
	b_left_foot_joint  = far_hip  + Vector2(-sm * LEG_UPPER_LENGTH * sin(lr) * 0.7,  LEG_UPPER_LENGTH * cos(lr))
	b_left_foot        = b_left_foot_joint  + Vector2(0, LEG_LOWER_LENGTH)

func get_belayer_guide_hand_world() -> Vector2:
	return b_right_hand

# ═══════════════════════════════════════════════════════════════════════════
## Belayer animation
# ═══════════════════════════════════════════════════════════════════════════

func update_belayer_animation(delta: float):
	var lean_target = 1.0 if catch_state in [CatchState.STRETCHING, CatchState.HELD] else 0.0
	belayer_lean = move_toward(belayer_lean, lean_target,
		(LEAN_ATTACK if lean_target > belayer_lean else LEAN_DECAY) * delta)

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
			guide_hand_pull    = -sin((1.0 - slack_burst_timer / BURST_DURATION) * PI) \
								 * BURST_MAGNITUDE * slack_burst_intensity
			if slack_burst_timer <= 0.0:
				slack_burst_active   = false
				slack_between_bursts = randf_range(BURST_INTERVAL_MIN, BURST_INTERVAL_MAX)
	else:
		# Guide hand yanks hard upward on catch
		guide_hand_pull = lerp(guide_hand_pull, -BURST_MAGNITUDE * 1.8, 10.0 * delta)

	if player:
		belayer_facing_right = get_player_chest_position().x > anchor_position.x

# ═══════════════════════════════════════════════════════════════════════════
## Rope physics
# ═══════════════════════════════════════════════════════════════════════════

func simulate_rope_physics(delta: float):
	if rope_points.size() < 3 or not player:
		return

	var belayer_hand = get_belayer_guide_hand_world()
	var player_chest = get_player_chest_position()

	for i in range(1, rope_points.size() - 1):
		rope_velocities[i].y += GRAVITY * delta
		rope_velocities[i]   *= SEGMENT_DRAG
		rope_points[i]       += rope_velocities[i] * delta

	# Rope whips downward during fall, snaps taut during stretch
	if catch_state == CatchState.FALLING:
		for i in range(1, rope_points.size() - 1):
			rope_velocities[i].y += fall_vel * delta * 0.15
	elif catch_state == CatchState.STRETCHING:
		for i in range(1, rope_points.size() - 1):
			rope_velocities[i].y += fall_vel * delta * 0.25

	for _iter in range(15):
		rope_points[0]                      = belayer_hand
		rope_points[rope_points.size() - 1] = player_chest

		var anchor_index = 0
		var min_dist     = rope_points[0].distance_to(anchor_position)
		for i in range(1, rope_points.size()):
			var d = rope_points[i].distance_to(anchor_position)
			if d < min_dist:
				min_dist = d; anchor_index = i
		rope_points[anchor_index] = anchor_position

		var up_seg = belayer_hand.distance_to(anchor_position)  / max(1.0, float(anchor_index))
		var dn_seg = anchor_position.distance_to(player_chest)  / max(1.0, float(rope_points.size() - anchor_index - 1))

		for i in range(anchor_index):
			var dv = rope_points[i+1] - rope_points[i]; var d = dv.length()
			if d < 0.1: continue
			var cv = dv.normalized() * (d - up_seg) * ROPE_STIFFNESS * 0.5
			if i > 0: rope_points[i] += cv
			if i+1 < rope_points.size()-1 and i+1 != anchor_index:
				rope_points[i+1] -= cv

		for i in range(anchor_index, rope_points.size() - 1):
			var dv = rope_points[i+1] - rope_points[i]; var d = dv.length()
			if d < 0.1: continue
			var cv = dv.normalized() * (d - dn_seg) * ROPE_STIFFNESS * 0.5
			if i != anchor_index: rope_points[i] += cv
			if i+1 < rope_points.size()-1:
				rope_points[i+1] -= cv

	_smooth_rope()

func _smooth_rope():
	if rope_points.size() < 3: return
	for i in range(1, rope_points.size() - 1):
		if rope_points[i].distance_to(anchor_position) >= 5.0:
			rope_points[i] = rope_points[i-1]*0.2 + rope_points[i]*0.6 + rope_points[i+1]*0.2

# ═══════════════════════════════════════════════════════════════════════════
## Visual
# ═══════════════════════════════════════════════════════════════════════════

func update_rope_visual():
	if not rope_line or rope_points.size() < 2: return
	var pts = PackedVector2Array()
	for p in rope_points: pts.append(p)
	rope_line.points = pts

	if catch_state == CatchState.STRETCHING:
		var t                   = clamp(fall_vel / 400.0, 0.0, 1.0)
		rope_line.width         = rope_thickness + t * 2.0
		rope_line.default_color = rope_color.darkened(t * 0.35)
	elif catch_state == CatchState.HELD:
		rope_line.width         = rope_thickness + 0.5
		rope_line.default_color = rope_color.darkened(0.15)
	else:
		rope_line.width         = rope_thickness
		rope_line.default_color = rope_color

func _draw():
	if not is_setup: return

	var black = Color.BLACK
	var lw    = 4.0

	var lean_y = -belayer_lean * 8.0
	var b      = to_local(belayer_position + Vector2(0, lean_y))
	var b_base = to_local(belayer_position)

	var neck = b      + Vector2(0, HEAD_OFFSET + 12)
	var hips = b_base + Vector2(0, HIP_DOWN)

	var lhj = to_local(b_left_hand_joint);  var lh = to_local(b_left_hand)
	var rhj = to_local(b_right_hand_joint); var rh = to_local(b_right_hand)
	var lfj = to_local(b_left_foot_joint);  var lf = to_local(b_left_foot)
	var rfj = to_local(b_right_foot_joint); var rf = to_local(b_right_foot)

	var sm            = 1.0 if belayer_facing_right else -1.0
	var near_shoulder = neck + Vector2( sm * 8.0, 0.0)
	var far_shoulder  = neck + Vector2(-sm * 8.0, 0.0)
	var near_hip      = hips + Vector2( sm * 6.0, 0.0)
	var far_hip       = hips + Vector2(-sm * 6.0, 0.0)

	draw_line(far_shoulder, lhj, black, lw); draw_line(lhj, lh, black, lw-1); draw_circle(lh, 5, black)
	draw_line(far_hip,      lfj, black, lw); draw_line(lfj, lf, black, lw-1); draw_circle(lf, 5, black)
	draw_line(neck, hips, black, lw)
	draw_line(near_shoulder, far_shoulder, black, lw)
	draw_circle(b + Vector2(0, HEAD_OFFSET), 16, black)
	draw_line(near_shoulder, rhj, black, lw); draw_line(rhj, rh, black, lw-1); draw_circle(rh, 5, black)
	draw_line(near_hip,      rfj, black, lw); draw_line(rfj, rf, black, lw-1); draw_circle(rf, 5, black)

	var al = to_local(anchor_position)
	draw_circle(al, 8, black); draw_circle(al, 6, Color.WHITE); draw_circle(al, 4, black)

# ═══════════════════════════════════════════════════════════════════════════
## Anchor lookup — snaps to the actual drawn polygon geometry
# ═══════════════════════════════════════════════════════════════════════════

func find_top_anchor() -> Vector2:
	var anchor_x := player.global_position.x if player else 0.0

	# Ask DynamicWall for the exact point on its drawn edge above the player
	for wall in get_tree().get_nodes_in_group("environment_walls"):
		if wall.has_method("get_anchor_position_for_x"):
			return wall.get_anchor_position_for_x(anchor_x)

	# Last resort: highest hold in the scene
	return _find_highest_hold_anchor()

func _find_highest_hold_anchor() -> Vector2:
	var best_y   := INF
	var best_pos := (belayer_position + Vector2(0, -200.0)) if belayer_position != Vector2.ZERO \
				 else Vector2(0.0, -200.0)
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.global_position.y < best_y:
			best_y   = hold.global_position.y
			best_pos = hold.global_position
	# Sit just above the highest hold rather than beside the belayer
	return best_pos + Vector2(0, -30.0)

# ═══════════════════════════════════════════════════════════════════════════

func get_player_chest_position() -> Vector2:
	if player: return player.global_position + player_attach_offset
	return belayer_position + Vector2(0, 100)

func _init_rope_points(from: Vector2, mid: Vector2, to: Vector2):
	rope_points.clear()
	rope_velocities.clear()
	var path      = [from, mid, to]
	var total_len = 0.0
	for i in range(path.size() - 1):
		total_len += path[i].distance_to(path[i + 1])
	var seg_len = total_len / float(ROPE_SEGMENTS - 1)
	var cs = 0; var dis = 0.0
	var ss = path[0]; var se = path[1]; var sl = ss.distance_to(se)
	for i in range(ROPE_SEGMENTS):
		var td = i * seg_len
		while td > dis + sl and cs < path.size() - 2:
			dis += sl; cs += 1; ss = path[cs]; se = path[cs+1]; sl = ss.distance_to(se)
		var t = (td - dis) / sl if sl > 0.0 else 0.0
		rope_points.append(ss.lerp(se, t))
		rope_velocities.append(Vector2.ZERO)

func cleanup():
	if rope_line: rope_line.queue_free()
	queue_free()
