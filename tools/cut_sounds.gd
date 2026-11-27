extends SceneTree
## Cuts the recorded footsteps and parcel knocks (assets/music/sounds/*.mp3) into short WAV files in
## assets/music/sounds/cuts/, one per step or knock, at the start times and lengths listed in sfx.gd.
## Playing a short WAV from its start costs nothing, while starting an MP3 in the middle makes Godot decode up
## to that point first (up to ~45 ms for a step in the 60 s stone recording: a stutter on every step).
## Plays each recording once into an AudioEffectCapture (real time, about a minute). Run it again whenever the
## recordings or the cut lists change:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tools/cut_sounds.gd

const OUT := "res://assets/music/sounds/cuts/"
var Sfx = preload("res://scripts/sfx.gd")
var jobs: Array = []
var frames := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sources := [
		["grass", Sfx.STEP_FILES.grass, _cuts(Sfx.STEP_CUTS.grass, Sfx.STEP_LEN.grass)],
		["stone", Sfx.STEP_FILES.stone, _cuts(Sfx.STEP_CUTS.stone, Sfx.STEP_LEN.stone)],
		["roll", Sfx.ROLL_FILE, _roll_cuts()],
	]
	for k in sources.size():
		var src: Array = sources[k]
		var bus := AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, "cut%d" % k)
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 2.0
		AudioServer.add_bus_effect(bus, cap)
		AudioServer.set_bus_volume_db(bus, -80.0)   # silent: the capture sits before the fader
		var s := AudioStreamMP3.new()
		s.data = FileAccess.get_file_as_bytes(src[1])
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = "cut%d" % k
		root.add_child(p)
		jobs.append({"name": src[0], "p": p, "cap": cap, "data": PackedVector2Array(), "cuts": src[2]})
	process_frame.connect(_tick)


## [[start, length], ...] for the footsteps (the length is the same for every step on a surface)
func _cuts(list: Array, len: float) -> Array:
	var out: Array = []
	for c in list:
		out.append([float(c[0]), len + 0.06])
	return out


func _roll_cuts() -> Array:
	var out: Array = []
	for c in Sfx.ROLL_CUTS:
		out.append([float(c[0]), float(c[2]) + 0.1])
	return out


func _tick() -> void:
	frames += 1
	if frames == 3:
		for j in jobs:
			j.p.play()
	if frames < 4:
		return
	var playing := false
	for j in jobs:
		j.data.append_array(j.cap.get_buffer(j.cap.get_frames_available()))
		if j.p.playing:
			playing = true
	if playing:
		return
	var rate := int(AudioServer.get_mix_rate())
	for j in jobs:
		var data: PackedVector2Array = j.data
		var n := 0
		for c in j.cuts:
			var i0 := int(float(c[0]) * rate)
			var cnt := mini(int(float(c[1]) * rate), data.size() - i0)
			if cnt <= 0:
				continue
			var fade := int(0.06 * rate)
			var bytes := PackedByteArray()
			bytes.resize(cnt * 2)
			for i in cnt:
				var v: Vector2 = data[i0 + i]
				var g := 1.0 if i < cnt - fade else float(cnt - i) / fade   # fade out over the last 60 ms
				bytes.encode_s16(i * 2, int(clampf((v.x + v.y) * 0.5 * g, -1.0, 1.0) * 32767.0))
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = rate
			w.stereo = false
			w.data = bytes
			w.save_to_wav(ProjectSettings.globalize_path(OUT + "%s_%02d.wav" % [j.name, n]))
			n += 1
		print("%s: %d cuts" % [j.name, n])
	quit()
