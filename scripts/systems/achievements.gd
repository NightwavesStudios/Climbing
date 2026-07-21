extends Node
## Autoload singleton for managing Steam achievements.
##
## Each public method checks the relevant game state and unlocks the
## achievement if the condition is met.  Call these from wherever the
## triggering event occurs (level completion, fall tracking, etc.).

# ── Achievement API Names ─────────────────────────────────────────────────
const FIRST_CLIMB    := "FIRST_CLIMB"
const DEMO_COMPLETE  := "DEMO_COMPLETE"
const GYM_RAT        := "GYM_RAT"
const ON_REAL_ROCK   := "ON_REAL_ROCK"
const LOOSE_ROCK     := "LOOSE_ROCK"
const GRAVITY_CHECK  := "GRAVITY_CHECK"
const SPEED_DEMON    := "SPEED_DEMON"
const PHOTO_FINISH   := "PHOTO_FINISH"
const ROPE_GUN       := "ROPE_GUN"

# ── Thresholds ────────────────────────────────────────────────────────────
const FALLING_HOLD_THRESHOLD := 50
const FALL_THRESHOLD         := 20

# ── Internal ──────────────────────────────────────────────────────────────

func setAchievement(ach: String) -> void:
	var status = Steam.getAchievement(ach)
	if status["achieved"]:
		print("Achievements: " + ach + " already unlocked!")
		return
	Steam.setAchievement(ach)
	print("Achievements: Unlocked \"" + ach + "\"")

# =============================================================================
#  ACHIEVEMENT CHECKS  (called by game logic when events occur)
# =============================================================================

## Called when the player tops out any level for the first time.
func check_first_climb() -> void:
	setAchievement(FIRST_CLIMB)

## Called when the last demo level (granite_crag_10) is completed.
func check_demo_complete() -> void:
	setAchievement(DEMO_COMPLETE)

## Called after a level is completed — checks whether all gym levels are done.
func check_gym_rat() -> void:
	if GameState.is_collection_completed("intro-gym"):
		setAchievement(GYM_RAT)

## Called after a level is completed — checks whether all granite levels are done.
func check_on_real_rock() -> void:
	if GameState.is_collection_completed("granite-crag"):
		setAchievement(ON_REAL_ROCK)

## Called whenever a falling hold is recorded.
func check_loose_rock() -> void:
	if GameState.get_total_falling_holds() >= FALLING_HOLD_THRESHOLD:
		setAchievement(LOOSE_ROCK)

## Called whenever a fall is recorded.
func check_gravity_check() -> void:
	if GameState.get_total_falls() >= FALL_THRESHOLD:
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