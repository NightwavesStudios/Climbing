extends Node2D
class_name RopeSystem

## Top-rope climbing system - PURELY VISUAL

@export var rope_color := Color.BLACK
@export var rope_thickness := 2.5

# Rope physics - purely visual
const ROPE_SEGMENTS := 25
const ROPE_STIFFNESS := 0.95
const ROPE_DAMPING := 0.98
const GRAVITY := 50.0
const SEGMENT_DRAG := 0.95

# ── Belayer body constants ────────────────────────────────────────────────
# Limbs scaled down vs the climbing player — belayer is standing relaxed,
# not stretched across a wall, so everything should look compact.
const ARM_UPPER_LENGTH := 28.0
const ARM_LOWER_LENGTH := 26.0
const LEG_UPPER_LENGTH := 30.0
const LEG_LOWER_LENGTH := 28.0
const SHOULDER_OFFSET  := 0.0
const HIP_OFFSET       := 0.0
const HIP_DOWN         := 18.0
const HEAD_OFFSET      := -18.0

# Tighter angles for a relaxed standing pose (not a spread-eagle climber)
const ARM_NATURAL_ANGLE_DEG := 25.0   # arms hang close to body
const LEG_NATURAL_SPLAY_DEG := 12.0   # feet only slightly apart

# ── Belayer joint positions (world-space, computed each frame) ─────────────
# These mirror the player's Node2D children (left_hand_joint, left_hand, etc.)
var b_left_hand_joint  := Vector2.ZERO
var b_right_hand_joint := Vector2.ZERO
var b_left_foot_joint  := Vector2.ZERO
var b_right_foot_joint := Vector2.ZERO
var b_left_hand        := Vector2.ZERO
var b_right_hand       := Vector2.ZERO
var b_left_foot        := Vector2.ZERO
var b_right_foot       := Vector2.ZERO

# ── Belayer animation ──────────────────────────────────────────────────────
var belayer_facing_right := true

# Guide hand pull — drives the near-wall hand upward during slack bursts
var guide_hand_pull := 0.0

# Slack burst system
var slack_burst_timer    : float = 0.0
var slack_burst_active   : bool  = false
var slack_burst_intensity: float = 0.0
var slack_between_bursts : float = 1.0

const BURST_INTERVAL_MIN := 1.4
const BURST_INTERVAL_MAX := 3.2
const BURST_DURATION     := 0.38
const BURST_MAGNITUDE    := 16.0   # pixels the guide hand travels upward

# How fast the free hand drifts back to neutral between bursts
const ARM_RETURN_SPEED := 4.0

# ── Rope state ─────────────────────────────────────────────────────────────
var belayer_position : Vector2 = Vector2.ZERO
var anchor_position  : Vector2 = Vector2.ZERO
var rope_points      : Array[Vector2] = []
var rope_velocities  : Array[Vector2] = []
var rope_tension     : float = 0.0
var is_setup         : bool  = false

# ── Player reference ───────────────────────────────────────────────────────
var player               : Node2D = null
var player_attach_offset : Vector2 = Vector2(0, -10)

# ── Visual ─────────────────────────────────────────────────────────────────
var rope_line: Line2D = null

# ═══════════════════════════════════════════════════════════════════════════
func _ready():
	global_position = Vector2.ZERO
	z_index = 50

	rope_line = Line2D.new()
	rope_line.width              = rope_thickness
	rope_line.default_color      = rope_color
	rope_line.z_index            = 49
	rope_line.top_level          = true
	rope_line.antialiased        = true
	rope_line.begin_cap_mode     = Line2D.LINE_CAP_ROUND
	rope_line.end_cap_mode       = Line2D.LINE_CAP_ROUND
	rope_line.joint_mode         = Line2D.LINE_JOINT_ROUND
	add_child(rope_line)

	set_process(true)

# ═══════════════════════════════════════════════════════════════════════════
func _process(delta):
	if not is_setup:
		return

	if player and rope_points.size() > 0:
		update_belayer_joints()          # compute joint world-positions
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

	if anchor_pos == Vector2.ZERO:
		anchor_position = find_top_anchor()
	else:
		anchor_position = anchor_pos

	var player_chest = get_player_chest_position()
	belayer_facing_right = player_chest.x > anchor_position.x

	# Initialise joint positions to natural pose before first frame
	update_belayer_joints()

	var belayer_hand = get_belayer_guide_hand_world()

	rope_points.clear()
	rope_velocities.clear()

	var path_points = [belayer_hand, anchor_position, player_chest]

	var total_length = 0.0
	for i in range(path_points.size() - 1):
		total_length += path_points[i].distance_to(path_points[i + 1])

	var segment_length    = total_length / float(ROPE_SEGMENTS - 1)
	var current_section   = 0
	var distance_in_section = 0.0
	var section_start     = path_points[0]
	var section_end       = path_points[1]
	var section_length    = section_start.distance_to(section_end)

	for i in range(ROPE_SEGMENTS):
		var target_distance = i * segment_length

		while target_distance > distance_in_section + section_length \
				and current_section < path_points.size() - 2:
			distance_in_section += section_length
			current_section     += 1
			section_start        = path_points[current_section]
			section_end          = path_points[current_section + 1]
			section_length       = section_start.distance_to(section_end)

		var t = 0.0
		if section_length > 0:
			t = (target_distance - distance_in_section) / section_length

		rope_points.append(section_start.lerp(section_end, t))
		rope_velocities.append(Vector2.ZERO)

	is_setup    = true
	visible     = true
	if rope_line:
		rope_line.visible = true

	print("Top-rope setup: ", rope_points.size(), " segments")
	print("  Belayer guide hand: ", belayer_hand)
	print("  Anchor: ",             anchor_position)
	print("  Player chest: ",       player_chest)

# ═══════════════════════════════════════════════════════════════════════════
## Belayer joint computation
## This mirrors EXACTLY what the player's apply_natural_limb_positions() does
## but for the belayer — driven by guide_hand_pull instead of physics.
# ═══════════════════════════════════════════════════════════════════════════

func update_belayer_joints():
	"""
	Compute all 8 joint world-positions for the belayer using the same
	shoulder/hip offsets and natural-pose angles as the player character.

	sm  = +1  →  facing right  (wall is to the right)
	sm  = -1  →  facing left   (wall is to the left)

	'near' = toward the wall  (guide hand side)
	'far'  = away from wall   (brake hand side)
	"""
	var sm   = 1.0 if belayer_facing_right else -1.0
	var b    = belayer_position                         # body origin (world)

	# ── Shoulder and hip world-positions (same offsets as player) ──────────
	# Player SHOULDER_OFFSET and HIP_OFFSET are both 0.0,
	# so shoulders/hips sit at the body centre — just like the player.
	# We add a small lateral splay so the arms read correctly.
	var near_shoulder = b + Vector2( sm * 8.0, 0.0)
	var far_shoulder  = b + Vector2(-sm * 8.0, 0.0)

	var near_hip = b + Vector2( sm * 6.0, HIP_DOWN)
	var far_hip  = b + Vector2(-sm * 6.0, HIP_DOWN)

	# ── GUIDE ARM (near / toward-wall) ────────────────────────────────────
	# Raised up toward the anchor, elbow bent, hand higher than shoulder.
	# guide_hand_pull animates this further up during slack bursts.
	var pull_offset = Vector2(0.0, guide_hand_pull)

	# Elbow: out slightly toward wall and raised to shoulder height
	b_right_hand_joint = near_shoulder + Vector2(sm * 8.0,  -8.0)  + pull_offset * 0.4
	# Hand: above and toward wall — actively feeding rope upward
	b_right_hand       = near_shoulder + Vector2(sm * 12.0, -22.0) + pull_offset

	# ── BRAKE ARM (far / away-from-wall) ──────────────────────────────────
	# Hangs down and slightly inward — locked-off brake position.
	b_left_hand_joint = far_shoulder + Vector2(-sm * 5.0,  14.0)
	b_left_hand       = far_shoulder + Vector2(-sm * 7.0,  26.0)

	# ── NEAR LEG (toward wall — slight forward stance) ────────────────────
	var leg_angle_rad = deg_to_rad(LEG_NATURAL_SPLAY_DEG)

	var near_knee_local = Vector2(
		 sm  * LEG_UPPER_LENGTH * sin(leg_angle_rad),
			   LEG_UPPER_LENGTH * cos(leg_angle_rad)
	)
	b_right_foot_joint = near_hip + near_knee_local
	b_right_foot       = b_right_foot_joint + Vector2(0.0, LEG_LOWER_LENGTH)

	# ── FAR LEG (away from wall — slight back stance) ─────────────────────
	var far_knee_local = Vector2(
		-sm  * LEG_UPPER_LENGTH * sin(leg_angle_rad) * 0.7,
			   LEG_UPPER_LENGTH * cos(leg_angle_rad)
	)
	b_left_foot_joint = far_hip + far_knee_local
	b_left_foot       = b_left_foot_joint + Vector2(0.0, LEG_LOWER_LENGTH)

# ═══════════════════════════════════════════════════════════════════════════
## Rope attachment point — the guide hand in world space
# ═══════════════════════════════════════════════════════════════════════════

func get_belayer_guide_hand_world() -> Vector2:
	return b_right_hand   # right_hand = near/guide hand

# ═══════════════════════════════════════════════════════════════════════════
## Belayer animation — slack bursts
# ═══════════════════════════════════════════════════════════════════════════

func update_belayer_animation(delta: float):
	"""
	Realistic belayer slack management.
	Between bursts the guide hand rests at neutral (guide_hand_pull → 0).
	A burst fires periodically: the hand sweeps UP (negative Y) then returns,
	like a real belayer taking in slack after the climber moves.
	"""
	if not slack_burst_active:
		slack_between_bursts -= delta
		# Drift guide hand back to neutral while waiting
		guide_hand_pull = lerp(guide_hand_pull, 0.0, ARM_RETURN_SPEED * delta)

		if slack_between_bursts <= 0.0:
			slack_burst_active    = true
			slack_burst_timer     = BURST_DURATION
			slack_burst_intensity = randf_range(0.55, 1.0)
	else:
		slack_burst_timer -= delta
		# sin arc: smooth 0 → peak → 0 over the burst window
		var t            = 1.0 - (slack_burst_timer / BURST_DURATION)
		var burst_curve  = sin(t * PI)
		guide_hand_pull  = -burst_curve * BURST_MAGNITUDE * slack_burst_intensity

		if slack_burst_timer <= 0.0:
			slack_burst_active   = false
			slack_between_bursts = randf_range(BURST_INTERVAL_MIN, BURST_INTERVAL_MAX)

	# Keep facing correct based on player position
	if player:
		var player_chest     = get_player_chest_position()
		var target_facing    = player_chest.x > anchor_position.x
		belayer_facing_right = target_facing

# ═══════════════════════════════════════════════════════════════════════════
## Rope physics
# ═══════════════════════════════════════════════════════════════════════════

func simulate_rope_physics(delta: float):
	if rope_points.size() < 3 or not player:
		return

	var belayer_hand = get_belayer_guide_hand_world()
	var player_chest = get_player_chest_position()

	# Gravity droop on internal points
	for i in range(1, rope_points.size() - 1):
		rope_velocities[i].y += GRAVITY * delta
		rope_velocities[i]   *= SEGMENT_DRAG

	for i in range(1, rope_points.size() - 1):
		rope_points[i] += rope_velocities[i] * delta

	rope_tension = 0.0

	for _iter in range(15):
		rope_points[0]                      = belayer_hand
		rope_points[rope_points.size() - 1] = player_chest

		# Find point closest to anchor
		var anchor_index = 0
		var min_dist     = rope_points[0].distance_to(anchor_position)
		for i in range(1, rope_points.size()):
			var dist = rope_points[i].distance_to(anchor_position)
			if dist < min_dist:
				min_dist     = dist
				anchor_index = i

		rope_points[anchor_index] = anchor_position

		var up_segment_count   = anchor_index
		var up_distance        = belayer_hand.distance_to(anchor_position)
		var down_distance      = anchor_position.distance_to(player_chest)
		var up_segment_length  = up_distance   / max(1.0, float(up_segment_count))
		var down_segment_length = down_distance / max(1.0, float(rope_points.size() - anchor_index - 1))

		# Up section constraints
		for i in range(up_segment_count):
			var p1        = rope_points[i]
			var p2        = rope_points[i + 1]
			var dv        = p2 - p1
			var distance  = dv.length()
			if distance < 0.1:
				continue
			var correction        = (distance - up_segment_length) * ROPE_STIFFNESS
			var correction_vector = dv.normalized() * correction * 0.5
			if i > 0:
				rope_points[i] += correction_vector
			if i + 1 < rope_points.size() - 1 and i + 1 != anchor_index:
				rope_points[i + 1] -= correction_vector

		# Down section constraints
		for i in range(anchor_index, rope_points.size() - 1):
			var p1        = rope_points[i]
			var p2        = rope_points[i + 1]
			var dv        = p2 - p1
			var distance  = dv.length()
			if distance < 0.1:
				continue
			var correction        = (distance - down_segment_length) * ROPE_STIFFNESS
			var correction_vector = dv.normalized() * correction * 0.5
			if i != anchor_index:
				rope_points[i] += correction_vector
			if i + 1 < rope_points.size() - 1:
				rope_points[i + 1] -= correction_vector

	smooth_rope_points()

func smooth_rope_points():
	if rope_points.size() < 3:
		return

	var smoothed = rope_points.duplicate()

	for i in range(1, rope_points.size() - 1):
		if rope_points[i].distance_to(anchor_position) < 5.0:
			continue
		var prev      = rope_points[i - 1]
		var curr      = rope_points[i]
		var next      = rope_points[i + 1]
		smoothed[i]   = prev * 0.2 + curr * 0.6 + next * 0.2

	for i in range(1, rope_points.size() - 1):
		if rope_points[i].distance_to(anchor_position) >= 5.0:
			rope_points[i] = smoothed[i]

# ═══════════════════════════════════════════════════════════════════════════
## Rope visual
# ═══════════════════════════════════════════════════════════════════════════

func update_rope_visual():
	if not rope_line or rope_points.size() < 2:
		return
	var points = PackedVector2Array()
	for point in rope_points:
		points.append(point)
	rope_line.points = points
	rope_line.width  = rope_thickness

# ═══════════════════════════════════════════════════════════════════════════
## Helper positions
# ═══════════════════════════════════════════════════════════════════════════

func get_player_chest_position() -> Vector2:
	if player:
		return player.global_position + player_attach_offset
	return belayer_position + Vector2(0, 100)

func find_top_anchor() -> Vector2:
	var highest_y = player.global_position.y
	for hold in get_tree().get_nodes_in_group("holds"):
		if hold.global_position.y < highest_y:
			highest_y = hold.global_position.y
	return Vector2(belayer_position.x, highest_y - 60.0)

# ═══════════════════════════════════════════════════════════════════════════
## Drawing — pure black stick figure, C&P structure from player's draw_stick_figure()
# ═══════════════════════════════════════════════════════════════════════════

func _draw():
	if not is_setup:
		return

	var black = Color.BLACK
	var lw    = 4.0

	# Convert all world-space joint positions to this node's local space.
	# The player uses node-local positions (child node .position) directly in
	# draw_line() — we do the same by converting world → local once here.
	var b     = to_local(belayer_position)

	var neck  = b + Vector2(0, HEAD_OFFSET + 12)
	var hips  = b + Vector2(0, HIP_DOWN)

	# Convert joint world positions → local
	var lhj = to_local(b_left_hand_joint)   # brake elbow
	var lh  = to_local(b_left_hand)         # brake hand
	var rhj = to_local(b_right_hand_joint)  # guide elbow
	var rh  = to_local(b_right_hand)        # guide hand
	var lfj = to_local(b_left_foot_joint)   # far knee
	var lf  = to_local(b_left_foot)         # far foot
	var rfj = to_local(b_right_foot_joint)  # near knee
	var rf  = to_local(b_right_foot)        # near foot

	# ── Compute shoulder and hip local positions ───────────────────────────
	# (same lateral offset used in update_belayer_joints)
	var sm            = 1.0 if belayer_facing_right else -1.0
	var near_shoulder = neck + Vector2( sm * 8.0, 0.0)
	var far_shoulder  = neck + Vector2(-sm * 8.0, 0.0)
	var near_hip      = hips + Vector2( sm * 6.0, 0.0)
	var far_hip       = hips + Vector2(-sm * 6.0, 0.0)

	# ── Draw order: back limbs first, then torso, then front limbs ─────────

	# FAR/BRAKE arm (behind torso)
	draw_line(far_shoulder, lhj, black, lw)
	draw_line(lhj,          lh,  black, lw - 1)
	draw_circle(lh, 5, black)

	# FAR leg (behind)
	draw_line(far_hip, lfj, black, lw)
	draw_line(lfj,     lf,  black, lw - 1)
	draw_circle(lf, 5, black)

	# ── TORSO (same as player: neck → hips spine line) ─────────────────────
	draw_line(neck, hips, black, lw)

	# Shoulder cross-bar
	draw_line(near_shoulder, far_shoulder, black, lw)

	# ── HEAD (same radius as player: 16) ──────────────────────────────────
	draw_circle(b + Vector2(0, HEAD_OFFSET), 16, black)

	# NEAR/GUIDE arm (in front of torso)
	draw_line(near_shoulder, rhj, black, lw)
	draw_line(rhj,           rh,  black, lw - 1)
	draw_circle(rh, 5, black)

	# NEAR leg (in front)
	draw_line(near_hip, rfj, black, lw)
	draw_line(rfj,      rf,  black, lw - 1)
	draw_circle(rf, 5, black)

	# ── ANCHOR marker ─────────────────────────────────────────────────────
	var anchor_local = to_local(anchor_position)
	draw_circle(anchor_local, 8, black)
	draw_circle(anchor_local, 6, Color.WHITE)
	draw_circle(anchor_local, 4, black)

# ═══════════════════════════════════════════════════════════════════════════

func cleanup():
	if rope_line:
		rope_line.queue_free()
	queue_free()
