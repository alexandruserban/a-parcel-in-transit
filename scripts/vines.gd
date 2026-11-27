extends RefCounted
## Grapevines trained up the town side of the city wall: a gnarled trunk from the foot of the wall, two or three
## cordons running along it, short shoots off the cordons, leaf cards with a five-lobed vine leaf cut out in the
## shader (vine_leaf.gdshader) and bunches of grapes hanging under the cordons. One batch, drawn within VIS m.

const Batch := preload("res://scripts/batch.gd")
const VIS := 170.0

var w
var vb: Batch
var rng := RandomNumberGenerator.new()
var leaf_mat: ShaderMaterial
var bark: Material
var grapes: Array = []
var berry: SphereMesh
var count := 0
const GREENS := ["#4f7a2c", "#5a8433", "#45702a", "#668f3a", "#3f6524", "#73963f"]
const AUTUMN := ["#a7a236", "#b98a2e", "#8e9a34"]


## faces: [{a: start of the face at the ground, dir: along it, n: out of the face, len}]
## avoid: [Vector3(x, z, radius)] stretches kept clear (towers, the gate)
func build(world, faces: Array, avoid: Array, parent: Node3D) -> int:
	w = world
	rng.seed = 4242
	vb = Batch.new()
	vb.chunk = 48.0
	leaf_mat = ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/vine_leaf.gdshader")
	leaf_mat.set_shader_parameter("sway_amp", 0.04)
	leaf_mat.set_meta("vcol", true)
	bark = w.tmat("bark", Vector2(0.6, 1.2), {"rough": 0.95, "tint": Color("#8a7a68")})
	for hex in ["#3b1b3e", "#4a2148", "#2f1631"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		m.roughness = 0.38
		m.rim_enabled = true   # the bloom on the skins
		m.rim = 0.35
		m.rim_tint = 0.2
		grapes.append(m)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("#a9b55c")
	white.roughness = 0.35
	grapes.append(white)
	berry = SphereMesh.new()
	berry.radius = 0.024
	berry.height = 0.048
	berry.radial_segments = 6
	berry.rings = 3
	var spacing: float = 11.0 / clampf(w.tree_detail, 0.4, 1.0)
	for f in faces:
		var a: Vector3 = f.a
		var dir: Vector3 = f.dir
		var s := rng.randf_range(3.0, 9.0)
		while s < f.len - 3.0:
			var root: Vector3 = a + dir * s
			if not _blocked(root, avoid, f.len, a, dir):
				_vine(root, dir, f.n)
				count += 1
			s += spacing * rng.randf_range(0.75, 1.35)
	vb.commit(parent, VIS)
	_green_wall(faces, avoid)
	return count


## Cover the whole town side of the wall in leaves (green_wall.gdshader): a dense layer against the stone and,
## except on phones, a sparser one in front for depth. Into the town's static batch (seen from anywhere), in
## 24 m panels whose UVs run on along the wall, so the leaf pattern has no seams.
func _green_wall(faces: Array, _avoid: Array) -> void:
	var layers := [[0.03, 1.0, 0.0, 1.0], [0.11, 0.5, 1.0, 1.15]]   # [off the wall, density, seed, shade]
	if w.tree_detail < 1.0:
		layers.resize(1)
	var H := 8.6
	for L in layers:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/green_wall.gdshader")
		m.set_shader_parameter("density", L[1])
		m.set_shader_parameter("layer_seed", L[2])
		m.set_shader_parameter("shade", L[3])
		m.set_shader_parameter("top_y", 8.55)
		for f in faces:
			var a: Vector3 = f.a
			var dir: Vector3 = f.dir
			var n: Vector3 = f.n
			var len: float = f.len
			var u := 0.0
			while u < len - 0.01:
				var u1 := minf(u + 24.0, len)
				var p0: Vector3 = a + dir * u + n * L[0]
				var p1: Vector3 = a + dir * u1 + n * L[0]
				var up := Vector3(0, H, 0)
				var uv0 := Vector2(u, 0)
				var uv1 := Vector2(u1, 0)
				var uv2 := Vector2(u1, -H)
				var uv3 := Vector2(u, -H)
				w.b.tri_uv(Transform3D.IDENTITY, p0, p1, p1 + up, uv0, uv1, uv2, m, n, false)
				w.b.tri_uv(Transform3D.IDENTITY, p0, p1 + up, p0 + up, uv0, uv2, uv3, m, n, false)
				u = u1


func _blocked(p: Vector3, avoid: Array, _len: float, _a: Vector3, _dir: Vector3) -> bool:
	for v in avoid:
		if Vector2(p.x - v.x, p.z - v.y).length() < v.z + 1.5:
			return true
	return false


## Woody stem from a to c (radius r0 to r1), a five-sided tube
func _limb(a: Vector3, c: Vector3, r0: float, r1: float) -> void:
	var d := c - a
	var len := d.length()
	if len < 0.01:
		return
	var y := d / len
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	vb.cylinder(Transform3D(Basis(x, y, z), a), Vector3.ZERO, r0, r1, len, 5, bark, false, 1.0, false)


## Wavy polyline: n points from p0 along step, wobbling sideways (side) and in and out of the wall (n_dir)
func _wobble(p0: Vector3, step: Vector3, n: int, side: Vector3, amp: float, n_dir: Vector3, out_min: float, out_max: float) -> Array:
	var pts: Array = [p0]
	var ph := rng.randf() * TAU
	for i in range(1, n + 1):
		var base: Vector3 = p0 + step * i
		var off := side * sin(ph + i * 1.3) * amp + side * rng.randf_range(-amp, amp) * 0.5
		var o := rng.randf_range(out_min, out_max)
		pts.append(base + off + n_dir * (o - n_dir.dot(base - p0)))
	return pts


func _leaf(c: Vector3, n: Vector3, size: float) -> void:
	# a leaf facing roughly out of the wall, its tip up-ish, turned and tipped a little at random
	var nn := (n + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.6), rng.randf_range(-0.5, 0.5))).normalized()
	var up := Vector3.UP.rotated(nn, rng.randf_range(-0.7, 0.7))
	var ax := up.cross(nn).normalized() * size * 0.5
	var ay := nn.cross(ax).normalized() * size * 0.5
	var autumn := rng.randf() < 0.1
	var col := Color(AUTUMN[rng.randi() % AUTUMN.size()] if autumn else GREENS[rng.randi() % GREENS.size()])
	vb.color = col.lerp(Color.WHITE, rng.randf_range(0.0, 0.08))
	var A := c - ax - ay
	var B := c + ax - ay
	var C := c + ax + ay
	var D := c - ax + ay
	vb.tri_uv(Transform3D.IDENTITY, A, B, C, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), leaf_mat, nn, false)
	vb.tri_uv(Transform3D.IDENTITY, A, C, D, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0), leaf_mat, nn, false)


func _leaves_round(p: Vector3, n: Vector3, along: Vector3, k: int, spread: float) -> void:
	for i in k:
		var c := p + n * rng.randf_range(0.05, 0.28) + along * rng.randf_range(-spread, spread) + Vector3(0, rng.randf_range(-spread, spread * 1.2), 0)
		_leaf(c, n, rng.randf_range(0.18, 0.3))


## Bunch of grapes hanging from p: rows of berries tapering to a point, on a short stalk
func _bunch(p: Vector3, n: Vector3, along: Vector3, mat: Material) -> void:
	var top := p + n * rng.randf_range(0.1, 0.18)
	_limb(p, top, 0.006, 0.006)
	var rows := [5, 4, 4, 3, 2, 1]
	var y := 0.0
	for r in rows.size():
		var cnt: int = rows[r]
		var rad := 0.012 * cnt
		var ph := rng.randf() * TAU
		for i in cnt:
			var a := ph + TAU * i / cnt
			var bp := top + Vector3(0, -0.03 - y, 0) + along * cos(a) * rad + n * sin(a) * rad * 0.8
			vb.mesh(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.85, 1.1)), bp), berry, mat, false)
		y += 0.034


func _vine(root: Vector3, along: Vector3, n: Vector3) -> void:
	var top := rng.randf_range(3.6, 6.4)
	var pick: Material = grapes[3] if rng.randf() < 0.25 else grapes[rng.randi() % 3]
	# trunk: thick and twisting at the foot, leaning on the wall higher up
	var base := root + n * 0.22
	var segs := int(top / 0.55)
	var trunk := _wobble(base, Vector3(0, top / segs, 0), segs, along, 0.1, n, 0.06, 0.14)
	trunk[0] = base
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		_limb(trunk[i], trunk[i + 1], lerpf(0.075, 0.035, t0), lerpf(0.075, 0.035, t1))
	# cordons along the wall from the trunk, both ways, every 1.4 - 1.8 m up
	var lvl := rng.randf_range(1.6, 2.2)
	var levels: Array = []
	while lvl < top + 0.2:
		levels.append(minf(lvl, top))
		lvl += rng.randf_range(1.4, 1.8)
	for li in levels.size():
		var h: float = levels[li]
		var k := clampi(int(h / (top / segs)), 0, segs)
		var start: Vector3 = trunk[k]
		for sgn in [-1.0, 1.0]:
			var L := rng.randf_range(1.6, 3.8)
			var ns := int(L / 0.45)
			var cord := _wobble(start, along * sgn * (L / ns), ns, Vector3.UP, 0.07, n, 0.05, 0.1)
			for i in ns:
				var t := float(i) / ns
				_limb(cord[i], cord[i + 1], lerpf(0.032, 0.012, t), lerpf(0.032, 0.012, t + 1.0 / ns))
				var p: Vector3 = cord[i + 1]
				_leaves_round(p, n, along, 5, 0.24)
				# a shoot at every node: mostly up, now and then trailing down
				var dn := rng.randf() < 0.3
				var sl := rng.randf_range(0.35, 0.9)
				var tip := p + Vector3(0, -sl if dn else sl, 0) + along * rng.randf_range(-0.25, 0.25) + n * rng.randf_range(0.05, 0.25)
				_limb(p, tip, 0.01, 0.005)
				var steps := int(sl / 0.13)
				for j in steps:
					var q := p.lerp(tip, float(j + 1) / steps)
					_leaves_round(q, n, along, 3, 0.14)
				# grapes hang under the lower cordons
				if li < 2 and rng.randf() < 0.32:
					_bunch(p + Vector3(0, -0.03, 0), n, along, pick)
