extends Node3D
## Game manager: builds the town, player, sky and HUD, and runs the tidy-up loop (backpack of 10 parcels,
## the depot that files them away, score, day/night, street-lamp light pool). Port of js/game.js.

const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const SkyCycle := preload("res://scripts/sky_cycle.gd")
const Hud := preload("res://scripts/hud.gd")
const Parcels := preload("res://scripts/parcels.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Touch := preload("res://scripts/touch.gd")
const Birds := preload("res://scripts/birds.gd")
const Ducks := preload("res://scripts/ducks.gd")
const Truck := preload("res://scripts/truck.gd")

const BACKPACK_CAP := 10
const LAMP_POOL := 14

var world
var player
var sky
var hud
var parcels
var sfx
var sun: DirectionalLight3D
var score := 0
var backpack: Array[String] = []
var is_night := false
var victory := false
var started := false
var lamp_pool: Array[OmniLight3D] = []
var _pool_t := 0.0
var mobile := false
var touch
var birds
var ducks
var truck
var room_lights: Array[OmniLight3D] = []
# Wind: a steady breeze plus a gust every couple of minutes that scatters the loose parcels (world.js initWind)
var wind := {"dir": Vector2(1, 0.3).normalized(), "strength": 0.25, "gust": 0.0, "active": false, "t": 0.0, "dur": 10.0, "next": 50.0, "time": 0.0}
var leaves: CPUParticles3D
# Saving: where you left off is written to user://save.json every 30 s, when you pause and when you leave
var SAVE_PATH := "user://save.json"
var stats := {"time": 0.0, "picked": 0, "walked": 0.0, "driven": 0.0, "gusts": 0, "doorbells": 0, "dropped": 0, "sessions": 0, "first": "", "last": "", "bells": []}
const INT_STATS := ["picked", "gusts", "doorbells", "dropped", "sessions"]
var _save_t := 30.0
var _bell_hour := -1
var _last_walk_pos := Vector3.INF
var test_mode := false
var loaded := false


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	mobile = OS.has_feature("mobile") or "--mobile" in OS.get_cmdline_user_args()
	if mobile:
		_mobile_graphics()
	sfx = Sfx.new()
	add_child(sfx)
	sfx.hang_bells(self, Vector3(-45, 29, 30.5))   # in St. Marien's belfry

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0 if mobile else 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if mobile else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)
	var env_node := WorldEnvironment.new()
	add_child(env_node)
	sky = SkyCycle.new()
	add_child(sky)
	sky.setup(env_node, sun)

	world = World.new()
	world.tree_detail = 0.5 if mobile else 1.0
	add_child(world)
	world.build()
	parcels = Parcels.new()
	parcels.world = world
	add_child(parcels)
	parcels.build()
	birds = Birds.new()
	add_child(birds)
	ducks = Ducks.new()
	ducks.world = world
	ducks.sfx = sfx
	add_child(ducks)
	ducks.build()

	player = Player.new()
	player.world = world
	player.game = self
	player.mobile = mobile
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	truck = Truck.new()
	truck.game = self
	truck.world = world
	add_child(truck)

	for i in LAMP_POOL:
		var l := OmniLight3D.new()
		l.light_color = Color("#ffc98a")
		l.light_energy = 2.0
		l.omni_range = 13.0
		l.omni_attenuation = 1.4
		l.visible = false
		add_child(l)
		lamp_pool.append(l)

	# Room lights: one in each room of the floor you're on, in whichever house you're in (game.js)
	for i in 5:
		var rl := OmniLight3D.new()
		rl.light_color = Color("#ffe2b8")
		rl.light_energy = 0.0
		rl.omni_range = 6.5
		rl.omni_attenuation = 1.2
		rl.visible = false
		add_child(rl)
		room_lights.append(rl)

	wind.next = 50.0 + randf() * 40.0
	_make_leaves()

	hud = Hud.new()
	hud.game = self
	hud.mobile = mobile
	add_child(hud)
	if mobile:
		touch = Touch.new()
		touch.game = self
		add_child(touch)
	if "--savetest" in OS.get_cmdline_user_args():
		SAVE_PATH = "user://save_test.json"   # never touch the real save
	test_mode = false
	for a in ["--smoke", "--shot", "--drive", "--stairs", "--gust", "--moat", "--kerb"]:
		if a in OS.get_cmdline_user_args():
			test_mode = true
	if not test_mode:
		loaded = load_game()
		stats.sessions += 1
		if stats.first == "":
			stats.first = Time.get_date_string_from_system()
	hud.set_quest(parcels.stored_total(), parcels.total)
	hud.set_backpack(backpack, BACKPACK_CAP)
	hud.set_score(score)
	print("Parcels in Transit ready in %d ms: %d parcels in the town" % [Time.get_ticks_msec() - t0, parcels.total])

	# Headless / CI smoke run and screenshot mode
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke_test()
		return
	if "--savetest" in OS.get_cmdline_user_args():
		_save_test()
		return
	if "--moat" in OS.get_cmdline_user_args():
		_moat_test()
		return
	if "--gust" in OS.get_cmdline_user_args():
		_gust_test()
		return
	if "--stairs" in OS.get_cmdline_user_args():
		_stairs_test()
		return
	if "--kerb" in OS.get_cmdline_user_args():
		_kerb_test()
		return
	if "--drive" in OS.get_cmdline_user_args():
		_drive_test()
		return
	if "--shot" in OS.get_cmdline_user_args():
		_screenshot_mode()
		return
	pause()


func pause() -> void:
	save_game()
	hud.set_stats(stats_rows(), loaded or stats.time > 0.0)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu(true)
	if touch:
		touch.visible = false


func resume() -> void:
	started = true
	hud.show_menu(false)
	get_tree().paused = false
	if touch:
		touch.visible = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sfx.start()


## Phones: the Android back button and leaving the app open the pause menu
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if hud and not get_tree().paused:
			pause()
		else:
			save_game()
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()


## Lighter settings for phones, like the web version's Low preset: lower 3D resolution, smaller and nearer
## shadows, half the leaf clusters in the big trees
func _mobile_graphics() -> void:
	get_viewport().scaling_3d_scale = 0.75
	RenderingServer.directional_shadow_atlas_set_size(2048, true)


func _process(delta: float) -> void:
	sky.update(delta, player.global_position)
	world.set_water_sky(sky.params, sky.sun_dir, sky.moon_dir, sky.moon_amt, sky.daylight(), sky.sun_visibility())
	birds.update(delta, sky.daylight())
	_update_stats(delta)
	# St. Marien strikes the hour
	var whole := int(sky.hour) % 24
	if started and whole != _bell_hour:
		if _bell_hour != -1:
			sfx.strike_hour(whole)
		_bell_hour = whole
	_update_wind(delta)
	ducks.update(delta, player.global_position)
	var night: bool = sky.is_night()
	if night != is_night:
		is_night = night
		world.set_night(night)
		sfx.night = night
	hud.set_clock(("%s %s" if mobile else "[N] %s %s") % [sky.clock_text(), sky.phase_name()])
	_update_lamp_pool(delta)
	_update_room_lights()
	world.house_parts.update(delta)
	world.moat.update(delta)
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_E, KEY_ENTER:
			interact()
		KEY_SPACE:
			if not truck.driving:
				player.jump()
		KEY_C, KEY_CTRL:
			if not truck.driving:
				player.toggle_crouch()
		KEY_Q:
			if truck.driving:
				truck.horn()
		KEY_V:
			truck.toggle_view()
		KEY_R:
			if truck.driving:
				truck.toggle_wipers()
		KEY_F:
			player.toggle_flashlight()
		KEY_G:
			drop_one()
		KEY_N:
			skip_time()
		KEY_B:
			toggle_weather()
		KEY_M:
			hud.minimap.visible = not hud.minimap.visible
		KEY_K:
			var on: bool = sfx.toggle()
			hud.sound_label.text = "[K] Sound: %s" % ("on" if on else "off")


# ------------------------------------------------------------------------------------------------
# Interaction
# ------------------------------------------------------------------------------------------------
func player_in_depot() -> bool:
	var p: Vector3 = player.global_position
	return world.in_warehouse(p.x, p.z)


func deposit_prompt() -> String:
	if backpack.size() > 0 and player_in_depot():
		return "[E] Store %d parcel%s in the depot" % [backpack.size(), "s" if backpack.size() > 1 else ""]
	return ""


func _update_prompt() -> void:
	if truck.driving:
		hud.set_prompt(truck.drive_text())
		return
	var cur = player.current
	var dep := deposit_prompt()
	if dep != "" and (cur == null or cur.has("slot")):
		hud.set_prompt(dep)
	elif cur == null:
		hud.set_prompt("")
	elif cur.has("slot"):
		hud.set_prompt(parcels.prompt_for(cur))
	else:
		hud.set_prompt(cur.prompt)


func interact() -> void:
	if truck.driving:
		truck.press_e()
		return
	var cur = player.current
	if (cur == null or cur.has("slot")) and deposit_prompt() != "":
		deposit_all()
		return
	if cur == null:
		return
	if cur.has("slot"):
		collect(cur)
		return
	if cur.type == "ledger":
		var c: Dictionary = parcels.counts
		hud.show_dialogue("Parcel Depot ledger", "In storage: %d parcels (%d small, %d medium, %d large). Walk in with parcels and press E: every parcel is filed into its place automatically." % [parcels.stored_total(), c.S, c.M, c.L])
		sfx.play("click")
		return
	var res: Dictionary = cur.call.call()
	if res.has("peal"):
		sfx.peal(int(res.peal))
	if res.get("sound", "") == "doorbell":
		stats.doorbells += 1
		# each household's greeting scores once; ringing the same bell again doesn't
		var house: int = int(res.get("house", -1))
		if house in stats.bells:
			res.erase("score")
		else:
			stats.bells.append(house)
	if res.has("sound"):
		sfx.play(res.sound, -4.0)
	if res.has("score"):
		add_score(res.score)
	if res.has("title"):
		hud.show_dialogue(res.title, res.message)


func collect(rec: Dictionary) -> void:
	if backpack.size() >= BACKPACK_CAP:
		sfx.play("warn", -8.0)
		hud.toast("Backpack full (%d parcels). Take them to the Parcel Depot." % BACKPACK_CAP, true)
		return
	sfx.play("pickup", -6.0)
	parcels.take(rec)
	backpack.append(rec.size)
	stats.picked += 1   # (no points here: you score when a parcel is filed in the depot)
	hud.set_backpack(backpack, BACKPACK_CAP)
	hud.toast("Parcel into the backpack (%d/%d)" % [backpack.size(), BACKPACK_CAP])


func deposit_all() -> void:
	var n := 0
	while not backpack.is_empty():
		if not parcels.store(backpack[0]):
			break
		backpack.remove_at(0)
		n += 1
	hud.set_backpack(backpack, BACKPACK_CAP)
	if n > 0:
		sfx.play("store", -4.0)
		add_score(n * 50)
		hud.toast("%d parcel%s filed away in the depot (%d stored)" % [n, "s" if n > 1 else "", parcels.stored_total()])
	else:
		hud.toast("The depot is completely full!", true)
	_update_quest()


func drop_one() -> void:
	if backpack.is_empty():
		hud.toast("The backpack is empty.", true)
		return
	if player_in_depot():
		deposit_all()
		return
	var size: String = backpack[backpack.size() - 1]
	var pl: Dictionary = parcels.placement_for(size, player.eye_position(), player.yaw)
	if not pl.ok or not parcels.drop(size, pl):
		sfx.play("warn", -8.0)
		hud.toast("Can't put it there.", true)
		return
	backpack.pop_back()
	stats.dropped += 1
	sfx.play("land", -6.0)
	hud.set_backpack(backpack, BACKPACK_CAP)


func add_score(n: int) -> void:
	score += n
	hud.set_score(score)


func _update_quest() -> void:
	var done: int = parcels.stored_total()
	hud.set_quest(done, parcels.total)
	if not victory and parcels.total > 0 and done >= parcels.total:
		victory = true
		hud.show_dialogue("MASTER OF THE DEPOT!", "Every last parcel in the town is stacked in the depot. The hoarders are speechless!")


# ------------------------------------------------------------------------------------------------
# Time & weather
# ------------------------------------------------------------------------------------------------
func skip_time() -> void:
	var stops := [[5.8, "Sunrise"], [12.5, "Midday"], [17.6, "Sunset"], [22.5, "Night"]]
	var now: float = sky.hour
	var next: Array = stops[0]
	for s in stops:
		if s[0] > now + 0.05:
			next = s
			break
	sky.hour = next[0]
	hud.show_dialogue(next[1], "Time skipped to %s. The day keeps moving on its own (a full day takes 20 minutes)." % sky.clock_text())


func toggle_weather() -> void:
	var overcast: bool = sky.weather_target < 0.5
	sky.weather_target = 1.0 if overcast else 0.0
	hud.weather_label.text = "[B] Weather: %s" % ("overcast" if overcast else "clear")
	hud.show_dialogue("Clouding over" if overcast else "Clearing up", "Grey skies rolling in: soft, shadowless light." if overcast else "The clouds are breaking up.")


# ------------------------------------------------------------------------------------------------
# Save game and stats
# ------------------------------------------------------------------------------------------------
func _update_stats(delta: float) -> void:
	if not started or get_tree().paused:
		return
	stats.time += delta
	var p: Vector3 = player.global_position
	if truck.driving:
		stats.driven += absf(truck.speed) * delta
		_last_walk_pos = Vector3.INF
	else:
		if _last_walk_pos != Vector3.INF:
			var step := Vector2(p.x - _last_walk_pos.x, p.z - _last_walk_pos.z).length()
			if step < 3.0:   # ignore teleports (getting out of the truck, loading a save)
				stats.walked += step
		_last_walk_pos = p
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 30.0
		save_game()


func save_game() -> void:
	if test_mode or not started:
		return
	var p: Vector3 = player.global_position
	if truck.driving:   # you'll be standing beside the cab when you come back
		var f: Vector2 = truck.fwd()
		var left := Vector2(f.y, -f.x)
		var spot: Vector2 = truck.pos + f * 1.8 + left * 2.3
		p = Vector3(spot.x, 0.1, spot.y)
	stats.last = Time.get_datetime_string_from_system(false, true)
	var d := {
		"version": 1,
		"player": [snappedf(p.x, 0.01), snappedf(p.y + 0.05, 0.01), snappedf(p.z, 0.01), snappedf(player.yaw, 0.001), snappedf(player.pitch, 0.001)],
		"hour": sky.hour, "weather": sky.weather_target, "score": score, "backpack": Array(backpack), "victory": victory,
		"truck": [truck.pos.x, truck.pos.y, truck.heading, Array(truck.cargo)],
		"parcels": parcels.save_state(),
		"stats": stats,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (d is Dictionary) or int(d.get("version", 0)) != 1:
		return false
	var pl: Array = d.player
	player.global_position = Vector3(pl[0], pl[1], pl[2])
	player.yaw = pl[3]
	player.pitch = pl[4]
	sky.hour = float(d.hour)
	sky.weather_target = float(d.weather)
	sky.weather = sky.weather_target
	hud.weather_label.text = "[B] Weather: %s" % ("overcast" if sky.weather_target > 0.5 else "clear")
	score = int(d.score)
	victory = bool(d.get("victory", false))
	backpack.clear()
	for s in d.backpack:
		backpack.append(String(s))
	var tr: Array = d.truck
	truck.pos = Vector2(tr[0], tr[1])
	truck.heading = tr[2]
	truck.cargo.clear()
	for s in tr[3]:
		truck.cargo.append(String(s))
	truck._sync()
	parcels.load_state(d.parcels)
	for k in d.stats:
		if stats.has(k):
			stats[k] = int(d.stats[k]) if k in INT_STATS else d.stats[k]   # JSON numbers come back as floats
	var bells: Array = []
	for h in stats.bells:
		bells.append(int(h))
	stats.bells = bells
	return true


## Start again: forget the save and rebuild the town
func new_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	test_mode = true   # nothing more gets saved from this session
	get_tree().paused = false
	get_tree().reload_current_scene()


static func _hms(t: float) -> String:
	var m := int(t / 60.0)
	return "%dh %02dm" % [m / 60, m % 60] if m >= 60 else "%d min" % m


func stats_rows() -> Array:
	var depot: int = parcels.stored_total()
	return [
		["Time played", _hms(stats.time)], ["Parcels in the depot", "%d / %d" % [depot, parcels.total]],
		["Parcels picked up", str(stats.picked)], ["Score", str(score)],
		["Distance walked", "%.1f km" % (stats.walked / 1000.0)], ["Distance driven", "%.1f km" % (stats.driven / 1000.0)],
		["Gusts weathered", str(stats.gusts)], ["Doorbells rung", str(stats.doorbells)],
		["Playing since", str(stats.first)], ["Sessions", str(stats.sessions)],
	]


## Leaves and dust that blow past only during a gust
func _make_leaves() -> void:
	leaves = CPUParticles3D.new()
	leaves.amount = 160 if mobile else 260
	leaves.lifetime = 4.5
	leaves.local_coords = false
	leaves.emitting = false
	leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	leaves.emission_box_extents = Vector3(22, 2, 22)
	leaves.gravity = Vector3(0, -0.4, 0)
	leaves.angular_velocity_min = -360.0
	leaves.angular_velocity_max = 360.0
	leaves.spread = 25.0
	leaves.scale_amount_min = 0.6
	leaves.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#8a7440")
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	q.material = m
	leaves.mesh = q
	add_child(leaves)


func start_gust() -> void:
	wind.active = true
	wind.t = 0.0
	wind.dur = 9.0 + randf() * 4.0
	var a := randf() * TAU
	wind.dir = Vector2(cos(a), sin(a))
	sfx.wind_gust(wind.dur)
	parcels.start_gust()
	stats.gusts += 1
	hud.show_dialogue("Gust of wind!", "A strong gust is sweeping through the town, scattering parcels everywhere. Anything stacked in the depot is safe!")


func _update_wind(delta: float) -> void:
	if not started:
		return
	wind.time += delta
	if not wind.active:
		wind.next -= delta
		if wind.next <= 0.0:
			start_gust()
	if wind.active:
		wind.t += delta
		var t: float = wind.t / wind.dur
		# quick build-up, long hold, slow fade
		wind.gust = t / 0.15 if t < 0.15 else (1.0 if t < 0.6 else maxf(0.0, 1.0 - (t - 0.6) / 0.4))
		if wind.t >= wind.dur + 7.5:   # let the last parcels land
			wind.active = false
			wind.next = 70.0 + randf() * 80.0
	parcels.update_gust(wind.t, wind.gust, delta)
	wind.strength = 0.18 + 0.1 * sin(wind.time * 0.21) * sin(wind.time * 0.53) + wind.gust * 0.8
	world.set_wind(wind.strength, wind.dir)
	# leaves blow past upwind of the player
	var d: Vector2 = wind.dir
	var speed: float = 6.0 + wind.gust * 14.0
	leaves.emitting = wind.gust > 0.05 and not world.house_parts.house_at(player.global_position.x, player.global_position.z)
	leaves.global_position = player.global_position + Vector3(-d.x * 14.0, 1.5, -d.y * 14.0)
	leaves.direction = Vector3(d.x, 0.15, d.y)
	leaves.initial_velocity_min = speed * 0.8
	leaves.initial_velocity_max = speed * 1.1


## Room lights follow you indoors (brighter at night); ceiling fixtures glow when the lights are on
func _update_room_lights() -> void:
	var p: Vector3 = player.global_position
	var house = world.house_parts.house_at(p.x, p.z)
	var day: float = sky.daylight()
	var target := (0.25 + 0.95 * (1.0 - day)) * 1.6 if house != null else 0.0
	if house != null:
		var spots: Array = world.house_parts.room_light_spots(house, p.y > 2.0)
		for i in room_lights.size():
			room_lights[i].global_position = spots[i]
	for l in room_lights:
		l.light_energy += (target - l.light_energy) * 0.15
		l.visible = l.light_energy > 0.02
	world.house_parts.fixture_mat.emission_energy_multiplier = (0.3 + 1.7 * (1.0 - day)) if house != null else (0.15 + (1.2 if is_night else 0.0))


## A handful of real lights follow the street, porch and pier lamps nearest the player at night
func _update_lamp_pool(delta: float) -> void:
	_pool_t -= delta
	if _pool_t > 0.0:
		return
	_pool_t = 0.3
	var dark: float = 1.0 - sky.daylight()
	if dark < 0.35:
		for l in lamp_pool:
			l.visible = false
		return
	var p: Vector3 = player.global_position
	var srcs: Array = world.lamp_sources.duplicate()
	srcs.sort_custom(func(a, c): return a.distance_squared_to(p) < c.distance_squared_to(p))
	for i in lamp_pool.size():
		var l := lamp_pool[i]
		if i < srcs.size():
			l.global_position = srcs[i]
			l.visible = true
			l.light_energy = 2.2 * clampf((dark - 0.35) / 0.4, 0.0, 1.0)
		else:
			l.visible = false


# ------------------------------------------------------------------------------------------------
# Test helpers (run with: godot -- --smoke   or   godot -- --shot)
# ------------------------------------------------------------------------------------------------
func _smoke_test() -> void:
	get_tree().paused = false
	await get_tree().create_timer(0.5).timeout
	var before: int = parcels.records.size()
	var rec: Dictionary = parcels.records[0]
	collect(rec)
	assert(backpack.size() == 1)
	assert(score == 0)   # picking up scores nothing
	player.global_position = Vector3(-165, 0.2, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	deposit_all()
	assert(score == 50)   # filing it in the depot does
	# a filed parcel can't be picked up again: look straight at it from close by
	var filed: Dictionary = parcels.records[parcels.records.size() - 1]
	assert(filed.stored)
	var eye: Vector3 = filed.pos + Vector3(0, 0.5, 1.2)
	assert(parcels.nearest(eye, (filed.pos - eye).normalized(), 3.5) == null)
	for i in 50:   # the bell is synthesised on a worker thread
		if sfx.bell_stream != null:
			break
		await get_tree().create_timer(0.1).timeout
	assert(sfx.bell_stream != null)
	print("SMOKE: bell ready, %.1f s long" % sfx.bell_stream.get_length())
	print("SMOKE: parcels %d -> %d, stored %d, score %d, backpack %d, player y %.2f" % [before, parcels.records.size(), parcels.stored_total(), score, backpack.size(), player.global_position.y])
	get_tree().quit(0 if parcels.stored_total() == 1 else 1)


## --savetest write: play a little and save;  --savetest read: load it back and report
func _save_test() -> void:
	var args := OS.get_cmdline_user_args()
	var writing: bool = args[args.find("--savetest") + 1] == "write"
	get_tree().paused = false
	hud.show_menu(false)
	if writing:
		started = true
		collect(parcels.records[0])
		collect(parcels.records[5])
		player.global_position = Vector3(-165, 0.1, 0)
		await get_tree().physics_frame
		deposit_all()
		collect(parcels.records[10])   # a loose one (filed parcels sit at the end of the list)
		player.global_position = Vector3(12.5, 0.1, 20.25)
		player.yaw = 1.25
		truck.pos = Vector2(-40, 2.5)
		truck.cargo.append("M")
		sky.hour = 19.5
		score = 777
		stats.time = 4000.0
		stats.walked = 1234.0
		start_gust()
		await get_tree().create_timer(2.0).timeout
		save_game()
		print("SAVE: wrote; depot %d, backpack %s, loose %d" % [parcels.stored_total(), backpack, parcels.records.size() - parcels.stored_total()])
	else:
		print("SAVE: loaded=%s player %s yaw %.2f hour %.1f score %d backpack %s truck %s cargo %s depot %d loose %d time %s walked %.0f gusts %d sessions %d" % [
			loaded, player.global_position, player.yaw, sky.hour, score, backpack, truck.pos, truck.cargo,
			parcels.stored_total(), parcels.records.size() - parcels.stored_total(), _hms(stats.time), stats.walked, stats.gusts, stats.sessions])
		if args.size() > args.find("--savetest") + 2:   # optional folder: screenshot the menu with the progress panel
			hud.set_stats(stats_rows(), true)
			hud.show_menu(true)
			for i in 30:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(args[args.find("--savetest") + 2].path_join("shot_menu_stats.png"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	get_tree().quit()


## Walk out through the Nordtor over the drawbridge to the bridgehead and back; raise the bridge; try again
func _moat_test() -> void:
	get_tree().paused = false
	hud.show_menu(false)
	var walk_to := func(target: Vector3, secs: float) -> void:
		var t := 0.0
		while t < secs:
			var to: Vector3 = target - player.global_position
			to.y = 0
			if to.length() < 0.3:
				break
			var d := to.normalized().rotated(Vector3.UP, -player.yaw)
			player.move_input = Vector2(d.x, d.z)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		player.move_input = Vector2.ZERO
	player.global_position = Vector3(0, 0.1, -176)
	await get_tree().create_timer(0.3).timeout
	await walk_to.call(Vector3(0, 0, -210), 12.0)
	print("MOAT: out at z %.1f y %.2f (bridgehead floor is beyond z -203)" % [player.global_position.z, player.global_position.y])
	await walk_to.call(Vector3(-20, 0, -210), 3.0)
	print("MOAT: tried to leave the bridgehead sideways: x %.1f" % player.global_position.x)
	await walk_to.call(Vector3(0, 0, -208), 4.0)
	await walk_to.call(Vector3(0, 0, -186), 12.0)
	print("MOAT: back inside at z %.1f" % player.global_position.z)
	var lever: Dictionary = {}
	for it in world.interactables:
		if it.type == "lever":
			lever = it
	var res: Dictionary = lever.call.call()
	print("MOAT: lever: ", res.get("message", ""))
	await get_tree().create_timer(3.0).timeout
	await walk_to.call(Vector3(0, 0, -210), 5.0)
	print("MOAT: with the bridge up, stopped at z %.1f" % player.global_position.z)
	get_tree().quit()


## Start a gust, screenshot the parcels in the air, check they all land somewhere new
func _gust_test() -> void:
	get_tree().paused = false
	hud.show_menu(false)
	started = true
	sky.hour = 12.0
	player.global_position = Vector3(30, 0.1, 40)
	player.yaw = 0.6
	player.pitch = 0.25
	await get_tree().create_timer(0.5).timeout
	var loose: Array = []
	for r in parcels.records:
		if not r.stored:
			loose.append([r, r.pos])
	start_gust()
	# watch the flights: none may pass through a roof
	var through := {}
	var watch := func() -> void:
		for r in parcels.records:
			if r.get("flying", false):
				var bottom: float = r.pos.y - parcels.SIZES[r.size].h / 2
				var roof: float = world.roof_top_at(r.pos.x, r.pos.z) - 0.4
				if world.house_at(r.pos.x, r.pos.z) and bottom < roof - 0.3:
					through[r] = true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
		watch.call()
	var flying := 0
	for r in parcels.records:
		if r.get("flying", false):
			flying += 1
	var args := OS.get_cmdline_user_args()
	get_viewport().get_texture().get_image().save_png(args[args.find("--gust") + 1].path_join("shot_gust.png"))
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 16000:
		await get_tree().process_frame
		watch.call()
	# and none may end up sunk into a pedestal, plinth or another parcel
	var sunk := 0
	for r in parcels.records:
		if r.stored:
			continue
		var under: float = parcels._rest_y(r, r.pos.x, r.pos.z, r.pos.y - parcels.SIZES[r.size].h / 2 + 0.02)   # what is beneath it only
		if r.pos.y < under - 0.05:
			sunk += 1
			if sunk <= 4:
				print("GUST: sunk %s at %s, should rest at y %.2f" % [r.size, r.pos, under])
	print("GUST: %d flew through a roof, %d landed sunk into something" % [through.size(), sunk])
	var moved := 0
	var still := 0
	for e in loose:
		if e[0].get("flying", false):
			still += 1
		if e[0].pos.distance_to(e[1]) > 1.0:
			moved += 1
	print("GUST: %d loose parcels, %d in the air at 4 s, %d moved, %d still flying at 20 s, gust active %s" % [loose.size(), flying, moved, still, wind.active])
	get_tree().quit()


## Open a front door, walk into the hall and up the stairs (joystick input in house space)
func _stairs_test() -> void:
	get_tree().paused = false
	hud.show_menu(false)
	var hp = world.house_parts
	var rec: Dictionary = hp.interiors[3]
	var xf: Transform3D = rec.xf
	var walk := func(target_local: Vector3, secs: float) -> void:
		var t := 0.0
		while t < secs:
			var to: Vector3 = xf * target_local - player.global_position
			to.y = 0
			if to.length() < 0.25:
				break
			var d := to.normalized().rotated(Vector3.UP, -player.yaw)
			player.move_input = Vector2(d.x, d.z)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		player.move_input = Vector2.ZERO
	player.global_position = xf * Vector3(0, 0.1, 9.5)
	await get_tree().physics_frame
	var door: Dictionary = {}
	for it in world.interactables:
		if it.type == "door" and it.pos.distance_to(xf * Vector3(0, 1.4, 7)) < 0.1:
			door = it
	door.call.call()
	await get_tree().create_timer(1.0).timeout
	await walk.call(Vector3(0.2, 0, 5.0), 4.0)
	await walk.call(Vector3(0.2, 0, -0.25), 4.0)
	print("STAIRS: in the hall at y %.2f, in house: %s" % [player.global_position.y, hp.house_at(player.global_position.x, player.global_position.z) != null])
	await walk.call(Vector3(1.0, 0, -0.25), 2.0)
	await walk.call(Vector3(7.0, 0, -0.25), 6.0)
	print("STAIRS: top of the flight at y %.2f" % player.global_position.y)
	await walk.call(Vector3(6.6, 0, 1.3), 3.0)
	await get_tree().create_timer(0.5).timeout
	print("STAIRS: upstairs landing at y %.2f (upper floor is %.2f)" % [player.global_position.y, hp.UP])
	get_tree().quit()


## Walk from the Ulmenstraße onto its pavement at walking speed, head-on and at a slant, and off again
func _kerb_test() -> void:
	get_tree().paused = false
	hud.show_menu(false)
	var ok := true
	for case in [[Vector3(2.0, 0.1, 60.0), Vector3(1, 0, 0)], [Vector3(2.0, 0.1, 80.0), Vector3(1, 0, 0.7)], [Vector3(2.0, 0.1, 100.0), Vector3(1, 0, -1.6)]]:
		player.global_position = case[0]
		player.yaw = 0.0
		for i in 10:
			await get_tree().physics_frame
		var d: Vector3 = (case[1] as Vector3).normalized()
		player.move_input = Vector2(d.x, d.z)
		var t := 0.0
		var top := 0.0
		while t < 1.2:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			top = maxf(top, player.global_position.y)
		player.move_input = Vector2.ZERO
		var p: Vector3 = player.global_position
		var up: bool = top > 0.2 and p.x > 6.0
		ok = ok and up
		print("KERB: from x %.1f heading (%.1f, %.1f): reached x %.2f, highest y %.2f %s" % [case[0].x, d.x, d.z, p.x, top, "climbed the kerb" if up else "STUCK"])
	# and back down onto the road
	player.move_input = Vector2(-1, 0)
	for i in 60:
		await get_tree().physics_frame
	player.move_input = Vector2.ZERO
	print("KERB: back on the road at x %.2f, y %.2f" % [player.global_position.x, player.global_position.y])
	print("KERB: %s" % ("ok" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)


## Get in the truck, hold W for 3 s (then W+A), screenshot the chase camera, stop and get out
func _drive_test() -> void:
	get_tree().paused = false
	hud.show_menu(false)
	sky.hour = 15.0
	await get_tree().create_timer(0.5).timeout
	var start: Vector2 = truck.pos
	truck.enter()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(3.0).timeout
	var evl := InputEventKey.new()
	evl.physical_keycode = KEY_A
	evl.pressed = true
	Input.parse_input_event(evl)
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	var args := OS.get_cmdline_user_args()
	img.save_png(args[args.find("--drive") + 1].path_join("shot_driving.png"))
	truck.toggle_view()   # the cab view, wipers going
	truck.wipers_on = true
	await get_tree().create_timer(0.75).timeout
	get_viewport().get_texture().get_image().save_png(args[args.find("--drive") + 1].path_join("shot_cab.png"))
	ev.pressed = false
	Input.parse_input_event(ev)
	evl.pressed = false
	Input.parse_input_event(evl)
	var sp := InputEventKey.new()
	sp.physical_keycode = KEY_SPACE
	sp.pressed = true
	Input.parse_input_event(sp)
	await get_tree().create_timer(2.0).timeout
	sp.pressed = false
	Input.parse_input_event(sp)
	print("DRIVE: moved %.1f m, heading %.2f, speed %.2f" % [truck.pos.distance_to(start), truck.heading, truck.speed])
	truck.exit()
	await get_tree().physics_frame
	print("DRIVE: driving=%s player at %s" % [truck.driving, player.global_position])
	get_tree().quit()


const UP_LOOK := 4.4
var _shots := []
func _screenshot_mode() -> void:
	get_tree().paused = false
	hud.show_menu(false)
	_shots = [
		[Vector3(0, 0.1, 30), 0.0, -0.05, 14.0, "street"],
		[Vector3(-45, 0.1, 6), PI, 0.25, 15.5, "church"],
		[Vector3(-130, 0.1, 0), PI / 2, 0.0, 10.0, "depot"],
		[Vector3(10, 0.1, -150), 0.0, 0.08, 17.8, "nordtor_sunset"],
		[Vector3(30, 0.1, -12), 2.4, 0.05, 22.5, "night"],
		[Vector3(-38, 0.1, 132), 0.15, -0.12, 15.0, "pond"],
		[Vector3(-60, 0.1, 85), -2.6, -0.02, 11.0, "park_trees"],
		[Vector3(-3.6, 0.1, 29.4), 0.785, 0.52, 19.0, "lamp"],
		[Vector3(0, 0.1, 30), "moon", 0.0, 23.0, "moon", 12.0],
		[Vector3(0, 0.1, 60), 0.6, 0.55, 11.0, "birds", 40.0],
		[Vector3(-45, 0.1, 130), 0.0, -0.3, 10.0, "ducks", 40.0],
		[Vector3(-15, 0.1, 9), 0.99, -0.12, 15.0, "truck", 60.0],
		[Vector3(-33, 1.7, 6.5), "cam", Vector3(-27.5, 1.9, 2.5), 15.0, "truck_front", 55.0],
		[Vector3(-24.3, 2.6, 6.2), "cam", Vector3(-26.5, 1.9, 2.0), 15.0, "truck_window", 55.0],
		[Vector3(0, 0.1, 30), 0.0, -0.05, 14.0, "menu", 75.0],
		[Vector3(-90, 0.1, -120), 1.30, 0.22, 16.0, "castle_town", 50.0],
		[Vector3(-90, 0.1, -120), 1.30, 0.22, 22.5, "castle_night", 50.0],
		[Vector3(0, 0.1, -176), 0.0, -0.05, 15.0, "nordtor_out", 70.0],
		[Vector3(-30, 9, -230), "cam", Vector3(0, 0, -200), 15.0, "moat_bridge", 65.0],
		[Vector3(150, 6, -205), "cam", Vector3(196, -1, -197), 15.0, "moat_corner", 65.0],
		[Vector3(-45, 0.1, -10), PI, 0.5, 22.5, "church_night", 70.0],
		[Vector3(-45, 1.7, 13), "cam", Vector3(-45, 6.5, 26), 11.0, "church_portal", 65.0],
		[Vector3(-170, 1.7, 2), "cam", Vector3(-160, 5.6, -4), 11.0, "depot_lamps", 70.0],
		[Vector3(-45, 1.7, 13), "cam", Vector3(-45, 6.5, 26), 22.5, "church_portal_night", 65.0],
		[Vector3(-22, 0.1, 86), PI / 2 - 0.2, 0.05, 22.5, "park_night", 75.0],
		[Vector3(-41, 0.1, 89), PI + 0.3, 0.02, 22.5, "park_night2", 75.0],
		[Vector3(0, 0, 0), "house", Vector3(-4.0, 1.6, 6.0), 15.0, "living_room", 75.0],
		[Vector3(0, 0, 0), "house", Vector3(-3.0, 1.6, -1.6), 15.0, "kitchen", 75.0],
		[Vector3(0, 0, 0), "house", Vector3(2.0, 5.2, 0.9), 15.0, "upstairs", 75.0],
		[Vector3(0, 0, 0), "house", Vector3(-1.0, 1.6, 12.0), 20.5, "house_front", 70.0],
		[Vector3(0, 0, 0), "house", Vector3(-4.0, 1.7, 22.0), 11.0, "house_timber", 70.0, 0],
		[Vector3(0, 0, 0), "house", Vector3(-20.0, 1.7, 12.0), 11.0, "garage_open", 60.0, 1],
		[Vector3(0, 0, 0), "house", Vector3(-19.0, 1.7, -8.0), 11.0, "garage_closed", 60.0, 0],
		[Vector3(0, 0, 0), "house", Vector3(-11.5, 1.6, 2.5), 11.0, "garage_inside", 75.0, 1],
		[Vector3(Vector3(-11.5, 2.0, 0.0)), "hcam", Vector3(-11.5, 1.7, 14.0), 11.0, "gar_front", 70.0, 0],
		[Vector3(Vector3(-11.5, 2.0, -1.0)), "hcam", Vector3(-14.0, 1.7, -13.0), 11.0, "gar_back", 70.0, 0],
		[Vector3(Vector3(-11.5, 2.0, -1.0)), "hcam", Vector3(-20.0, 8.0, 6.0), 11.0, "gar_high", 70.0, 0],
		[Vector3(Vector3(-11.5, 2.0, 0.0)), "hcam", Vector3(-11.5, 1.7, 14.0), 11.0, "gar_front1", 70.0, 1],
		[Vector3(Vector3(0.0, 1.2, 7.0)), "hcam", Vector3(0.0, 1.6, 10.5), 11.0, "front_door", 70.0, 0],
		[Vector3(-200, 30, -110), "cam", Vector3(-290, 95, -175), 16.0, "castle_near", 55.0],
		[Vector3(-262, 92, -165), "cam", Vector3(-298, 100, -178), 21.5, "castle_court", 70.0],
		[Vector3(-31, 0.1, -5), -2.3, -0.12, 15.0, "truck_rear", 60.0],
		[Vector3(-45, 0.1, 130), "duck", 0, 10.0, "drake", 20.0],
		[Vector3(-45, 0.1, 130), "duck", 1, 10.0, "hen", 20.0],
		[Vector3(0, 0.1, 30), "moon", 0.0, 23.0, "moonwide", 75.0],
		[Vector3(-25.6, 0.9, 5.9), "cam", Vector3(-27.55, 0.45, 3.5), 15.0, "truck_wheel", 50.0],
		[Vector3(-20.6, 0.9, 6.2), "cam", Vector3(-22.7, 0.45, 3.7), 15.0, "truck_rwheel", 50.0],
		[Vector3(0.0, 3.8, 7.0), "hcam", Vector3(0.0, 1.8, 18.0), 14.0, "fresco_gothic", 60.0, 3],
		[Vector3(0.0, 3.8, 7.0), "hcam", Vector3(0.0, 1.8, 18.0), 14.0, "fresco_plain", 60.0, 7],
		[Vector3(0.0, 2.6, 7.0), "hcam", Vector3(1.0, 1.7, 13.0), 14.0, "fresco_upper", 60.0, 14],
		[Vector3(-2.25, 4.4, 7.0), "hcam", Vector3(-1.6, 2.4, 10.5), 14.0, "fresco_close", 55.0, 7],
		[Vector3(-2.25, 5.3, 7.0), "hcam", Vector3(-2.0, 4.2, 10.0), 14.0, "fresco_close2", 50.0, 12],
		[Vector3(40, 1.7, 168), "cam", Vector3(52, 3.5, 185), 15.0, "wall_vines", 65.0],
		[Vector3(96, 1.6, 180.5), "cam", Vector3(99, 2.6, 185), 15.0, "wall_vines_near", 60.0],
		[Vector3(170, 2.0, 40), "cam", Vector3(185, 5.0, 25), 10.0, "wall_east", 65.0],
		[Vector3(14, 2.0, -158), "cam", Vector3(0, 13.0, -182), 15.0, "nordtor_town", 60.0],
		[Vector3(26, 7, -222), "cam", Vector3(0, 13.0, -191), 15.0, "nordtor_moat", 60.0],
		[Vector3(0.5, 1.7, -186.0), "cam", Vector3(0.8, 12.0, -185.0), 15.0, "nordtor_under", 75.0],
		[Vector3(0, 14.0, -172.0), "cam", Vector3(0, 17.0, -181.5), 15.0, "clock_nordtor", 45.0],
		[Vector3(-34, 27.0, 52.0), "cam", Vector3(-45, 23.5, 35.0), 15.0, "clock_church", 40.0],
		[Vector3(9.0, 1.7, -178.0), "cam", Vector3(6.5, 22.0, -181.5), 15.0, "nordtor_turret", 70.0],
		[Vector3(14, 2.0, -158), "cam", Vector3(0, 13.0, -182), 22.5, "nordtor_night", 60.0],
	]
	# `--only a,b` renders just the named views
	var args := OS.get_cmdline_user_args()
	var only: PackedStringArray = args[args.find("--only") + 1].split(",") if "--only" in args else PackedStringArray()
	for s in _shots:
		if only.size() > 0 and not (s[4] in only):
			continue
		player.global_position = s[0]
		sky.hour = s[3]
		player.camera.fov = s[5] if s.size() > 5 else 75.0
		if not (s[1] is String):
			player.yaw = s[1]
			player.pitch = s[2]
		for i in 40:
			await get_tree().process_frame
			if s[1] is String and s[1] == "moon":   # aim at the moon (zoomed in so the face shows)
				var d: Vector3 = sky.moon_dir
				player.yaw = atan2(-d.x, -d.z)
				player.pitch = asin(d.y)
			elif s[1] is String and s[1] == "house":   # inside / in front of the first house: s[2] is the eye in house space
				var rec: Dictionary = world.house_parts.interiors[s[6] if s.size() > 6 else 3]
				var hx: Transform3D = rec.xf
				var eye: Vector3 = hx * s[2]
				var look: Vector3 = hx * (Vector3(-6.0, 1.0, 2.0) if s[4] == "living_room" else (Vector3(-5.0, 0.9, -6.5) if s[4] == "kitchen" else (Vector3(-5.0, UP_LOOK, 4.0) if s[4] == "upstairs" else (Vector3(-11.5, 1.5, 0.0) if s[4] in ["garage_open", "garage_closed"] else (Vector3(-11.5, 1.0, -5.0) if s[4] == "garage_inside" else Vector3(0, 4.0, 0))))))
				player.set_physics_process(false)
				player.set_process(false)
				player.global_position = Vector3(eye.x, eye.y - 1.6, eye.z)
				player.camera.global_transform = Transform3D(Basis(), eye).looking_at(look)
			elif s[1] is String and s[1] == "hcam":   # house-space camera: eye s[2], target s[0], house s[6]
				var hx2: Transform3D = world.house_parts.interiors[s[6]].xf
				player.set_physics_process(false)
				player.set_process(false)
				player.camera.global_transform = Transform3D(Basis(), hx2 * s[2]).looking_at(hx2 * s[0])
			elif s[1] is String and s[1] == "cam":   # free camera: from s[0] towards s[2]
				player.set_physics_process(false)
				player.set_process(false)
				player.camera.global_transform = Transform3D(Basis(), s[0]).looking_at(s[2])
			elif s[1] is String and s[1] == "duck":   # stand by the pond edge nearest a drake and look at it
				var dd: Dictionary = ducks.lakes[0].sim[s[2]]
				var dk: Node3D = dd.g
				var side := Vector3(-sin(dd.heading), 0, cos(dd.heading))   # profile view, from just above the water
				player.set_physics_process(false)
				player.set_process(false)
				var eye := dk.position + side * 2.0 + Vector3(0, 0.6, 0)
				player.camera.global_transform = Transform3D(Basis(), eye).looking_at(dk.position + Vector3(0, 0.12, 0))
		if s[4] == "menu":
			hud.show_menu(true)
			await get_tree().process_frame
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		if s[4] == "menu":
			hud.show_menu(false)
		var path: String = OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--shot") + 1] if OS.get_cmdline_user_args().size() > 1 else "user://"
		img.save_png(path.path_join("shot_%s.png" % s[4]))
		print("saved shot ", s[4])
	get_tree().quit()
