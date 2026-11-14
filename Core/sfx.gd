extends Node
## Autoload "Sfx": procedural sound effects + ambient music (no audio files needed).
## Streams are synthesised on first use and cached. Master volume comes from Settings.
##   Sfx.play("click")            one-shot
##   Sfx.loop("rumble", -6.0)     start/adjust a loop;  Sfx.loop_stop("rumble")

const RATE := 22050

var _cache: Dictionary = {}
var _loops: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 4242
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -20.0
	add_child(_music)


func play(sound: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var st := _stream(sound)
	for p in _pool:
		if not p.playing:
			p.stream = st
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return


func loop(sound: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p == null:
		p = AudioStreamPlayer.new()
		p.stream = _stream(sound)
		add_child(p)
		_loops[sound] = p
	p.volume_db = vol_db
	p.pitch_scale = pitch
	if not p.playing:
		p.play()


func loop_stop(sound: String) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p != null:
		p.stop()


func stop_all_loops() -> void:
	for k in _loops:
		(_loops[k] as AudioStreamPlayer).stop()


func music(on: bool = true) -> void:
	if on:
		if _music.stream == null:
			_music.stream = _stream("ambient")
		if not _music.playing:
			_music.play()
	else:
		_music.stop()


# ------------------------------------------------------------- synthesis ------
func _stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var s: AudioStreamWAV
	match sound:
		"click":
			s = _wav(_tone(0.06, 1300.0, 700.0, 0.35, 30.0))
		"hover":
			s = _wav(_tone(0.035, 2000.0, 1800.0, 0.12, 60.0))
		"beep":
			s = _wav(_tone(0.14, 880.0, 880.0, 0.35, 12.0))
		"tick":
			s = _wav(_tone(0.09, 660.0, 660.0, 0.4, 18.0))
		"go":
			s = _wav(_tone(0.45, 990.0, 1320.0, 0.4, 5.0))
		"success":
			s = _wav(_arp([523.25, 659.25, 783.99, 1046.5], 0.17, 0.35))
		"fail":
			s = _wav(_arp([392.0, 329.63, 261.63, 196.0], 0.22, 0.4))
		"repair":
			s = _wav(_arp([660.0, 990.0], 0.1, 0.35))
		"hit":
			s = _wav(_noise_burst(0.25, 0.7, 9.0))
		"whoosh":
			s = _wav(_sweep_noise(1.1))
		"clang":
			s = _wav(_clang(0.9))
		"ignite":
			s = _wav(_swell_noise(2.2))
		"rumble":
			s = _wav(_rumble(3.0), true)
		"hiss":
			s = _wav(_hiss(1.0), true)
		"alarm":
			s = _wav(_alarm(0.8), true)
		"ambient":
			s = _wav(_ambient(8.0), true)
		_:
			s = _wav(_tone(0.05, 800.0, 800.0, 0.2, 20.0))
	_cache[sound] = s
	return s


func _wav(samples: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


func _buf(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	return a


func _tone(sec: float, f0: float, f1: float, amp: float, decay: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / sec)
		ph += TAU * f / RATE
		a[i] = sin(ph) * amp * exp(-decay * t) * minf(1.0, t * 400.0)
	return a


func _arp(freqs: Array, step: float, amp: float) -> PackedFloat32Array:
	var a := _buf(step * freqs.size() + 0.5)
	for k in freqs.size():
		var start := int(k * step * RATE)
		var ph := 0.0
		for i in range(start, a.size()):
			var t := float(i - start) / RATE
			ph += TAU * float(freqs[k]) / RATE
			a[i] += (sin(ph) + 0.3 * sin(ph * 2.0)) * amp * 0.6 * exp(-5.0 * t) * minf(1.0, t * 300.0)
	return a


func _noise_burst(sec: float, amp: float, decay: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var lp := 0.0
	for i in a.size():
		var t := float(i) / RATE
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.35)
		a[i] = lp * amp * exp(-decay * t)
	return a


func _sweep_noise(sec: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var lp := 0.0
	for i in a.size():
		var t := float(i) / sec / RATE
		var k := lerpf(0.05, 0.6, sin(t * PI))
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), k)
		a[i] = lp * 0.5 * sin(t * PI)
	return a


func _clang(sec: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var freqs := [310.0, 487.0, 733.0, 1190.0, 1721.0]
	for i in a.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * float(freqs[k]) * t) * exp(-(4.0 + k * 2.5) * t) / (1.0 + k * 0.5)
		a[i] = v * 0.3 * minf(1.0, t * 500.0)
	return a


func _swell_noise(sec: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var lp := 0.0
	var low := 0.0
	for i in a.size():
		var t := float(i) / sec / RATE
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.18)
		low += (lp - low) * 0.04
		a[i] = (low * 1.6 + lp * 0.3) * pow(t, 1.5) * (1.0 - 0.3 * t) * 0.9
	return a


func _rumble(sec: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var lp := 0.0
	var low := 0.0
	var n := a.size()
	for i in n:
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.22)
		low += (lp - low) * 0.05
		var t := float(i) / RATE
		a[i] = low * 1.7 + lp * 0.18 + sin(TAU * 41.0 * t) * 0.12 + sin(TAU * 83.0 * t) * 0.05
	# cross-fade the tail into the head so the loop has no click
	var fade := 1500
	for i in fade:
		var k := float(i) / fade
		a[i] = lerpf(a[n - fade + i], a[i], k)
	return a


func _hiss(sec: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var prev := 0.0
	var n := a.size()
	for i in n:
		var w := _rng.randf_range(-1.0, 1.0)
		a[i] = (w - prev * 0.6) * 0.14
		prev = w
	for i in 600:
		var k := float(i) / 600.0
		a[i] = lerpf(a[n - 600 + i], a[i], k)
	return a


func _alarm(sec: float) -> PackedFloat32Array:
	var a := _buf(sec)
	for i in a.size():
		var t := float(i) / RATE
		var f := 620.0 if fmod(t, 0.4) < 0.2 else 820.0
		a[i] = signf(sin(TAU * f * t)) * 0.12 * minf(1.0, fmod(t, 0.2) * 200.0)
	return a


func _ambient(sec: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var freqs := [55.0, 82.5, 110.0, 165.0, 220.0, 329.625]
	for i in a.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			var trem := 0.6 + 0.4 * sin(TAU * (k + 1) / sec * t + k)
			v += sin(TAU * float(freqs[k]) * t) * trem / (1.0 + k * 0.6)
		a[i] = v * 0.16
	return a
