extends Node
## MusicPlayer with seamless crossfade between tracks.
##
## Instead of dead silence between tracks, we crossfade: as one track
## finishes, the next fades in smoothly using dual AudioStreamPlayers.

const TRACKS: Array[String] = [
	"res://assets/audio/music/Track_1.mp3",
	"res://assets/audio/music/Track_2.mp3",
	"res://assets/audio/music/Track_3.mp3",
]

## Duration of the crossfade transition (seconds).
const CROSSFADE_DURATION := 0
## Brief natural pause between tracks before the crossfade starts (seconds).
const BREATH_GAP := 1.5
## How many past tracks to remember (avoids immediate repeats).
const HISTORY_SIZE := 2

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer  # points to whichever is currently playing
var _timer: Timer
var _history: Array[int] = []
var _crossfade_tween: Tween = null
var _next_index: int = -1
var _is_crossfading: bool = false

func _ready() -> void:
	_setup_audio()
	_setup_timer()
	_active_player = _player_a
	_schedule_next_track()

	# Pause music when the window loses focus
	var root := get_tree().root as Window
	if root:
		root.focus_exited.connect(_on_focus_lost)
		root.focus_entered.connect(_on_focus_gained)


# ── Focus handling ──────────────────────────────────────────────────────────

func _on_focus_lost() -> void:
	_timer.stop()
	_player_a.stream_paused = true
	_player_b.stream_paused = true


func _on_focus_gained() -> void:
	_player_a.stream_paused = false
	_player_b.stream_paused = false
	if not _player_a.playing and not _player_b.playing:
		_schedule_next_track()


# ── Setup ───────────────────────────────────────────────────────────────────

func _setup_audio() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_a.bus = "Music"
	add_child(_player_a)

	_player_b = AudioStreamPlayer.new()
	_player_b.bus = "Music"
	add_child(_player_b)

	# Both players start silent so the first track can fade in
	_player_a.volume_db = -80.0
	_player_b.volume_db = -80.0


func _setup_timer() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_begin_crossfade)


# ── Public API ──────────────────────────────────────────────────────────────

func stop() -> void:
	_timer.stop()
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_player_a.stop()
	_player_b.stop()
	_player_a.volume_db = -80.0
	_player_b.volume_db = -80.0
	_is_crossfading = false


func resume() -> void:
	_schedule_next_track()


# ── Crossfade logic ─────────────────────────────────────────────────────────

## Schedule the next track to play after a brief natural pause.
func _schedule_next_track() -> void:
	if TRACKS.is_empty():
		return

	var index := _pick_track()
	_next_index = index
	_update_history(index)
	_timer.start(BREATH_GAP)


## Begin the actual crossfade: old track fades out, new track fades in.
func _begin_crossfade() -> void:
	if _is_crossfading:
		return
	if _next_index < 0 or _next_index >= TRACKS.size():
		return

	_is_crossfading = true
	var index := _next_index
	_next_index = -1

	var stream := _load_track(TRACKS[index])
	if stream == null:
		_is_crossfading = false
		_schedule_next_track()
		return

	# Pick the inactive player for the new track
	var new_player: AudioStreamPlayer = _player_b if _active_player == _player_a else _player_a
	var old_player: AudioStreamPlayer = _active_player

	# Configure and start the new track at silent volume
	new_player.stream = stream
	stream.loop = false
	new_player.volume_db = -80.0
	new_player.play()

	print("[MusicPlayer] Crossfading → track %d: %s" % [index + 1, TRACKS[index].get_file()])

	# Kill any previous crossfade tween
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	_crossfade_tween = create_tween().set_parallel(true)
	_crossfade_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	# Fade out old track
	if old_player.playing:
		_crossfade_tween.tween_property(old_player, "volume_db", -80.0, CROSSFADE_DURATION)

	# Fade in new track from silence to full volume
	_crossfade_tween.tween_property(new_player, "volume_db", 0.0, CROSSFADE_DURATION)

	_crossfade_tween.finished.connect(func():
		# Fully stop the old player
		if old_player.playing:
			old_player.stop()
		old_player.volume_db = -80.0

		_active_player = new_player
		_is_crossfading = false

		# Listen for the new track finishing so we can queue the next one
		if not new_player.finished.is_connected(_on_track_finished):
			new_player.finished.connect(_on_track_finished, CONNECT_ONE_SHOT)

	, CONNECT_ONE_SHOT)


func _on_track_finished() -> void:
	print("[MusicPlayer] Track finished — scheduling next")
	_schedule_next_track()


# ── Track selection (no immediate repeats) ─────────────────────────────────

func _pick_track() -> int:
	var available: Array[int] = []
	for i in TRACKS.size():
		if i not in _history:
			available.append(i)
	if available.is_empty():
		return randi() % TRACKS.size()
	return available.pick_random()


func _update_history(index: int) -> void:
	_history.append(index)
	var max_history := mini(HISTORY_SIZE, TRACKS.size() - 1)
	while _history.size() > max_history:
		_history.pop_front()


# ── Helpers ─────────────────────────────────────────────────────────────────

func _load_track(path: String) -> AudioStream:
	var stream := load(path) as AudioStream
	if stream:
		return stream
	push_error("[MusicPlayer] Could not load: " + path)
	return null
