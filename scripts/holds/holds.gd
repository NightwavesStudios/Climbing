extends Area2D
class_name ClimbingHold

enum HoldType { JUG, START, TOP_OUT, CRIMP, SLOPER, FOOTHOLD, POCKET, WINDOW }

@export var hold_type: HoldType = HoldType.JUG
@export var difficulty: float = 0.0
@export var rest_value: float = 0.0
@export var snap_to_point: bool = true
@export var is_grabbable: bool = true
@export var multi_area_enabled: bool = false
@export var shadow_enabled: bool = false


# =============================================================================
#  SHADOW EXPORTS
# =============================================================================
@export_group("Shadow")
## Overall shadow darkness multiplier.
@export_range(0.5, 3.0, 0.05) var shadow_intensity: float = 2.2
## How many pixels the shadow spreads beyond the sprite edge.
@export var shadow_spread: float = 12.0
## Number of stacked shadow passes — more = softer, denser gradient.
@export_range(1, 5, 1) var shadow_passes: int = 4
## How far the shadow is cast along the light direction.
@export var shadow_offset_scale: float = 7.0
@export_group("")

const GRAB_SFX = preload("res://assets/audio/sfx/grab-hold.wav")

var _audio_player: AudioStreamPlayer
var occupied_by: Node2D = null
var limb_placements: Dictionary = {}
var grab_areas: Array[CollisionShape2D] = []
var sprite_nodes: Dictionary = {}
var _type_was_set_manually: bool = false
var _max_limbs: int = 1

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
		await _wait_for_env_config()
		_update_sprite_for_environment()
		return

	collision_layer = 2
	collision_mask = 0
	monitoring = true
	set_process(true)

	if not _type_was_set_manually:
		_auto_detect_type_from_name()
		_configure_hold_properties()

	# Load max_limbs from HoldRegistry
	var registry = get_node_or_null("/root/HoldRegistry")
	if registry:
		var type_key = HoldType.keys()[hold_type]
		_max_limbs = registry.get_config_value(type_key, "max_limbs", 1)
		print("Hold: ", name, " | type: ", type_key, " | _max_limbs: ", _max_limbs)

	add_to_group("holds")

	if multi_area_enabled:
		_setup_multi_areas()

	_cache_sprite_nodes()
	await _wait_for_env_config()
	_update_sprite_for_environment()

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.stream = GRAB_SFX
	_audio_player.volume_db = 12.0

func _wait_for_env_config() -> void:
	var timeout := 0
	while get_node_or_null("/root/EnvironmentConfig") == null and timeout < 120:
		await get_tree().process_frame
		timeout += 1

func _process(delta: float) -> void:
	for child in get_children():
		if child.has_method("on_process"):
			child.on_process(delta)
	queue_redraw()

func _setup_multi_areas():
	grab_areas.clear()
	for child in get_children():
		if child is CollisionShape2D:
			grab_areas.append(child)
	print("multi_area setup on ", name, " — found ", grab_areas.size(), " shapes")

func _find_nearest_shape(global_pos: Vector2) -> CollisionShape2D:
	if grab_areas.is_empty():
		return get_node_or_null("CollisionShape2D")
	var nearest: CollisionShape2D = grab_areas[0]
	var nearest_dist: float = INF
	for shape in grab_areas:
		var dist: float = shape.global_position.distance_to(global_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = shape
	return nearest

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
			elif "Ice" in node_name:
				sprite_nodes["Ice"] = child

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
	elif "window" in filename:
		hold_type = HoldType.WINDOW

func _configure_hold_properties():
	match hold_type:
		HoldType.JUG:
			difficulty = 0.0; rest_value = 50.0
		HoldType.START:
			difficulty = 0.0; rest_value = 50.0
		HoldType.TOP_OUT:
			difficulty = 0.0; rest_value = 10.0
		HoldType.CRIMP:
			difficulty = 3.0; rest_value = 0.0
		HoldType.SLOPER:
			difficulty = 2.5; rest_value = 0.0
		HoldType.FOOTHOLD:
			difficulty = 1.0; rest_value = 0.0
		HoldType.POCKET:
			difficulty = 1.2; rest_value = 0.0
		HoldType.WINDOW:
			difficulty = 1.5; rest_value = 5.0

func set_hold_type_from_string(type_str: String):
	_type_was_set_manually = true
	match type_str.to_upper():
		"START":  hold_type = HoldType.START
		"TOP":    hold_type = HoldType.TOP_OUT
		"JUG":    hold_type = HoldType.JUG
		"CRIMP":  hold_type = HoldType.CRIMP
		"SLOPER": hold_type = HoldType.SLOPER
		"FOOT":   hold_type = HoldType.FOOTHOLD
		"POCKET": hold_type = HoldType.POCKET
		"WINDOW": hold_type = HoldType.WINDOW
	_configure_hold_properties()

func is_start_hold() -> bool: return hold_type == HoldType.START
func is_top_out()    -> bool: return hold_type == HoldType.TOP_OUT
func is_jug()        -> bool: return hold_type == HoldType.JUG
func is_crimp()      -> bool: return hold_type == HoldType.CRIMP
func is_sloper()     -> bool: return hold_type == HoldType.SLOPER
func is_foothold()   -> bool: return hold_type == HoldType.FOOTHOLD
func is_pocket()     -> bool: return hold_type == HoldType.POCKET
func is_window()     -> bool: return hold_type == HoldType.WINDOW

func try_claim(limb: Node2D, is_foot: bool, grab_position: Vector2) -> bool:
	if not is_grabbable:
		return false
	if is_foothold() and not is_foot:
		return false
	if is_pocket():
		if occupied_by != null and occupied_by != limb:
			return false
	if not is_pocket() and limb not in limb_placements and limb_placements.size() >= _max_limbs:
		return false

	for child in get_children():
		if child.has_method("allow_grab"):
			if not child.allow_grab(limb, is_foot):
				return false

	var local_grab: Vector2
	if snap_to_point:
		if multi_area_enabled:
			var snap_shape = _find_nearest_shape(grab_position)
			local_grab = to_local(snap_shape.global_position)
		else:
			local_grab = to_local(grab_position) if grab_position != Vector2.ZERO else Vector2.ZERO
	else:
		local_grab = to_local(grab_position)
		var shape_node: CollisionShape2D
		if multi_area_enabled:
			shape_node = _find_nearest_shape(grab_position)
		else:
			shape_node = get_node_or_null("CollisionShape2D")
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

	for child in get_children():
		if child.has_method("on_grab"):
			child.on_grab(limb)

	return true

func release(limb: Node2D):
	if occupied_by == limb:
		occupied_by = null
	limb_placements.erase(limb)

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
	if not is_pocket() and limb not in limb_placements and limb_placements.size() >= _max_limbs:
		return false

	for child in get_children():
		if child.has_method("allow_grab"):
			if not child.allow_grab(limb, is_foot):
				return false

	return true

func get_limb_anchor(limb: Node2D) -> Vector2:
	if limb in limb_placements:
		return to_global(limb_placements[limb])
	if snap_to_point:
		if multi_area_enabled:
			return _find_nearest_shape(limb.global_position).global_position
		return global_position
	return limb.global_position

func get_placement_offset(limb: Node2D) -> float:
	if limb not in limb_placements:
		return 0.0
	var local_pos = limb_placements[limb]
	var shape_node: CollisionShape2D
	if multi_area_enabled and not grab_areas.is_empty():
		shape_node = _find_nearest_shape(to_global(local_pos))
	else:
		shape_node = get_node_or_null("CollisionShape2D")
	if not shape_node or not shape_node.shape:
		return 0.0
	var shape_extents = Vector2.ZERO
	if shape_node.shape is RectangleShape2D:
		shape_extents = shape_node.shape.size / 2.0
	elif shape_node.shape is CircleShape2D:
		shape_extents = Vector2(shape_node.shape.radius, shape_node.shape.radius)
	if shape_extents.length() < 0.1:
		return 0.0
	return clamp(local_pos.length() / shape_extents.length(), 0.0, 1.0)

func get_placement_difficulty_modifier(limb: Node2D) -> float:
	if not snap_to_point:
		var offset = get_placement_offset(limb)
		match hold_type:
			HoldType.SLOPER: return 1.0 + (offset * 2.0)
			HoldType.CRIMP:  return 1.0 + (offset * 1.0)
			HoldType.POCKET: return 1.0 + (offset * 0.3)
			HoldType.WINDOW: return 1.0 + (offset * 0.5)
			_:               return 1.0 + (offset * 0.5)
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
	for child in get_children():
		if child.has_method("on_climb_reset"):
			child.on_climb_reset()

# =============================================================================
#  DRAW
# =============================================================================

func _draw() -> void:
	var spr := _get_active_sprite()
	if spr == null or spr.texture == null:
		return

	if shadow_enabled:
		_draw_hold_shadow(spr)


func _get_active_sprite() -> Sprite2D:
	for suffix in sprite_nodes:
		var spr: Sprite2D = sprite_nodes[suffix]
		if spr and spr.visible:
			return spr
	return null


# =============================================================================
#  SHADOW
# =============================================================================

func _draw_hold_shadow(spr: Sprite2D) -> void:
	var light: Dictionary = _get_light_info()
	var intensity: float  = light["intensity"] as float
	if intensity <= 0.005:
		return

	var light_dir: Vector2 = light["direction"] as Vector2
	var tex: Texture2D     = spr.texture
	var use_region: bool   = spr.region_enabled
	var region: Rect2      = spr.region_rect if use_region else Rect2(Vector2.ZERO, tex.get_size())
	var base_size: Vector2 = (region.size if use_region else tex.get_size()) * spr.scale
	var center: Vector2    = to_local(spr.global_position)
	var wall_col: Color    = _get_wall_color()

	var offset := Vector2(
		light_dir.x * shadow_offset_scale,
		light_dir.y * shadow_offset_scale * 0.55
	)

	var sr := wall_col.r * 0.52
	var sg := wall_col.g * 0.47
	var sb := wall_col.b * 0.40

	draw_set_transform(Vector2.ZERO, spr.rotation, Vector2.ONE)

	for i in range(shadow_passes):
		var t: float = float(i) / float(max(shadow_passes - 1, 1))
		var spread := shadow_spread * (1.0 - t * 0.65)
		var shadow_size := base_size + Vector2(spread * 2.0, spread * 2.0)
		var pass_alpha = clamp(intensity * shadow_intensity * 0.20 * (0.20 + t * 0.80), 0.0, 0.55)
		var dest := Rect2(center + offset - shadow_size * 0.5, shadow_size)
		draw_texture_rect_region(tex, dest, region, Color(sr, sg, sb, pass_alpha))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── Environment helpers ───────────────────────────────────────────────────────

func _get_wall_color() -> Color:
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if env_config and env_config.has_method("get_environment_data"):
		return env_config.get_environment_data().get("wall_color", Color(0.82, 0.75, 0.62))
	return Color(0.82, 0.75, 0.62)


func _get_light_info() -> Dictionary:
	var env_wall: Node2D = get_tree().get_first_node_in_group("environment_walls")
	if not env_wall:
		return {"direction": Vector2(0.3, 1.0).normalized(), "intensity": 0.38, "ambient": 0.14}

	var env: Dictionary = env_wall.get("_env") if env_wall.get("_env") != null else {}

	var wmod: Node        = get_tree().get_first_node_in_group("weather_modifier")
	var weather_type: int = 0
	if wmod and "weather" in wmod:
		weather_type = wmod.weather

	if weather_type == 2:
		var blend = wmod.get_blend() if wmod.has_method("get_blend") else 1.0
		return {"direction": Vector2(0.0, 1.0), "intensity": 0.05 * blend, "ambient": 0.02}

	if weather_type == 5:
		var blend = wmod.get_blend() if wmod.has_method("get_blend") else 1.0
		return {"direction": Vector2(0.0, 1.0),
				"intensity": lerp(0.34, 0.07, blend),
				"ambient":   lerp(0.12, 0.20, blend)}

	var weather_shadow_mult := 1.0
	if weather_type in [1, 4, 6]:
		var blend = wmod.get_blend() if wmod.has_method("get_blend") else 0.0
		weather_shadow_mult = lerp(1.0, 0.42, blend)

	if not env.get("has_sun", true):
		return {"direction": Vector2(0.0, 1.0), "intensity": 0.11 * weather_shadow_mult, "ambient": 0.07}

	var sun_color: Color = env.get("sun_color",   Color(1.0, 0.95, 0.70))
	var sun_lum:   float = sun_color.r * 0.299 + sun_color.g * 0.587 + sun_color.b * 0.114
	var sky_top:   Color = env.get("sky_top",     Color(0.20, 0.45, 0.78))
	var sky_lum:   float = sky_top.r * 0.299 + sky_top.g * 0.587 + sky_top.b * 0.114
	var sky_horiz: Color = env.get("sky_horizon", Color(0.72, 0.85, 0.95))
	var is_dusk:   bool  = sky_horiz.r > sky_horiz.b + 0.15

	var direction: Vector2
	var intensity: float
	var ambient:   float

	if is_dusk:
		direction = Vector2(0.55, 0.95).normalized()
		intensity = 0.44 * sun_lum * weather_shadow_mult
		ambient   = 0.17
	elif sky_lum < 0.15:
		direction = Vector2(0.0, 1.0)
		intensity = 0.05 * weather_shadow_mult
		ambient   = 0.03
	else:
		direction = Vector2(0.28, 0.96).normalized()
		intensity = clamp(sun_lum * 0.54, 0.20, 0.54) * weather_shadow_mult
		ambient   = 0.11

	if env.get("has_gym_interior", false):
		direction = Vector2(0.12, 1.0).normalized()
		intensity = 0.18 * weather_shadow_mult
		ambient   = 0.22

	return {"direction": direction, "intensity": intensity, "ambient": ambient}
