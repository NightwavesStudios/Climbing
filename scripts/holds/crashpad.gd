extends Area2D
class_name Crashpad

@export var cushion_strength: float = 0.8
@export var landing_duration: float = 1.0
@export var min_fall_velocity: float = 200.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D

@export var click_volume_db: float = 0.0
@export var randomize_pitch: bool = true
@export var pitch_range: float = 0.1

const HIT_SOUND = preload("res://assets/audio/sfx/crashpad.wav")

var _audio_player: AudioStreamPlayer
var sprite_nodes: Dictionary = {}
var _player_on_pad: bool = false
var _reset_triggered: bool = false
var _landing_in_progress: bool = false
var _ragdoll_active: bool = false

# Ragdoll physics
var _limb_positions: Dictionary = {}
var _limb_velocities: Dictionary = {}
var _pad_top_y: float = 0.0
const RAGDOLL_DAMPING := 0.85
const RAGDOLL_GRAVITY := 1500.0
const PAD_BOUNCE := 0.2

func _ready():
	collision_layer = 8
	collision_mask = 1
	monitoring = true
	monitorable = true
	
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.stream = HIT_SOUND
	_audio_player.volume_db = click_volume_db
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	
	_cache_sprite_nodes()
	_update_sprite_for_environment()
	
	add_to_group("crashpads")
	
	# Calculate pad surface
	if collision_shape and collision_shape.shape is RectangleShape2D:
		_pad_top_y = global_position.y - collision_shape.shape.size.y / 2

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
	elif sprite:
		sprite.visible = true

func _on_body_entered(body: Node2D):
	if _is_player(body):
		_player_on_pad = true
		_check_and_trigger_landing(body)

func _on_body_exited(body: Node2D):
	if _is_player(body):
		_player_on_pad = false
		_reset_triggered = false

func _on_area_entered(area: Area2D):
	var parent = area.get_parent()
	if parent and _is_player_limb(parent):
		var player = _get_player_from_limb(parent)
		if player:
			_player_on_pad = true
			_check_and_trigger_landing(player)
	elif parent and _is_player(parent):
		_player_on_pad = true
		_check_and_trigger_landing(parent)

func _is_player_limb(node: Node) -> bool:
	if not node:
		return false
	var limb_names = ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]
	return node.name in limb_names

func _get_player_from_limb(limb_node: Node) -> Node2D:
	var parent = limb_node.get_parent()
	if parent and _is_player(parent):
		return parent
	return null

func _is_player(node: Node) -> bool:
	if not node:
		return false
	if node.is_in_group("player"):
		return true
	if node.name == "Character":
		return true
	if node is CharacterBody2D:
		if node.has_node("LeftHand") or node.has_node("RightHand"):
			return true
	return false

func _check_and_trigger_landing(player: Node2D):
	if _reset_triggered or _landing_in_progress:
		return
	
	var fall_velocity = 0.0
	if player.has_method("get") and player.get("com_velocity"):
		fall_velocity = player.com_velocity.y
	elif player.has_method("get") and player.get("velocity"):
		fall_velocity = player.velocity.y
	
	if fall_velocity > min_fall_velocity:
		_trigger_landing(player, fall_velocity)
	else:
		on_player_landed(player)

func _trigger_landing(player: Node2D, fall_velocity: float):
	_landing_in_progress = true
	_reset_triggered = true
	_ragdoll_active = true
	
	# Play impact sound
	if randomize_pitch:
		_audio_player.pitch_scale = 1.0 + randf_range(-pitch_range, pitch_range)
	else:
		_audio_player.pitch_scale = 1.0
	_audio_player.play()
	
	# Initialize ragdoll physics
	_init_ragdoll(player)
	
	# Animate the ragdoll landing
	await _animate_ragdoll_landing(player, fall_velocity)
	
	# Reset after landing animation
	var main = get_tree().current_scene
	if main and main.has_method("on_player_reset"):
		main.on_player_reset()
	else:
		if player.has_method("reset_climb"):
			player.reset_climb()
	
	_landing_in_progress = false
	_ragdoll_active = false

func _init_ragdoll(player: Node2D):
	"""Initialize ragdoll physics with current limb positions and velocities"""
	_limb_positions.clear()
	_limb_velocities.clear()
	
	# Capture current state of all limbs
	var limbs = ["left_hand", "right_hand", "left_foot", "right_foot"]
	for limb_name in limbs:
		if player.has_node(limb_name.capitalize().replace("_", "")):
			var limb = player.get_node(limb_name.capitalize().replace("_", ""))
			_limb_positions[limb_name] = limb.global_position
			
			# Get current velocity
			var vel_prop = limb_name + "_velocity"
			if player.get(vel_prop) != null:
				_limb_velocities[limb_name] = player.get(vel_prop)
			else:
				_limb_velocities[limb_name] = Vector2.ZERO
	
	# Also track body center
	_limb_positions["body"] = player.global_position
	if player.get("com_velocity") != null:
		_limb_velocities["body"] = player.com_velocity
	else:
		_limb_velocities["body"] = Vector2.ZERO

func _animate_ragdoll_landing(player: Node2D, fall_velocity: float):
	"""Simulate ragdoll physics until settled on pad"""
	var delta = get_process_delta_time()
	var settled_timer = 0.0
	var max_landing_time = landing_duration
	var elapsed = 0.0
	
	# Disable player physics
	_disable_player_physics(player)
	
	# Ragdoll simulation loop
	while elapsed < max_landing_time:
		await get_tree().process_frame
		delta = get_process_delta_time()
		elapsed += delta
		
		var all_settled = true
		
		# Update each limb with ragdoll physics
		for limb_name in _limb_positions.keys():
			var pos = _limb_positions[limb_name]
			var vel = _limb_velocities[limb_name]
			
			# Apply gravity
			vel.y += RAGDOLL_GRAVITY * delta
			
			# Apply velocity
			pos += vel * delta
			
			# Collision with pad surface
			if pos.y > _pad_top_y:
				pos.y = _pad_top_y
				# Bounce with energy loss
				if vel.y > 20:
					vel.y = -vel.y * PAD_BOUNCE
					all_settled = false
				else:
					vel.y = 0
				# Friction on X
				vel.x *= 0.7
			
			# Apply damping
			vel *= RAGDOLL_DAMPING
			
			# Check if settled
			if vel.length() > 10:
				all_settled = false
			
			# Store updated values
			_limb_positions[limb_name] = pos
			_limb_velocities[limb_name] = vel
			
			# Update actual limb position
			if limb_name != "body":
				var node_name = limb_name.capitalize().replace("_", "")
				if player.has_node(node_name):
					var limb = player.get_node(node_name)
					limb.global_position = pos
		
		# Update body position
		player.global_position = _limb_positions["body"]
		
		# Check if all limbs settled
		if all_settled:
			settled_timer += delta
			if settled_timer > 0.3:
				break
		else:
			settled_timer = 0.0
	
	# Final rest position
	_ensure_limbs_on_surface(player)

func _disable_player_physics(player: Node2D):
	"""Disable player's physics simulation"""
	if player.has_method("set"):
		# Zero all velocities
		if player.get("com_velocity") != null:
			player.com_velocity = Vector2.ZERO
		if player.get("body_velocity") != null:
			player.body_velocity = Vector2.ZERO
		if player.get("velocity") != null:
			player.velocity = Vector2.ZERO
		
		# Zero limb velocities
		var limb_names = ["left_hand", "right_hand", "left_foot", "right_foot"]
		for limb_name in limb_names:
			var vel_prop = limb_name + "_velocity"
			if player.get(vel_prop) != null:
				player.set(vel_prop, Vector2.ZERO)
			
			var joint_vel_prop = limb_name + "_joint_velocity"
			if player.get(joint_vel_prop) != null:
				player.set(joint_vel_prop, Vector2.ZERO)

func _ensure_limbs_on_surface(player: Node2D):
	"""Make sure all limbs are resting on pad surface"""
	var limbs = ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]
	for limb_name in limbs:
		if player.has_node(limb_name):
			var limb = player.get_node(limb_name)
			if limb.global_position.y > _pad_top_y:
				limb.global_position.y = _pad_top_y

func on_player_landed(player: Node2D):
	"""Fallback for immediate reset without animation"""
	if _reset_triggered:
		return
	
	_reset_triggered = true
	
	if randomize_pitch:
		_audio_player.pitch_scale = 1.0 + randf_range(-pitch_range, pitch_range)
	else:
		_audio_player.pitch_scale = 1.0
	
	_audio_player.play()
	
	await get_tree().create_timer(0.1).timeout
	
	var main = get_tree().current_scene
	if main and main.has_method("on_player_reset"):
		main.on_player_reset()
	else:
		if player.has_method("reset_climb"):
			player.reset_climb()

func _physics_process(_delta):
	if not monitoring or _landing_in_progress:
		return
	
	var overlapping_bodies = get_overlapping_bodies()
	var overlapping_areas = get_overlapping_areas()
	
	for body in overlapping_bodies:
		if _is_player(body) and not _reset_triggered:
			_check_and_trigger_landing(body)
			return
	
	for area in overlapping_areas:
		var parent = area.get_parent()
		if parent and _is_player_limb(parent):
			var player = _get_player_from_limb(parent)
			if player and not _reset_triggered:
				_check_and_trigger_landing(player)
				return

func get_cushion_strength() -> float:
	return cushion_strength

func is_player_on_pad() -> bool:
	return _player_on_pad

func reset():
	_reset_triggered = false
	_player_on_pad = false
	_landing_in_progress = false
	_ragdoll_active = false
