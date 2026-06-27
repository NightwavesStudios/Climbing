extends Node

const TRACKS: Array[String] = [
	"res://assets/audio/music/Track_1.mp3",
	"res://assets/audio/music/Track_2.mp3",
	"res://assets/audio/music/Track_3.mp3",
]

const SILENCE_MIN := 5.0
const SILENCE_MAX := 30.0

const HISTORY_SIZE := 2

var _player: AudioStreamPlayer
var _timer: Timer

var _history: Array[int] = []

func _ready() -> void:
	_setup_audio()
	_setup_timer()

	_play_next()

func _setup_audio() -> void:
	_player = AudioStreamPlayer.new()

	_player.bus = "Music"

	add_child(_player)

	_player.finished.connect(_on_track_finished)


func _setup_timer() -> void:
	_timer = Timer.new()

	_timer.one_shot = true

	add_child(_timer)

	_timer.timeout.connect(_play_next)

func _play_next() -> void:
	if TRACKS.is_empty():
		return

	var index := _pick_track()

	_update_history(index)

	var stream := _load_track(TRACKS[index])

	if stream == null:
		_schedule_next_track()
		return

	_configure_stream(stream)

	_play_stream(stream, index)


func _play_stream(stream: AudioStream, index: int) -> void:
	_player.stream = stream
	_player.play()

	print(
		"[MusicPlayer] Playing track %d: %s"
		% [index + 1, TRACKS[index].get_file()]
	)

func _load_track(path: String) -> AudioStream:
	var stream := load(path) as AudioStream

	if stream:
		return stream

	push_error("[MusicPlayer] Could not load: " + path)

	return null


func _configure_stream(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = false

	elif stream is AudioStreamMP3:
		stream.loop = false

	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

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

	var max_history := mini(
		HISTORY_SIZE,
		TRACKS.size() - 1
	)

	while _history.size() > max_history:
		_history.pop_front()

func _on_track_finished() -> void:
	_schedule_next_track()


func _schedule_next_track() -> void:
	var delay := randf_range(
		SILENCE_MIN,
		SILENCE_MAX
	)

	_timer.start(delay)

	print(
		"[MusicPlayer] Next track in %.0fs"
		% delay
	)
	
func stop() -> void:
	_timer.stop()
	_player.stop()


func resume() -> void:
	_schedule_next_track()
