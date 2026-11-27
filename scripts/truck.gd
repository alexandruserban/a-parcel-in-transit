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
var cab_light: OmniLight3D
var steer_wheel: Node3D
var ind_mat: Array = []
var reverse_mat: StandardMaterial3D
var marker_mat: StandardMaterial3D
var wipers: Array[Node3D] = []
var wipers_on := false
var _wipe_phase := 0.0
var _blink := 0.0
var steer_tilt := Basis()
const WHEEL_RATIO := 4.5   # steering-wheel turn per radian of road-wheel steer
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
	# see-through windscreen and side windows (from the cab you look out through them)
	var glass := _std(Color(Color("#9db3bf"), 0.16), 0.03, 0.2)   # clear enough to see the cab inside
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rubber := _std(Color("#1b1b1c"), 0.88)
	var hub := _std(Color("#c4c7ca"), 0.38, 0.55)   # painted steel rims
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
	var chrome := _std(Color("#d5d8dc"), 0.2, 0.95)
	ind_mat = [_lamp(Color("#ffb300")), _lamp(Color("#ffb300"))]   # left, right indicators
	reverse_mat = _lamp(Color("#ffffff"))
	marker_mat = _lamp(Color("#ffa000"))
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
	# (faces that would cut through the cab interior are left out: _cab_interior lines it from inside)
	B.call(1.62, 1.25, 2.3, [null, paint, null, paint, null, null], 2.31, 1.45, 0)      # cab, below the windows
	_wheel_arches(b, paint, dark)
	B.call(0.48, 1.25, 2.3, [paint, null, paint, paint, paint, paint], 3.36, 1.45, 0)   # bonnet
	# upper cab as panels with real openings for the windscreen and side windows (see-through from outside)
	var UX0 := 1.5
	var UX1 := 3.2
	var UY0 := 2.075
	var UY1 := 3.025
	var UZ := 1.15
	var pq := func(a: Vector3, c: Vector3, d: Vector3, e: Vector3, n: Vector3) -> void:
		b.quad(I, a, c, d, e, paint, n, 1.0, true)
	pq.call(Vector3(UX0, UY1, -UZ), Vector3(UX1, UY1, -UZ), Vector3(UX1, UY1, UZ), Vector3(UX0, UY1, UZ), Vector3.UP)
	var front_panel := func(z0: float, z1: float, y0: float, y1: float) -> void:
		pq.call(Vector3(UX1, y0, z0), Vector3(UX1, y0, z1), Vector3(UX1, y1, z1), Vector3(UX1, y1, z0), Vector3.RIGHT)
	front_panel.call(-UZ, UZ, UY0, 2.1)
	front_panel.call(-UZ, UZ, 2.9, UY1)
	front_panel.call(-UZ, -0.98, 2.1, 2.9)
	front_panel.call(0.98, UZ, 2.1, 2.9)
	for s in [-1.0, 1.0]:
		var z: float = s * UZ
		var n := Vector3(0, 0, s)
		var side_panel := func(x0: float, x1: float, y0: float, y1: float) -> void:
			pq.call(Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z), n)
		side_panel.call(UX0, UX1, UY0, 2.18)
		side_panel.call(UX0, UX1, 2.82, UY1)
		side_panel.call(UX0, 1.98, 2.18, 2.82)
		side_panel.call(2.92, UX1, 2.18, 2.82)
	B.call(1.3, 0.5, 2.2, paint, 2.0, 3.1, 0, -0.25)
	for k in 3:   # amber marker lights along the top of the cab
		B.call(0.06, 0.06, 0.16, marker_mat, 2.62, 3.24, (k - 1) * 0.45, -0.25)
	B.call(2.12, 0.16, 2.32, [orange, orange, null, null, orange, orange], 2.55, 1.6, 0)
	B.call(5.22, 0.16, 2.48, orange, -1.1, 1.15, 0)
	B.call(0.05, 0.85, 2.05, glass, 3.25, 2.5, 0, 0.18)
	for s in [-1.0, 1.0]:
		B.call(1.0, 0.7, 0.03, glass, 2.45, 2.5, s * 1.16)
	B.call(0.06, 0.55, 1.5, dark, 3.62, 1.25, 0)
	for k in 4:
		B.call(0.07, 0.04, 1.45, grille, 3.64, 1.05 + k * 0.13, 0)
	# lights, mirrors, step, mud flaps
	for s in [-1.0, 1.0]:
		var lamp_axis := Basis(Vector3.BACK, -PI / 2)   # cylinders facing forward (+x)
		b.cylinder(Transform3D(lamp_axis, Vector3(3.6, 1.35, s * 0.82)), Vector3.ZERO, 0.17, 0.17, 0.05, 20, chrome)
		b.cylinder(Transform3D(lamp_axis, Vector3(3.63, 1.35, s * 0.82)), Vector3.ZERO, 0.14, 0.14, 0.03, 20, head_mat)
		B.call(0.05, 0.12, 0.16, ind_mat[0 if s < 0 else 1], 3.62, 1.35, s * 1.06)      # front indicator
		B.call(0.05, 0.3, 0.14, tail_mat, -3.75, 1.0, s * 1.08)
		B.call(0.05, 0.12, 0.14, ind_mat[0 if s < 0 else 1], -3.75, 1.24, s * 1.08)     # rear indicator
		B.call(0.05, 0.1, 0.14, reverse_mat, -3.75, 0.8, s * 1.08)                      # reversing light
		B.call(0.06, 0.06, 0.12, ind_mat[0 if s < 0 else 1], 2.0, 1.45, s * 1.17)       # side repeater
		B.call(0.06, 0.3, 0.16, dark, 3.0, 2.45, s * 1.32)
		B.call(0.4, 0.06, 0.25, dark, 1.75, 0.6, s * 1.2)      # cab step, behind the front wheel
		# rear mudguard over the twin wheels, and a rubber mud flap hanging behind them
		for k in 16:
			var a := PI * (0.12 + 0.76 * k / 15.0)
			B.call(0.16, 0.03, 0.7, dark, -2.3 + cos(a) * 0.62, 0.5 + sin(a) * 0.62, s * 1.08, a - PI / 2)
		B.call(0.025, 0.55, 0.66, dark, -2.98, 0.5, s * 1.08)
	_cab_interior(b)
	b.commit(self)
	_build_wipers(dark)

	# wheels: steerable fronts, dual rears; every wheel shares one mesh, its dished face turned outwards
	var wheel_mesh := _wheel_mesh(rubber, hub, chrome)
	for s in [-1.0, 1.0]:
		for w in [[2.55, s * 1.0, true], [-2.3, s * 0.92, false], [-2.3, s * 1.24, false]]:
			var pivot := Node3D.new()
			pivot.position = Vector3(w[0], 0.5, w[1])
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var mi := MeshInstance3D.new()
			mi.mesh = wheel_mesh
			if s < 0.0:
				mi.basis = Basis(Vector3.UP, PI)
			spin.add_child(mi)
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


## The cab from the inside: trimmed walls, headliner and floor facing inwards, with openings that line up with
## the windscreen and side windows and reveals that close the gap to the glass, a dashboard with gauges, the
## steering wheel on its column, a centre console and two seats. (The outside boxes are invisible from within.)
const CX0 := 1.58     # back wall
const CX1 := 3.12     # front wall (the windscreen glass leans just beyond it)
const CY0 := 1.0      # floor
const CY1 := 2.98     # headliner
const CZ := 1.1       # side walls
const WS := [2.1, 2.9, 0.98]            # windscreen opening: bottom, top, half width
const SW := [1.98, 2.92, 2.18, 2.82]    # side window openings: x0, x1, y0, y1

func _cab_interior(b) -> void:
	var trim := _std(Color("#4b4f55"), 0.85)
	var dash := _std(Color("#24262a"), 0.7)
	var head := _std(Color("#9a9c9f"), 0.95)
	var floor_m := _std(Color("#1a1b1d"), 0.95)
	var seat := _std(Color("#2c3440"), 0.9)
	var chrome := _std(Color("#c9ccd0"), 0.25, 0.9)
	var gauge := _std(Color("#20262d"), 0.3)
	gauge.emission_enabled = true
	gauge.emission = Color("#6fc3ff")
	gauge.emission_energy_multiplier = 0.35
	var I := Transform3D.IDENTITY
	var q := func(a: Vector3, c: Vector3, d: Vector3, e: Vector3, mat: Material, n: Vector3) -> void:
		b.quad(I, a, c, d, e, mat, n, 1.0, false)
	# floor and headliner
	q.call(Vector3(CX0, CY0, -CZ), Vector3(CX1, CY0, -CZ), Vector3(CX1, CY0, CZ), Vector3(CX0, CY0, CZ), floor_m, Vector3.UP)
	q.call(Vector3(CX0, CY1, -CZ), Vector3(CX1, CY1, -CZ), Vector3(CX1, CY1, CZ), Vector3(CX0, CY1, CZ), head, Vector3.DOWN)
	# back wall
	q.call(Vector3(CX0, CY0, -CZ), Vector3(CX0, CY0, CZ), Vector3(CX0, CY1, CZ), Vector3(CX0, CY1, -CZ), trim, Vector3.RIGHT)
	# front wall round the windscreen opening (in z, y), facing back into the cab
	var fw := func(z0: float, z1: float, y0: float, y1: float) -> void:
		q.call(Vector3(CX1, y0, z0), Vector3(CX1, y0, z1), Vector3(CX1, y1, z1), Vector3(CX1, y1, z0), trim, Vector3.LEFT)
	fw.call(-CZ, CZ, CY0, WS[0])
	fw.call(-CZ, CZ, WS[1], CY1)
	fw.call(-CZ, -WS[2], WS[0], WS[1])
	fw.call(WS[2], CZ, WS[0], WS[1])
	# windscreen reveals out to the leaning glass (A-pillars, header, sill)
	var gx := 3.36
	q.call(Vector3(CX1, WS[0], -WS[2]), Vector3(gx, WS[0], -WS[2]), Vector3(gx, WS[1], -WS[2]), Vector3(CX1, WS[1], -WS[2]), trim, Vector3.BACK)
	q.call(Vector3(CX1, WS[0], WS[2]), Vector3(gx, WS[0], WS[2]), Vector3(gx, WS[1], WS[2]), Vector3(CX1, WS[1], WS[2]), trim, Vector3.FORWARD)
	q.call(Vector3(CX1, WS[1], -WS[2]), Vector3(gx, WS[1], -WS[2]), Vector3(gx, WS[1], WS[2]), Vector3(CX1, WS[1], WS[2]), trim, Vector3.DOWN)
	q.call(Vector3(CX1, WS[0], -WS[2]), Vector3(gx, WS[0], -WS[2]), Vector3(gx, WS[0], WS[2]), Vector3(CX1, WS[0], WS[2]), dash, Vector3.UP)
	# side walls with the window openings, and their reveals out to the glass
	for s in [-1.0, 1.0]:
		var z: float = s * CZ
		var n := Vector3(0, 0, -s)
		var sw := func(x0: float, x1: float, y0: float, y1: float) -> void:
			q.call(Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z), trim, n)
		sw.call(CX0, CX1, CY0, SW[2])
		sw.call(CX0, CX1, SW[3], CY1)
		sw.call(CX0, SW[0], SW[2], SW[3])
		sw.call(SW[1], CX1, SW[2], SW[3])
		var zo: float = s * 1.18
		q.call(Vector3(SW[0], SW[2], z), Vector3(SW[0], SW[2], zo), Vector3(SW[0], SW[3], zo), Vector3(SW[0], SW[3], z), trim, Vector3.RIGHT)
		q.call(Vector3(SW[1], SW[2], z), Vector3(SW[1], SW[2], zo), Vector3(SW[1], SW[3], zo), Vector3(SW[1], SW[3], z), trim, Vector3.LEFT)
		q.call(Vector3(SW[0], SW[3], z), Vector3(SW[1], SW[3], z), Vector3(SW[1], SW[3], zo), Vector3(SW[0], SW[3], zo), trim, Vector3.DOWN)
		q.call(Vector3(SW[0], SW[2], z), Vector3(SW[1], SW[2], z), Vector3(SW[1], SW[2], zo), Vector3(SW[0], SW[2], zo), trim, Vector3.UP)
		# door card: armrest and a handle under the window
		b.box(I, Vector3(2.45, 1.75, s * (CZ - 0.05)), Vector3(0.7, 0.07, 0.1), dash, 1.0, false)
		b.box(I, Vector3(2.85, 1.95, s * (CZ - 0.03)), Vector3(0.14, 0.04, 0.05), chrome, 1.0, false)
	# dashboard: a deep moulding under the windscreen, the instrument binnacle and gauges, vents
	b.box(I, Vector3(2.93, 1.55, 0), Vector3(0.38, 1.1, 2.18), dash, 1.0, false, true)
	b.box(I, Vector3(2.8, 2.06, 0), Vector3(0.2, 0.04, 2.18), dash, 1.0, false)          # padded top edge
	b.box(I, Vector3(2.82, 2.13, -0.5), Vector3(0.18, 0.12, 0.62), dash, 1.0, false)     # binnacle hood
	for gz in [-0.66, -0.34]:
		b.cylinder(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(2.73, 2.02, gz)), Vector3.ZERO, 0.065, 0.065, 0.01, 18, gauge, true, 1.0, false)
	for vz in [-0.95, 0.15, 0.95]:
		b.box(I, Vector3(2.73, 1.92, vz), Vector3(0.02, 0.1, 0.22), floor_m, 1.0, false)
	# steering wheel on its column, leaning back towards the driver
	var tilt := Basis(Vector3.BACK, -0.5)
	var hub := Vector3(2.55, 1.98, -0.5)
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.17
	wheel.outer_radius = 0.22
	wheel.rings = 28
	wheel.ring_segments = 8
	# the rim, spokes and boss are their own node, so the wheel turns with the steering (_sync)
	steer_wheel = Node3D.new()
	steer_wheel.transform = Transform3D(tilt, hub)
	steer_tilt = tilt
	add_child(steer_wheel)
	var wb := Batch.new()
	wb.mesh(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3.ZERO), wheel, dash, false)
	for k in 3:   # spokes
		var a := k * TAU / 3 + PI / 2
		wb.box(Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO), Vector3(0, 0.1, 0), Vector3(0.025, 0.19, 0.04), dash, 1.0, false)
	wb.cylinder(Transform3D(Basis(Vector3.BACK, PI / 2), Vector3.ZERO), Vector3.ZERO, 0.06, 0.06, 0.05, 12, dash, true, 1.0, false)
	wb.box(Transform3D.IDENTITY, Vector3(-0.012, 0.205, 0), Vector3(0.03, 0.03, 0.06), chrome, 1.0, false)   # a marker at the top of the rim
	wb.commit(steer_wheel)
	b.cylinder(Transform3D(tilt * Basis(Vector3.BACK, -PI / 2), hub), Vector3.ZERO, 0.035, 0.045, 0.42, 10, dash, false, 1.0, false)
	# centre console with a gear selector, and two seats behind you
	b.box(I, Vector3(2.35, 1.3, 0.0), Vector3(0.9, 0.6, 0.32), dash, 1.0, false)
	b.box(I, Vector3(2.45, 1.66, 0.0), Vector3(0.06, 0.14, 0.06), chrome, 1.0, false)
	for sz in [-0.5, 0.55]:
		b.box(I, Vector3(2.1, 1.45, sz), Vector3(0.55, 0.14, 0.55), seat, 1.0, false)
		b.box(I, Vector3(1.8, 1.95, sz), Vector3(0.14, 0.9, 0.55), seat, 1.0, false)
		b.box(I, Vector3(1.8, 2.5, sz), Vector3(0.12, 0.22, 0.3), seat, 1.0, false)
		b.box(I, Vector3(2.1, 1.2, sz), Vector3(0.4, 0.36, 0.4), floor_m, 1.0, false)
	# rear-view mirror at the top of the windscreen
	b.box(I, Vector3(3.0, 2.82, 0.1), Vector3(0.03, 0.08, 0.26), dash, 1.0, false)
	# soft courtesy light, on while you sit in the cab (the roof shades the inside otherwise)
	cab_light = OmniLight3D.new()
	cab_light.light_color = Color("#ffe9cc")
	cab_light.light_energy = 0.9
	cab_light.omni_range = 3.2
	cab_light.position = Vector3(2.3, 2.85, 0)
	cab_light.visible = false
	add_child(cab_light)


## A lamp lens: its colour, lit by emission (0 = off)
func _lamp(col: Color) -> StandardMaterial3D:
	var m := _std(col.darkened(0.45), 0.25)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.0
	return m


## Two wipers on the windscreen, pivoting at its foot; they lie flat along the bottom when parked
func _build_wipers(dark: Material) -> void:
	var glass_frame := Basis(Vector3.BACK, 0.18)        # the windscreen leans back by this much
	for pz in [-0.5, 0.45]:
		var foot := Vector3(3.25, 2.5, 0) + glass_frame * Vector3(0, -0.4, 0)
		var w := Node3D.new()
		w.transform = Transform3D(glass_frame, foot + glass_frame * Vector3(0.05, 0, pz))
		add_child(w)
		var wb := Batch.new()
		wb.cylinder(Transform3D(Basis(Vector3.BACK, -PI / 2), Vector3.ZERO), Vector3.ZERO, 0.035, 0.035, 0.04, 10, dark)
		wb.box(Transform3D.IDENTITY, Vector3(0, 0, 0.36), Vector3(0.02, 0.025, 0.72), dark, 1.0, false)    # arm
		wb.box(Transform3D.IDENTITY, Vector3(0.012, 0, 0.62), Vector3(0.015, 0.03, 0.5), dark, 1.0, false)  # blade
		wb.commit(w)
		w.set_meta("rest", w.transform)
		wipers.append(w)


func toggle_wipers() -> void:
	wipers_on = not wipers_on
	game.sfx.play("click")


## Cab sides below the windows with arched cut-outs over the front wheels, a dark liner inside each arch and a
## black trim round its edge (the wheel turns inside the arch instead of vanishing into the body)
func _wheel_arches(b, paint: Material, dark: Material) -> void:
	var X0 := 1.5
	var X1 := 3.12
	var Y0 := 0.825
	var Y1 := 2.075
	var C := Vector2(2.55, 0.5)
	var R := 0.6
	var a0 := asin((Y0 - C.y) / R)        # where the arch meets the bottom edge of the cab
	var arc := PackedVector2Array()
	var arc_out := PackedVector2Array()
	var N := 18
	for k in N + 1:
		var a := PI - a0 - (PI - 2.0 * a0) * k / N
		arc.append(C + Vector2(cos(a), sin(a)) * R)
		arc_out.append(C + Vector2(cos(a), sin(a)) * (R + 0.07))
	var outline := PackedVector2Array([Vector2(X0, Y0)])
	outline.append_array(arc)
	outline.append_array(PackedVector2Array([Vector2(X1, Y0), Vector2(X1, Y1), Vector2(X0, Y1)]))
	var liner := _std(Color("#141516"), 0.95)
	liner.cull_mode = BaseMaterial3D.CULL_DISABLED
	for s in [-1.0, 1.0]:
		var z: float = s * 1.15
		# the side panel: polygon facing +z, turned round for the -z side (mirrored outline)
		if s > 0:
			b.polygon(Transform3D(Basis(), Vector3(0, 0, z)), outline, paint, 1.0, true)
		else:
			var rev := PackedVector2Array()
			for i in range(outline.size() - 1, -1, -1):
				rev.append(Vector2(-outline[i].x, outline[i].y))
			b.polygon(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, z)), rev, paint, 1.0, true)
		# liner: the arch surface from the side panel in to the chassis
		for k in N:
			var p0: Vector2 = arc[k]
			var p1: Vector2 = arc[k + 1]
			b.quad(Transform3D.IDENTITY, Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z), Vector3(p1.x, p1.y, s * 0.7), Vector3(p0.x, p0.y, s * 0.7), liner, Vector3.ZERO, 1.0, false)
		# black trim standing a little proud of the panel
		var f := Transform3D(Basis(), Vector3(0, 0, z + s * 0.015))
		b.strip(f, arc_out, arc, dark, Vector3(0, 0, s))
		for k in N:
			var p0: Vector2 = arc_out[k]
			var p1: Vector2 = arc_out[k + 1]
			b.quad(Transform3D.IDENTITY, Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z), Vector3(p1.x, p1.y, z + s * 0.015), Vector3(p0.x, p0.y, z + s * 0.015), dark, Vector3((p0.x + p1.x) / 2 - C.x, (p0.y + p1.y) / 2 - C.y, 0), 1.0, false)


## A lathe surface spun round the z axis from a profile of (radius, z) points; a repeated point makes a crease.
## The profile runs so that its outside is on the right of the direction of travel (as seen with r up, z right).
## mod(r, z, angle) -> r reshapes the surface (tread blocks).
static func _lathe_z(st: SurfaceTool, prof: Array, segs: int, mod := Callable()) -> void:
	var n := prof.size()
	var base := 0
	var groups := PackedInt32Array()   # a new smoothing group after each repeated point: a hard edge there
	var g := 0
	for i in n:
		if i > 0 and prof[i] == prof[i - 1]:
			g += 1
		groups.append(g)
	for j in segs:
		var a := TAU * j / segs
		for i in n:
			var p: Vector2 = prof[i]
			var r: float = mod.call(p.x, p.y, a) if mod.is_valid() else p.x
			st.set_smooth_group(groups[i])
			st.add_vertex(Vector3(cos(a) * r, sin(a) * r, p.y))
	for j in segs:
		var j2 := (j + 1) % segs
		for i in n - 1:
			var a := base + j * n + i
			var b := base + j2 * n + i
			var c := b + 1
			var d := a + 1
			for k in [a, d, b, b, d, c]:
				st.add_index(k)


## Truck wheel: a tyre with rounded shoulders, two circumferential grooves, slanted shoulder blocks and a raised
## sidewall ring, on a deeply dished steel rim with vent holes, a raised hub, ten wheel nuts and a centre cap.
## The outer face looks towards +z. One ArrayMesh, a surface per material.
func _wheel_mesh(rubber: Material, rim: Material, chrome: Material) -> ArrayMesh:
	var out := ArrayMesh.new()
	# tyre: from the inner bead round the tread to the outer bead
	var half := [Vector2(0.300, -0.120), Vector2(0.318, -0.140), Vector2(0.350, -0.156), Vector2(0.400, -0.164),
		Vector2(0.420, -0.166), Vector2(0.428, -0.173), Vector2(0.438, -0.173), Vector2(0.446, -0.166),
		Vector2(0.470, -0.158), Vector2(0.488, -0.142), Vector2(0.497, -0.122),
		Vector2(0.500, -0.105), Vector2(0.500, -0.064), Vector2(0.486, -0.060), Vector2(0.486, -0.036), Vector2(0.500, -0.032)]
	var prof := half.duplicate()
	for i in range(half.size() - 1, -1, -1):
		prof.append(Vector2(half[i].x, -half[i].y))
	var tread := func(r: float, z: float, a: float) -> float:
		if r < 0.495 or absf(z) < 0.062:
			return r
		var u := a * 34.0 / TAU + (absf(z) - 0.06) * 6.0 * signf(z)   # slanted blocks, a chevron across the tread
		return r - 0.016 if fposmod(u, 1.0) < 0.3 else r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe_z(st, prof, 170, tread)
	st.generate_normals()
	st.set_material(rubber)
	st.commit(out)
	# steel rim: the back plate, the barrel hidden in the tyre, the flange, the dish, the hub and the centre cap
	var rp := [Vector2(0.0, -0.105), Vector2(0.27, -0.105), Vector2(0.27, -0.105), Vector2(0.30, -0.128),
		Vector2(0.312, -0.13), Vector2(0.312, 0.118), Vector2(0.312, 0.118), Vector2(0.320, 0.128), Vector2(0.306, 0.137),
		Vector2(0.292, 0.128), Vector2(0.286, 0.10), Vector2(0.283, 0.072), Vector2(0.283, 0.072), Vector2(0.256, 0.056),
		Vector2(0.21, 0.050), Vector2(0.182, 0.054), Vector2(0.168, 0.072), Vector2(0.168, 0.072), Vector2(0.125, 0.080),
		Vector2(0.098, 0.084), Vector2(0.098, 0.084), Vector2(0.092, 0.104), Vector2(0.070, 0.118), Vector2(0.070, 0.118),
		Vector2(0.066, 0.126), Vector2(0.040, 0.132), Vector2(0.0, 0.134)]
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe_z(st, rp, 48)
	st.generate_normals()
	st.set_material(rim)
	st.commit(out)
	# vent holes in the dish (dark ovals) and the wheel nuts round the hub
	var holes := SurfaceTool.new()
	holes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hole := CylinderMesh.new()
	hole.top_radius = 0.034
	hole.bottom_radius = 0.034
	hole.height = 0.004
	hole.radial_segments = 14
	hole.rings = 1
	var axle := Basis(Vector3.RIGHT, PI / 2)
	for k in 8:
		var a := TAU * (k + 0.5) / 8
		var hb := Basis(Vector3.BACK, a) * axle * Basis.from_scale(Vector3(1.0, 1.0, 1.45))
		holes.append_from(hole, 0, Transform3D(hb, Vector3(cos(a) * 0.226, sin(a) * 0.226, 0.054)))
	holes.set_material(_std(Color("#0b0b0c"), 0.95))
	holes.commit(out)
	var nuts := SurfaceTool.new()
	nuts.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nut := CylinderMesh.new()
	nut.top_radius = 0.017
	nut.bottom_radius = 0.019
	nut.height = 0.042
	nut.radial_segments = 6
	nut.rings = 1
	var stud := CylinderMesh.new()
	stud.top_radius = 0.008
	stud.bottom_radius = 0.008
	stud.height = 0.02
	stud.radial_segments = 8
	stud.rings = 1
	for k in 10:
		var a := TAU * k / 10
		var p := Vector3(cos(a) * 0.132, sin(a) * 0.132, 0.096)
		nuts.append_from(nut, 0, Transform3D(Basis(Vector3.BACK, a) * axle, p))
		nuts.append_from(stud, 0, Transform3D(axle, p + Vector3(0, 0, 0.026)))
	nuts.set_material(chrome)
	nuts.commit(out)
	return out


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
	game.player.pitch = -0.15 if view == "cab" else 0.0   # glancing down over the dashboard


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
	cab_light.visible = driving and view == "cab"
	beam.light_energy = 3.2
	head_mat.emission_energy_multiplier = (2.5 if night else 0.6) if driving else 0.15
	# indicators blink on the side you're steering towards; hazards blink both while parked with cargo aboard
	_blink += dt
	var on := fmod(_blink, 0.8) < 0.4
	var turn_l := driving and steer > 0.12
	var turn_r := driving and steer < -0.12
	(ind_mat[0] as StandardMaterial3D).emission_energy_multiplier = 3.0 if turn_l and on else 0.0
	(ind_mat[1] as StandardMaterial3D).emission_energy_multiplier = 3.0 if turn_r and on else 0.0
	reverse_mat.emission_energy_multiplier = 2.5 if driving and speed < -0.3 else 0.0
	marker_mat.emission_energy_multiplier = 2.0 if driving and night else 0.0
	# wipers sweep back and forth when switched on, or by themselves in grey weather while you drive
	var wiping: bool = wipers_on or (driving and game.sky.weather > 0.5)
	if wiping or _wipe_phase > 0.0:
		_wipe_phase += dt * 2.6
		if not wiping and fmod(_wipe_phase, TAU) < dt * 2.6 * 1.5:
			_wipe_phase = 0.0   # finish the stroke, then park
		var a := -1.65 * (0.5 - 0.5 * cos(_wipe_phase))
		for w in wipers:
			w.transform = (w.get_meta("rest") as Transform3D) * Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO)
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
	if steer_wheel != null:   # turning left winds the wheel anticlockwise, as the driver sees it
		steer_wheel.basis = steer_tilt * Basis(Vector3.RIGHT, -steer * WHEEL_RATIO)


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
		var eye := Vector3(pos.x + f.x * 2.05 + left.x * 0.5, 2.45, pos.y + f.y * 2.05 + left.y * 0.5)   # driver's seat
		cam.global_transform = Transform3D(Basis(Vector3.UP, P.yaw) * Basis(Vector3.RIGHT, P.pitch), eye)
	# the player rides along (minimap, lamps, ducks all follow); the camera keeps the view set above
	var keep := cam.global_transform
	P.global_position = Vector3(pos.x, 0.1, pos.y)
	cam.global_transform = keep


func drive_text() -> String:
	var unload := in_depot() and not cargo.is_empty()
	if game.mobile:   # touch buttons: Use, Cam, Horn, Wipers
		var u := "Use: unload %d parcels" % cargo.size() if unload else "Use: get out"
		return "%d km/h - Cargo %d/%d - %s" % [roundi(absf(speed) * 3.6), cargo.size(), CAPACITY, u]
	var e := "[E] Unload %d parcels into the depot" % cargo.size() if unload else "[E] Get out"
	return "%d km/h - Cargo %d/%d - %s - [V] Camera - [R] Wipers" % [roundi(absf(speed) * 3.6), cargo.size(), CAPACITY, e]
