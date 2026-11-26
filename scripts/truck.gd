extends Node3D
## Delivery truck, ported from truck.js: walk up to the driver's door and press E to drive it. WASD / arrows
## drive, Space brakes, Q sounds the horn, V switches between the chase camera and the cab, E gets out.
## At the rear doors, E loads everything in your backpack into the truck (50 parcels), or - with an empty
## backpack - takes parcels back out, so you can ferry big loads to the depot. Drive into the depot and press E
## to unload. On phones the joystick drives (push up for throttle, pull back to brake / reverse).

const Batch := preload("res://scripts/batch.gd")
const CAPACITY := 50
const SPOT := Vector3(-25, 2.5, PI)     # x, z, heading (world.js truckSpot)

var game
var world
var pos := Vector2(SPOT.x, SPOT.y)
var heading := SPOT.z                 # forward = (cos h, sin h) on the x/z plane
var speed := 0.0
var steer := 0.0
var wheel_spin := 0.0
var driving := false
var braking := false
var view := "chase"
var cargo: Array[String] = []
var cam_pos := Vector3.ZERO
var wheels: Array = []                # [{pivot, spin, steerable}]
var head_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var beam: SpotLight3D
var body: AnimatableBody3D
var door_item := {}
var rear_item := {}
var _grid := {}                       # 16 m cells -> solids, for the truck's own collision test
var _grid_built := false


func _ready() -> void:
	_build_model()
	body = AnimatableBody3D.new()
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(7.6, 3.4, 2.6)   # bumper to bumper, mirror to mirror
	cs.shape = bs
	cs.position = Vector3(0, 1.7, 0)
	body.add_child(cs)
	add_child(body)
	door_item = {"pos": Vector3.ZERO, "prompt": "[E] Drive the delivery truck", "type": "truck", "call": _enter_call}
	rear_item = {"pos": Vector3.ZERO, "prompt": "", "type": "truck", "call": load_or_unload}
	world.interactables.append(door_item)
	world.interactables.append(rear_item)
	_sync()


# ---------------------------------------------------------------- model (built facing +x)
func _std(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _build_model() -> void:
	var paint := _std(Color("#f3f2ee"), 0.35, 0.15)
	var orange := _std(Color("#e8731c"), 0.4, 0.15)
	var dark := _std(Color("#1f2124"), 0.6, 0.3)
	var glass := _std(Color("#182028"), 0.05, 0.6)
	var rubber := _std(Color("#151515"), 0.9)
	var hub := _std(Color("#b8bcc0"), 0.3, 0.9)
	var door := _std(Color("#d8dbde"), 0.35, 0.5)
	var grille := _std(Color("#8c9196"), 0.3, 0.8)
	head_mat = _std(Color("#f6f4ea"), 0.2)
	head_mat.emission_enabled = true
	head_mat.emission = Color("#fff3d0")
	head_mat.emission_energy_multiplier = 0.2
	tail_mat = _std(Color("#8a0f0f"), 0.3)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color("#ff2a1a")
	tail_mat.emission_energy_multiplier = 0.3
	# Livery: one copy of the picture over each side of the cargo box (the batch's UVs are in metres)
	var livery := _std(Color.WHITE, 0.4, 0.1)
	livery.albedo_texture = world.tex("livery_col")
	livery.uv1_scale = Vector3(1.0 / 5.2, 1.0 / 2.55, 1.0)
	livery.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var b := Batch.new()
	var I := Transform3D.IDENTITY
	var B := func(w: float, h: float, d: float, mat, x: float, y: float, z: float, rz := 0.0) -> void:
		b.box(Transform3D(Basis(Vector3.BACK, rz), Vector3(x, y, z)), Vector3.ZERO, Vector3(w, h, d), mat, 1.0, true, true)
	# chassis and bumpers
	B.call(6.6, 0.28, 1.8, dark, -0.3, 0.68, 0)
	B.call(0.25, 0.35, 2.3, dark, 3.72, 0.7, 0)
	B.call(0.2, 0.3, 2.3, dark, -3.78, 0.72, 0)
	# cargo box with the livery on both sides, roll-up door at the back
	B.call(5.2, 2.55, 2.46, [paint, paint, paint, paint, livery, livery], -1.1, 2.1, 0)
	B.call(0.04, 2.3, 2.2, door, -3.72, 2.0, 0)
	for k in 9:
		B.call(0.02, 0.02, 2.2, dark, -3.745, 1.0 + k * 0.25, 0)
	B.call(0.06, 0.06, 2.3, dark, -3.74, 3.32, 0)
	# cab: body, roof fairing, stripe, windscreen, side windows, grille
	B.call(2.1, 1.25, 2.3, paint, 2.55, 1.45, 0)
	B.call(1.7, 0.95, 2.3, paint, 2.35, 2.55, 0)
	B.call(1.3, 0.5, 2.2, paint, 2.0, 3.1, 0, -0.25)
	B.call(2.12, 0.16, 2.32, orange, 2.55, 1.6, 0)
	B.call(5.22, 0.16, 2.48, orange, -1.1, 1.15, 0)
	B.call(0.05, 0.85, 2.05, glass, 3.25, 2.5, 0, 0.18)
	for s in [-1.0, 1.0]:
		B.call(1.0, 0.7, 0.03, glass, 2.45, 2.5, s * 1.16)
	B.call(0.06, 0.55, 1.5, dark, 3.62, 1.25, 0)
	for k in 4:
		B.call(0.07, 0.04, 1.45, grille, 3.64, 1.05 + k * 0.13, 0)
	# lights, mirrors, step, mud flaps
	for s in [-1.0, 1.0]:
		B.call(0.06, 0.22, 0.4, head_mat, 3.62, 1.35, s * 0.88)
		B.call(0.05, 0.3, 0.14, tail_mat, -3.75, 1.0, s * 1.08)
		B.call(0.06, 0.3, 0.16, dark, 3.0, 2.45, s * 1.32)
		B.call(0.4, 0.06, 0.25, dark, 2.6, 0.55, s * 1.2)
		B.call(1.0, 0.7, 0.05, dark, -2.3, 1.0, s * 1.3)
	b.commit(self)

	# wheels: steerable fronts, dual rears
	var tyre := CylinderMesh.new()
	tyre.top_radius = 0.5
	tyre.bottom_radius = 0.5
	tyre.height = 0.32
	tyre.radial_segments = 24
	var hubm := CylinderMesh.new()
	hubm.top_radius = 0.26
	hubm.bottom_radius = 0.26
	hubm.height = 0.34
	hubm.radial_segments = 12
	var nut := BoxMesh.new()
	nut.size = Vector3(0.05, 0.05, 0.36)
	var axle := Basis(Vector3.RIGHT, PI / 2)
	for s in [-1.0, 1.0]:
		for w in [[2.55, s * 1.0, true], [-2.3, s * 0.92, false], [-2.3, s * 1.24, false]]:
			var pivot := Node3D.new()
			pivot.position = Vector3(w[0], 0.5, w[1])
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			_part(spin, tyre, rubber, Transform3D(axle, Vector3.ZERO))
			_part(spin, hubm, hub, Transform3D(axle, Vector3.ZERO))
			for k in 5:
				_part(spin, nut, dark, Transform3D(Basis(), Vector3(cos(k * 1.256) * 0.16, sin(k * 1.256) * 0.16, 0)))
			wheels.append({"pivot": pivot, "spin": spin, "steerable": w[2]})
	# headlight beam (only at night while driving)
	beam = SpotLight3D.new()
	beam.light_color = Color("#fff1d6")
	beam.spot_range = 45.0
	beam.spot_angle = rad_to_deg(0.55)
	beam.spot_angle_attenuation = 1.5
	beam.shadow_enabled = true
	beam.position = Vector3(3.7, 1.3, 0)
	beam.look_at_from_position(beam.position, Vector3(14, 0, 0), Vector3.UP)
	beam.visible = false
	add_child(beam)


func _part(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)


# ---------------------------------------------------------------- interactions
func fwd() -> Vector2:
	return Vector2(cos(heading), sin(heading))


func in_depot() -> bool:
	return world.in_warehouse(pos.x, pos.y, -1.0)


func unload_into_depot() -> void:
	var n := 0
	while not cargo.is_empty() and game.parcels.store(cargo[cargo.size() - 1]):
		cargo.pop_back()
		n += 1
	if n > 0:
		game.sfx.play("door_open", -6.0)
		game.sfx.play("store", -4.0)
		game.add_score(n * 50)
		game.hud.toast("Unloaded %d parcel%s from the truck into the depot (%d stored)" % [n, "s" if n > 1 else "", game.parcels.stored_total()])
		game._update_quest()
	else:
		game.hud.toast("The depot is completely full!", true)


## E while driving: unload in the depot, otherwise get out
func press_e() -> void:
	if in_depot() and not cargo.is_empty():
		unload_into_depot()
	else:
		exit()


func load_or_unload() -> Dictionary:
	var bp: Array[String] = game.backpack
	if in_depot() and not cargo.is_empty():
		unload_into_depot()
	elif not bp.is_empty():
		var moved := 0
		while not bp.is_empty() and cargo.size() < CAPACITY:
			cargo.append(bp.pop_back())
			moved += 1
		if moved == 0:
			game.hud.toast("The truck is full! Drive it into the depot and press E.", true)
		else:
			game.sfx.play("door_close", -6.0)
			game.hud.toast("Loaded %d parcel%s (%d/%d in the truck)" % [moved, "s" if moved > 1 else "", cargo.size(), CAPACITY])
	elif not cargo.is_empty():
		var moved := 0
		while not cargo.is_empty() and bp.size() < game.BACKPACK_CAP:
			bp.append(cargo.pop_back())
			moved += 1
		game.sfx.play("door_open", -6.0)
		game.hud.toast("Took %d parcel%s out of the truck" % [moved, "s" if moved > 1 else ""])
	else:
		game.hud.toast("The truck is empty. Pick up parcels and load them in at the back.", true)
	game.hud.set_backpack(bp, game.BACKPACK_CAP)
	return {}


func _enter_call() -> Dictionary:
	enter()
	return {}


func enter() -> void:
	driving = true
	view = "chase"
	var P = game.player
	cam_pos = P.eye_position()
	P.set_physics_process(false)
	P.shape.disabled = true
	P.velocity = Vector3.ZERO
	body.get_child(0).disabled = true
	game.sfx.start_engine()
	game.sfx.play("door_close", -6.0)
	var keys := "joystick drive and steer, Use gets out" if game.mobile else "W/S drive, A/D steer, Space brake, Q horn, V camera, E get out"
	game.hud.toast("Truck: %s (or unload, inside the depot)" % keys)


func exit() -> void:
	if absf(speed) > 2.0:
		game.hud.toast("Stop the truck first (Space brakes)", true)
		return
	var f := fwd()
	var left := Vector2(f.y, -f.x)
	var spot = null
	for t in [[1.8, 2.3], [1.8, -2.3], [-5.0, 0.0], [5.2, 0.0]]:
		var p: Vector2 = pos + f * t[0] + left * t[1]
		if not blocked(p.x, p.y, 0.5, true):
			spot = p
			break
	if spot == null:
		game.hud.toast("No room to get out here", true)
		return
	driving = false
	speed = 0.0
	body.get_child(0).disabled = false
	var P = game.player
	P.global_position = Vector3(spot.x, 0.1, spot.y)
	P.velocity = Vector3.ZERO
	P.shape.disabled = false
	P.set_physics_process(true)
	P.yaw = -heading - PI / 2
	P.pitch = 0.0
	P.head.position = Vector3(0, P.eye, 0)
	P.camera.transform = Transform3D(Basis(Vector3.RIGHT, 0.0), Vector3.ZERO)
	game.sfx.stop_engine()
	game.sfx.play("door_open", -6.0)
	beam.visible = false


func toggle_view() -> void:
	if not driving:
		return
	view = "cab" if view == "chase" else "chase"
	game.player.yaw = -heading - PI / 2
	game.player.pitch = -0.05 if view == "cab" else 0.0


func horn() -> void:
	game.sfx.play("horn", -6.0)


# ---------------------------------------------------------------- collision
func _build_grid() -> void:
	_grid_built = true
	for s in world.solids:
		if s.bottom > 1.5 or s.top < 0.3:
			continue
		var r: Rect2 = s.rect
		for cx in range(floori(r.position.x / 16.0), floori(r.end.x / 16.0) + 1):
			for cz in range(floori(r.position.y / 16.0), floori(r.end.y / 16.0) + 1):
				var key := Vector2i(cx, cz)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(r)


## Would a circle at (x, z) hit anything solid? (houses, walls, trees, posts, hedges, ponds, the city wall)
func blocked(x: float, z: float, r: float, include_truck := false) -> bool:
	if not _grid_built:
		_build_grid()
	var F: float = world.FENCE - 0.5
	if absf(x) > F - r or absf(z) > F - r:
		return true
	for cx in range(floori((x - r) / 16.0), floori((x + r) / 16.0) + 1):
		for cz in range(floori((z - r) / 16.0), floori((z + r) / 16.0) + 1):
			for rc in _grid.get(Vector2i(cx, cz), []):
				var rr: Rect2 = rc
				var qx := clampf(x, rr.position.x, rr.end.x)
				var qz := clampf(z, rr.position.y, rr.end.y)
				if (x - qx) * (x - qx) + (z - qz) * (z - qz) < r * r:
					return true
	for l in world.lakes:
		if pow((x - l.cx) / (l.rw + r), 2) + pow((z - l.cz) / (l.rd + r), 2) < 1.0:
			return true
	if include_truck:
		var d := Vector2(x, z) - pos
		var f := fwd()
		var lx := d.dot(f)
		var lz := d.dot(Vector2(-f.y, f.x))
		var qx := clampf(lx, -3.8, 3.8)
		var qz := clampf(lz, -1.3, 1.3)
		if (lx - qx) * (lx - qx) + (lz - qz) * (lz - qz) < r * r:
			return true
	return false


# ---------------------------------------------------------------- per frame
func _key(a: Key, b := KEY_NONE) -> bool:
	return Input.is_physical_key_pressed(a) or (b != KEY_NONE and Input.is_physical_key_pressed(b))


func _physics_process(dt: float) -> void:
	var P = game.player
	if driving:
		var mi: Vector2 = P.move_input
		var throttle := _key(KEY_W, KEY_UP) or mi.y < -0.3
		var reverse := _key(KEY_S, KEY_DOWN) or mi.y > 0.3
		var steer_in := (1.0 if _key(KEY_A, KEY_LEFT) else 0.0) - (1.0 if _key(KEY_D, KEY_RIGHT) else 0.0)
		if absf(mi.x) > 0.15:
			steer_in = clampf(-mi.x * 1.3, -1.0, 1.0)
		var brake := _key(KEY_SPACE)
		if throttle:
			speed += (14.0 if speed < -0.3 else 5.5) * dt
		if reverse:
			speed -= (12.0 if speed > 0.3 else 3.5) * dt
		if not throttle and not reverse:
			speed -= signf(speed) * minf(absf(speed), 1.8 * dt)
		if brake:
			speed -= signf(speed) * minf(absf(speed), 16.0 * dt)
		speed = clampf(speed, -6.0, 20.0)
		var max_steer := 0.55 * (1.0 - minf(absf(speed) / 32.0, 0.55))
		steer += (steer_in * max_steer - steer) * minf(1.0, dt * 5.0)
		braking = brake or (reverse and speed > 0.3) or (throttle and speed < -0.3)
		game.sfx.set_engine(absf(speed) / 20.0, throttle)
	else:
		speed -= signf(speed) * minf(absf(speed), 8.0 * dt)
		steer *= 0.9
		braking = false

	# move (bicycle model), bounce off anything solid
	if absf(speed) > 0.001:
		var dh := -speed / 4.85 * tan(steer) * dt   # positive steer = turn left
		var nh := heading + dh
		var nx := pos.x + cos(nh) * speed * dt
		var nz := pos.y + sin(nh) * speed * dt
		var hit := false
		for o in [-2.6, 0.0, 2.6]:
			if blocked(nx + cos(nh) * o, nz + sin(nh) * o, 1.2):
				hit = true
				break
		if hit:
			if absf(speed) > 3.0:
				game.sfx.play("land", -4.0)
			speed = -speed * 0.25
		else:
			pos = Vector2(nx, nz)
			heading = nh
			if driving and view == "cab":
				P.yaw -= dh
	wheel_spin -= speed * dt / 0.5
	_sync()

	# lights
	var night: bool = game.is_night
	beam.visible = driving and night
	beam.light_energy = 3.2
	head_mat.emission_energy_multiplier = (2.5 if night else 0.6) if driving else 0.15
	tail_mat.emission_energy_multiplier = 2.2 if braking else (0.9 if driving and night else 0.25)

	# interaction points follow the truck
	var f := fwd()
	var left := Vector2(f.y, -f.x)
	door_item.pos = Vector3(pos.x + f.x * 2.5 + left.x * 1.35, 1.6, pos.y + f.y * 2.5 + left.y * 1.35)
	rear_item.pos = Vector3(pos.x - f.x * 4.0, 1.4, pos.y - f.y * 4.0)
	var used := cargo.size()
	if in_depot() and used > 0:
		rear_item.prompt = "[E] Unload %d parcels into the depot" % used
	elif game.backpack.size() > 0:
		rear_item.prompt = "[E] Load backpack into the truck (%d/%d)" % [used, CAPACITY]
	elif used > 0:
		rear_item.prompt = "[E] Take parcels out of the truck (%d/%d)" % [used, CAPACITY]
	else:
		rear_item.prompt = "Truck cargo: empty (0/%d)" % CAPACITY
	door_item.prompt = "" if driving else "[E] Drive the delivery truck"
	if driving:
		_update_camera(dt)


func _sync() -> void:
	transform = Transform3D(Basis(Vector3.UP, -heading), Vector3(pos.x, 0, pos.y))
	for w in wheels:
		w.pivot.rotation.y = steer if w.steerable else 0.0
		w.spin.rotation.z = wheel_spin


func _update_camera(dt: float) -> void:
	var P = game.player
	var cam: Camera3D = P.camera
	var f := fwd()
	if view == "chase":
		var back := 10.0 + absf(speed) * 0.15
		var want := Vector3(pos.x - f.x * back, 4.4, pos.y - f.y * back)
		cam_pos = cam_pos.lerp(want, 1.0 - exp(-dt * 5.0))
		cam.global_transform = Transform3D(Basis(), cam_pos).looking_at(Vector3(pos.x + f.x * 4.0, 1.6, pos.y + f.y * 4.0))
		P.yaw = -heading - PI / 2
	else:
		var left := Vector2(f.y, -f.x)
		var eye := Vector3(pos.x + f.x * 2.35 + left.x * 0.5, 2.55, pos.y + f.y * 2.35 + left.y * 0.5)
		cam.global_transform = Transform3D(Basis(Vector3.UP, P.yaw) * Basis(Vector3.RIGHT, P.pitch), eye)
	# the player rides along (minimap, lamps, ducks all follow); the camera keeps the view set above
	var keep := cam.global_transform
	P.global_position = Vector3(pos.x, 0.1, pos.y)
	cam.global_transform = keep


func drive_text() -> String:
	var e := "[E] Unload %d parcels into the depot" % cargo.size() if in_depot() and not cargo.is_empty() else "[E] Get out"
	return "%d km/h - Cargo %d/%d - %s - [V] Camera" % [roundi(absf(speed) * 3.6), cargo.size(), CAPACITY, e]
