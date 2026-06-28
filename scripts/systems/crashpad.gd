extends Area2D
class_name Crashpad

@export var landing_duration: float = 1.0
@export var click_volume_db: float = 0.0
@export var randomize_pitch: bool = true
@export var pitch_range: float = 0.1

const HIT_SOUND = preload("res://assets/audio/sfx/crashpad.wav")

var _audio_player: AudioStreamPlayer
var sprite_nodes: Dictionary = {}
var _triggered: bool = false

func _ready():
	collision_layer = 8
	collision_mask  = 1
	monitoring  = true
	monitorable = true
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.stream    = HIT_SOUND
	_audio_player.volume_db = click_volume_db
	body_entered.connect(_on_body_entered)
	_cache_sprite_nodes()
	_update_sprite_for_environment()
	add_to_group("crashpads")

func _cache_sprite_nodes():
	for child in get_children():
		if child is Sprite2D:
			if   "Gym"       in child.name: sprite_nodes["Gym"]       = child
			elif "Granite"   in child.name: sprite_nodes["Granite"]   = child
			elif "Sandstone" in child.name: sprite_nodes["Sandstone"] = child

func _update_sprite_for_environment():
	var env = get_node_or_null("/root/EnvironmentConfig")
	if not env: return
	var suf = env.get_sprite_suffix()
	for k in sprite_nodes: sprite_nodes[k].visible = false
	if suf in sprite_nodes: sprite_nodes[suf].visible = true

func _on_body_entered(body: Node2D):
	if _triggered: return
	if not _is_player(body): return
	# ── Don't trigger during level load — player hasn't grabbed start hold yet ──
	if "grab_initialized" in body and not body._grab_initialized:
		return
	# ────────────────────────────────────────────────────────────────────────────
	_triggered = true
	_do_landing(body)

func _is_player(node: Node) -> bool:
	if not node: return false
	if node.is_in_group("player"): return true
	if node.name == "Character":   return true
	if node is CharacterBody2D and (node.has_node("LeftHand") or node.has_node("RightHand")):
		return true
	return false

func _do_landing(player: Node2D):
	if randomize_pitch:
		_audio_player.pitch_scale = 1.0 + randf_range(-pitch_range, pitch_range)
	_audio_player.play()

	if player.has_method("play_crashpad_ragdoll"):
		player.play_crashpad_ragdoll(landing_duration)

	await get_tree().create_timer(landing_duration + 0.3).timeout

	# ── Detect manual reset during the animation ───────────────────────────────
	# If the player pressed R/Escape while the timer was running, reset_climb()
	# already moved them back to spawn — far from the crashpad. Don't call
	# on_player_fell() again, otherwise the player gets double-reset and the
	# crashpad re-arms (triggered = false), letting it fire again when the
	# player inevitably falls back through from spawn.
	if global_position.distance_to(player.global_position) > 200.0:
		_triggered = false
		return
	# ────────────────────────────────────────────────────────────────────────────

	# ── Guard again after the timer — a level transition may have started ──────
	if "grab_initialized" in player and not player._grab_initialized:
		await get_tree().process_frame
		_triggered = false
		return
	# ────────────────────────────────────────────────────────────────────────────

	var main = get_tree().current_scene
	if main and main.has_method("on_player_fell"):
		main.on_player_fell()
	elif player.has_method("reset_climb"):
		player.reset_climb()

	await get_tree().process_frame
	_triggered = false
