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

func _ready():
	collision_layer = 2
	collision_mask = 0
	monitoring = true
	
	# Only auto-detect if type wasn't set manually by level loader
	# AND only if properties haven't been configured yet
	if not _type_was_set_manually:
		_auto_detect_type_from_name()
		_configure_hold_properties()
	
	# Add to holds group
	add_to_group("holds")
	
	# Debug output
	var type_name = HoldType.keys()[hold_type]
	print("Hold initialized: ", name, " type=", type_name, " at ", global_position)

func _auto_detect_type_from_name():
	"""Auto-detect hold type from scene filename"""
	var scene_path = scene_file_path
	if scene_path == "":
		return
	
	var filename = scene_path.get_file().to_lower()
	
	# Only auto-detect if type is still JUG (default)
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
		_:
			print("WARNING: Unknown hold type string: ", type_str)
	
	# Configure properties immediately when type is set manually
	# This ensures the properties are correct even if called before _ready()
	_configure_hold_properties()

func is_start_hold() -> bool:
	var result = hold_type == HoldType.START
	return result

func is_top_out() -> bool:
	var result = hold_type == HoldType.TOP_OUT
	return result

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

# Attempt to claim this hold for a specific limb at a specific position
func try_claim(limb: Node2D, is_foot: bool, grab_position: Vector2) -> bool:
	# Footholds can only be used by feet
	if is_foothold() and not is_foot:
		return false
	
	# Pockets can only hold one limb at a time
	if is_pocket():
		if occupied_by != null and occupied_by != limb:
			return false
	
	# Validate that grab position is reasonably close to hold
	var local_grab = to_local(grab_position)
	var shape = get_node_or_null("CollisionShape2D")
	if shape and shape.shape:
		var max_grab_distance = 0.0
		
		if shape.shape is RectangleShape2D:
			var extents = shape.shape.size / 2.0
			max_grab_distance = extents.length() + 10.0  # Allow 10 pixels outside
		elif shape.shape is CircleShape2D:
			max_grab_distance = shape.shape.radius + 10.0  # Allow 10 pixels outside
		
		# Check if grab is too far from hold center
		if local_grab.length() > max_grab_distance:
			return false
	
	occupied_by = limb
	limb_placements[limb] = local_grab
	return true

# Release this hold
func release(limb: Node2D):
	if occupied_by == limb:
		occupied_by = null
	limb_placements.erase(limb)

# Check if this hold can be grabbed
func can_grab(limb: Node2D, is_foot: bool) -> bool:
	if is_foothold() and not is_foot:
		return false
	
	if is_pocket() and occupied_by != null and occupied_by != limb:
		return false
	
	return true

# Get the global position where a limb is holding
func get_limb_anchor(limb: Node2D) -> Vector2:
	if limb in limb_placements:
		return to_global(limb_placements[limb])
	# Fallback to center point
	return hold_point.global_position

# Calculate how off-center a placement is (0 = center, 1 = edge)
func get_placement_offset(limb: Node2D) -> float:
	if limb not in limb_placements:
		return 0.0
	
	var local_pos = limb_placements[limb]
	var shape = get_node_or_null("CollisionShape2D")
	if not shape or not shape.shape:
		return 0.0
	
	# Get shape bounds
	var shape_extents = Vector2.ZERO
	if shape.shape is RectangleShape2D:
		shape_extents = shape.shape.size / 2.0
	elif shape.shape is CircleShape2D:
		var radius = shape.shape.radius
		shape_extents = Vector2(radius, radius)
	
	if shape_extents.length() < 0.1:
		return 0.0
	
	# Calculate distance from center as fraction of shape size
	var offset = local_pos.length() / shape_extents.length()
	return clamp(offset, 0.0, 1.0)

# Slopers and crimps are more sensitive to placement
func get_placement_difficulty_modifier(limb: Node2D) -> float:
	var offset = get_placement_offset(limb)
	
	match hold_type:
		HoldType.SLOPER:
			# Off-center = much harder
			return 1.0 + (offset * 2.0)
		HoldType.CRIMP:
			# Off-center = harder
			return 1.0 + (offset * 1.0)
		HoldType.POCKET:
			# Pockets are forgiving once you're in
			return 1.0 + (offset * 0.3)
		_:
			# Other holds don't care much
			return 1.0 + (offset * 0.5)

func get_state_pressure(delta: float, body_offset: float, time_static: float, foot_support_ratio: float, limb: Node2D) -> float:
	var pressure = difficulty * delta
	
	# Apply placement-based modifier
	var placement_mod = get_placement_difficulty_modifier(limb)
	pressure *= placement_mod
	
	# Slopers are relentless
	if is_sloper():
		pressure += delta * 2.0
	
	# Bad body position increases pressure
	pressure += body_offset * 0.3 * delta
	
	# Staying static too long on difficult holds
	if difficulty > 0.5:
		pressure += time_static * 0.2 * delta
	
	# Reduce pump proportionally to feet support (max 50% reduction)
	if foot_support_ratio > 0.0:
		pressure *= 1.0 - (0.5 * foot_support_ratio)
	
	return pressure

func get_recovery_rate(delta: float, body_balance: float, foot_support_ratio: float) -> float:
	if rest_value <= 0.0:
		return 0.0
	
	var recovery = rest_value * delta
	
	# Better balance = better recovery
	recovery += body_balance * 0.5 * delta
	
	# Multiply by foot support: more weight on feet = better recovery
	recovery *= 0.5 + 0.5 * foot_support_ratio
	
	return recovery
