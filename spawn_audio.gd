class_name SpawnAudio
extends Node

const SAMPLE_RATE := 22050

var _player: AudioStreamPlayer
var _stream: AudioStreamWAV
var _frame_played := -1
var _enabled := true
var _volume_db := -12.0
var play_count := 0

func _ready() -> void:
	_stream = _make_pop()
	_player = AudioStreamPlayer.new()
	_player.stream = _stream
	_player.bus = "Master"
	_player.max_polyphony = 1
	add_child(_player)

func configure(settings: Dictionary) -> void:
	var effects := bool(settings.get("effects_enabled", settings.get("effects", true)))
	var master := clampf(float(settings.get("volume", settings.get("master_volume", 1.0))), 0.0, 1.0)
	var shot := clampf(float(settings.get("shot_volume", 1.0)), 0.0, 1.0)
	_enabled = effects and master > 0.0 and shot > 0.0
	var gain := master * shot
	_volume_db = -60.0 if gain <= 0.001 else linear_to_db(gain) - 12.0
	if is_instance_valid(_player):
		_player.volume_db = _volume_db

func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null
	_stream = null

func spawn_at(_position: Vector2 = Vector2.ZERO) -> void:
	if not _enabled or not is_inside_tree() or not is_instance_valid(_player):
		return
	var frame := Engine.get_process_frames()
	if frame == _frame_played:
		return
	_frame_played = frame
	_player.volume_db = _volume_db
	_player.play()
	play_count += 1

func _make_pop() -> AudioStreamWAV:
	var samples := PackedByteArray()
	var count := int(SAMPLE_RATE * 0.11)
	samples.resize(count * 2)
	var state := 0x5a17
	for i in count:
		state = (state * 1103515245 + 12345) & 0x7fffffff
		var noise := float((state >> 16) & 0x7fff) / 16383.5 - 1.0
		var t := float(i) / SAMPLE_RATE
		var envelope := exp(-t * 34.0)
		var body := sin(TAU * (190.0 - 90.0 * t / 0.11) * t) * 0.38
		var sample := clampi(roundi((body + noise * 0.24) * envelope * 32767.0), -32768, 32767)
		samples[i * 2] = sample & 0xff
		samples[i * 2 + 1] = (sample >> 8) & 0xff
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = samples
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav
