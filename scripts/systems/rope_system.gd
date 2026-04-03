extends Node2D
class_name RopeSystem

# =============================================================================
#  ROPE SYSTEM
#  Top-rope: visual rope simulation + fall catch + belayer figure.
#  Designed for character.gd (com_velocity / com_position API).
# =============================================================================

@export var rope_color     := Color("#C8A06A")
@export var rope_thickness := 4.5

# -- Rope sim -----------------------------------------------------------------
const ROPE_SEGMENTS  = 28
const ROPE_STIFFNESS = 0.92
const ROPE_GRAVITY   = 60.0
const SEGMENT_DRAG   = 0.94

# -- Fall catch ---------------------------------------------------------------
@export var fall_trigger_velocity : float = 120.0
@export var rope_stretch_distance : float = 120.0
@export var catch_decel_rate      : float = 6.0
@export var lower_speed           : float = 55.0

# -- Belayer anatomy (matches character.gd scale) ----------------------------
const BODY_HEIGHT    = 44.0
const HEAD_RADIUS    = 14.0
const SHOULDER_WIDTH = 13.0
const HIP_WIDTH      = 9.0
const HIP_DOWN       = 20.0
const LEG_UPPER      = 26.0
const LEG_LOWER      = 24.0

# -- Belayer animation --------------------------------------------------------
const BREATH_SPEED      = 1.0
const SWAY_SPEED        = 0.5
const LEAN_ATTACK       = 8.0
const LEAN_DECAY        = 2.0
const CATCH_SHAKE_DECAY = 6.0
const FACING_LERP_SPEED = 5.0

# -- Slack burst (belayer takes in rope rhythmically) -------------------------
const BURST_INTERVAL_MIN = 1.6
const BURST_INTERVAL_MAX = 3.5
const BURST_DURATION     = 0.35
const BURST_MAGNITUDE    = 12.0
const ARM_RETURN_SPEED   = 3.5

signal player_caught

# =============================================================================
#  STATE
# =============================================================================

enum CatchState { IDLE, FALLING, STRETCHING, HELD }
var catch_state   : CatchState = CatchState.IDLE
var fall_origin_y : float = 0.0
var fall_vel      : float = 0.0
var held_y        : float = 0.0
var _is_lowering  : bool  = false

# Belayer pose (world-space joint positions, set each frame by _update_pose)
var b_guide_hand_joint : Vector2
var b_guide_hand       : Vector2
var b_brake_hand_joint : Vector2
var b_brake_hand       : Vector2
var b_near_foot_joint  : Vector2
var b_near_foot        : Vector2
var b_far_foot_joint   : Vector2
var b_far_foot         : Vector2

# Animation scalars
var anim_breath      : float = 0.0  # phase
var anim_sway        : float = 0.0  # phase
var anim_lean        : float = 0.0  # 0-1
var anim_catch_shake : float = 0.0  # 0-1 decaying
var anim_shake_dir   : float = 1.0  # ±1
var anim_guide_pull  : float = 0.0  # px offset for slack-taking
var anim_head_tilt   : float = 0.0  # 0-1

var burst_timer    : float = 0.0
var burst_active   : bool  = false
var burst_intensity: float = 0.0
var burst_cooldown : float = 1.0

var facing         : float = 1.0   # +1 = right
var facing_target  : float = 1.0

# Rope
var belayer_position : Vector2
var anchor_position  : Vector2
var rope_points      : Array[Vector2] = []
var rope_velocities  : Array[Vector2] = []

# References
var player       : Node2D = null
var is_setup     : bool   = false
var rope_line    : Line2D = null
var rope_lower   : Line2D = null

# =============================================================================
#  INIT
# =============================================================================

func _ready() -> void:
	global_position = Vector2.ZERO
	z_index = 50
	rope_line  = _make_line()
	rope_lower = _make_line()
	add_child(rope_line)
	add_child(rope_lower)


func _make_line() -> Line2D:
	var l               = Line2D.new()
	l.width             = rope_thickness
	l.default_color     = rope_color
	l.z_index           = 5
	l.top_level         = true
	l.antialiased       = true
	l.begin_cap_mode    = Line2D.LINE_CAP_ROUND
	l.end_cap_mode      = Line2D.LINE_CAP_ROUND
	l.joint_mode        = Line2D.LINE_JOINT_ROUND
	return l


func setup_rope(belayer_pos: Vector2, player_node: Node2D, anchor_pos: Vector2 = Vector2.ZERO) -> void:
	belayer_position = belayer_pos
	player           = player_node
	anchor_position  = anchor_pos if anchor_pos != Vector2.ZERO else _find_anchor()
	facing_target    = 1.0 if _player_chest().x > anchor_position.x else -1.0
	facing           = facing_target
	_init_rope()
	is_setup = true
	visible  = true
	catch_state = CatchState.IDLE

# =============================================================================
#  MAIN LOOP
# =============================================================================

func _process(delta: float) -> void:
	if not is_setup or not is_instance_valid(player):
		is_setup = false
		return
	_update_catch(delta)
	_update_animation(delta)
	_update_pose()
	_simulate_rope(delta)
	_update_rope_visual()
	queue_redraw()

# =============================================================================
#  CATCH STATE MACHINE
# =============================================================================

func _update_catch(delta: float) -> void:
	match catch_state:

		CatchState.IDLE:
			if not _has_hand_hold() and player.com_velocity.y >= fall_trigger_velocity:
				catch_state   = CatchState.FALLING
				fall_origin_y = player.com_position.y
				fall_vel      = player.com_velocity.y

		CatchState.FALLING:
			fall_vel = player.com_velocity.y
			if player.com_position.y - fall_origin_y >= rope_stretch_distance and fall_vel > 0.0:
				catch_state      = CatchState.STRETCHING
				fall_vel         = player.com_velocity.y
				anim_lean        = 1.0
				anim_catch_shake = clamp(fall_vel / 280.0, 0.5, 1.0)
				anim_shake_dir   = randf_range(-1.0, 1.0)
				emit_signal("player_caught")
			if _has_hand_hold():
				catch_state = CatchState.IDLE

		CatchState.STRETCHING:
			fall_vel = move_toward(fall_vel, 0.0, catch_decel_rate * delta * fall_vel + 35.0 * delta)
			_set_player_pos(player.com_position + Vector2(0, fall_vel * delta))
			if fall_vel <= 1.5:
				held_y      = player.com_position.y
				catch_state = CatchState.HELD

		CatchState.HELD:
			if _has_hand_hold():
				catch_state = CatchState.IDLE
				return
			player.com_velocity.y  = minf(player.com_velocity.y, 0.0)
			_is_lowering = Input.is_action_pressed("ui_accept")
			if _is_lowering:
				held_y += lower_speed * delta
			_set_player_pos(Vector2(player.com_position.x, held_y))


func _set_player_pos(pos: Vector2) -> void:
	player.com_position    = pos
	player.body_velocity   = Vector2.ZERO
	player.global_position = pos + Vector2(0, -player.COM_OFFSET_Y)

# =============================================================================
#  ANIMATION
# =============================================================================

func _update_animation(delta: float) -> void:
	# Facing
	facing_target = 1.0 if _player_chest().x > anchor_position.x else -1.0
	facing = lerpf(facing, facing_target, FACING_LERP_SPEED * delta)

	# Lean (pulled back when catching)
	var lean_tgt = 1.0 if catch_state in [CatchState.STRETCHING, CatchState.HELD] else 0.0
	var lean_spd = LEAN_ATTACK if lean_tgt > anim_lean else LEAN_DECAY
	anim_lean = move_toward(anim_lean, lean_tgt, lean_spd * delta)

	# Breath & sway (faster when catching)
	var breath_mult = 1.7 if catch_state != CatchState.IDLE else 1.0
	anim_breath = fmod(anim_breath + BREATH_SPEED * breath_mult * delta, TAU)
	if catch_state == CatchState.IDLE:
		anim_sway = fmod(anim_sway + SWAY_SPEED * delta, TAU)
	else:
		anim_sway = lerpf(anim_sway, 0.0, 3.0 * delta)

	# Catch shake (decays naturally)
	anim_catch_shake = move_toward(anim_catch_shake, 0.0,
		CATCH_SHAKE_DECAY * anim_catch_shake * delta + 0.4 * delta)

	# Head tilt toward climber
	var chest    = _player_chest()
	var tilt_tgt = clamp(-(chest - belayer_position).y / 350.0, 0.0, 1.0) * 0.3
	anim_head_tilt = lerpf(anim_head_tilt, tilt_tgt, 3.0 * delta)

	# Slack bursts (guide hand takes in rope while idle)
	if catch_state == CatchState.IDLE:
		if burst_active:
			burst_timer -= delta
			anim_guide_pull = -sin((1.0 - burst_timer / BURST_DURATION) * PI) * BURST_MAGNITUDE * burst_intensity
			if burst_timer <= 0.0:
				burst_active  = false
				burst_cooldown = randf_range(BURST_INTERVAL_MIN, BURST_INTERVAL_MAX)
		else:
			burst_cooldown   -= delta
			anim_guide_pull   = lerpf(anim_guide_pull, 0.0, ARM_RETURN_SPEED * delta)
			if burst_cooldown <= 0.0:
				burst_active    = true
				burst_timer     = BURST_DURATION
				burst_intensity = randf_range(0.5, 1.0)
	else:
		anim_guide_pull = lerpf(anim_guide_pull, -BURST_MAGNITUDE * 1.5, 10.0 * delta)

# =============================================================================
#  POSE  (belayer joint positions, world-space)
#  "near" side faces the wall.  "far" side is away from wall.
#  Guide hand (near) feeds rope up toward anchor.
#  Brake hand (far) holds rope down — classic ATC position.
# =============================================================================

func _update_pose() -> void:
	var sm    := facing
	var bob_y := sin(anim_breath) * 1.0
	var sway  := sin(anim_sway) * 2.0
	var shake := sin(anim_catch_shake * TAU * 8.0) * anim_catch_shake * 4.0 * anim_shake_dir
	var lean  := -anim_lean * 8.0

	var b    := belayer_position + Vector2(sway + shake, lean + bob_y)
	var base := belayer_position

	var neck      := b    + Vector2(0.0, -BODY_HEIGHT * 0.5)
	var hips      := base + Vector2(0.0, HIP_DOWN)
	var near_sh   := neck + Vector2( sm * SHOULDER_WIDTH, 2.0)
	var far_sh    := neck + Vector2(-sm * SHOULDER_WIDTH, 2.0)
	var near_hip  := hips + Vector2( sm * HIP_WIDTH, 0.0)
	var far_hip   := hips + Vector2(-sm * HIP_WIDTH, 0.0)

	# Guide hand — elbow forward-up, hand reaches toward rope
	b_guide_hand_joint = near_sh + Vector2(sm * 14.0, -4.0)
	b_guide_hand       = near_sh + Vector2(sm * 22.0, -20.0 + anim_guide_pull)

	# Brake hand — elbow down-back, hand at hip
	var brake_drop = anim_lean * 18.0
	b_brake_hand_joint = far_sh + Vector2(-sm * 12.0, 14.0 + brake_drop * 0.3)
	b_brake_hand       = far_sh + Vector2(-sm * 16.0, 30.0 + brake_drop)

	# Feet — near slightly forward, far slightly back
	var lr := deg_to_rad(10.0)
	b_near_foot_joint = near_hip + Vector2( sm * LEG_UPPER * sin(lr),       LEG_UPPER * cos(lr))
	b_near_foot       = b_near_foot_joint + Vector2( sm * 5.0, LEG_LOWER)
	b_far_foot_joint  = far_hip  + Vector2(-sm * LEG_UPPER * sin(lr) * 0.6, LEG_UPPER * cos(lr))
	b_far_foot        = b_far_foot_joint  + Vector2(-sm * 2.0, LEG_LOWER)


func get_belayer_guide_hand_world() -> Vector2:
	return b_guide_hand

# =============================================================================
#  ROPE PHYSICS
# =============================================================================

func _simulate_rope(delta: float) -> void:
	if rope_points.size() < 3: return
	var chest := _player_chest()

	for i in range(1, rope_points.size() - 1):
		rope_velocities[i].y += ROPE_GRAVITY * delta
		if catch_state == CatchState.FALLING:   rope_velocities[i].y += fall_vel * delta * 0.12
		elif catch_state == CatchState.STRETCHING: rope_velocities[i].y += fall_vel * delta * 0.2
		rope_velocities[i] *= SEGMENT_DRAG
		rope_points[i]     += rope_velocities[i] * delta

	var ai := _anchor_index()
	var up  := b_guide_hand.distance_to(anchor_position) / maxf(float(ai), 1.0)
	var dn  := anchor_position.distance_to(chest)        / maxf(float(rope_points.size() - ai - 1), 1.0)

	for _pass in range(15):
		rope_points[0]                        = b_guide_hand
		rope_points[rope_points.size() - 1]  = chest
		rope_points[ai]                       = anchor_position
		_constrain_segment(0, ai, up)
		_constrain_segment(ai, rope_points.size() - 1, dn)

	_smooth_rope(ai)


func _constrain_segment(from: int, to: int, seg_len: float) -> void:
	for i in range(from, to):
		var dv := rope_points[i + 1] - rope_points[i]
		var d  := dv.length()
		if d < 0.1: continue
		var cv = dv.normalized() * (d - seg_len) * ROPE_STIFFNESS * 0.5
		if i > from and rope_points[i].distance_to(anchor_position) >= 5.0:
			rope_points[i] += cv
		if i + 1 < to:
			rope_points[i + 1] -= cv


func _smooth_rope(ai: int) -> void:
	for i in range(1, rope_points.size() - 1):
		if rope_points[i].distance_to(anchor_position) >= 5.0:
			rope_points[i] = rope_points[i - 1] * 0.2 + rope_points[i] * 0.6 + rope_points[i + 1] * 0.2


func _anchor_index() -> int:
	var best := 0
	var min_d := rope_points[0].distance_to(anchor_position)
	for i in range(1, rope_points.size()):
		var d := rope_points[i].distance_to(anchor_position)
		if d < min_d: min_d = d; best = i
	return best

# =============================================================================
#  ROPE VISUAL
# =============================================================================

func _update_rope_visual() -> void:
	if not is_instance_valid(rope_line) or rope_points.size() < 2: return
	var ai := _anchor_index()
	var up  := PackedVector2Array()
	var dn  := PackedVector2Array()
	for i in range(ai + 1):          up.append(rope_points[i])
	for i in range(ai, rope_points.size()): dn.append(rope_points[i])
	rope_line.points  = up
	rope_lower.points = dn

# =============================================================================
#  DRAW
# =============================================================================

func _draw() -> void:
	if not is_setup: return
	_draw_anchor()
	_draw_belayer()


func _draw_anchor() -> void:
	var al := to_local(anchor_position)
	draw_circle(al, 12.0, Color("#2A2A30"))
	draw_circle(al,  8.5, Color("#6E6E78"))
	draw_circle(al,  5.0, Color("#A8A8B2"))
	draw_circle(al,  2.8, Color("#D4A84B"))


func _draw_belayer() -> void:
	var skin_color  := Color("#C68642")
	var shirt_color := Color("#2E4A6B")
	var pants_color := Color("#1A1A2E")
	var shoe_color  := Color("#d89418ff")
	const OW = 5.5

	var sm    := facing
	var bob_y := sin(anim_breath) * 1.0
	var sway  := sin(anim_sway) * 2.0
	var shake := sin(anim_catch_shake * TAU * 8.0) * anim_catch_shake * 4.0 * anim_shake_dir
	var lean  := -anim_lean * 8.0

	var b     := to_local(belayer_position + Vector2(sway + shake, lean + bob_y))
	var base  := to_local(belayer_position)
	var neck  := b    + Vector2(0.0, -BODY_HEIGHT * 0.5)
	var hips  := base + Vector2(0.0, HIP_DOWN)

	var head_center  := neck + Vector2(sm * anim_head_tilt * 3.0, -HEAD_RADIUS - 2.0 - anim_head_tilt * 7.0)
	var near_sh      := neck + Vector2( sm * SHOULDER_WIDTH, 2.0)
	var far_sh       := neck + Vector2(-sm * SHOULDER_WIDTH, 2.0)
	var near_hip     := hips + Vector2( sm * HIP_WIDTH, 0.0)
	var far_hip      := hips + Vector2(-sm * HIP_WIDTH, 0.0)

	# Convert world joints to local
	var ghj := to_local(b_guide_hand_joint)
	var gh  := to_local(b_guide_hand)
	var bhj := to_local(b_brake_hand_joint)
	var bh  := to_local(b_brake_hand)
	var nfj := to_local(b_near_foot_joint)
	var nf  := to_local(b_near_foot)
	var ffj := to_local(b_far_foot_joint)
	var ff  := to_local(b_far_foot)

	var near_sl := near_sh.lerp(ghj, 0.35)
	var far_sl  := far_sh.lerp(bhj, 0.35)

	var oc_skin  := _outline(skin_color)
	var oc_shirt := _outline(shirt_color)
	var oc_pants := _outline(pants_color)
	var oc_shoe  := _outline(shoe_color)

	# ── OUTLINE PASS ──────────────────────────────────────────────────────────
	# Far leg
	draw_line(far_hip, ffj, oc_pants, 9.0 + OW); draw_circle(ffj, 4.5 + OW*0.5, oc_pants)
	draw_line(ffj, ff, oc_pants, 9.0 + OW);       draw_circle(ff,  8.5 + OW*0.5, oc_shoe)
	# Near leg
	draw_line(near_hip, nfj, oc_pants, 9.0 + OW); draw_circle(nfj, 4.5 + OW*0.5, oc_pants)
	draw_line(nfj, nf, oc_pants, 9.0 + OW);        draw_circle(nf,  8.5 + OW*0.5, oc_shoe)
	# Torso
	draw_line(far_hip, near_hip, oc_pants, 17.0 + OW)
	draw_line(hips, neck, oc_shirt, 19.0 + OW)
	# Brake arm (far)
	draw_circle(far_sh, 6.5 + OW*0.5, oc_shirt)
	draw_line(far_sh, far_sl, oc_shirt, 13.0 + OW); draw_line(far_sl, bhj, oc_skin, 12.0 + OW)
	draw_circle(bhj, 5.5 + OW*0.5, oc_skin); draw_line(bhj, bh, oc_skin, 10.5 + OW)
	draw_circle(bh, 8.5 + OW*0.5, oc_skin)
	# Guide arm (near)
	draw_circle(near_sh, 6.5 + OW*0.5, oc_shirt)
	draw_line(near_sh, near_sl, oc_shirt, 13.0 + OW); draw_line(near_sl, ghj, oc_skin, 12.0 + OW)
	draw_circle(ghj, 5.5 + OW*0.5, oc_skin); draw_line(ghj, gh, oc_skin, 10.5 + OW)
	draw_circle(gh, 8.5 + OW*0.5, oc_skin)
	# Head
	draw_line(neck, head_center + Vector2(0, HEAD_RADIUS), oc_skin, 11.0 + OW)
	draw_circle(head_center, HEAD_RADIUS + OW*0.5, oc_skin)

	# ── FILL PASS ─────────────────────────────────────────────────────────────
	# Far leg
	draw_line(far_hip, ffj, pants_color, 9.0); draw_circle(ffj, 4.5, pants_color)
	draw_line(ffj, ff, pants_color, 9.0);       draw_circle(ff,  8.5, shoe_color)
	# Near leg
	draw_line(near_hip, nfj, pants_color, 9.0); draw_circle(nfj, 4.5, pants_color)
	draw_line(nfj, nf, pants_color, 9.0);        draw_circle(nf,  8.5, shoe_color)
	# Torso
	draw_line(far_hip, near_hip, pants_color, 17.0)
	draw_line(hips, neck, shirt_color, 19.0)
	# Brake arm
	draw_circle(far_sh, 6.5, shirt_color)
	draw_line(far_sh, far_sl, shirt_color, 13.0); draw_line(far_sl, bhj, skin_color, 12.0)
	draw_circle(bhj, 5.5, skin_color); draw_line(bhj, bh, skin_color, 10.5)
	draw_circle(bh, 8.5, skin_color)
	# Guide arm
	draw_circle(near_sh, 6.5, shirt_color)
	draw_line(near_sh, near_sl, shirt_color, 13.0); draw_line(near_sl, ghj, skin_color, 12.0)
	draw_circle(ghj, 5.5, skin_color); draw_line(ghj, gh, skin_color, 10.5)
	draw_circle(gh, 8.5, skin_color)
	# Head + neck
	draw_line(neck, head_center + Vector2(0, HEAD_RADIUS), skin_color, 11.0)
	draw_circle(head_center, HEAD_RADIUS, skin_color)


func _outline(col: Color) -> Color:
	var lum := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	return Color(
		lerpf(lerpf(col.r, lum, 0.09), 0.0, 0.30),
		lerpf(lerpf(col.g, lum, 0.09), 0.0, 0.30),
		lerpf(lerpf(col.b, lum, 0.09), 0.0, 0.30),
		1.0)

# =============================================================================
#  HELPERS
# =============================================================================

func _has_hand_hold() -> bool:
	if not is_instance_valid(player): return false
	return player.lh.hold != null or player.rh.hold != null


func _player_chest() -> Vector2:
	return player.global_position + Vector2(0, -10) if is_instance_valid(player) \
		else belayer_position + Vector2(0, 100)


func _find_anchor() -> Vector2:
	for wall in get_tree().get_nodes_in_group("environment_walls"):
		if wall.has_method("get_anchor_position_for_x"):
			return wall.get_anchor_position_for_x(player.global_position.x if is_instance_valid(player) else 0.0)
	# Fall back to highest hold
	var best_y   := INF
	var best_pos := belayer_position + Vector2(0, -200)
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.global_position.y < best_y:
			best_y = hold.global_position.y; best_pos = hold.global_position
	return best_pos + Vector2(0, -30)


func _init_rope() -> void:
	rope_points.clear(); rope_velocities.clear()
	var waypoints := [b_guide_hand, anchor_position, _player_chest()]
	var total     := 0.0
	for i in range(waypoints.size() - 1): total += waypoints[i].distance_to(waypoints[i + 1])
	var seg_len := total / float(ROPE_SEGMENTS - 1)
	var seg_i   := 0;  var accum := 0.0
	var seg_s   = waypoints[0]; var seg_e = waypoints[1]; var seg_l = seg_s.distance_to(seg_e)
	for i in range(ROPE_SEGMENTS):
		var td := i * seg_len
		while td > accum + seg_l and seg_i < waypoints.size() - 2:
			accum += seg_l; seg_i += 1
			seg_s = waypoints[seg_i]; seg_e = waypoints[seg_i + 1]; seg_l = seg_s.distance_to(seg_e)
		rope_points.append(seg_s.lerp(seg_e, clamp((td - accum) / maxf(seg_l, 0.001), 0.0, 1.0)))
		rope_velocities.append(Vector2.ZERO)

# =============================================================================
#  EXTERNAL API
# =============================================================================

func apply_rope_force_to_player(vel: Vector2) -> Vector2:
	return vel  # Hook for future tension feedback


func cleanup() -> void:
	is_setup = false
	set_process(false)
	if is_instance_valid(rope_line):  rope_line.queue_free();  rope_line  = null
	if is_instance_valid(rope_lower): rope_lower.queue_free(); rope_lower = null
