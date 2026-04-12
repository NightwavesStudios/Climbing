extends Node
## Minecraft-style ambient music system.
## Plays tracks in random order with silence gaps between them.
## To add more tracks: just append to the TRACKS array.

# ─── Track list ───────────────────────────────────────────────────────────────
# Add or remove paths here — nothing else needs to change.
const TRACKS: Array[String] = [
	"res://assets/audio/music/Track_1.mp3",
	"res://assets/audio/music/Track_2.mp3",
	"res://assets/audio/music/Track_3.mp3",
]

# ─── Timing ───────────────────────────────────────────────────────────────────
## Seconds of silence between tracks.
const SILENCE_MIN: float = 5.0
const SILENCE_MAX: float = 60.0

## First track delay — shorter so the game doesn't feel dead on launch.
const FIRST_DELAY_MIN: float = 2.0
const FIRST_DELAY_MAX: float = 20.0

# ─── Repeat avoidance ────────────────────────────────────────────────────────
## How many recent tracks to remember. With 3 tracks this is capped to 1
## automatically so we never deadlock. Raise freely when you have more tracks.
const HISTORY_SIZE: int = 2

# ─────────────────────────────────────────────────────────────────────────────

var _player: AudioStreamPlayer
var _history: Array[int] = []   # indices of recently played tracks
var _timer: Timer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"        # route through a Music bus if you have one
	add_child(_player)
	_player.finished.connect(_on_track_finished)

	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_play_next)

	var first_delay := randf_range(FIRST_DELAY_MIN, FIRST_DELAY_MAX)
	_timer.start(first_delay)
	print("[MusicPlayer] Ready — first track in %.0fs" % first_delay)


func _play_next() -> void:
	if TRACKS.is_empty():
		return

	var idx := _pick_track()
	_history.append(idx)

	# Cap history so it never exceeds (track_count - 1) to avoid deadlocks.
	var max_hist := mini(HISTORY_SIZE, TRACKS.size() - 1)
	while _history.size() > max_hist:
		_history.pop_front()

	var path := TRACKS[idx]
	var stream := load(path) as AudioStream
	if not stream:
		push_error("[MusicPlayer] Could not load: " + path)
		_schedule_silence()   # skip broken file, try again after gap
		return

	# Disable any built-in looping on the stream asset.
	if stream is AudioStreamOggVorbis:
		stream.loop = false
	elif stream is AudioStreamMP3:
		stream.loop = false
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

	_player.stream = stream
	_player.play()
	print("[MusicPlayer] Playing track %d: %s" % [idx + 1, path.get_file()])


func _on_track_finished() -> void:
	_schedule_silence()


func _schedule_silence() -> void:
	var gap := randf_range(SILENCE_MIN, SILENCE_MAX)
	_timer.start(gap)
	print("[MusicPlayer] Silence for %.0fs (%.1f min)" % [gap, gap / 60.0])


## Returns a track index that is not in the recent history.
func _pick_track() -> int:
	var available: Array[int] = []
	for i in TRACKS.size():
		if i not in _history:
			available.append(i)

	# Fallback: if history covers everything (shouldn't happen with capping),
	# just pick anything randomly.
	if available.is_empty():
		return randi() % TRACKS.size()

	return available[randi() % available.size()]


## Call this to immediately stop music (e.g. cutscene, credits).
func stop() -> void:
	_timer.stop()
	_player.stop()


## Resume the scheduler after stop(). Starts a normal silence gap.
func resume() -> void:
	_schedule_silence()
