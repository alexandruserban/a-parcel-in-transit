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
	var name := "step_grass" if surface == "grass" else "step_hard"
	play(name, -8.0 if sprint else -11.0, rng.randf_range(0.88, 1.12))


func _process(delta: float) -> void:
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


func _build() -> void:
	rng.seed = 99
	streams.step_hard = _wav(_noise_burst(0.09, 45.0, 0.35, 1.4, 0.35, 95.0))
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
