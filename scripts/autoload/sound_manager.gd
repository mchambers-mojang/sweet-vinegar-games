extends Node

## Procedural sound effects for game interactions

var _players: Array[AudioStreamPlayer] = []
const POOL_SIZE := 4
const SAMPLE_RATE := 22050


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)


func _get_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0]


func play_place() -> void:
	if not SettingsManager.sound_enabled:
		return
	_play_tone(800.0, 0.06, -12.0)


func play_pencil() -> void:
	if not SettingsManager.sound_enabled:
		return
	_play_tone(1200.0, 0.03, -18.0)


func play_erase() -> void:
	if not SettingsManager.sound_enabled:
		return
	_play_tone(400.0, 0.08, -14.0)


func play_error() -> void:
	if not SettingsManager.sound_enabled:
		return
	_play_tone(200.0, 0.15, -10.0)


func play_select() -> void:
	if not SettingsManager.sound_enabled:
		return
	_play_tone(600.0, 0.03, -20.0)


func play_win() -> void:
	if not SettingsManager.sound_enabled:
		return
	# Rising arpeggio
	_play_tone(523.0, 0.12, -10.0)  # C5
	var t := create_tween()
	t.tween_callback(func() -> void: _play_tone(659.0, 0.12, -10.0)).set_delay(0.12)  # E5
	t.tween_callback(func() -> void: _play_tone(784.0, 0.12, -10.0)).set_delay(0.12)  # G5
	t.tween_callback(func() -> void: _play_tone(1047.0, 0.2, -8.0)).set_delay(0.12)   # C6


func play_unit_complete() -> void:
	if not SettingsManager.sound_enabled:
		return
	_play_tone(880.0, 0.08, -14.0)


func _play_tone(frequency: float, duration: float, volume_db: float) -> void:
	var sample_count := int(SAMPLE_RATE * duration)
	var audio := AudioStreamWAV.new()
	audio.mix_rate = SAMPLE_RATE
	audio.format = AudioStreamWAV.FORMAT_8_BITS
	audio.stereo = false

	var data := PackedByteArray()
	data.resize(sample_count)

	for i in sample_count:
		var t := float(i) / SAMPLE_RATE
		var envelope := 1.0 - (float(i) / sample_count)  # Linear fade out
		envelope *= envelope  # Exponential decay
		var sample := sin(t * frequency * TAU) * envelope
		# Convert to 8-bit unsigned (0-255, 128 = center)
		data[i] = int(clampf(sample * 80.0 + 128.0, 0.0, 255.0))

	audio.data = data

	var player := _get_player()
	player.stream = audio
	player.volume_db = volume_db
	player.play()
