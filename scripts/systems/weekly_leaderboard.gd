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
# Cache of Steam persona names keyed by 64-bit steam_id.
var _persona_names: Dictionary = {}
# Last emitted leaderboard data, so we can refresh names when persona data loads async.
var _last_entries: Array = []
var _last_player_rank: int = 0
var _last_player_time: float = 0.0
# Player's rank from the last successful upload (global_rank_new) — used to
# identify the player's row even if the entry's steam_id comes back as 0.
var _last_uploaded_rank: int = 0
# Cached local player persona name (Steam.getPersonaName).
var _local_player_name: String = ""

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
	Steam.persona_state_change.connect(_on_persona_state_change)
	print("WeeklyLeaderboard: Ready")

func _process(_delta: float) -> void:
	if _steam_available:
		Steam.run_callbacks()

@warning_ignore("integer_division")
func get_current_week_number() -> int:
	var unix_now := int(Time.get_unix_time_from_system())
	return unix_now / (7 * 86400)

func get_leaderboard_name() -> String:
	return LEADERBOARD_PREFIX + str(get_current_week_number())

func _find_or_create(callback_op: int) -> void:
	_current_leaderboard_name = get_leaderboard_name()
	_pending_operation = callback_op
	Steam.findOrCreateLeaderboard(
		_current_leaderboard_name,
		Steam.LEADERBOARD_SORT_METHOD_ASCENDING,
		Steam.LEADERBOARD_DISPLAY_TYPE_TIME_MILLISECONDS
	)

func upload_score(time_seconds: float) -> void:
	if not _steam_available:
		return
	if time_seconds <= 0.0:
		return
	_pending_score_ms = int(time_seconds * 1000.0)
	_last_uploaded_rank = 0  # Fresh per completion — set again on successful upload.
	_find_or_create(PendingOp.UPLOAD)

func download_entries_around_player() -> void:
	if not _steam_available:
		return
	_find_or_create(PendingOp.DOWNLOAD)

func _on_leaderboard_find_result(leaderboard_handle: int, _found: int) -> void:
	_current_leaderboard_handle = leaderboard_handle
	match _pending_operation:
		PendingOp.UPLOAD:
			Steam.uploadLeaderboardScore(
				_pending_score_ms,
				true,
				PackedInt32Array(),
				_current_leaderboard_handle
			)
		PendingOp.DOWNLOAD:
			Steam.downloadLeaderboardEntries(
				-2,
				2,
				Steam.LEADERBOARD_DATA_REQUEST_GLOBAL_AROUND_USER,
				_current_leaderboard_handle
			)
	_pending_operation = PendingOp.NONE

func _on_leaderboard_score_uploaded(success: int, _this_handle: int, this_score: Dictionary) -> void:
	_pending_score_ms = 0
	var rank: int = 0
	if success != 0:
		rank = this_score.get("global_rank_new", 0)
		_last_uploaded_rank = rank
	score_uploaded.emit(success == 1, rank)
	# Always fetch leaderboard entries — even if upload failed, we still show
	# whatever data is available (or "No leaderboard data yet").
	download_entries_around_player()

func _on_leaderboard_scores_downloaded(_message: String, _leaderboard_handle: int, leaderboard_entries: Array) -> void:
	var parsed_entries: Array[Dictionary] = []
	var player_rank: int = 0
	var player_time: float = 0.0
	var local_steam_id: int = Steam.getSteamID()
	var local_name: String = _get_local_player_name()
	for entry in leaderboard_entries:
		var entry_dict: Dictionary = entry as Dictionary
		var entry_steam_id: int = entry_dict.get("steam_id", 0)
		var entry_rank: int = entry_dict.get("global_rank", 0)
		# Identify the local player's row three ways:
		# 1. steam_id matches the local user, or
		# 2. rank matches the rank reported by the last upload callback, or
		# 3. steam_id missing AND this is the only entry (fresh weekly board).
		var is_local_player: bool = false
		if entry_steam_id > 0 and entry_steam_id == local_steam_id:
			is_local_player = true
		elif _last_uploaded_rank > 0 and entry_rank == _last_uploaded_rank:
			is_local_player = true
		elif entry_steam_id <= 0 and leaderboard_entries.size() == 1:
			is_local_player = true
		if is_local_player:
			player_rank = entry_rank
			player_time = entry_dict.get("score", 0) / 1000.0
		# Name: Steam persona lookup by steam_id; fall back to the local
		# player's own name when the lookup fails but we know it's them.
		var entry_name: String = ""
		if entry_steam_id > 0:
			entry_name = _get_persona_name(entry_steam_id)
		if entry_name == "" and is_local_player:
			entry_name = local_name
		parsed_entries.append({
			"steam_id": entry_steam_id,
			"global_rank": entry_rank,
			"score": entry_dict.get("score", 0),
			"name": entry_name
		})
	# Defer the emit to the next frame so the overlay (which started the async chain
	# in the current frame) has time to connect to the signal before receiving data.
	call_deferred(&"_deferred_emit_leaderboard_ready", parsed_entries, player_rank, player_time)


func _deferred_emit_leaderboard_ready(entries: Array, player_rank: int, player_time: float) -> void:
	# Remember the last emitted data so we can refresh names when Steam
	# finishes loading persona info asynchronously (persona_state_change).
	_last_entries = entries
	_last_player_rank = player_rank
	_last_player_time = player_time
	leaderboard_ready.emit(entries, player_rank, player_time)


func _get_persona_name(steam_id: int) -> String:
	"""Fetch a user's Steam persona name, kicking off async loading if needed."""
	if steam_id <= 0:
		return ""
	if _persona_names.has(steam_id):
		return _persona_names[steam_id]
	# The local player's own name is always available synchronously via getPersonaName().
	# getFriendPersonaName() can return "" for self while persona data loads async.
	if steam_id == Steam.getSteamID():
		var self_name: String = get_local_player_name()
		if self_name != "":
			_persona_names[steam_id] = self_name
		return self_name
	# Kick off async persona name loading (returns true if data is still loading).
	Steam.requestUserInformation(steam_id, true)
	var persona_name: String = Steam.getFriendPersonaName(steam_id)
	if persona_name != "":
		_persona_names[steam_id] = persona_name
	return persona_name


func _get_local_player_name() -> String:
	"""The local player's own Steam persona name (cached)."""
	if _local_player_name == "":
		_local_player_name = Steam.getPersonaName()
	return _local_player_name


func get_local_player_name() -> String:
	"""Public accessor for the local player's cached Steam persona name."""
	return _get_local_player_name()


func _on_persona_state_change(steam_id: int, _flags: int) -> void:
	"""Persona data finished loading — update any leaderboard rows showing this user."""
	if not _steam_available:
		return
	var persona_name: String = Steam.getFriendPersonaName(steam_id)
	if persona_name == "":
		return
	_persona_names[steam_id] = persona_name
	var updated: bool = false
	for entry in _last_entries:
		if entry.get("steam_id", 0) == steam_id and entry.get("name", "") != persona_name:
			entry["name"] = persona_name
			updated = true
	if updated:
		leaderboard_ready.emit(_last_entries, _last_player_rank, _last_player_time)

func format_time(seconds: float) -> String:
	var mins := int(seconds / 60.0)
	var secs := int(seconds) % 60
	var millis := int((seconds - int(seconds)) * 100.0)
	return "%02d:%02d.%02d" % [mins, secs, millis]
