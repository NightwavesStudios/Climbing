class_name WallEnvironmentTheme
extends RefCounted
## Provides environment-specific color palettes and theme data for the DynamicWall.
## All methods are static; they receive a seed for deterministic variation.

static func tod(seed: int, seed_xor: int) -> int:
	return (abs((seed ^ seed_xor) * 1664525 + 1013904223) >> 7) % 3

static func _hf(v: int) -> float:
	return float(hash(v) % 10000) / 10000.0

static func apply_for_environment(env_name: String, scenery_seed: int, _env: Dictionary) -> Dictionary:
	_env.clear()
	match env_name:
		"granite", "night":
			return _apply_granite_theme(scenery_seed)
		"sandstone":
			return _apply_sandstone_theme(scenery_seed)
		"ice":
			return _apply_ice_theme(scenery_seed)
		"menu_sunset":
			return _apply_menu_sunset_theme()
		"gym":
			return _apply_gym_theme(scenery_seed)
		"deep water solo":
			return _apply_deep_water_theme()
		"building":
			return _apply_building_theme(scenery_seed)
		_:
			return _apply_default_theme()

static func _apply_granite_theme(seed: int) -> Dictionary:
	match tod(seed, 0x9E3779B9):
		1: return {
				"sky_top": Color(0.12,0.10,0.32), "sky_horizon": Color(1.0,0.62,0.22),
				"cloud_color": Color(1.0,0.65,0.40,1.0), "cloud_shadow": Color(0.65,0.25,0.12),
				"has_sun": true, "sun_color": Color(1.0,0.65,0.15), "has_mountains": true,
				"ground_type": "grass_dusk",
				"ground_top": Color(0.14,0.22,0.10), "ground_mid": Color(0.24,0.16,0.08), "ground_deep": Color(0.16,0.10,0.06),
				"ground_detail": "rocks", "fog_color": Color(0.90,0.45,0.15,0.10),
				"mtn_colors": [Color(0.62,0.38,0.52),Color(0.44,0.24,0.36),Color(0.28,0.14,0.22),Color(0.18,0.08,0.14)],
			}
		2: return {
				"sky_top": Color(0.02,0.02,0.08), "sky_horizon": Color(0.06,0.08,0.18),
				"cloud_color": Color(0.22,0.25,0.38,0.7), "cloud_shadow": Color(0.10,0.12,0.20),
				"has_sun": false, "has_moon": true, "has_stars": true, "has_mountains": true,
				"ground_type": "grass_night",
				"ground_top": Color(0.08,0.14,0.07), "ground_mid": Color(0.12,0.10,0.08), "ground_deep": Color(0.07,0.06,0.05),
				"ground_detail": "rocks", "fog_color": Color(0.05,0.06,0.15,0.12),
			}
		_: return {
				"sky_top": Color(0.20,0.45,0.78), "sky_horizon": Color(0.72,0.85,0.95),
				"cloud_color": Color(1.0,1.0,1.0,1.0), "cloud_shadow": Color(0.75,0.82,0.90),
				"has_sun": true, "sun_color": Color(1.0,0.96,0.78), "has_mountains": true,
				"ground_type": "grass",
				"ground_top": Color(0.22,0.52,0.14), "ground_mid": Color(0.38,0.28,0.16), "ground_deep": Color(0.28,0.20,0.10),
				"ground_detail": "rocks", "fog_color": Color(0.65,0.80,0.95,0.0),
			}

static func _apply_sandstone_theme(seed: int) -> Dictionary:
	match tod(seed, 0x4E2A9F3B):
		1: return {
				"sky_top": Color(0.14,0.09,0.22), "sky_horizon": Color(0.96,0.46,0.12),
				"cloud_color": Color(1.0,0.60,0.28,0.9), "cloud_shadow": Color(0.68,0.28,0.10),
				"has_sun": false, "has_mountains": true, "ground_type": "sand_dusk",
				"ground_top": Color(0.72,0.44,0.18), "ground_mid": Color(0.54,0.30,0.10), "ground_deep": Color(0.36,0.18,0.06),
				"fog_color": Color(0.88,0.42,0.12,0.10), "has_sand_wind": true,
			}
		2: return {
				"sky_top": Color(0.03,0.03,0.10), "sky_horizon": Color(0.10,0.10,0.22),
				"cloud_color": Color(0.18,0.20,0.32,0.55), "cloud_shadow": Color(0.08,0.08,0.18),
				"has_sun": false, "has_moon": true, "has_stars": true, "has_mountains": true,
				"ground_type": "sand_night",
				"ground_top": Color(0.44,0.28,0.10), "ground_mid": Color(0.28,0.16,0.06), "ground_deep": Color(0.16,0.09,0.03),
				"fog_color": Color(0.06,0.06,0.16,0.10), "has_sand_wind": false,
			}
		_: return {
				"sky_top": Color(0.48,0.32,0.14), "sky_horizon": Color(0.88,0.70,0.40),
				"cloud_color": Color(1.0,0.92,0.78,0.70), "cloud_shadow": Color(0.80,0.64,0.40),
				"has_sun": true, "sun_color": Color(1.0,0.88,0.54), "has_mountains": true,
				"ground_type": "sand",
				"ground_top": Color(0.82,0.62,0.32), "ground_mid": Color(0.62,0.40,0.16), "ground_deep": Color(0.42,0.24,0.08),
				"fog_color": Color(0.90,0.72,0.40,0.07), "has_sand_wind": true,
			}

static func _apply_ice_theme(seed: int) -> Dictionary:
	match (abs((seed ^ 0xC7D3E1F2) * 22695477 + 1) >> 9) % 3:
		1: return {
				"sky_top": Color(0.18,0.10,0.30), "sky_horizon": Color(0.94,0.44,0.52),
				"cloud_color": Color(1.0,0.62,0.70,0.85), "cloud_shadow": Color(0.60,0.22,0.38),
				"has_sun": false, "has_mountains": true, "ground_type": "ice_snow",
				"ground_top": Color(0.78,0.84,0.90), "ground_mid": Color(0.60,0.70,0.80), "ground_deep": Color(0.38,0.48,0.62),
				"ground_detail": "snow", "fog_color": Color(0.80,0.60,0.70,0.08),
				"has_ice_sheen": true, "ice_sheen_color": Color(0.94,0.72,0.82),
			}
		2: return {
				"sky_top": Color(0.02,0.03,0.10), "sky_horizon": Color(0.06,0.10,0.24),
				"cloud_color": Color(0.12,0.16,0.30,0.65), "cloud_shadow": Color(0.04,0.06,0.14),
				"has_sun": false, "has_moon": true, "has_stars": true, "has_mountains": true,
				"ground_type": "ice_snow",
				"ground_top": Color(0.56,0.66,0.80), "ground_mid": Color(0.34,0.44,0.60), "ground_deep": Color(0.16,0.22,0.38),
				"ground_detail": "snow", "fog_color": Color(0.04,0.06,0.18,0.14),
				"has_ice_sheen": true, "ice_sheen_color": Color(0.40,0.58,0.90),
			}
		_: return {
				"sky_top": Color(0.12,0.36,0.72), "sky_horizon": Color(0.70,0.88,0.98),
				"cloud_color": Color(1.0,1.0,1.0,0.92), "cloud_shadow": Color(0.76,0.84,0.94),
				"has_sun": true, "sun_color": Color(1.0,0.98,0.90), "has_mountains": true,
				"ground_type": "ice_snow",
				"ground_top": Color(0.90,0.94,0.98), "ground_mid": Color(0.70,0.80,0.92), "ground_deep": Color(0.46,0.60,0.78),
				"ground_detail": "snow", "fog_color": Color(0.72,0.88,0.98,0.05),
				"has_ice_sheen": true, "ice_sheen_color": Color(0.82,0.94,1.00),
			}

static func _apply_menu_sunset_theme() -> Dictionary:
	return {
		"sky_top": Color(0.88,0.55,0.75), "sky_horizon": Color(0.98,0.72,0.48),
		"cloud_color": Color(1.0,0.85,0.92,0.8), "cloud_shadow": Color(0.6,0.38,0.65,0.5),
		"has_sun": true, "sun_color": Color(1.0,0.82,0.55), "has_mountains": true,
		"fog_color": Color(0.95,0.68,0.82,0.18),
		"ground_type": "grass_dusk",
		"ground_top": Color(0.45,0.38,0.42), "ground_mid": Color(0.38,0.32,0.35), "ground_deep": Color(0.28,0.24,0.30),
		"ground_detail": "rocks",
	}

static func _apply_gym_theme(seed: int) -> Dictionary:
	var tod_val: int = (abs((seed ^ 0x6B43FA1D) * 22695477 + 1) >> 9) % 3
	var base := {
		"sky_top": Color(0.96,0.96,0.97), "sky_horizon": Color(0.92,0.92,0.93),
		"cloud_color": Color(1.0,1.0,1.0,0.0), "has_sun": false, "has_mountains": false,
		"has_gym_interior": true, "gym_time_of_day": tod_val,
		"ground_type": "gym_floor",
		"ground_top": Color(0.22,0.22,0.24), "ground_mid": Color(0.16,0.16,0.18), "ground_deep": Color(0.11,0.11,0.12),
	}
	match tod_val:
		1: base.merge({
				"gym_sky_top": Color(0.12,0.10,0.32), "gym_sky_mid": Color(0.72,0.28,0.12), "gym_sky_haze": Color(0.98,0.52,0.18),
				"gym_sun_color": Color(1.0,0.55,0.10),
				"gym_mtn_colors": [Color(0.58,0.35,0.28),Color(0.42,0.22,0.18),Color(0.28,0.14,0.12),Color(0.16,0.08,0.08)],
				"gym_grass_color": Color(0.14,0.22,0.10),
			})
		2: base.merge({
				"gym_sky_top": Color(0.02,0.02,0.08), "gym_sky_mid": Color(0.04,0.06,0.14), "gym_sky_haze": Color(0.06,0.08,0.20),
				"gym_sun_color": Color.TRANSPARENT,
				"gym_mtn_colors": [Color(0.14,0.16,0.22),Color(0.10,0.12,0.18),Color(0.06,0.08,0.13),Color(0.03,0.04,0.08)],
				"gym_grass_color": Color(0.08,0.14,0.07), "has_gym_stars": true, "has_gym_moon": true,
			})
		_: base.merge({
				"gym_sky_top": Color(0.10,0.28,0.65), "gym_sky_mid": Color(0.30,0.58,0.88), "gym_sky_haze": Color(0.82,0.90,0.97),
				"gym_sun_color": Color(1.0,0.96,0.78),
				"gym_mtn_colors": [Color(0.72,0.82,0.91),Color(0.54,0.67,0.80),Color(0.38,0.52,0.66),Color(0.24,0.38,0.53)],
				"gym_grass_color": Color(0.18,0.26,0.19),
			})
	return base

static func _apply_deep_water_theme() -> Dictionary:
	return {
		"sky_top": Color(0.18,0.42,0.72), "sky_horizon": Color(0.60,0.82,0.94),
		"cloud_color": Color(1.0,1.0,1.0,0.85), "cloud_shadow": Color(0.72,0.84,0.92),
		"has_sun": true, "sun_color": Color(1.0,0.95,0.75), "has_mountains": false,
		"has_water": true, "ground_type": "water",
		"ground_top": Color(0.04,0.22,0.44), "ground_mid": Color(0.02,0.14,0.30), "ground_deep": Color(0.01,0.08,0.18),
		"fog_color": Color(0.50,0.75,0.90,0.06), "has_sea_cliffs": true,
	}

static func _apply_building_theme(seed: int) -> Dictionary:
	match tod(seed, 0x3F7A2B1C):
		1: return {
				"sky_top": Color(0.06,0.05,0.14), "sky_horizon": Color(0.72,0.28,0.10),
				"cloud_color": Color(1.0,0.55,0.25,0.70), "cloud_shadow": Color(0.55,0.20,0.10),
				"has_sun": false, "has_moon": false, "has_mountains": false, "has_city": true, "city_time": 1,
				"ground_type": "city_street",
				"ground_top": Color(0.22,0.18,0.14), "ground_mid": Color(0.16,0.13,0.10), "ground_deep": Color(0.11,0.09,0.07),
				"fog_color": Color(0.60,0.25,0.08,0.08),
			}
		2: return {
				"sky_top": Color(0.02,0.02,0.07), "sky_horizon": Color(0.05,0.06,0.14),
				"cloud_color": Color(0.20,0.22,0.35,0.60), "cloud_shadow": Color(0.08,0.10,0.20),
				"has_sun": false, "has_moon": true, "has_stars": true, "has_mountains": false, "has_city": true, "city_time": 2,
				"ground_type": "city_street",
				"ground_top": Color(0.14,0.14,0.16), "ground_mid": Color(0.10,0.10,0.12), "ground_deep": Color(0.06,0.06,0.08),
				"fog_color": Color(0.04,0.05,0.12,0.10),
			}
		_: return {
				"sky_top": Color(0.16,0.38,0.70), "sky_horizon": Color(0.62,0.78,0.94),
				"cloud_color": Color(1.0,1.0,1.0,0.90), "cloud_shadow": Color(0.76,0.84,0.92),
				"has_sun": true, "sun_color": Color(1.0,0.96,0.78), "has_mountains": false, "has_city": true, "city_time": 0,
				"ground_type": "city_street",
				"ground_top": Color(0.28,0.28,0.30), "ground_mid": Color(0.20,0.20,0.22), "ground_deep": Color(0.13,0.13,0.14),
				"fog_color": Color(0.60,0.76,0.94,0.04),
			}

static func _apply_default_theme() -> Dictionary:
	return {
		"sky_top": Color(0.2,0.45,0.78).darkened(0.25), "sky_horizon": Color(0.53,0.81,0.92).lightened(0.15),
		"cloud_color": Color(1.0,1.0,1.0,1.0), "cloud_shadow": Color(0.78,0.84,0.92),
		"has_sun": true, "sun_color": Color(1.0,0.95,0.70), "has_mountains": true,
		"ground_type": "grass",
		"ground_top": Color(0.22,0.52,0.14), "ground_mid": Color(0.38,0.28,0.16), "ground_deep": Color(0.28,0.20,0.10),
		"ground_detail": "rocks", "fog_color": Color(0.0,0.0,0.0,0.0),
	}
