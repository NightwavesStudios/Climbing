extends Node
## Autoload singleton for managing Steam achievements and stats.
##
## Provides safe wrappers around the Steam API. All methods gracefully
## no-op when Steam is not running (e.g. during editor play or non-Steam builds).

# ── Achievement API names (must match Steamworks backend) ──────────────────
const ACHIEVEMENTS := {
	FIRST_CLIMB    = "FIRST_CLIMB",
	DEMO_COMPLETE  = "DEMO_COMPLETE",
	GYM_RAT        = "GYM_RAT",
	ON_REAL_ROCK   = "ON_REAL_ROCK",
	LOOSE_ROCK     = "LOOSE_ROCK",
	GRAVITY_CHECK  = "GRAVITY_CHECK",
	SPEED_DEMON    = "SPEED_DEMON",
	PHOTO_FINISH   = "PHOTO_FINISH",
	ROPE_GUN       = "ROPE_GUN",
}

# ── Stat names ─────────────────────────────────────────────────────────────
const STAT_FALLS         := "stat_falls"
const STAT_FALLING_HOLDS := "stat_falling_holds"

# ── Thresholds ─────────────────────────────────────────────────────────────
const FALLS_REQUIRED         := 20
const FALLING_HOLDS_REQUIRED := 50

var _steam_initialized: bool = false
var _steam_available: bool = false


func _ready() -> void:
	# Detect whether the Steam singleton exists and the Steam client is running.
	# In GodotSteam GDExtension, the Steam singleton is always present but
	# steam_init() returns false when no Steam client is detected.
	if not _try_init_steam():
		print("SteamManager: Steam not available — achievements disabled")
	else:
		_steam_available = true
		print("SteamManager: Steam initialized successfully")


func _try_init_steam() -> bool:
	# Guard: Steam singleton may not be compiled in (non-Steam builds).
	if not _has_steam_singleton():
		return false

	# Double-check the Steam client is actually running.
	if not Steam.isSteamRunning():
		print("SteamManager: Steam client is not running")
		return false

	# Initialize the Steam API. On GodotSteam GDExtension, this may already be
	# auto-initialized; calling it again is safe and returns true.
	var result = Steam.steamInit()
	if not result:
		print("SteamManager: steam_init() returned false")
		return false

	_steam_initialized = true
	return true


## Returns true if Steam is initialized and available for API calls.
func is_available() -> bool:
	return _steam_initialized and _steam_available


## Unlock a Steam achievement by its API name.
## Safe to call even when Steam is not running — it simply no-ops.
func unlock_achievement(api_name: String) -> void:
	if not is_available():
		return

	# Avoid re-setting already-unlocked achievements (saves a store_stats round-trip).
	if Steam.getAchievement(api_name):
		return

	Steam.setAchievement(api_name)
	Steam.storeStats()
	print("SteamManager: ✅ Achievement unlocked: ", api_name)


## Set a Steam stat value (int). Used for progressive achievements.
func set_stat_int(stat_name: String, value: int) -> void:
	if not is_available():
		return
	Steam.setStatInt(stat_name, value)
	Steam.storeStats()


## Get the current value of an int stat from Steam.
func get_stat_int(stat_name: String) -> int:
	if not is_available():
		return 0
	return Steam.getStatInt(stat_name)


## Increment an int stat by the given amount and check threshold-based achievements.
func increment_stat(stat_name: String, amount: int = 1) -> void:
	if not is_available():
		return

	var current: int = Steam.getStatInt(stat_name)
	current += amount
	Steam.setStatInt(stat_name, current)
	Steam.storeStats()

	# Check threshold-based achievements
	match stat_name:
		STAT_FALLS:
			if current >= FALLS_REQUIRED:
				unlock_achievement(ACHIEVEMENTS.GRAVITY_CHECK)
		STAT_FALLING_HOLDS:
			if current >= FALLING_HOLDS_REQUIRED:
				unlock_achievement(ACHIEVEMENTS.LOOSE_ROCK)


func _has_steam_singleton() -> bool:
	# Check if the Steam singleton class is registered in ClassDB.
	# ClassDB.class_exists() safely queries without needing the reference.
	return ClassDB.class_exists("Steam")
