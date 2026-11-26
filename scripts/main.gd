extends Node3D
## Game manager: builds the town, player, sky and HUD, and runs the tidy-up loop (backpack of 10 parcels,
## the depot that files them away, score, day/night, street-lamp light pool). Port of js/game.js.

const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const SkyCycle := preload("res://scripts/sky_cycle.gd")
const Hud := preload("res://scripts/hud.gd")
const Parcels := preload("res://scripts/parcels.gd")
const Sfx := preload("res://scripts/sfx.gd")

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
var _gfx_frames := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	sfx = Sfx.new()
	add_child(sfx)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)
	var env_node := WorldEnvironment.new()
	add_child(env_node)
	sky = SkyCycle.new()
	add_child(sky)
	sky.setup(env_node, sun)

	world = World.new()
	add_child(world)
	world.build()
	parcels = Parcels.new()
	parcels.world = world
	add_child(parcels)
	parcels.build()

	player = Player.new()
	player.world = world
	player.game = self
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)

	for i in LAMP_POOL:
		var l := OmniLight3D.new()
		l.light_color = Color("#ffc98a")
		l.light_energy = 2.0
		l.omni_range = 13.0
		l.omni_attenuation = 1.4
		l.visible = false
		add_child(l)
		lamp_pool.append(l)

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.set_quest(0, parcels.total)
	hud.set_backpack(backpack, BACKPACK_CAP)
	print("Parcel Run ready in %d ms: %d parcels in the town" % [Time.get_ticks_msec() - t0, parcels.total])

	# Headless / CI smoke run and screenshot mode
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke_test()
		return
	if "--shot" in OS.get_cmdline_user_args():
		_screenshot_mode()
		return
	pause()


func pause() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu(true)


func resume() -> void:
	started = true
	hud.show_menu(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sfx.start()


func _process(delta: float) -> void:
	sky.update(delta, player.global_position)
	var night: bool = sky.is_night()
	if night != is_night:
		is_night = night
		world.set_night(night)
		sfx.night = night
	hud.set_clock("[N] %s %s" % [sky.clock_text(), sky.phase_name()])
	_update_lamp_pool(delta)
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_E, KEY_ENTER:
			interact()
		KEY_SPACE:
			player.jump()
		KEY_C, KEY_CTRL:
			player.toggle_crouch()
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
	add_score(20)
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
	player.global_position = Vector3(-165, 0.2, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	deposit_all()
	print("SMOKE: parcels %d -> %d, stored %d, score %d, backpack %d, player y %.2f" % [before, parcels.records.size(), parcels.stored_total(), score, backpack.size(), player.global_position.y])
	get_tree().quit(0 if parcels.stored_total() == 1 else 1)


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
	]
	for s in _shots:
		player.global_position = s[0]
		player.yaw = s[1]
		player.pitch = s[2]
		sky.hour = s[3]
		for i in 40:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path: String = OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--shot") + 1] if OS.get_cmdline_user_args().size() > 1 else "user://"
		img.save_png(path.path_join("shot_%s.png" % s[4]))
		print("saved shot ", s[4])
	get_tree().quit()
