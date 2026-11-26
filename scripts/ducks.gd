extends Node3D
## Mallards on the ponds, ported from ducks.js: drakes (glossy green head, white collar, chestnut breast, grey
## body, curled black tail) and hens (mottled brown, orange bill), plus a hen with a line of ducklings on the
## park pond. They wander, rest, tip up to dabble, bob their heads as they paddle, leave spreading ripples
## and quack when you are near.

var world
var sfx
var lakes: Array = []      # [{lake: Dictionary, sim: Array, quack: float}]
var time := 0.0
var rng := RandomNumberGenerator.new()
var M := {}
var ripple_mesh: ArrayMesh


func build() -> void:
	rng.seed = 777
	_materials()
	ripple_mesh = _ring_mesh(0.85, 1.0, 32)
	for li in world.lakes.size():
		var lake: Dictionary = world.lakes[li]
		var entry := {"lake": lake, "sim": [], "quack": 4.0 + rng.randf() * 8.0}
		lakes.append(entry)
		for kind in ["drake", "hen", "drake", "hen"]:
			_spawn(entry, kind, null)
		if li == 0:
			var mum: Dictionary = _spawn(entry, "hen", null)
			var prev := mum
			for i in 5:
				prev = _spawn(entry, "duckling", prev)


func _std(color: Color, rough: float, metal := 0.0, tex := "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if tex != "":
		m.albedo_texture = world.tex(tex)
	return m


func _materials() -> void:
	M.drake_body = _std(Color.WHITE, 0.85, 0.0, "feather_drake_col")
	M.drake_head = _std(Color("#1d5a33"), 0.28, 0.35)
	M.chest = _std(Color("#5e3420"), 0.75)
	M.dark = _std(Color("#1c1c1e"), 0.6)
	M.white = _std(Color("#f2f2ee"), 0.7)
	M.hen = _std(Color.WHITE, 0.9, 0.0, "feather_hen_col")
	M.duckling = _std(Color.WHITE, 1.0, 0.0, "feather_duckling_col")
	M.bill_y = _std(Color("#d8b23a"), 0.5)
	M.bill_o = _std(Color("#c7792c"), 0.55)
	M.eye = _std(Color("#0a0a0a"), 0.15, 0.3)
	M.speculum = _std(Color("#3550b0"), 0.3, 0.4)
	var r := StandardMaterial3D.new()
	r.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r.albedo_color = Color(Color("#e8f2f6"), 0.32)
	r.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r.cull_mode = BaseMaterial3D.CULL_DISABLED
	M.ripple = r


var _mesh_cache := {}
func _sphere(r: float, segs := 16, rings := 10) -> Mesh:
	var key := "s%f" % r
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = segs
		m.rings = rings
		_mesh_cache[key] = m
	return _mesh_cache[key]


func _cyl(r_top: float, r_bot: float, h: float, segs := 12) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


## three.js TorusGeometry(radius, tube) lies in the XY plane; Godot's TorusMesh lies in XZ
func _torus(radius: float, tube: float) -> Mesh:
	var m := TorusMesh.new()
	m.inner_radius = radius - tube
	m.outer_radius = radius + tube
	m.rings = 20
	m.ring_segments = 6
	return m


func _box(w: float, h: float, d: float) -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, d)
	return m


## Euler XYZ as three.js composes it (Rx * Ry * Rz)
static func _rot(x: float, y: float, z: float) -> Basis:
	return Basis(Vector3.RIGHT, x) * Basis(Vector3.UP, y) * Basis(Vector3.BACK, z)


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, rot := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(rot * Basis.from_scale(scl), pos)
	parent.add_child(mi)
	return mi


## A mallard facing +x, water line at y = 0 (buildDuckModel)
func _model(kind: String) -> Node3D:
	var drake := kind == "drake"
	var baby := kind == "duckling"
	var body_mat: Material = M.drake_body if drake else (M.duckling if baby else M.hen)
	var g := Node3D.new()
	var inner := Node3D.new()   # carries the duckling scale so the root can be posed freely
	g.add_child(inner)
	if baby:
		inner.scale = Vector3.ONE * 0.42
	# body: long, boat-shaped, sitting low in the water
	_add(inner, _sphere(0.2, 20, 14), body_mat, Vector3(0, 0.05, 0), Vector3(1.45, 0.62, 0.8))
	if drake:
		_add(inner, _sphere(0.12), M.chest, Vector3(0.16, 0.08, 0), Vector3(1.0, 0.95, 1.15))
	# tail: tapering point lifted up; drakes have black tail coverts with the curl
	_add(inner, _cyl(0.0, 0.075, 0.2, 10), M.dark if drake else body_mat, Vector3(-0.3, 0.1, 0), Vector3(1, 1, 0.6), _rot(0, 0, PI / 2 + 0.35))
	if drake:
		_add(inner, _sphere(0.06, 10, 8), M.white, Vector3(-0.22, 0.08, 0), Vector3(1.2, 0.8, 1.1))
		_add(inner, _torus(0.025, 0.006), M.dark, Vector3(-0.31, 0.19, 0), Vector3.ONE, _rot(0, PI / 2, 0) * _rot(PI / 2, 0, 0))
	# folded wings with the blue speculum
	if not baby:
		for s in [-1.0, 1.0]:
			_add(inner, _sphere(0.17, 14, 10), M.drake_body if drake else M.hen, Vector3(-0.05, 0.13, s * 0.1), Vector3(1.55, 0.32, 0.5), _rot(s * 0.12, 0, 0))
			_add(inner, _box(0.09, 0.03, 0.01), M.speculum, Vector3(-0.12, 0.13, s * 0.165))
	# neck and head (the head is its own node so it can bob)
	_add(inner, _cyl(0.045, 0.06, 0.15), M.drake_head if drake else body_mat, Vector3(0.2, 0.17, 0), Vector3.ONE, _rot(0, 0, -0.35))
	var head := Node3D.new()
	head.position = Vector3(0.24, 0.27, 0)
	inner.add_child(head)
	_add(head, _sphere(0.072), M.drake_head if drake else body_mat, Vector3.ZERO, Vector3(1.25, 0.95, 0.92))
	if drake:
		_add(head, _torus(0.05, 0.009), M.white, Vector3(-0.035, -0.07, 0), Vector3.ONE, _rot(PI / 2, -0.35, 0) * _rot(PI / 2, 0, 0))
	elif not baby:
		_add(head, _box(0.1, 0.012, 0.13), M.dark, Vector3(0.03, 0.012, 0))   # dark eye-stripe
	_add(head, _sphere(0.048, 12, 8), M.bill_y if drake else M.bill_o, Vector3(0.1, -0.018, 0), Vector3(1.55, 0.32, 0.75))
	for s in [-1.0, 1.0]:
		_add(head, _sphere(0.011, 8, 6), M.eye, Vector3(0.04, 0.018, s * 0.058))
	g.set_meta("head", head)
	return g


func _ring_mesh(r0: float, r1: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p := [Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a0) * r1, 0, sin(a0) * r1),
			Vector3(cos(a1) * r1, 0, sin(a1) * r1), Vector3(cos(a1) * r0, 0, sin(a1) * r0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(p[k])
	return st.commit()


func _spawn(entry: Dictionary, kind: String, leader) -> Dictionary:
	var lake: Dictionary = entry.lake
	var g := _model(kind)
	add_child(g)
	var a := rng.randf() * TAU
	var r := 0.2 + rng.randf() * 0.45
	var pos := Vector2(lake.cx + cos(a) * lake.rw * r, lake.cz + sin(a) * lake.rd * r)
	g.position = Vector3(pos.x, world.WATER_Y, pos.y)
	# two ripple rings that spread from the duck as it paddles
	var ripples: Array = []
	for k in 2:
		var rm := MeshInstance3D.new()
		rm.mesh = ripple_mesh
		rm.material_override = M.ripple
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rm.visible = false
		add_child(rm)
		ripples.append({"mesh": rm, "t": float(k), "active": false})
	var d := {"g": g, "kind": kind, "pos": pos, "heading": rng.randf() * TAU, "speed": 0.0, "target": null,
		"state": "swim", "timer": 0.0, "leader": leader, "ripples": ripples, "phase": rng.randf() * 10.0, "tip": 0.0}
	entry.sim.append(d)
	return d


func _inside(lake: Dictionary, x: float, z: float, f: float) -> bool:
	return pow((x - lake.cx) / (lake.rw * f), 2) + pow((z - lake.cz) / (lake.rd * f), 2) < 1.0


func _pick_target(lake: Dictionary, lim: float) -> Vector2:
	for i in 20:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * lim
		var x: float = lake.cx + cos(a) * lake.rw * r
		var z: float = lake.cz + sin(a) * lake.rd * r
		if _inside(lake, x, z, lim):
			return Vector2(x, z)
	return Vector2(lake.cx, lake.cz)


func update(dt: float, focus: Vector3) -> void:
	if dt <= 0.0:
		return
	dt = minf(dt, 0.1)
	time += dt
	var WY: float = world.WATER_Y
	for entry in lakes:
		var lake: Dictionary = entry.lake
		var sim: Array = entry.sim
		var lim := 0.78   # stay inside this fraction of the pond
		for d in sim:
			d.timer -= dt
			var desired: float = d.speed
			var tgt = null
			if d.leader != null:
				# ducklings paddle along in a line behind mum
				var L: Dictionary = d.leader
				tgt = L.pos + Vector2(cos(L.heading), sin(L.heading)) * -0.32
				desired = minf(0.55, (tgt as Vector2).distance_to(d.pos) * 1.4)
				d.state = "swim"
			elif d.state == "swim":
				if d.target == null or (d.target as Vector2).distance_to(d.pos) < 0.6:
					d.target = _pick_target(lake, lim)
				tgt = d.target
				desired = 0.32
				if d.timer <= 0.0:
					var r := rng.randf()
					if r < 0.25:
						d.state = "dabble"
						d.timer = 2.0 + rng.randf() * 2.0
					elif r < 0.45:
						d.state = "rest"
						d.timer = 3.0 + rng.randf() * 5.0
					else:
						d.timer = 3.0 + rng.randf() * 6.0
			else:
				desired = 0.03 if d.state == "rest" else 0.0
				if d.timer <= 0.0:
					d.state = "swim"
					d.timer = 4.0 + rng.randf() * 6.0
			# steer smoothly toward the target
			if tgt != null:
				var want := atan2(tgt.y - d.pos.y, tgt.x - d.pos.x)
				var diff := wrapf(want - d.heading, -PI, PI)
				d.heading += clampf(diff, -1.6 * dt, 1.6 * dt)
			d.speed += (desired - d.speed) * minf(1.0, dt * 1.5)
			# keep apart from the other ducks
			for o in sim:
				if o == d or o.leader == d or d.leader == o:
					continue
				var dx: float = d.pos.x - o.pos.x
				var dz: float = d.pos.y - o.pos.y
				var r2 := dx * dx + dz * dz
				if r2 < 0.5 and r2 > 1e-4:
					d.pos += Vector2(dx, dz) / r2 * 0.02 * dt
			d.pos += Vector2(cos(d.heading), sin(d.heading)) * d.speed * dt
			if not _inside(lake, d.pos.x, d.pos.y, 0.9):
				d.target = Vector2(lake.cx, lake.cz)
				d.state = "swim"

			# pose: bob on the water, head nods with each paddle stroke, tip up when dabbling
			var t: float = time + d.phase
			var g: Node3D = d.g
			var tip := 0.0
			if d.state == "dabble":
				tip = 1.0 if d.timer > 0.6 else maxf(d.timer, 0.0) / 0.6
			d.tip += (tip - d.tip) * minf(1.0, dt * 4.0)
			g.position = Vector3(d.pos.x, WY + sin(t * 1.3) * 0.008 - d.tip * 0.05, d.pos.y)
			g.basis = Basis(Vector3.UP, -d.heading) * Basis(Vector3.BACK, -d.tip * 1.25)
			var head: Node3D = g.get_meta("head")
			head.position.x = 0.24 + sin(t * 7.0) * 0.012 * minf(1.0, d.speed * 4.0)
			head.rotation.y = sin(t * 0.7) * 0.25 * (1.0 if d.state == "rest" else 0.3)

			# ripples spread out from a paddling duck
			var moving: bool = d.speed > 0.05 or d.tip > 0.2
			for rp in d.ripples:
				rp.t += dt / 1.8
				var rm: MeshInstance3D = rp.mesh
				if rp.t >= 1.0:
					rp.t -= 1.0
					rm.position = Vector3(d.pos.x, WY + 0.004, d.pos.y)
					rp.active = moving
				var s: float = (0.18 + rp.t * 0.9) * (0.5 if d.kind == "duckling" else 1.0)
				rm.scale = Vector3(s, s, s)
				rm.visible = rp.active
				rm.transparency = rp.t

		# the odd quack when you're nearby
		entry.quack -= dt
		if entry.quack <= 0.0:
			entry.quack = 5.0 + rng.randf() * 12.0
			if sfx:
				var dist: float = Vector2(focus.x - lake.cx, focus.z - lake.cz).length() - minf(lake.rw, lake.rd)
				sfx.quack(maxf(0.0, 1.0 - maxf(0.0, dist) / 30.0))
