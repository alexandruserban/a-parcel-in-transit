extends Node
## Procedural sound, like the Web Audio engine in audio.js: every effect is synthesised into a small
## AudioStreamWAV at start-up (no sound files), plus the looping soundtrack, a wind bed, and birdsong by day /
## crickets at night.

const RATE := 22050
const MUSIC_PATH := "res://assets/music/Beneath_the_Ancient_Canopy.mp3"
const SETTINGS := "user://settings.cfg"

var enabled := true
var music_volume := 0.4
var night := false
var streams := {}
var music: AudioStreamPlayer
var ambient: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _nature_t := 3.0
var rng := RandomNumberGenerator.new()
var engine: AudioStreamPlayer
var _engine_vol := 0.0
var _engine_target := 0.0
var _engine_pitch := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		music_volume = clampf(cfg.get_value("audio", "music_volume", 0.4), 0.0, 1.0)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_build()
	music = AudioStreamPlayer.new()
	if ResourceLoader.exists(MUSIC_PATH):
		var s: AudioStream = load(MUSIC_PATH)
		if s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = true
		music.stream = s
	add_child(music)
	ambient = AudioStreamPlayer.new()
	ambient.stream = streams.wind
	ambient.volume_db = -20.0
	add_child(ambient)
	engine = AudioStreamPlayer.new()
	engine.stream = streams.engine
	add_child(engine)
	_apply_music()


func start() -> void:
	if enabled and not ambient.playing:
		ambient.play()
	_apply_music()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.save(SETTINGS)
	_apply_music()


func _apply_music() -> void:
	if music.stream == null:
		return
	var v := music_volume if enabled else 0.0
	if v <= 0.0:
		music.stop()
		return
	music.volume_db = linear_to_db(v * v)
	if not music.playing:
		music.play()


func toggle() -> bool:
	enabled = not enabled
	_apply_music()
	if enabled:
		ambient.play()
	else:
		ambient.stop()
	return enabled


func play(name: String, db := 0.0, pitch := 1.0) -> void:
	if not enabled or not streams.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = streams[name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func footstep(surface: String, sprint := false) -> void:
	if surface == "grass":
		play("step_grass", -8.0 if sprint else -11.0, rng.randf_range(0.88, 1.12))
	else:   # pavement, cobbles, floors: a soft tap
		play("step_hard", -13.0 if sprint else -16.0, rng.randf_range(0.9, 1.1))


## Rushing wind gust (playWindGust): the wind loop through its own player, swelling and fading over `duration`
var gust_player: AudioStreamPlayer
var _gust_t := -1.0
var _gust_len := 10.0
func wind_gust(duration: float) -> void:
	if not enabled:
		return
	if gust_player == null:
		gust_player = AudioStreamPlayer.new()
		gust_player.stream = streams.wind
		add_child(gust_player)
	_gust_t = 0.0
	_gust_len = duration
	gust_player.volume_db = -60.0
	gust_player.play()


func _update_gust(delta: float) -> void:
	if _gust_t < 0.0 or gust_player == null:
		return
	_gust_t += delta
	var t := _gust_t / _gust_len
	if t >= 1.0:
		gust_player.stop()
		_gust_t = -1.0
		return
	var env := t / 0.2 if t < 0.2 else (1.0 if t < 0.55 else 1.0 - (t - 0.55) / 0.45)
	gust_player.volume_db = linear_to_db(maxf(env * 1.3, 0.001))
	gust_player.pitch_scale = 1.0 + 1.4 * (t / 0.3 if t < 0.3 else maxf(0.0, 1.0 - (t - 0.3) / 0.7) * 0.8 + 0.2)


## Mallard quack, louder the nearer the pond (volume 0..1, like playQuack)
func quack(volume: float) -> void:
	if volume > 0.01:
		play("quack_%d" % rng.randi_range(0, 2), linear_to_db(volume) - 3.0, rng.randf_range(0.95, 1.08))


## Diesel engine loop for the truck: pitch and loudness follow speed / throttle (startEngine / setEngine)
func start_engine() -> void:
	_engine_target = 0.004
	_engine_pitch = 0.75
	if enabled and not engine.playing:
		engine.play()


func set_engine(speed01: float, throttle: bool) -> void:
	# an electric motor is nearly silent at a standstill and its whine climbs steeply with speed
	_engine_pitch = 0.75 + speed01 * 0.9
	_engine_target = 0.004 + speed01 * 0.035 + (0.006 if throttle else 0.0)


func stop_engine() -> void:
	_engine_target = 0.0


func _process(delta: float) -> void:
	_update_gust(delta)
	_engine_vol = move_toward(_engine_vol, _engine_target if enabled else 0.0, delta * 0.4)
	if engine.playing:
		engine.pitch_scale = lerpf(engine.pitch_scale, _engine_pitch, minf(1.0, delta * 6.0))
		engine.volume_db = linear_to_db(maxf(_engine_vol * 7.0, 0.0001))
		if _engine_vol <= 0.0 and _engine_target <= 0.0:
			engine.stop()
	if not enabled or get_tree().paused:
		return
	_nature_t -= delta
	if _nature_t <= 0.0:
		if night:
			play("cricket", -22.0, rng.randf_range(0.95, 1.05))
			_nature_t = rng.randf_range(0.6, 2.0)
		else:
			play("chirp", -20.0, rng.randf_range(0.85, 1.25))
			_nature_t = rng.randf_range(1.5, 5.0)


# ------------------------------------------------------------------------------------------------
# Synthesis
# ------------------------------------------------------------------------------------------------
func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _amp(s: PackedFloat32Array, k: float) -> PackedFloat32Array:
	for i in s.size():
		s[i] *= k
	return s


func _buf(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(seconds * RATE))
	return a


func _noise_burst(seconds: float, decay: float, lp: float, gain: float, thud := 0.0, thud_hz := 90.0) -> PackedFloat32Array:
	var s := _buf(seconds)
	var y := 0.0
	for i in s.size():
		var t := float(i) / RATE
		y += lp * ((rng.randf() * 2.0 - 1.0) - y)
		s[i] = (y * gain + thud * sin(TAU * thud_hz * t)) * exp(-t * decay)
	return s


func _tone(s: PackedFloat32Array, start: float, hz: float, dur: float, decay: float, gain: float, harmonics := 0.0) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), s.size() - i0)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(1.0, t * 400.0)
		s[i0 + i] += gain * env * (sin(TAU * hz * t) + harmonics * sin(TAU * hz * 2.0 * t) + harmonics * 0.4 * sin(TAU * hz * 3.0 * t))


## RBJ biquad filters over a whole buffer (Web Audio's BiquadFilterNode)
func _biquad(s: PackedFloat32Array, kind: String, hz: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * hz / RATE
	var alpha := sin(w0) / (2.0 * q)
	var c := cos(w0)
	var b0: float; var b1: float; var b2: float
	if kind == "band":
		b0 = alpha; b1 = 0.0; b2 = -alpha
	else:
		b0 = (1.0 - c) / 2.0; b1 = 1.0 - c; b2 = (1.0 - c) / 2.0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * c
	var a2 := 1.0 - alpha
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	var out := PackedFloat32Array()
	out.resize(s.size())
	for i in s.size():
		var x := s[i]
		var y := (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1; x1 = x; y2 = y1; y1 = y
		out[i] = y
	return out


static func _saw(ph: float) -> float:
	return 2.0 * (ph - floorf(ph + 0.5))


func _build() -> void:
	rng.seed = 99
	var tap := _buf(0.09)
	var tph := 0.0
	for i in tap.size():
		var t := float(i) / RATE
		tph += (260.0 * pow(80.0 / 260.0, minf(t / 0.07, 1.0))) / RATE
		var tri_w := 4.0 * absf(tph - floorf(tph + 0.5)) - 1.0
		tap[i] = (tri_w * 0.55 + (rng.randf() * 2.0 - 1.0) * 0.06) * exp(-t * 55.0) * minf(1.0, t * 800.0)
	streams.step_hard = _wav(_biquad(tap, "low", 1400.0, 0.707))
	streams.step_grass = _wav(_noise_burst(0.14, 26.0, 0.12, 1.6, 0.15, 70.0))
	streams.jump = _wav(_noise_burst(0.16, 18.0, 0.08, 1.2))
	streams.land = _wav(_noise_burst(0.2, 22.0, 0.1, 1.2, 0.6, 65.0))
	streams.click = _wav(_noise_burst(0.02, 300.0, 0.6, 0.9))
	var pick := _buf(0.3)
	_tone(pick, 0.0, 660.0, 0.12, 25.0, 0.35)
	_tone(pick, 0.07, 990.0, 0.22, 16.0, 0.35)
	streams.pickup = _wav(pick)
	var store := _buf(0.6)
	_tone(store, 0.0, 523.25, 0.3, 9.0, 0.25, 0.2)
	_tone(store, 0.08, 659.25, 0.3, 9.0, 0.25, 0.2)
	_tone(store, 0.16, 783.99, 0.4, 7.0, 0.25, 0.2)
	streams.store = _wav(store)
	var bell := _buf(2.4)
	_tone(bell, 0.0, 659.25, 1.4, 3.0, 0.32, 0.35)
	_tone(bell, 0.55, 523.25, 1.8, 2.4, 0.32, 0.35)
	streams.doorbell = _wav(bell)
	var warn := _buf(0.25)
	_tone(warn, 0.0, 220.0, 0.25, 12.0, 0.3, 0.5)
	streams.warn = _wav(warn)
	var chirp := _buf(0.5)
	for k in 3:
		var t0 := k * 0.12
		var i0 := int(t0 * RATE)
		var n := int(0.07 * RATE)
		var ph := 0.0
		for i in n:
			var t := float(i) / RATE
			var f := 2800.0 + 1600.0 * (t / 0.07)
			ph += TAU * f / RATE
			chirp[i0 + i] += 0.25 * sin(ph) * sin(PI * t / 0.07)
	streams.chirp = _wav(chirp)
	var cricket := _buf(0.3)
	for k in 4:
		_tone(cricket, k * 0.05, 4500.0, 0.03, 60.0, 0.2)
	streams.cricket = _wav(cricket)
	# Wind bed: 4 s of low-passed noise with slow swells, cross-faded so the loop has no seam
	var wind := _buf(4.0)
	var y := 0.0
	for i in wind.size():
		var t := float(i) / RATE
		y += 0.025 * ((rng.randf() * 2.0 - 1.0) - y)
		wind[i] = y * 3.0 * (0.75 + 0.25 * sin(TAU * t / 4.0))
	var fade := int(0.4 * RATE)
	for i in fade:
		var k := float(i) / fade
		var j := wind.size() - fade + i
		wind[i] = wind[i] * k + wind[j] * (1.0 - k)
	wind.resize(wind.size() - fade)
	streams.wind = _wav(wind, true)
	# Quacks: 1-3 nasal "waak" bursts, a sawtooth falling in pitch through a narrow band-pass
	for v in 3:
		var q := _buf(0.6)
		var bursts := 1 + v
		for k in bursts:
			var t0 := k * (0.16 + rng.randf() * 0.05)
			var f := 360.0 + rng.randf() * 60.0
			var ph := 0.0
			var i0 := int(t0 * RATE)
			for i in int(0.14 * RATE):
				var t := float(i) / RATE
				ph += f * 1.15 * pow(0.8 / 1.15, minf(t / 0.13, 1.0)) / RATE
				var env := minf(t / 0.015, 1.0) * exp(-maxf(t - 0.015, 0.0) * 50.0)
				q[i0 + i] += _saw(ph) * env
		streams["quack_%d" % v] = _wav(_amp(_biquad(q, "band", 1150.0, 4.0), 1.6))
	# Door: a latch click, then a low-passed creak rising (opening) or falling (closing)
	for opening in [true, false]:
		var d := _buf(0.62)
		var cf := 1800.0 if opening else 1200.0
		for i in int(0.05 * RATE):
			var t := float(i) / RATE
			d[i] += (1.0 if fmod(t * cf, 1.0) < 0.5 else -1.0) * 0.25 * exp(-t * 90.0)
		var creak := _buf(0.62)
		var ph := 0.0
		for i in int(0.55 * RATE):
			var t := float(i) / RATE
			var f: float = lerpf(180.0 if opening else 240.0, 260.0 if opening else 150.0, minf(t / 0.45, 1.0))
			ph += f / RATE
			var env := minf(t / 0.1, 1.0) * exp(-maxf(t - 0.1, 0.0) * 12.0)
			creak[int(0.05 * RATE) + i] = _saw(ph) * env * 0.35
		creak = _biquad(creak, "low", 900.0, 0.707)
		for i in d.size():
			d[i] += creak[i]
		streams["door_open" if opening else "door_close"] = _wav(d)
	# Horn: two square waves, a major third apart
	var horn := _buf(0.6)
	for f in [349.0, 440.0]:
		for i in horn.size():
			var t := float(i) / RATE
			var env := minf(t / 0.03, 1.0) * (1.0 if t < 0.45 else exp(-(t - 0.45) * 40.0))
			horn[i] += (0.16 if fmod(t * f, 1.0) < 0.5 else -0.16) * env
	streams.horn = _wav(horn)
	# Electric drive, kept subtle: a soft low hum (a sine and a quiet octave) under a gentle low-passed rush of
	# tyres and air. 2 s of whole-hertz tones, so the loop is seamless.
	var eng := _buf(2.0)
	var rush := 0.0
	for i in eng.size():
		var t := float(i) / RATE
		rush += 0.015 * ((rng.randf() * 2.0 - 1.0) - rush)
		eng[i] = 0.3 * sin(TAU * 110.0 * t) + 0.06 * sin(TAU * 220.0 * t) + rush * 2.2
	var efade := int(0.2 * RATE)
	for i in efade:   # cross-fade the noise seam
		var k := float(i) / efade
		eng[i] = eng[i] * k + eng[eng.size() - efade + i] * (1.0 - k)
	eng.resize(eng.size() - efade)
	streams.engine = _wav(_amp(_biquad(eng, "low", 600.0, 0.707), 0.6), true)
