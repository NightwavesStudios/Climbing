extends Area2D
class_name ClimbingHold

enum HoldType { JUG, START, TOP_OUT, CRIMP, SLOPER, FOOTHOLD, POCKET }

@export var hold_type: HoldType = HoldType.JUG

# Grip state pressure: how much this hold pushes you toward PUMPED
@export var difficulty: float = 0.0
@export var rest_value: float = 0.0

# Pocket-specific: track if a limb is already using this hold
var occupied_by: Node2D = null

# Track where on the hold each limb is grabbing (for placement-based physics)
var limb_placements: Dictionary = {}  # Node2D -> Vector2 (local position)

@onready var hold_point: Marker2D = $HoldPoint

# Flag to prevent auto-detection if type was set manually
var _type_was_set_manually: bool = false

# Sprite nodes for different environments
var sprite_nodes: Dictionary = {}

func _ready():
	collision_layer = 2
	collision_mask = 0
	monitoring = true
	
	# Only auto-detect if type wasn't set manually
	if not _type_was_set_manually:
		_auto_detect_type_from_name()
		_configure_hold_properties()
	
	add_to_group("holds")
	
	_cache_sprite_nodes()
	_update_sprite_for_environment()
	
	var type_name = HoldType.keys()[hold_type]
	print("Hold initialized: ", name, " type=", type_name)

func _cache_sprite_nodes():
	"""Find and cache all sprite nodes for different environments"""
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
	"""Show only the sprite for the current environment"""
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
	"""Auto-detect hold type from scene filename"""
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
	"""Set hold type from string (called by level loader BEFORE _ready)"""
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

# =============================================================================
# HOLD TYPE CHECKS
# =============================================================================

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

# =============================================================================
# GRAB/RELEASE
# =============================================================================

func try_claim(limb: Node2D, is_foot: bool, grab_position: Vector2) -> bool:
	if is_foothold() and not is_foot:
		return false
	
	if is_pocket():
		if occupied_by != null and occupied_by != limb:
			return false
	
	var local_grab = to_local(grab_position)
	var shape = get_node_or_null("CollisionShape2D")
	if shape and shape.shape:
		var max_grab_distance = 0.0
		
		if shape.shape is RectangleShape2D:
			var extents = shape.shape.size / 2.0
			max_grab_distance = extents.length() + 10.0
		elif shape.shape is CircleShape2D:
			max_grab_distance = shape.shape.radius + 10.0
		
		if local_grab.length() > max_grab_distance:
			return false
	
	occupied_by = limb
	limb_placements[limb] = local_grab
	
	return true

func release(limb: Node2D):
	if occupied_by == limb:
		occupied_by = null
	limb_placements.erase(limb)

func can_grab(limb: Node2D, is_foot: bool) -> bool:
	if is_foothold() and not is_foot:
		return false
	
	if is_pocket() and occupied_by != null and occupied_by != limb:
		return false
	
	return true

# =============================================================================
# POSITIONING
# =============================================================================

func get_limb_anchor(limb: Node2D) -> Vector2:
	if limb in limb_placements:
		return to_global(limb_placements[limb])
	return hold_point.global_position

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
	
	var offset = local_pos.length() / shape_extents.length()
	return clamp(offset, 0.0, 1.0)

func get_placement_difficulty_modifier(limb: Node2D) -> float:
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

# =============================================================================
# PRESSURE CALCULATIONS
# =============================================================================

func get_state_pressure(delta: float, body_offset: float, time_static: float, foot_support_ratio: float, limb: Node2D) -> float:
	var pressure = difficulty * delta
	
	var placement_mod = get_placement_difficulty_modifier(limb)
	pressure *= placement_mod
	
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
