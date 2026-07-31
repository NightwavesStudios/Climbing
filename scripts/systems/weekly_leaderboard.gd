extends Node
## Autoload singleton for managing Steam leaderboards for weekly levels.
## Updated for GodotSteam GDExtension API.
##
## Each week gets its own leaderboard named "WeeklyLevelTimesN" where N
## is the current week number (weeks since Unix epoch). Times are stored
## as integer milliseconds with ascending sort (lower = better).
##
## If the player beats their own time, Steam's KEEP_BEST upload method
## automatically replaces the old score with the new better one.

enum PendingOp { NONE, UPLOAD, DOWNLOAD }

const LEADERBOARD_PREFIX := "WeeklyLevelTimes"

var _current_leaderboard_handle: int = 0
var _current_leaderboard_name: String = ""
var _pending_operation: int = PendingOp.NONE
var _pending_score_ms: int = 0
var _steam_available := false

signal leaderboard_ready(entries: Array, player_rank: int, player_time: float)
signal score_uploaded(success: bool, rank: int)

func _ready() -> void:
	_steam_available = Engine.has_singleton("Steam") and Steam.isSteamRunning()
	if not _steam_available:
		print("WeeklyLeaderboard: Steam not available — leaderboard disabled")
		return
	process_mode = PROCESS_MODE_ALWAYS
	Steam.leaderboard_find_result.connect(_on_leaderboard_find_result)
	Steam.leaderboard_score_uploaded.connect(_on_leaderboard_score_uploaded)
	Steam.leaderboard_scores_downloaded.connect(_on_leaderboard_scores_downloaded)
	print("WeeklyLeaderboard: Ready")

func _process(_delta: float) -> void:
	if _steam_available:
		Steam.run_callbacks()

func get_current_week_number() -> int:
	var unix_now := int(Time.get_unix_time_from_system())
	return unix_now / (7 * 86400)

func get_leaderboard_name() -> String:
	return LEADERBOARD_PREFIX + str(get_current_week_number())

func _find_or_create(callback_op: int) -> void:
	_current_leaderboard_name = get_leaderboard_name()
	_pending_operation = callback_op
	print("DEBUG _find_or_create: name=", _current_leaderboard_name, " op=", callback_op)
	Steam.findOrCreateLeaderboard(
		_current_leaderboard_name,
		Steam.LEADERBOARD_SORT_METHOD_ASCENDING,
		Steam.LEADERBOARD_DISPLAY_TYPE_TIME_MILLISECONDS
	)

func upload_score(time_seconds: float) -> void:
	print("DEBUG upload_score: called with time=", time_seconds, " _steam_available=", _steam_available)
	if not _steam_available:
		print("DEBUG upload_score: Steam not available, returning")
		return
	if time_seconds <= 0.0:
		print("DEBUG upload_score: time <= 0.0, returning")
		return
	_pending_score_ms = int(time_seconds * 1000.0)
	print("DEBUG upload_score: score_ms=", _pending_score_ms)
	_find_or_create(PendingOp.UPLOAD)

func download_entries_around_player() -> void:
	print("DEBUG download_entries_around_player: called, _steam_available=", _steam_available)
	if not _steam_available:
		return
	_find_or_create(PendingOp.DOWNLOAD)

func _on_leaderboard_find_result(leaderboard_handle: int, _found: int) -> void:
	print("DEBUG _on_leaderboard_find_result: handle=", leaderboard_handle, " found=", _found, " pending_op=", _pending_operation)
	_current_leaderboard_handle = leaderboard_handle
	match _pending_operation:
		PendingOp.UPLOAD:
			print("DEBUG _on_leaderboard_find_result: calling uploadLeaderboardScore with score=", _pending_score_ms, " handle=", _current_leaderboard_handle)
			Steam.uploadLeaderboardScore(
				_pending_score_ms,
				true,
				PackedInt32Array(),
				_current_leaderboard_handle
			)
		PendingOp.DOWNLOAD:
			print("DEBUG _on_leaderboard_find_result: calling downloadLeaderboardEntries")
			Steam.downloadLeaderboardEntries(
				-2,
				2,
				Steam.LEADERBOARD_DATA_REQUEST_GLOBAL_AROUND_USER,
				_current_leaderboard_handle
			)
	_pending_operation = PendingOp.NONE

func _on_leaderboard_score_uploaded(success: int, _this_handle: int, this_score: Dictionary) -> void:
	print("DEBUG _on_leaderboard_score_uploaded: success=", success, " score=", this_score)
	_pending_score_ms = 0
	var rank: int = 0
	if success != 0:
		rank = this_score.get("global_rank_new", 0)
	score_uploaded.emit(success == 1, rank)
	# Always fetch leaderboard entries — even if upload failed, we still show
	# whatever data is available (or "No leaderboard data yet").
	download_entries_around_player()

func _on_leaderboard_scores_downloaded(_message: String, _leaderboard_handle: int, leaderboard_entries: Array) -> void:
	print("DEBUG _on_leaderboard_scores_downloaded: message=", _message, " entries=", leaderboard_entries.size())
	var parsed_entries: Array[Dictionary] = []
	var player_rank: int = 0
	var player_time: float = 0.0
	var local_steam_id: int = Steam.getSteamID()
	for entry in leaderboard_entries:
		var entry_dict: Dictionary = entry as Dictionary
		var entry_steam_id: int = entry_dict.get("steam_id", 0)
		var entry_name: String = entry_dict.get("name", "Unknown")
		parsed_entries.append({
			"steam_id": entry_steam_id,
			"global_rank": entry_dict.get("global_rank", 0),
			"score": entry_dict.get("score", 0),
			"name": entry_name
		})
		if entry_steam_id == local_steam_id:
			player_rank = entry_dict.get("global_rank", 0)
			player_time = entry_dict.get("score", 0) / 1000.0
	print("DEBUG parsed entries: ", parsed_entries, " player_rank=", player_rank, " local_steam_id=", local_steam_id)
	# Defer the emit to the next frame so the overlay (which started the async chain
	# in the current frame) has time to connect to the signal before receiving data.
	call_deferred(&"_deferred_emit_leaderboard_ready", parsed_entries, player_rank, player_time)


func _deferred_emit_leaderboard_ready(entries: Array, player_rank: int, player_time: float) -> void:
	leaderboard_ready.emit(entries, player_rank, player_time)

func format_time(seconds: float) -> String:
	var mins := int(seconds / 60.0)
	var secs := int(seconds) % 60
	var millis := int((seconds - int(seconds)) * 100.0)
	return "%02d:%02d.%02d" % [mins, secs, millis]
