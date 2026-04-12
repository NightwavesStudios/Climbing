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

# -- Belayer anatomy (mirrors character.gd scale exactly) --------------------
#    character uses ARM_UPPER=50, ARM_LOWER=50, LEG_UPPER=45, LEG_LOWER=45
#    belayer is a bystander so slightly smaller feels right
const BODY_HEIGHT    = 44.0
const HEAD_RADIUS    = 14.0
const SHOULDER_OFF   = 12.0   # half shoulder width (character uses SHOULDER_OFFSET=0 but draws offset)
const HIP_OFF        = 8.0
const HIP_DOWN       = 20.0
const ARM_UPPER      = 38.0
const ARM_LOWER      = 36.0
const LEG_UPPER      = 32.0
const LEG_LOWER      = 30.0
const HEAD_OFFSET_Y  = -20.0  # neck-to-head, matches character HEAD_OFFSET

# -- Outline (matches character.gd export values) ----------------------------
const OUTLINE_WIDTH  = 5.5
const OUTLINE_DARKEN = 0.25
const OUTLINE_ALPHA  = 1.0

# -- Colors (identical palette to character.gd) ------------------------------
const SKIN_COLOR    = Color("#C68642")
const SHIRT_COLOR   = Color("#8B3A3A")   # different shirt so they read as separate people
const PANTS_COLOR   = Color("#1A1A2E")
const SHOE_COLOR    = Color("#d89418ff")
const HARNESS_COLOR = Color("#E8A020")

# -- Reactivity ---------------------------------------------------------------
const BREATH_SPEED         = 1.1
const SWAY_SPEED           = 0.4
const LEAN_ATTACK          = 7.0
const LEAN_DECAY           = 1.6
const CATCH_SHAKE_DECAY    = 5.0
const FACING_LERP_SPEED    = 4.0
const WEIGHT_SHIFT_SPEED   = 3.0
const HEAD_TRACK_SPEED     = 5.0
const ROPE_TENSION_SPEED   = 6.0
const ALERT_SPEED          = 4.5
const BRACE_FOOT_SPREAD    = 16.0
const HIGH_CLIMBER_LEAN    = 0.30   # extra lean when climber is far above

# -- Slack burst (belayer takes in rope rhythmically) ------------------------
const BURST_INTERVAL_MIN = 1.8
const BURST_INTERVAL_MAX = 3.8
const BURST_DURATION     = 0.35
const BURST_MAGNITUDE    = 14.0
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

# -- Reactive animation scalars -----------------------------------------------
var _rope_tension       : float = 0.0   # 0-1; how taut the rope feels right now
var _alert_level        : float = 0.0   # 0-1; 0=relaxed watching, 1=full brace
var _anticipation       : float = 0.0   # 0-1; reads climber fail_stage before fall
var _weight_shift       : float = 0.0   # -1=near side, +1=far side
var _foot_brace_lerp    : float = 0.0   # 0-1; feet spread wider under load
var _guide_elbow_raise  : float = 0.0   # 0-1; guide elbow lifts as climber goes up
var _brake_tension_pull : float = 0.0   # px; brake hand pulled further down/back
var _climber_height_t   : float = 0.0   # 0=level, 1=climber far above
var _head_look_angle    : float = 0.0   # radians; actual look direction
var _last_climber_vel_y : float = 0.0

# -- Base animation phases ----------------------------------------------------
var anim_breath      : float = 0.0
var anim_sway        : float = 0.0
var anim_lean        : float = 0.0
var anim_catch_shake : float = 0.0
var anim_shake_dir   : float = 1.0
var anim_guide_pull  : float = 0.0
var anim_head_tilt   : float = 0.0

var burst_timer    : float = 0.0
var burst_active   : bool  = false
var burst_intensity: float = 1.0
var burst_cooldown : float = 1.5

var facing        : float = 1.0
var facing_target : float = 1.0

# -- Computed world-space joint positions (set by _update_pose each frame) ----
var _b_root            : Vector2   # body root (with bob/sway/lean applied)
var _b_neck            : Vector2
var _b_hips            : Vector2
var _b_near_sh         : Vector2
var _b_far_sh          : Vector2
var _b_near_hip        : Vector2
var _b_far_hip         : Vector2
var _b_guide_elbow     : Vector2
var _b_guide_hand      : Vector2
var _b_brake_elbow     : Vector2
var _b_brake_hand      : Vector2
var _b_near_knee       : Vector2
var _b_near_foot       : Vector2
var _b_far_knee        : Vector2
var _b_far_foot        : Vector2
var _b_head_center     : Vector2

# -- Old names kept for rope physics compatibility ----------------------------
var b_guide_hand_joint : Vector2
var b_guide_hand       : Vector2
var b_brake_hand_joint : Vector2
var b_brake_hand       : Vector2
var b_near_foot_joint  : Vector2
var b_near_foot        : Vector2
var b_far_foot_joint   : Vector2
var b_far_foot         : Vector2

# -- Scene refs ---------------------------------------------------------------
var belayer_position : Vector2
var anchor_position  : Vector2
var rope_points      : Array[Vector2] = []
var rope_velocities  : Array[Vector2] = []
var player           : Node2D = null
var is_setup         : bool   = false
var rope_line        : Line2D = null
var rope_lower       : Line2D = null

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
	_reset_anim_state()
	_update_pose()
	_init_rope()
	is_setup = true
	visible  = true
	catch_state = CatchState.IDLE


func _reset_anim_state() -> void:
	_rope_tension       = 0.0
	_alert_level        = 0.0
	_anticipation       = 0.0
	_weight_shift       = 0.0
	_foot_brace_lerp    = 0.0
	_guide_elbow_raise  = 0.0
	_brake_tension_pull = 0.0
	_climber_height_t   = 0.0
	_head_look_angle    = 0.0
	_last_climber_vel_y = 0.0
	anim_lean           = 0.0
	anim_catch_shake    = 0.0
	anim_guide_pull     = 0.0
	anim_breath         = 0.0
	anim_sway           = 0.0
	burst_active        = false
	burst_cooldown      = randf_range(BURST_INTERVAL_MIN, BURST_INTERVAL_MAX)

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
			# FLOOR GUARD: catch immediately if about to hit ground
			var floor_y := belayer_position.y - 20.0   # belayer stands at ground level
			if player.com_position.y >= floor_y - 30.0:
				catch_state      = CatchState.STRETCHING
				fall_vel         = minf(fall_vel, 60.0)   # cap velocity at near-floor catch
				anim_lean        = 1.0
				anim_catch_shake = 0.5
				anim_shake_dir   = randf_range(-1.0, 1.0)
				emit_signal("player_caught")
				return
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
			var new_pos = player.com_position + Vector2(0, fall_vel * delta)
			# Hard floor clamp during stretch
			var floor_y := belayer_position.y - 20.0
			new_pos.y    = minf(new_pos.y, floor_y)
			_set_player_pos(new_pos)
			if fall_vel <= 1.5 or new_pos.y >= floor_y:
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
			# Clamp held position to floor
			var floor_y := belayer_position.y - 20.0
			held_y       = minf(held_y, floor_y)
			_set_player_pos(Vector2(player.com_position.x, held_y))

func _set_player_pos(pos: Vector2) -> void:
	player.com_position    = pos
	player.body_velocity   = Vector2.ZERO
	player.global_position = pos + Vector2(0, -player.COM_OFFSET_Y)

# =============================================================================
#  ANIMATION — reads climber state every frame
# =============================================================================

func _update_animation(delta: float) -> void:
	if not is_instance_valid(player): return

	var chest         := _player_chest()
	var climber_vel_y = player.com_velocity.y
	var climber_accel = (climber_vel_y - _last_climber_vel_y) / maxf(delta, 0.001)
	_last_climber_vel_y = climber_vel_y

	# ── Climber height: how far above the belayer, normalized ────────────────
	var height_diff   := belayer_position.y - chest.y  # positive = above
	_climber_height_t  = clamp(height_diff / 380.0, 0.0, 1.0)

	# ── Rope tension: driven by fall speed, catch state, and climber height ──
	var raw_tension := 0.0
	match catch_state:
		CatchState.FALLING:    raw_tension = clamp(climber_vel_y / 300.0, 0.0, 1.0)
		CatchState.STRETCHING: raw_tension = 1.0
		CatchState.HELD:       raw_tension = 0.85
		CatchState.IDLE:
			# Light tension when climber is high and on the rope
			raw_tension = clamp(_climber_height_t * 0.35, 0.0, 0.35)
	_rope_tension = lerpf(_rope_tension, raw_tension, ROPE_TENSION_SPEED * delta)

	# ── Anticipation: belayer reads climber's grip failure before it happens ─
	var anticipate_target := 0.0
	if is_instance_valid(player):
		for hand in [player.lh, player.rh]:
			if hand.hold != null:
				match hand.fail_stage:
					1: anticipate_target = maxf(anticipate_target, 0.35)  # SLIP
					2: anticipate_target = maxf(anticipate_target, 0.65)  # STRUGGLE
					3: anticipate_target = maxf(anticipate_target, 0.90)  # FALLING
	_anticipation = lerpf(_anticipation, anticipate_target, 3.5 * delta)

	# ── Alert level: composite of all stress signals ─────────────────────────
	var alert_target := 0.0
	match catch_state:
		CatchState.FALLING:    alert_target = clamp(climber_vel_y / fall_trigger_velocity, 0.4, 1.0)
		CatchState.STRETCHING: alert_target = 1.0
		CatchState.HELD:       alert_target = 0.8
		CatchState.IDLE:
			# Anticipation bleeds into alert level
			alert_target = _anticipation * 0.85
			# Sudden downward acceleration (unexpected slip)
			if climber_accel > 250.0 and not _has_hand_hold():
				alert_target = maxf(alert_target, 0.55)
	var alert_spd  := ALERT_SPEED if alert_target > _alert_level else ALERT_SPEED * 0.35
	_alert_level    = lerpf(_alert_level, alert_target, alert_spd * delta)

	# ── Facing ───────────────────────────────────────────────────────────────
	facing_target = 1.0 if chest.x > belayer_position.x else -1.0
	facing        = lerpf(facing, facing_target, FACING_LERP_SPEED * delta)

	# ── Head tracking ────────────────────────────────────────────────────────
	var to_climber     := chest - belayer_position
	var look_angle_tgt := atan2(-to_climber.y, to_climber.x * facing)
	look_angle_tgt      = clamp(look_angle_tgt, -PI * 0.42, PI * 0.52)
	_head_look_angle    = lerpf(_head_look_angle, look_angle_tgt, HEAD_TRACK_SPEED * delta)
	anim_head_tilt      = clamp(_climber_height_t * 0.5 + _alert_level * 0.15, 0.0, 0.65)

	# ── Lean back: rope tension pulls belayer away from wall ─────────────────
	var lean_tgt := (
		_alert_level      * 0.50 +
		_rope_tension     * 0.28 +
		_climber_height_t * HIGH_CLIMBER_LEAN
	)
	var lean_spd := LEAN_ATTACK if lean_tgt > anim_lean else LEAN_DECAY
	anim_lean     = lerpf(anim_lean, lean_tgt, lean_spd * delta)

	# ── Weight shift: hips slide to far foot when bracing ────────────────────
	var shift_tgt := lerpf(-0.12, 0.72, _alert_level)
	_weight_shift  = lerpf(_weight_shift, shift_tgt, WEIGHT_SHIFT_SPEED * delta)

	# ── Foot brace spread ────────────────────────────────────────────────────
	_foot_brace_lerp = lerpf(_foot_brace_lerp, _alert_level, WEIGHT_SHIFT_SPEED * delta)

	# ── Guide arm: elbow rises as climber goes up and rope loads ─────────────
	_guide_elbow_raise = lerpf(_guide_elbow_raise,
		_climber_height_t * 0.65 + _rope_tension * 0.35,
		ROPE_TENSION_SPEED * delta)

	# ── Brake arm: hand pulled further down/back under tension ───────────────
	var brake_tgt       := _rope_tension * 30.0 + _alert_level * 14.0
	_brake_tension_pull  = lerpf(_brake_tension_pull, brake_tgt, ROPE_TENSION_SPEED * delta)

	# ── Breath: faster and shallower when stressed ───────────────────────────
	var breath_mult := 1.0 + _alert_level * 1.3
	anim_breath      = fmod(anim_breath + BREATH_SPEED * breath_mult * delta, TAU)

	# ── Sway: only present when relaxed ──────────────────────────────────────
	var sway_amt := 1.0 - _alert_level
	anim_sway     = fmod(anim_sway + SWAY_SPEED * sway_amt * delta, TAU)

	# ── Catch shake (impact reaction) ────────────────────────────────────────
	if catch_state == CatchState.STRETCHING and anim_catch_shake < 0.1:
		anim_catch_shake = clamp(climber_vel_y / 280.0, 0.5, 1.0)
		anim_shake_dir   = randf_range(-1.0, 1.0)
	anim_catch_shake = move_toward(anim_catch_shake, 0.0,
		CATCH_SHAKE_DECAY * anim_catch_shake * delta + 0.3 * delta)

	# ── Slack bursts: guide hand takes in rope while relaxed ─────────────────
	if catch_state == CatchState.IDLE and _alert_level < 0.22:
		if burst_active:
			burst_timer -= delta
			anim_guide_pull = -sin((1.0 - burst_timer / BURST_DURATION) * PI) * BURST_MAGNITUDE * burst_intensity
			if burst_timer <= 0.0:
				burst_active   = false
				burst_cooldown = randf_range(BURST_INTERVAL_MIN, BURST_INTERVAL_MAX)
		else:
			burst_cooldown  -= delta
			anim_guide_pull  = lerpf(anim_guide_pull, 0.0, ARM_RETURN_SPEED * delta)
			if burst_cooldown <= 0.0:
				burst_active    = true
				burst_timer     = BURST_DURATION
				burst_intensity = randf_range(0.5, 1.0)
	else:
		# Alert or catching: arms commit, no bursts
		anim_guide_pull = lerpf(anim_guide_pull,
			-BURST_MAGNITUDE * (0.9 + _alert_level * 0.8), 9.0 * delta)
		if burst_active:
			burst_active   = false
			burst_cooldown = randf_range(BURST_INTERVAL_MIN, BURST_INTERVAL_MAX)

# =============================================================================
#  POSE — all joint positions in world space
#  Follows the same two-segment IK logic as character.gd's _constrain_arm.
# =============================================================================

func _update_pose() -> void:
	var bob_y := sin(anim_breath) * lerpf(1.2, 0.25, _alert_level)
	var shake  := sin(anim_catch_shake * TAU * 8.0) * anim_catch_shake * 5.0 * anim_shake_dir

	var root := belayer_position + Vector2(0, bob_y + shake)

	# Torso spine — neck is top, hips is bottom
	_b_neck = root + Vector2(0, -20)
	_b_hips = root + Vector2(0,  22)

	# Head flush on neck top
	_b_head_center = _b_neck + Vector2(0, -HEAD_RADIUS)

	# Shoulders: partway DOWN the torso (not at neck), inside torso width
	# Torso is TW=28 wide => half = 14px. Shoulders at ±9 so torso overdraw covers root.
	var shoulder_y := _b_neck.y + 10.0   # 10px below neck = upper chest
	_b_near_sh = Vector2(belayer_position.x - 9,  shoulder_y)
	_b_far_sh  = Vector2(belayer_position.x + 9,  shoulder_y)

	# Hips: inside torso width
	_b_near_hip = Vector2(belayer_position.x - 8, _b_hips.y)
	_b_far_hip  = Vector2(belayer_position.x + 8, _b_hips.y)

	# Guide arm (left): elbow out-left and down from shoulder, hand up toward rope
	var guide_raise := lerpf(0.0, -24.0, _guide_elbow_raise + _rope_tension * 0.4)
	_b_guide_elbow = _b_near_sh + Vector2(-20, 16)
	_b_guide_hand  = _b_near_sh + Vector2(-22, guide_raise + anim_guide_pull)

	# Brake arm (right): elbow out-right and down, hand lower
	_b_brake_elbow = _b_far_sh + Vector2( 20, 16)
	_b_brake_hand  = _b_far_sh + Vector2( 16, 28 + _brake_tension_pull)

	# Legs: down from hips, feet slightly wider than hips
	var spread := lerpf(8.0, 14.0, _foot_brace_lerp)
	_b_near_knee = _b_near_hip + Vector2(-2, LEG_UPPER - 6)
	_b_near_foot = _b_near_hip + Vector2(-spread, LEG_UPPER + LEG_LOWER - 10)
	_b_far_knee  = _b_far_hip  + Vector2( 2, LEG_UPPER - 6)
	_b_far_foot  = _b_far_hip  + Vector2( spread, LEG_UPPER + LEG_LOWER - 10)

	# Sync legacy names
	b_guide_hand_joint = _b_guide_elbow
	b_guide_hand       = _b_guide_hand
	b_brake_hand_joint = _b_brake_elbow
	b_brake_hand       = _b_brake_hand
	b_near_foot_joint  = _b_near_knee
	b_near_foot        = _b_near_foot
	b_far_foot_joint   = _b_far_knee
	b_far_foot         = _b_far_foot

# Two-segment IK — identical law-of-cosines math to character.gd _constrain_arm.
# bend_sign: which side the elbow/knee pops out to.
#   +1 = pops to the RIGHT of the shoulder→hand vector
#   -1 = pops to the LEFT
func _solve_elbow(shoulder: Vector2, hand: Vector2, upper: float, lower: float, bend_sign: float) -> Vector2:
	var to_h := hand - shoulder
	var dist  = clamp(to_h.length(), abs(upper - lower) + 0.5, upper + lower - 0.5)
	var dir   := to_h.normalized()
	var ca    = clamp((upper * upper + dist * dist - lower * lower) / (2.0 * upper * dist), -1.0, 1.0)
	var ang   := acos(ca)
	# Perpendicular: Vector2(-dir.y, dir.x) is 90° CCW from dir
	return shoulder + dir * (upper * cos(ang)) + Vector2(-dir.y, dir.x) * (upper * sin(ang)) * bend_sign


func _solve_knee(hip: Vector2, foot: Vector2, upper: float, lower: float, bend_sign: float) -> Vector2:
	var to_f := foot - hip
	var dist  = clamp(to_f.length(), abs(upper - lower) + 0.5, upper + lower - 0.5)
	var dir   := to_f.normalized()
	var ca    = clamp((upper * upper + dist * dist - lower * lower) / (2.0 * upper * dist), -1.0, 1.0)
	var ang   := acos(ca)
	return hip + dir * (upper * cos(ang)) + Vector2(-dir.y, dir.x) * (upper * sin(ang)) * bend_sign

# =============================================================================
#  ROPE PHYSICS
# =============================================================================

func _simulate_rope(delta: float) -> void:
	if rope_points.size() < 3: return
	var chest := _player_chest()

	for i in range(1, rope_points.size() - 1):
		rope_velocities[i].y += ROPE_GRAVITY * delta
		if catch_state == CatchState.FALLING:
			rope_velocities[i].y += fall_vel * delta * 0.12
		elif catch_state == CatchState.STRETCHING:
			rope_velocities[i].y += fall_vel * delta * 0.20
		rope_velocities[i] *= SEGMENT_DRAG
		rope_points[i]     += rope_velocities[i] * delta

	var ai := _anchor_index()
	var up  := b_guide_hand.distance_to(anchor_position) / maxf(float(ai), 1.0)
	var dn  := anchor_position.distance_to(chest) / maxf(float(rope_points.size() - ai - 1), 1.0)

	for _pass in range(15):
		rope_points[0]                       = b_guide_hand
		rope_points[rope_points.size() - 1]  = chest
		rope_points[ai]                      = anchor_position
		_constrain_segment(0, ai, up)
		_constrain_segment(ai, rope_points.size() - 1, dn)

	_smooth_rope()


func _constrain_segment(from: int, to: int, seg_len: float) -> void:
	for i in range(from, to):
		var dv := rope_points[i + 1] - rope_points[i]
		var d  := dv.length()
		if d < 0.1: continue
		var cv := dv.normalized() * (d - seg_len) * ROPE_STIFFNESS * 0.5
		if i > from and rope_points[i].distance_to(anchor_position) >= 5.0:
			rope_points[i] += cv
		if i + 1 < to:
			rope_points[i + 1] -= cv


func _smooth_rope() -> void:
	for i in range(1, rope_points.size() - 1):
		if rope_points[i].distance_to(anchor_position) >= 5.0:
			rope_points[i] = rope_points[i - 1] * 0.2 + rope_points[i] * 0.6 + rope_points[i + 1] * 0.2


func _anchor_index() -> int:
	var best  := 0
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
	for i in range(ai + 1):                  up.append(rope_points[i])
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

# =============================================================================
#  BELAYER DRAW — two-pass outline+fill, identical visual grammar to character.gd
#
#  character.gd reference weights:
#    torso:      19px fill,  (19+ow) outline
#    upper arm:  12px fill,  (12+ow) outline
#    lower arm:  10px fill,  (10+ow) outline
#    upper leg:  12px fill,  (12+ow) outline
#    lower leg:  11px fill,  (11+ow) outline
#    hand:        8px circle fill,  (8+ow*0.5) outline
#    foot:        9px circle fill,  (9+ow*0.5) outline
#    elbow/knee:  5px circle
#    shoulder:    5px circle
#    head:       16px circle
#
#  Belayer is drawn at ~80% of those weights to feel like a background figure.
# =============================================================================

func _draw_belayer() -> void:
	const OW  = OUTLINE_WIDTH
	const TW  = 28.0
	var oc_skin  := _outline_color(SKIN_COLOR)
	var oc_shirt := _outline_color(SHIRT_COLOR)
	var oc_pants := _outline_color(PANTS_COLOR)
	var oc_shoe  := _outline_color(SHOE_COLOR)

	var neck  := to_local(_b_neck)
	var hips  := to_local(_b_hips)
	var nsh   := to_local(_b_near_sh)
	var fsh   := to_local(_b_far_sh)
	var nhip  := to_local(_b_near_hip)
	var fhip  := to_local(_b_far_hip)
	var gej   := to_local(_b_guide_elbow)
	var gh    := to_local(_b_guide_hand)
	var bej   := to_local(_b_brake_elbow)
	var bh    := to_local(_b_brake_hand)
	var nk    := to_local(_b_near_knee)
	var nf    := to_local(_b_near_foot)
	var fk    := to_local(_b_far_knee)
	var ff    := to_local(_b_far_foot)
	var head  := to_local(_b_head_center)

	# ── OUTLINE ───────────────────────────────────────────────────────────────

	# Legs
	draw_line(nhip, nk,  oc_pants, 13.0 + OW)
	draw_circle(nk,  6.0 + OW * 0.5, oc_pants)
	draw_line(nk,   nf,  oc_pants, 12.0 + OW)
	draw_circle(nf,  9.0 + OW * 0.5, oc_shoe)
	draw_line(fhip, fk,  oc_pants, 13.0 + OW)
	draw_circle(fk,  6.0 + OW * 0.5, oc_pants)
	draw_line(fk,   ff,  oc_pants, 12.0 + OW)
	draw_circle(ff,  9.0 + OW * 0.5, oc_shoe)

	# Arms
	draw_line(nsh,  gej, oc_skin, 13.0 + OW)
	draw_circle(gej, 6.5 + OW * 0.5, oc_skin)
	draw_line(gej,  gh,  oc_skin, 11.0 + OW)
	draw_circle(gh,  7.0 + OW * 0.5, oc_skin)
	draw_line(fsh,  bej, oc_skin, 13.0 + OW)
	draw_circle(bej, 6.5 + OW * 0.5, oc_skin)
	draw_line(bej,  bh,  oc_skin, 11.0 + OW)
	draw_circle(bh,  7.0 + OW * 0.5, oc_skin)

	# Torso over arm/leg roots
	draw_line(hips, neck, oc_shirt, TW + OW)

	# Head over torso top
	draw_circle(head, HEAD_RADIUS + OW * 0.5, oc_skin)

	# ── FILL ──────────────────────────────────────────────────────────────────

	# Legs
	draw_line(nhip, nk,  PANTS_COLOR, 13.0)
	draw_circle(nk,  6.0, PANTS_COLOR)
	draw_line(nk,   nf,  PANTS_COLOR, 12.0)
	draw_circle(nf,  9.0, SHOE_COLOR)
	draw_line(fhip, fk,  PANTS_COLOR, 13.0)
	draw_circle(fk,  6.0, PANTS_COLOR)
	draw_line(fk,   ff,  PANTS_COLOR, 12.0)
	draw_circle(ff,  9.0, SHOE_COLOR)

	# Hip harness
	draw_line(nhip, fhip, PANTS_COLOR,   18.0)
	draw_line(nhip, fhip, HARNESS_COLOR,  4.0)

	# Arms
	draw_line(nsh,  gej, SKIN_COLOR, 13.0)
	draw_circle(gej, 6.5, SKIN_COLOR)
	draw_line(gej,  gh,  SKIN_COLOR, 11.0)
	draw_circle(gh,  7.0, SKIN_COLOR)
	draw_line(fsh,  bej, SKIN_COLOR, 13.0)
	draw_circle(bej, 6.5, SKIN_COLOR)
	draw_line(bej,  bh,  SKIN_COLOR, 11.0)
	draw_circle(bh,  7.0, SKIN_COLOR)

	# Torso over arm/leg roots
	draw_line(hips, neck, SHIRT_COLOR, TW)

	# Head over torso top
	draw_circle(head, HEAD_RADIUS, SKIN_COLOR)

	if _rope_tension > 0.05:
		var device_color := HARNESS_COLOR.lerp(Color("#FF8C00"), _rope_tension * 0.6)
		device_color.a   = clamp(_rope_tension * 2.0, 0.3, 0.85)
		draw_circle(bh, 4.5, device_color)

# =============================================================================
#  OUTLINE HELPER — matches character.gd _outline_color exactly
# =============================================================================

func _outline_color(col: Color) -> Color:
	var lum := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	var r   := lerpf(lerpf(col.r, lum, OUTLINE_DARKEN * 0.3), 0.0, OUTLINE_DARKEN)
	var g   := lerpf(lerpf(col.g, lum, OUTLINE_DARKEN * 0.3), 0.0, OUTLINE_DARKEN)
	var b   := lerpf(lerpf(col.b, lum, OUTLINE_DARKEN * 0.3), 0.0, OUTLINE_DARKEN)
	return Color(r, g, b, OUTLINE_ALPHA)

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
			return wall.get_anchor_position_for_x(
				player.global_position.x if is_instance_valid(player) else 0.0)
	var best_y   := INF
	var best_pos := belayer_position + Vector2(0, -200)
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.global_position.y < best_y:
			best_y = hold.global_position.y
			best_pos = hold.global_position
	return best_pos + Vector2(0, -30)


func _init_rope() -> void:
	rope_points.clear()
	rope_velocities.clear()
	var waypoints := [b_guide_hand, anchor_position, _player_chest()]
	var total     := 0.0
	for i in range(waypoints.size() - 1):
		total += waypoints[i].distance_to(waypoints[i + 1])
	var seg_len := total / float(ROPE_SEGMENTS - 1)
	var seg_i   := 0
	var accum   := 0.0
	var seg_s   = waypoints[0]
	var seg_e   = waypoints[1]
	var seg_l   = seg_s.distance_to(seg_e)
	for i in range(ROPE_SEGMENTS):
		var td := i * seg_len
		while td > accum + seg_l and seg_i < waypoints.size() - 2:
			accum += seg_l
			seg_i += 1
			seg_s  = waypoints[seg_i]
			seg_e  = waypoints[seg_i + 1]
			seg_l  = seg_s.distance_to(seg_e)
		rope_points.append(seg_s.lerp(seg_e,
			clamp((td - accum) / maxf(seg_l, 0.001), 0.0, 1.0)))
		rope_velocities.append(Vector2.ZERO)

# =============================================================================
#  EXTERNAL API
# =============================================================================

func get_belayer_guide_hand_world() -> Vector2:
	return _b_guide_hand


func apply_rope_force_to_player(vel: Vector2) -> Vector2:
	return vel  # hook for future tension feedback


func cleanup() -> void:
	is_setup = false
	set_process(false)
	if is_instance_valid(rope_line):  rope_line.queue_free();  rope_line  = null
	if is_instance_valid(rope_lower): rope_lower.queue_free(); rope_lower = null
