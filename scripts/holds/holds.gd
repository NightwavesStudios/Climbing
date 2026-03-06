extends Area2D
class_name ClimbingHold

enum HoldType { JUG, START, TOP_OUT, CRIMP, SLOPER, FOOTHOLD, POCKET, WINDOW }

@export var hold_type: HoldType = HoldType.JUG
@export var difficulty: float = 0.0
@export var rest_value: float = 0.0
@export var snap_to_point: bool = true
@export var is_grabbable: bool = true
@export var multi_area_enabled: bool = false

const GRAB_SFX = preload("res://assets/audio/sfx/grab-hold.wav")

var _audio_player: AudioStreamPlayer
var occupied_by: Node2D = null
var limb_placements: Dictionary = {}
var grab_areas: Dictionary = {}
var sprite_nodes: Dictionary = {}
var _type_was_set_manually: bool = false

@onready var hold_point: Marker2D = $HoldPoint

func _ready():
	print("climbing_hold _ready fired on: ", name, " | has _process: ", has_method("_process"))
	if not is_grabbable:
		collision_layer = 0
		collision_mask = 0
		monitoring = false
		monitorable = false
		set_process(false)
		add_to_group("decorations")
		_cache_sprite_nodes()
		_update_sprite_for_environment()
		return

	collision_layer = 2
	collision_mask = 0
	monitoring = true
	# Explicitly enable _process so modifiers receive on_process() every frame.
	set_process(true)

	if not _type_was_set_manually:
		_auto_detect_type_from_name()
		_configure_hold_properties()

	add_to_group("holds")

	if multi_area_enabled:
		_setup_multi_areas()

	_cache_sprite_nodes()
	_update_sprite_for_environment()

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.stream = GRAB_SFX
	_audio_player.volume_db = 12.0

# ── Modifier hook: drive on_process every frame ───────────────────────────────
func _process(delta: float) -> void:
	for child in get_children():
		if child.has_method("on_process"):
			child.on_process(delta)

func _setup_multi_areas():
	grab_areas.clear()
	for child in get_children():
		if child is Area2D and child != self:
			var point_name = child.name.replace("Area2D", "Point")
			var point = get_node_or_null(point_name)
			if point and point is Marker2D:
				grab_areas[child] = point

func _cache_sprite_nodes():
	sprite_nodes.clear()
	for child in get_children():
		if child is Sprite2D:
			var node_name = child.name
			if "Gym" in node_name:
				sprite_nodes["Gym"] = child
			elif "Granite" in node_name:
				sprite_nodes["Granite"] = child
			elif "Sandstone" in node_name:
				sprite_nodes["Sandstone"] = child

	if sprite_nodes.size() == 0 and get_parent():
		for sibling in get_parent().get_children():
			if sibling is Sprite2D and sibling != self:
				var node_name = sibling.name
				if "Gym" in node_name:
					sprite_nodes["Gym"] = sibling
				elif "Granite" in node_name:
					sprite_nodes["Granite"] = sibling
				elif "Sandstone" in node_name:
					sprite_nodes["Sandstone"] = sibling

func _update_sprite_for_environment():
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if not env_config:
		return
	var sprite_suffix = env_config.get_sprite_suffix()
	for suffix in sprite_nodes:
		if sprite_nodes[suffix]:
			sprite_nodes[suffix].visible = false
	if sprite_suffix in sprite_nodes and sprite_nodes[sprite_suffix]:
		sprite_nodes[sprite_suffix].visible = true

func _auto_detect_type_from_name():
	var scene_path = scene_file_path
	if scene_path == "":
		return
	var filename = scene_path.get_file().to_lower()
	if hold_type != HoldType.JUG:
		return
	if "start" in filename:
		hold_type = HoldType.START
	elif "top" in filename:
		hold_type = HoldType.TOP_OUT
	elif "crimp" in filename:
		hold_type = HoldType.CRIMP
	elif "sloper" in filename:
		hold_type = HoldType.SLOPER
	elif "pocket" in filename:
		hold_type = HoldType.POCKET
	elif "foot" in filename:
		hold_type = HoldType.FOOTHOLD

func _configure_hold_properties():
	match hold_type:
		HoldType.JUG:
			difficulty = 0.0
			rest_value = 50.0
		HoldType.START:
			difficulty = 0.0
			rest_value = 50.0
		HoldType.TOP_OUT:
			difficulty = 0.0
			rest_value = 10.0
		HoldType.CRIMP:
			difficulty = 3.0
			rest_value = 0.0
		HoldType.SLOPER:
			difficulty = 2.5
			rest_value = 0.0
		HoldType.FOOTHOLD:
			difficulty = 1.0
			rest_value = 0.0
		HoldType.POCKET:
			difficulty = 1.2
			rest_value = 0.0

func set_hold_type_from_string(type_str: String):
	_type_was_set_manually = true
	match type_str.to_upper():
		"START":
			hold_type = HoldType.START
		"TOP":
			hold_type = HoldType.TOP_OUT
		"JUG":
			hold_type = HoldType.JUG
		"CRIMP":
			hold_type = HoldType.CRIMP
		"SLOPER":
			hold_type = HoldType.SLOPER
		"FOOT":
			hold_type = HoldType.FOOTHOLD
		"POCKET":
			hold_type = HoldType.POCKET
	_configure_hold_properties()

func is_start_hold() -> bool:
	return hold_type == HoldType.START

func is_top_out() -> bool:
	return hold_type == HoldType.TOP_OUT

func is_jug() -> bool:
	return hold_type == HoldType.JUG

func is_crimp() -> bool:
	return hold_type == HoldType.CRIMP

func is_sloper() -> bool:
	return hold_type == HoldType.SLOPER

func is_foothold() -> bool:
	return hold_type == HoldType.FOOTHOLD

func is_pocket() -> bool:
	return hold_type == HoldType.POCKET

func try_claim(limb: Node2D, is_foot: bool, grab_position: Vector2) -> bool:
	if not is_grabbable:
		return false
	if is_foothold() and not is_foot:
		return false
	if is_pocket():
		if occupied_by != null and occupied_by != limb:
			return false

	# ── Modifier: allow_grab gate ─────────────────────────────────────────────
	for child in get_children():
		if child.has_method("allow_grab"):
			if not child.allow_grab(limb, is_foot):
				return false

	var local_grab: Vector2
	if snap_to_point:
		if multi_area_enabled:
			var snap_point = _find_nearest_area_point(grab_position)
			local_grab = to_local(snap_point.global_position)
		else:
			if grab_position != Vector2.ZERO:
				local_grab = to_local(grab_position)
			else:
				local_grab = to_local(hold_point.global_position)
	else:
		local_grab = to_local(grab_position)
		var shape_node = get_node_or_null("CollisionShape2D")
		if shape_node and shape_node.shape:
			var shape_offset: Vector2 = shape_node.position
			var local_relative = local_grab - shape_offset
			if shape_node.shape is RectangleShape2D:
				var half = shape_node.shape.size / 2.0
				local_relative = Vector2(
					clamp(local_relative.x, -half.x, half.x),
					clamp(local_relative.y, -half.y, half.y)
				)
			elif shape_node.shape is CircleShape2D:
				var radius = shape_node.shape.radius
				if local_relative.length() > radius:
					local_relative = local_relative.normalized() * radius
			local_grab = local_relative + shape_offset

	occupied_by = limb
	limb_placements[limb] = local_grab

	_audio_player.pitch_scale = randf_range(0.8, 1.3)
	_audio_player.play()

	# ── Modifier: notify grab ─────────────────────────────────────────────────
	for child in get_children():
		if child.has_method("on_grab"):
			child.on_grab(limb)

	return true

func _find_nearest_area_point(global_pos: Vector2) -> Marker2D:
	if grab_areas.size() == 0:
		return hold_point
	var nearest_point = hold_point
	var nearest_dist = INF
	for area in grab_areas:
		var point = grab_areas[area]
		var dist = point.global_position.distance_to(global_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_point = point
	return nearest_point

func release(limb: Node2D):
	if occupied_by == limb:
		occupied_by = null
	limb_placements.erase(limb)

	# ── Modifier: notify release ──────────────────────────────────────────────
	for child in get_children():
		if child.has_method("on_release"):
			child.on_release(limb)

func can_grab(limb: Node2D, is_foot: bool) -> bool:
	if not is_grabbable:
		return false
	if is_foothold() and not is_foot:
		return false
	if is_pocket() and occupied_by != null and occupied_by != limb:
		return false

	# ── Modifier: allow_grab gate ─────────────────────────────────────────────
	for child in get_children():
		if child.has_method("allow_grab"):
			if not child.allow_grab(limb, is_foot):
				return false

	return true

func get_limb_anchor(limb: Node2D) -> Vector2:
	if limb in limb_placements:
		return to_global(limb_placements[limb])
	if snap_to_point:
		return hold_point.global_position
	return limb.global_position

func get_placement_offset(limb: Node2D) -> float:
	if limb not in limb_placements:
		return 0.0
	var local_pos = limb_placements[limb]
	var shape = get_node_or_null("CollisionShape2D")
	if not shape or not shape.shape:
		return 0.0
	var shape_extents = Vector2.ZERO
	if shape.shape is RectangleShape2D:
		shape_extents = shape.shape.size / 2.0
	elif shape.shape is CircleShape2D:
		var radius = shape.shape.radius
		shape_extents = Vector2(radius, radius)
	if shape_extents.length() < 0.1:
		return 0.0
	return clamp(local_pos.length() / shape_extents.length(), 0.0, 1.0)

func get_placement_difficulty_modifier(limb: Node2D) -> float:
	if not snap_to_point:
		var offset = get_placement_offset(limb)
		match hold_type:
			HoldType.SLOPER:
				return 1.0 + (offset * 2.0)
			HoldType.CRIMP:
				return 1.0 + (offset * 1.0)
			HoldType.POCKET:
				return 1.0 + (offset * 0.3)
			_:
				return 1.0 + (offset * 0.5)
	return 1.0

func get_state_pressure(delta: float, body_offset: float, time_static: float, foot_support_ratio: float, limb: Node2D) -> float:
	var pressure = difficulty * delta
	pressure *= get_placement_difficulty_modifier(limb)
	if is_sloper():
		pressure += delta * 2.0
	pressure += body_offset * 0.3 * delta
	if difficulty > 0.5:
		pressure += time_static * 0.2 * delta
	if foot_support_ratio > 0.0:
		pressure *= 1.0 - (0.5 * foot_support_ratio)
	return pressure

func get_recovery_rate(delta: float, body_balance: float, foot_support_ratio: float) -> float:
	if rest_value <= 0.0:
		return 0.0
	var recovery = rest_value * delta
	recovery += body_balance * 0.5 * delta
	recovery *= 0.5 + 0.5 * foot_support_ratio
	return recovery

func notify_climb_start():
	# Reset all modifiers so falling holds restore on climb reload.
	for child in get_children():
		if child.has_method("on_climb_reset"):
			child.on_climb_reset()
