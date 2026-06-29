class_name HoldShadowDrawer
extends RefCounted
## Static utility for drawing drop shadows on climbing holds.
##
## Separates the complex multi-pass shadow rendering from ClimbingHold,
## keeping the hold script focused on physics and state management.
##
## Usage: Call HoldShadowDrawer.draw_hold_shadow(hold, sprite) from the
## hold's _draw() method when shadow_enabled is true.

## Draw the shadow for the given hold, using its active sprite and environment.
## Returns true if any shadow was drawn.
static func draw_hold_shadow(hold: Node2D, spr: Sprite2D) -> bool:
	if spr == null or spr.texture == null:
		return false

	# Check if shadow is enabled on the hold
	if not hold.has_method("is_shadow_enabled") or not hold.is_shadow_enabled():
		return false

	var light: Dictionary = _get_light_info()
	var intensity: float  = light["intensity"] as float
	if intensity <= 0.005:
		return false

	var shadow_intensity: float = hold.get("shadow_intensity") if "shadow_intensity" in hold else 2.2
	var shadow_spread: float    = hold.get("shadow_spread") if "shadow_spread" in hold else 12.0
	var shadow_passes: int      = hold.get("shadow_passes") if "shadow_passes" in hold else 4
	var shadow_offset_scale: float = hold.get("shadow_offset_scale") if "shadow_offset_scale" in hold else 7.0

	var light_dir: Vector2 = light["direction"] as Vector2
	var tex: Texture2D     = spr.texture
	var use_region: bool   = spr.region_enabled
	var region: Rect2      = spr.region_rect if use_region else Rect2(Vector2.ZERO, tex.get_size())
	var base_size: Vector2 = (region.size if use_region else tex.get_size()) * spr.scale
	var center: Vector2    = hold.to_local(spr.global_position)
	var wall_col: Color    = _get_wall_color()

	var offset := Vector2(
		light_dir.x * shadow_offset_scale,
		light_dir.y * shadow_offset_scale * 0.55
	)

	var sr := wall_col.r * 0.52
	var sg := wall_col.g * 0.47
	var sb := wall_col.b * 0.40

	hold.draw_set_transform(Vector2.ZERO, spr.rotation, Vector2.ONE)

	for i in range(shadow_passes):
		var t: float = float(i) / float(max(shadow_passes - 1, 1))
		var spread := shadow_spread * (1.0 - t * 0.65)
		var shadow_size := base_size + Vector2(spread * 2.0, spread * 2.0)
		var pass_alpha = clamp(intensity * shadow_intensity * 0.20 * (0.20 + t * 0.80), 0.0, 0.55)
		var dest := Rect2(center + offset - shadow_size * 0.5, shadow_size)
		hold.draw_texture_rect_region(tex, dest, region, Color(sr, sg, sb, pass_alpha))

	hold.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


# ── Environment helpers ───────────────────────────────────────────────────────

static func _get_wall_color() -> Color:
	var env_config = _get_env_config()
	if env_config and env_config.has_method("get_environment_data"):
		return env_config.get_environment_data().get("wall_color", Color(0.82, 0.75, 0.62))
	return Color(0.82, 0.75, 0.62)


static func _get_light_info() -> Dictionary:
	var env_wall: Node2D = _get_tree().get_first_node_in_group("environment_walls")
	if not env_wall:
		return {"direction": Vector2(0.3, 1.0).normalized(), "intensity": 0.38, "ambient": 0.14}

	var env: Dictionary = env_wall.get("_env") if env_wall.get("_env") != null else {}

	var wmod: Node = _get_tree().get_first_node_in_group("weather_modifier")
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


# ── Tree access (cached for performance) ──────────────────────────────────────

static var _tree: SceneTree = null
static var _env_config: Node = null

static func _get_tree() -> SceneTree:
	if _tree == null or not _tree.is_inside_tree():
		_tree = Engine.get_main_loop() as SceneTree
	return _tree

static func _get_env_config() -> Node:
	if _env_config == null or not _env_config.is_inside_tree():
		if _get_tree():
			_env_config = _get_tree().root.get_node_or_null("/root/EnvironmentConfig")
	return _env_config
