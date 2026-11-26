extends RefCounted
## Trees, ported from buildTree / randomCard / buildCardGeometry / _buildWillowTree in world.js:
## a tapered trunk, limbs and branches (bark, batched with the town), and leaf clusters made of alpha-cut
## cards at the branch tips. Pines are whorls of drooping needle boughs. Every tree's cards are merged into a
## few world-space meshes (per texture and 96 m chunk); the foliage and bark shaders sway them in the wind
## the way applyWindSway() does. The far forest on the mountains is one MultiMesh of small cones.

const CHUNK := 96.0

var world
var rng := RandomNumberGenerator.new()
var _cards := {}          # key -> {kind, pos, nor, uv, idx}
var bark_mat: ShaderMaterial
var leaf_mats := {}       # kind -> ShaderMaterial
var spots: Array[Vector2] = []


func _init(w) -> void:
	world = w
	rng.seed = 4242
	bark_mat = ShaderMaterial.new()
	bark_mat.shader = load("res://shaders/bark.gdshader")
	bark_mat.set_shader_parameter("albedo_tex", world.tex("bark_col"))
	bark_mat.set_shader_parameter("normal_tex", world.tex("bark_nrm"))
	for kind in ["leafcard_leaf", "leafcard_blossom", "needlecard"]:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/foliage_card.gdshader")
		m.set_shader_parameter("leaf_tex", _coverage_texture(kind))
		leaf_mats[kind] = m


## Leaf textures keep the web version's coverage-preserving mip chain (see applyCoverageMips in textures.js):
## plain mipmaps would make alpha-cut foliage thin out and vanish in the distance.
func _coverage_texture(name: String) -> Texture2D:
	var levels: Array[Image] = []
	var k := 0
	while ResourceLoader.exists("res://assets/textures/mips/%s_%d.png" % [name, k]):
		var t: Texture2D = load("res://assets/textures/mips/%s_%d.png" % [name, k])
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		levels.append(img)
		k += 1
	if levels.is_empty():
		return world.tex(name + "_col")
	var data := PackedByteArray()
	for img in levels:
		data.append_array(img.get_data())
	var full := Image.create_from_data(levels[0].get_width(), levels[0].get_height(), levels.size() > 1, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(full)


func _r() -> float:
	return rng.randf()


# ------------------------------------------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------------------------------------------
## Tapered limb between two points (world space)
func _limb(a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.01:
		return
	var y := dir / len
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.BACK
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	world.b.cylinder(Transform3D(Basis(x, y, z), a), Vector3.ZERO, r0, r1, len, 7, bark_mat, false, 1.0, true)


## One leaf card: c centre, ax / ay half-width and half-height vectors, n the crown normal (world space)
func _card(kind: String, c: Vector3, ax: Vector3, ay: Vector3, n: Vector3) -> void:
	var key := "%s:%d:%d" % [kind, floori(c.x / CHUNK), floori(c.z / CHUNK)]
	var e: Variant = _cards.get(key)
	if e == null:
		e = {"kind": kind, "pos": PackedVector3Array(), "nor": PackedVector3Array(), "uv": PackedVector2Array(), "idx": PackedInt32Array()}
		_cards[key] = e
	var base: int = e.pos.size()
	e.pos.append(c - ax - ay); e.uv.append(Vector2(0, 1))
	e.pos.append(c + ax - ay); e.uv.append(Vector2(1, 1))
	e.pos.append(c + ax + ay); e.uv.append(Vector2(1, 0))
	e.pos.append(c - ax + ay); e.uv.append(Vector2(0, 0))
	for i in 4:
		e.nor.append(n)
	e.idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## randomCard() from world.js, in the tree's local frame
func _random_card(center: Vector3, size: float, crown: Vector3, up_bias := 0.5) -> Array:
	var ax := Vector3(_r() - 0.5, (_r() - 0.5) * 0.6, _r() - 0.5).normalized()
	var ay := Vector3(_r() - 0.5, _r() - 0.5, _r() - 0.5).cross(ax).normalized()
	var n := (center - crown).normalized()
	n.y += up_bias
	return [center, ax * (size / 2), ay * (size / 2), n.normalized()]


# ------------------------------------------------------------------------------------------------
# Trees
# ------------------------------------------------------------------------------------------------
func build_tree(x: float, z: float, type := "deciduous", scale := 1.0) -> void:
	spots.append(Vector2(x, z))
	var xf := Transform3D(Basis(Vector3.UP, _r() * TAU), Vector3(x, 0, z))
	var s := (0.85 + _r() * 0.35) * scale
	var limb := func(a: Vector3, b: Vector3, r0: float, r1: float) -> void: _limb(xf * a, xf * b, r0, r1)
	var card := func(kind: String, c: Vector3, ax: Vector3, ay: Vector3, n: Vector3) -> void:
		_card(kind, xf * c, xf.basis * ax, xf.basis * ay, (xf.basis * n).normalized())

	if type == "pine":
		# Straight tapering trunk with whorls of drooping boughs, longest at the bottom
		var H := 9.0 * s
		limb.call(Vector3.ZERO, Vector3(0, H, 0), 0.3 * s, 0.03)
		var h := 1.4 * s
		while h < H - 0.2:
			var f := (h - 1.6 * s) / (H - 1.6 * s)
			var len := (2.9 * (1 - f) + 0.45) * s
			var twist := _r() * PI
			for bi in 9:
				var a := twist + (bi / 9.0) * TAU + (_r() - 0.5) * 0.4
				var out := Vector3(cos(a), -0.25 - _r() * 0.2 - (1 - f) * 0.1, sin(a)).normalized()
				var c := Vector3(0, h, 0) + out * (len / 2)
				var side := Vector3(-sin(a), 0, cos(a))
				var n := Vector3(cos(a), 0.9, sin(a)).normalized()
				# flat bough + a tilted copy so it has thickness from the side
				card.call("needlecard", c, out * (len / 2), side * (len * 0.42), n)
				var tilted := (side * 0.6 + Vector3(0, 0.8, 0)).normalized()
				card.call("needlecard", c, out * (len / 2), tilted * (len * 0.25), n)
			h += 0.3 * s
		card.call("needlecard", Vector3(0, H + 0.1, 0), Vector3(0, 0.5, 0), Vector3(0.3, 0, 0), Vector3.UP)
	else:
		# Deciduous / flowering / linden: leaning trunk, main limbs, secondary branches, leaf clusters at the tips
		var lush := type == "linden"
		var trunk_h := (2.4 if type == "flowering" else (3.6 if lush else 3.2)) * s
		var lean := Vector3((_r() - 0.5) * 0.3, 1, (_r() - 0.5) * 0.3).normalized()
		var trunk_top := lean * trunk_h
		limb.call(Vector3.ZERO, trunk_top, 0.34 * s, 0.22 * s)
		var crown := trunk_top + Vector3(0, 2.0 * s, 0)
		var tips: Array[Vector3] = []
		var limbs := 5 if type == "flowering" else (8 if lush else 6)
		for l in limbs:
			var a := (float(l) / limbs) * TAU + _r() * 0.6
			var start := trunk_top - lean * (_r() * 0.8 * s)
			var dir := Vector3(cos(a), 0.9 + _r() * 0.7, sin(a)).normalized()
			var len := ((2.6 + _r() * 1.0) if lush else (2.0 + _r() * 1.1)) * s
			var end := start + dir * len
			limb.call(start, end, 0.17 * s, 0.07 * s)
			tips.append(end)
			for k in (3 if lush else 2):
				var from := start.lerp(end, 0.5 + _r() * 0.3)
				var d2 := (dir + Vector3((_r() - 0.5) * 1.4, _r() * 0.5, (_r() - 0.5) * 1.4)).normalized()
				var e2 := from + d2 * (len * (0.45 + _r() * 0.25))
				limb.call(from, e2, 0.07 * s, 0.025 * s)
				tips.append(e2)
		tips.append(crown + Vector3(0, 0.8 * s, 0))
		var kind := "leafcard_blossom" if type == "flowering" else "leafcard_leaf"
		var per_tip := 12 if type == "flowering" else (maxi(6, roundi(14 * world.tree_detail)) if lush else 13)
		var spread := 2.5 if lush else 2.0
		for tip in tips:
			for i in per_tip:
				var off := Vector3(_r() - 0.5, _r() - 0.4, _r() - 0.5) * (spread * s)
				var size := ((1.3 + _r() * 0.6) if lush else (1.1 + _r() * 0.5)) * s
				var rc := _random_card(tip + off, size, crown, 0.45)
				card.call(kind, rc[0], rc[1], rc[2], rc[3])
		if lush:
			# fill the inside of the crown so it reads as one dense dome, not a ring of clumps
			for i in roundi(36 * world.tree_detail):
				var off := Vector3(_r() - 0.5, _r() - 0.35, _r() - 0.5) * (4.4 * s)
				var rc := _random_card(crown + Vector3(0, 0.6 * s, 0) + off, (1.4 + _r() * 0.6) * s, crown, 0.35)
				card.call(kind, rc[0], rc[1], rc[2], rc[3])
	world.solid_cyl(x, z, 0.5, 4.0)


## Weeping willow by the pond: leaning trunk, arching limbs and long curtains of leaves
func build_willow(x: float, z: float) -> void:
	spots.append(Vector2(x, z))
	var o := Vector3(x, 0, z)
	var top := Vector3(0.3, 3.6, 0.2)
	_limb(o, o + top, 0.42, 0.28)
	var crown := top + Vector3(0, 1.5, 0)
	for l in 7:
		var a := (l / 7.0) * TAU + _r() * 0.4
		var dir := Vector3(cos(a), 0.7 + _r() * 0.4, sin(a)).normalized()
		var end := top + dir * (2.6 + _r() * 0.8)
		_limb(o + top, o + end, 0.16, 0.05)
		for s in 9:
			var from := top.lerp(end, 0.4 + _r() * 0.6) + Vector3((_r() - 0.5) * 1.6, _r() * 0.6, (_r() - 0.5) * 1.6)
			var len := 2.2 + _r() * minf(2.4, from.y - 0.6)
			var out := Vector3(from.x, 0, from.z).normalized()
			for k in 3:
				var c := from + Vector3(0, -len * (k + 0.5) / 3, 0) + out * (0.15 * k)
				var ax := Vector3(-out.z, 0, out.x).rotated(Vector3.UP, (_r() - 0.5) * 1.2) * 0.32
				var ay := Vector3(0, len / 6 + 0.05, 0)
				var n := (c - crown)
				n.y = 0.3
				_card("leafcard_leaf", o + c, ax, ay, n.normalized())
	for i in 40:
		var c := crown + Vector3((_r() - 0.5) * 4, (_r() - 0.3) * 1.6, (_r() - 0.5) * 4)
		var rc := _random_card(c, 1.0 + _r() * 0.4, crown, 0.5)
		_card("leafcard_leaf", o + rc[0], rc[1], rc[2], rc[3])
	world.solid_cyl(x, z, 0.6, 4.0)


## Conifer forest on the lower mountain slopes: small dark cones, as in buildMountains()
func build_forest(parent: Node3D) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	cone.cap_bottom = false
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var tries := 0
	while xfs.size() < 5000 and tries < 30000:
		tries += 1
		var a := _r() * TAU
		var r := 255.0 + pow(_r(), 1.6) * 420.0
		var x := cos(a) * r
		var z := sin(a) * r
		if maxf(absf(x), absf(z)) < 228:
			continue
		if world.Castle.hill_mask(x, z) > 0.02:   # the crag has its own conifers (castle.gd)
			continue
		var h: float = world.mountain_height(x, z)
		if h > 130 + world._vnoise(x * 0.01, z * 0.01) * 50 or world._vnoise(x * 0.012 + 7, z * 0.012) < 0.35:
			continue
		var e := 3.0
		var slope := Vector2(world.mountain_height(x + e, z) - h, world.mountain_height(x, z + e) - h).length() / e
		if slope > 0.9:
			continue
		var th := 5.0 + _r() * 5.0
		xfs.append(Transform3D(Basis.from_scale(Vector3(th * 0.28, th, th * 0.28)), Vector3(x, h - 0.5 + th / 2, z)))
		cols.append(Color.from_hsv(0.28 + _r() * 0.06, 0.55, 0.2 + _r() * 0.1))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cone
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Merge all leaf cards into meshes
func commit(parent: Node3D) -> int:
	var cards := 0
	for key in _cards:
		var e: Dictionary = _cards[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = e.pos
		arrays[Mesh.ARRAY_NORMAL] = e.nor
		arrays[Mesh.ARRAY_TEX_UV] = e.uv
		arrays[Mesh.ARRAY_INDEX] = e.idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, leaf_mats[e.kind])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		parent.add_child(mi)
		cards += e.pos.size() / 4
	_cards.clear()
	return cards
