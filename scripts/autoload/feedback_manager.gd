extends Node

## Unified feedback autoload — merges SoundManager (procedural audio) and
## HapticManager (touch vibration) into a single module.
## Internal seams are preserved: sound logic is in the Sound section,
## haptic logic is in the Haptic section, for independent unit testing.


# ============================================================
# Sound (previously SoundManager)
# ============================================================

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
	if not PlatformSettings.sound_enabled:
		return
	_play_tone(800.0, 0.06, -12.0)


func play_pencil() -> void:
	if not PlatformSettings.sound_enabled:
		return
	_play_tone(1200.0, 0.03, -18.0)


func play_erase() -> void:
	if not PlatformSettings.sound_enabled:
		return
	_play_tone(400.0, 0.08, -14.0)


func play_error() -> void:
	if not PlatformSettings.sound_enabled:
		return
	_play_tone(200.0, 0.15, -10.0)


func play_select() -> void:
	if not PlatformSettings.sound_enabled:
		return
	_play_tone(600.0, 0.03, -20.0)


func play_win() -> void:
	if not PlatformSettings.sound_enabled:
		return
	# Rising arpeggio
	_play_tone(523.0, 0.12, -10.0)  # C5
	var t := create_tween()
	t.tween_callback(func() -> void: _play_tone(659.0, 0.12, -10.0)).set_delay(0.12)  # E5
	t.tween_callback(func() -> void: _play_tone(784.0, 0.12, -10.0)).set_delay(0.12)  # G5
	t.tween_callback(func() -> void: _play_tone(1047.0, 0.2, -8.0)).set_delay(0.12)   # C6


func play_unit_complete() -> void:
	if not PlatformSettings.sound_enabled:
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


# ============================================================
# Haptic (previously HapticManager)
# ============================================================

const THROTTLE_MS := 50

# Initialised to -THROTTLE_MS so the very first vibrate call is never suppressed.
var _last_vibrate_msec: int = -THROTTLE_MS


func vibrate_light() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(15)


func vibrate_medium() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(30)


func vibrate_heavy() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(50)


func vibrate_error() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(80)


func vibrate_success() -> void:
	if not PlatformSettings.haptic_enabled:
		return
	_do_vibrate(40)
	var t := create_tween()
	t.tween_callback(func() -> void: _do_vibrate(40)).set_delay(0.1)


## Cancel any active vibration immediately.
## Intentionally skips the haptic_enabled check — stopping must always work
## to prevent a stuck vibration even if the setting is toggled mid-session.
func stop() -> void:
	Input.vibrate_handheld(0)


func _do_vibrate(duration_ms: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_vibrate_msec < THROTTLE_MS:
		return  # Suppress rapid-fire calls to prevent vibration stacking
	_last_vibrate_msec = now
	Input.vibrate_handheld(duration_ms)
