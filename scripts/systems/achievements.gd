extends Node
## Autoload singleton for managing Steam achievements.
##
## Each public method checks the relevant game state and unlocks the
## achievement if the condition is met.  Call these from wherever the
## triggering event occurs (level completion, fall tracking, etc.).

# ── Achievement API Names ─────────────────────────────────────────────────
const FIRST_CLIMB    := "FIRST_CLIMB"
const DEMO_COMPLETE  := "DEMO_COMPLETE"
const WEEKLY_LEVEL   := "WEEKLY_LEVEL"
# const ON_REAL_ROCK   := "ON_REAL_ROCK"  # reserved for full game
const LOOSE_ROCK     := "LOOSE_ROCK"
const GRAVITY_CHECK  := "GRAVITY_CHECK"
const SPEED_DEMON    := "SPEED_DEMON"
const PHOTO_FINISH   := "PHOTO_FINISH"
const ROPE_GUN       := "ROPE_GUN"

# ── Thresholds ────────────────────────────────────────────────────────────
const FALLING_HOLD_THRESHOLD := 50
const FALL_THRESHOLD         := 20

# ── Internal ──────────────────────────────────────────────────────────────

var _steam_available := false

func _ready() -> void:
	_steam_available = Engine.has_singleton("Steam") and Steam.isSteamRunning()
	if not _steam_available:
		print("Achievements: Steam not available — achievements disabled")

func setAchievement(ach: String) -> void:
	if not _steam_available:
		return
	var status: Dictionary = Steam.getAchievement(ach)
	if status.get("achieved", false):
		print("Achievements: " + ach + " already unlocked!")
		return
	Steam.setAchievement(ach)
	Steam.storeStats()
	print("Achievements: Unlocked \"" + ach + "\"")

func _update_progress_stat(ach: String, current: int, target: int) -> void:
	"""Update a Steam achievement's progress stat so the overlay shows fractional progress.
	Only calls indicateAchievementProgress if the achievement isn't already achieved."""
	if not _steam_available:
		return
	if Steam.getAchievement(ach).get("achieved", false):
		return
	var display: String = "%d/%d" % [current, target]
	print("Achievements: Progress \"%s\" = %s" % [ach, display])
	Steam.indicateAchievementProgress(ach, current, target)

# =============================================================================
#  ACHIEVEMENT CHECKS  (called by game logic when events occur)
# =============================================================================

## Called when the player tops out any level for the first time.
func check_first_climb() -> void:
	setAchievement(FIRST_CLIMB)

## Called when the last demo level (gym tutorial) is completed.
func check_demo_complete() -> void:
	setAchievement(DEMO_COMPLETE)

## Called when the weekly level is completed.
func check_weekly_level() -> void:
	setAchievement(WEEKLY_LEVEL)

## Called whenever a falling hold is recorded.
## Tracks progress via Steam stats so the player sees "X/50" in the overlay.
func check_loose_rock() -> void:
	var total := GameState.get_total_falling_holds()
	_update_progress_stat(LOOSE_ROCK, total, FALLING_HOLD_THRESHOLD)
	if total >= FALLING_HOLD_THRESHOLD:
		setAchievement(LOOSE_ROCK)

## Called whenever a fall is recorded.
## Tracks progress via Steam stats so the player sees "X/20" in the overlay.
func check_gravity_check() -> void:
	var total := GameState.get_total_falls()
	_update_progress_stat(GRAVITY_CHECK, total, FALL_THRESHOLD)
	if total >= FALL_THRESHOLD:
		setAchievement(GRAVITY_CHECK)

## Called when a speed climb is completed.
## time_remaining: how many seconds were left on the timer.
## time_limit:     the total time limit for the route.
func check_speed_demon(time_remaining: float, time_limit: float) -> void:
	if time_limit <= 0.0:
		return
	var fraction_left := time_remaining / time_limit
	if fraction_left >= 0.5:
		setAchievement(SPEED_DEMON)

## Called when a speed climb is completed.
## time_remaining: how many seconds were left on the timer.
func check_photo_finish(time_remaining: float) -> void:
	if time_remaining >= 0.0 and time_remaining < 3.0:
		setAchievement(PHOTO_FINISH)

## Called when a roped climb is completed.
func check_rope_gun() -> void:
	setAchievement(ROPE_GUN)
