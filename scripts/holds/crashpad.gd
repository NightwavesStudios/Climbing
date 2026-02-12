extends Area2D
class_name Crashpad
## Crashpad - soft landing zone at the bottom of climbing routes

@export var cushion_strength: float = 0.8  ## How much it softens falls (0-1)

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D

var sprite_nodes: Dictionary = {}
var _player_on_pad: bool = false

func _ready():
	# Area2D collision setup
	collision_layer = 8  # Crashpad layer
	collision_mask = 1   # Detect player layer (usually layer 1)
	
	monitoring = true
	monitorable = true
	
	# Connect Area2D signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	_cache_sprite_nodes()
	_update_sprite_for_environment()
	
	add_to_group("crashpads")
	
	print("Crashpad ready: ", name, " at ", global_position)

func _cache_sprite_nodes():
	"""Cache sprite variants for different environments"""
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
	"""Show sprite matching current environment"""
	var env_config = get_node_or_null("/root/EnvironmentConfig")
	if not env_config:
		return
	
	var sprite_suffix = env_config.get_sprite_suffix()
	
	# Hide all sprites
	for suffix in sprite_nodes:
		if sprite_nodes[suffix]:
			sprite_nodes[suffix].visible = false
	
	# Show current environment sprite
	if sprite_suffix in sprite_nodes and sprite_nodes[sprite_suffix]:
		sprite_nodes[sprite_suffix].visible = true
	elif sprite:
		sprite.visible = true

# =============================================================================
# COLLISION DETECTION
# =============================================================================

func _on_body_entered(body: Node2D):
	"""Triggered when player enters crashpad area"""
	print("Body entered crashpad: ", body.name)
	
	if body.is_in_group("player") or body.name == "Character":
		_player_on_pad = true
		on_player_landed(body)

func _on_body_exited(body: Node2D):
	"""Triggered when player leaves crashpad area"""
	if body.is_in_group("player") or body.name == "Character":
		_player_on_pad = false

# =============================================================================
# PLAYER INTERACTION
# =============================================================================

func on_player_landed(player: Node2D):
	"""Called when player touches the crashpad - notifies main scene for reset"""
	print("Player landed on crashpad!")
	
	# Notify main scene to handle reset
	var main = get_tree().current_scene
	if main and main.has_method("on_player_reset"):
		print("Notifying main scene of crashpad landing...")
		main.on_player_reset()

func get_cushion_strength() -> float:
	return cushion_strength

func is_player_on_pad() -> bool:
	return _player_on_pad
