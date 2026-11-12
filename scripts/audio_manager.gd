extends Node
## Autoload "Sfx": every sound is synthesised by code at startup (no audio files)
## and played through a small pool of AudioStreamPlayer nodes.
##   Sfx.play(&"gunshot_rifle")
##   Sfx.play(&"footstep", -8.0, 1.0, 0.1)   # volume dB, pitch, random pitch

const RATE := 22050

@export var master_volume_db: float = -5.0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Keep playing while the game is paused (victory / defeat / menus).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 12345
	for i in 14:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_build_sounds()


func has_sound(sound: StringName) -> bool:
	return _streams.has(sound)


func play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0, pitch_random: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	var player := _pick_player()
	player.stream = stream
	player.volume_db = master_volume_db + volume_db
	player.pitch_scale = maxf(pitch + _rng.randf_range(-pitch_random, pitch_random), 0.05)
	player.play()


func _pick_player() -> AudioStreamPlayer:
	for i in _players.size():
		var index := (_next + i) % _players.size()
		if not _players[index].playing:
			_next = (index + 1) % _players.size()
			return _players[index]
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	return player


# ---------------------------------------------------------------------------
# Sound design
# ---------------------------------------------------------------------------

func _build_sounds() -> void:
	_streams[&"gunshot_rifle"] = _wav(_gunshot(0.24, 190.0, 45.0, 30.0, 16.0, 0.55))
	_streams[&"gunshot_pistol"] = _wav(_gunshot(0.17, 300.0, 80.0, 42.0, 24.0, 0.7))
	_streams[&"gunshot_enemy"] = _wav(_gunshot(0.3, 150.0, 40.0, 20.0, 13.0, 0.16))
	_streams[&"reload_out"] = _wav(_mix([
		_click(0.0, 1500.0, 0.03, 0.7), _click(0.11, 900.0, 0.05, 0.9)], 0.24))
	_streams[&"reload_in"] = _wav(_mix([
		_click(0.0, 800.0, 0.05, 0.9), _click(0.13, 1900.0, 0.025, 0.6), _click(0.2, 1200.0, 0.045, 1.0)], 0.32))
	_streams[&"weapon_switch"] = _wav(_mix([_click(0.0, 1100.0, 0.04, 0.6), _click(0.07, 700.0, 0.05, 0.5)], 0.16))
	_streams[&"empty"] = _wav(_click(0.0, 2400.0, 0.02, 0.5))
	_streams[&"footstep"] = _wav(_thud(0.1, 95.0, 48.0, 0.22))
	_streams[&"land"] = _wav(_thud(0.16, 70.0, 30.0, 0.3))
	_streams[&"hit"] = _wav(_tone([1500.0], 0.06, 80.0, 0.6))
	_streams[&"headshot"] = _wav(_tone([2100.0, 3150.0], 0.22, 20.0, 0.55))
	_streams[&"hurt"] = _wav(_thud(0.18, 130.0, 22.0, 0.5))
	_streams[&"death"] = _wav(_sweep(330.0, 80.0, 0.5, 6.0, 0.5))
	_streams[&"beacon"] = _wav(_melody([[660.0, 0.1], [880.0, 0.1], [1320.0, 0.3]], 7.0, 0.45))
	_streams[&"victory"] = _wav(_melody([[523.25, 0.13], [659.25, 0.13], [783.99, 0.13], [1046.5, 0.2], [783.99, 0.1], [1046.5, 0.6]], 3.5, 0.5))
	_streams[&"defeat"] = _wav(_melody([[392.0, 0.25], [311.13, 0.25], [261.63, 0.3], [196.0, 0.8]], 2.5, 0.5))
	_streams[&"ricochet"] = _wav(_sweep(3200.0, 1500.0, 0.16, 16.0, 0.3))
	_streams[&"ui_click"] = _wav(_tone([900.0, 1350.0], 0.07, 45.0, 0.35))


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## Gunshot: filtered noise crack + a falling low "thump". brightness 0..1 (low = distant).
func _gunshot(duration: float, freq_start: float, freq_end: float, noise_decay: float, body_decay: float, brightness: float) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		var k := t / duration
		phase += TAU * lerpf(freq_start, freq_end, sqrt(k)) / RATE
		var body := sin(phase) * exp(-t * body_decay)
		var noise := _rng.randf_range(-1.0, 1.0) * exp(-t * noise_decay)
		lp += (noise - lp) * brightness
		var fade := minf((1.0 - k) * 12.0, 1.0)
		out[i] = tanh((body * 0.9 + lp * 1.3) * 1.7) * 0.85 * fade
	return out


## Short mechanical click: noise burst + a pitched ping, starting at `start` seconds.
func _click(start: float, freq: float, length: float, gain: float) -> PackedFloat32Array:
	var offset := int(start * RATE)
	var count := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(offset + count)
	var prev := 0.0
	for i in count:
		var t := float(i) / RATE
		var env := exp(-t * (5.0 / length))
		var noise := _rng.randf_range(-1.0, 1.0)
		var high := noise - prev  # crude high-pass
		prev = noise
		out[offset + i] = (high * 0.5 + sin(TAU * freq * t) * 0.6) * env * gain
	return out


## Low thud for footsteps and landings.
func _thud(duration: float, freq: float, decay: float, noise_amount: float) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var lp := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		phase += TAU * freq * (1.0 - 0.4 * t / duration) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.12
		var env := exp(-t * decay) * minf(t * 400.0, 1.0)
		out[i] = (sin(phase) * 0.8 + lp * noise_amount * 4.0) * env * 0.8
	return out


## Bell-like tone made of one or more partials.
func _tone(freqs: Array, duration: float, decay: float, gain: float) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t)
		var env := exp(-t * decay) * minf(t * 600.0, 1.0) * minf((duration - t) * 200.0, 1.0)
		out[i] = v / float(freqs.size()) * env * gain
	return out


## Falling tone with a bit of grit (enemy death).
func _sweep(freq_start: float, freq_end: float, duration: float, decay: float, gain: float) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var k := t / duration
		phase += TAU * lerpf(freq_start, freq_end, k) / RATE
		var v := sin(phase) * 0.7 + sin(phase * 2.0) * 0.2 + _rng.randf_range(-1.0, 1.0) * 0.12
		out[i] = tanh(v * 1.5) * exp(-t * decay) * minf(t * 300.0, 1.0) * minf((1.0 - k) * 10.0, 1.0) * gain
	return out


## Sequence of notes: [[frequency, seconds], ...].
func _melody(notes: Array, decay: float, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for note in notes:
		var freq: float = note[0]
		var length: float = note[1]
		var count := int(length * RATE)
		for i in count:
			var t := float(i) / RATE
			# Soft square-ish voice: fundamental + odd harmonics.
			var v := sin(TAU * freq * t) + sin(TAU * freq * 3.0 * t) * 0.25 + sin(TAU * freq * 2.0 * t) * 0.2
			var env := exp(-t * decay) * minf(t * 300.0, 1.0) * minf((length - t) * 120.0, 1.0)
			out.append(v * env * gain * 0.6)
	return out


## Mixes several sample arrays into one of total_length seconds.
func _mix(parts: Array, total_length: float) -> PackedFloat32Array:
	var count := int(total_length * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for part in parts:
		var samples: PackedFloat32Array = part
		for i in mini(samples.size(), count):
			out[i] += samples[i]
	return out
