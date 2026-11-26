extends RefCounted
## Houses, ported from houses.js (and the house parts of oldtown.js and gothic.js): hollow two-storey shells
## with real window openings (glass you can see through), a hinged front door, a staircase to the upper floor,
## furnished rooms (living room, kitchen, guest room, two bedrooms, study, bathroom), garages - some left open
## with a hobby workshop inside - and the outside: roof, timber frame or Gothic front, gable windows, shutters.
## Local house frame: x across the front (-8..8), z towards the street (-7..7), ground floor y 0, upper floor y 3.62.
## Interior parts go into their own batch, drawn only within 60 m.

const Batch := preload("res://scripts/batch.gd")
const Castle := preload("res://scripts/castle.gd")
const W := 16.0
const D := 14.0
const H := 6.5
const T := 0.2
const UP := 3.62          # upper floor surface
const SLAB0 := 3.45       # underside of the upper floor (ground-floor ceiling)
const CEIL2 := 6.35       # upper ceiling
const SX0 := 1.6          # stairs: straight flight rising towards +x
const SX1 := 6.2
const SZ0 := -0.94
const SZ1 := 0.46
const IX := W / 2 - T
const IZ := D / 2 - T
const VIS := 60.0

var w                     # world.gd
var be                    # batch for the unchanging outside parts (the template while recording)
var bi                    # batch for the unchanging inside parts
var vbe                   # batches for the parts that differ from house to house
var vbi
var real_be               # world batch (outside)
var real_bi               # interior batch, drawn within VIS
var tpl_be
var tpl_bi
var null_b
var mode := 0             # 0 normal, 1 recording the template, 2 per-house parts only
var tpl_ext: Array = []
var tpl_int: Array = []
var WALL_PH := StandardMaterial3D.new()   # stands in for the house's wall material in the template
var hm := {}
var doors: Array = []     # [{hinge, angle, target, shape}]
var interiors: Array = [] # [{rect: Rect2, xf: Transform3D}]
var window_mats: Array = []   # [{mat, lit}] house window glass (lit: brightness at night, 0 = dark)
var fixture_mat: StandardMaterial3D
var open_garages := 0
var rng := RandomNumberGenerator.new()
var _mesh := {}


func setup(world) -> void:
	w = world
	real_be = world.b
	real_bi = Batch.new()
	real_bi.chunk = 48.0
	tpl_be = Batch.new()
	tpl_be.chunk = 1e6
	tpl_bi = Batch.new()
	tpl_bi.chunk = 1e6
	null_b = preload("res://scripts/null_batch.gd").new()
	_set_mode(0)
	rng.seed = 5150
	_materials()


func commit(parent: Node3D) -> int:
	return real_bi.commit(parent, VIS)


## Every house shares its layout, so the unchanging parts are built once and stamped into each house
func _set_mode(m: int) -> void:
	mode = m
	be = tpl_be if m == 1 else (null_b if m == 2 else real_be)
	bi = tpl_bi if m == 1 else (null_b if m == 2 else real_bi)
	vbe = null_b if m == 1 else real_be
	vbi = null_b if m == 1 else real_bi


func _record_template() -> void:
	_set_mode(1)
	_shell(Transform3D.IDENTITY, WALL_PH, {"number": 0})
	_interior(Transform3D.IDENTITY, {"number": 0})
	tpl_ext = tpl_be.bake()
	tpl_int = tpl_bi.bake()
	_set_mode(0)


# ---------------------------------------------------------------------------------------------- materials
## Plain colours share a handful of vertex-coloured materials: {mat, color}
func _vc(kind: String, hex: String) -> Dictionary:
	return {"mat": hm["_vc_" + kind], "color": Color(hex)}


func _vmat(rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	m.set_meta("vcol", true)
	return m


func _texmat(name: String, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = w.tex(name)
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _materials() -> void:
	hm._vc_paint = _vmat(0.5)
	hm._vc_matte = _vmat(0.9)
	hm._vc_glossy = _vmat(0.15)
	hm._vc_metal = _vmat(0.3, 0.88)
	hm._vc_dark = _vmat(0.08, 0.5)
	var fab := _vmat(1.0)
	fab.albedo_texture = w.tex("fabric_col")
	fab.uv1_scale = Vector3(2, 2, 1)
	hm._vc_fabric = fab
	# texture sizes in metres, as the web's su / sv
	hm.plaster = w.tmat("plaster_ece6da", Vector2(6.5, 6.5), {"rough": 0.92})
	hm.plaster3 = w.tmat("plaster_ece6da", Vector2(3, 3), {"rough": 0.92})
	var ceil: ShaderMaterial = w.tmat("plaster_f4f2ee", Vector2(3, 3), {"rough": 0.95, "emission_tint": Color("#9a8f80")})
	ceil.set_shader_parameter("emission", 0.12)
	hm.ceil = ceil
	hm.floor = w.tmat("wood_8b6a4a", Vector2(2, 2), {"rough": 0.55, "normal": "wood_nrm", "depth": 0.3})
	hm.floor_up = w.tmat("wood_a07c55", Vector2(2, 2), {"rough": 0.6, "normal": "wood_nrm", "depth": 0.3})
	hm.wood_mid = w.tmat("wood_7a5536", Vector2(1, 1), {"rough": 0.6})
	hm.wood_dark = w.tmat("wood_4a3426", Vector2(1, 1), {"rough": 0.55})
	hm.wood_light = w.tmat("wood_b89468", Vector2(1, 1), {"rough": 0.6})
	hm.counter = w.tmat("plaster_55514c", Vector2(1, 1), {"rough": 0.25})
	hm.tile_kitchen = w.tmat("tile_d7e6e2_8", Vector2(0.6, 0.6), {"rough": 0.18})
	hm.tile_bath = w.tmat("tile_e9eef2_6", Vector2(0.9, 0.9), {"rough": 0.18})
	hm.tile_floor = w.tmat("tile_c9c1b3_4", Vector2(0.6, 0.6), {"rough": 0.35})
	hm.concrete = w.tmat("concrete", Vector2(2, 2), {"rough": 0.95, "tint": Color("#a9a59d")})
	hm.leaf = w.tmat("foliage_leaf", Vector2(1, 1), {"rough": 0.85})
	hm.books = _texmat("books_col", 0.8)
	hm.chalk = _texmat("chalkboard_col", 0.9)
	hm.trim = _vc("paint", "#f1eee8")
	hm.white = _vc("paint", "#eceae5")
	hm.cabinet = _vc("paint", "#e4ddcf")
	hm.cabinet_door = _vc("paint", "#f0ebe0")
	hm.radiator = _vc("paint", "#f3f1ec")
	hm.steel = _vc("metal", "#cfd2d4")
	hm.brushed = _vc("metal", "#aeb2b5")
	hm.dark_steel = _vc("metal", "#4a4e52")
	hm.copper = _vc("metal", "#c27a4a")
	hm.black = _vc("dark", "#141518")
	hm.glass_dark = _vc("dark", "#0b0d10")
	hm.screen = _vc("dark", "#07090c")
	hm.rubber = _vc("matte", "#1b1b1c")
	hm.porcelain = _vc("glossy", "#f7f7f4")
	hm.brown_glass = _vc("glossy", "#4a2408")
	hm.pot = _vc("matte", "#9a5b3c")
	hm.clay = _vc("matte", "#9c7a62")
	hm.cork = _vc("matte", "#c19a6b")
	hm.pegboard = _vc("matte", "#c8a676")
	hm.red = _vc("paint", "#b3261e")
	hm.yellow = _vc("paint", "#e0b324")
	hm.orange = _vc("paint", "#e0672a")
	hm.linen = fabric("#f0ede6")
	hm.canvas_beige = fabric("#d9ccb0")
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color("#e2e8ec")
	mirror.roughness = 0.02
	mirror.metallic = 1.0
	hm.mirror = mirror
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(Color("#b8d0d6"), 0.3)
	glass.roughness = 0.05
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.glass = glass
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(Color("#a5571a"), 0.85)
	amber.roughness = 0.15
	amber.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.amber = amber
	var fluoro := StandardMaterial3D.new()
	fluoro.albedo_color = Color.WHITE
	fluoro.emission_enabled = true
	fluoro.emission = Color("#f4f7ff")
	fluoro.emission_energy_multiplier = 1.2
	hm.fluoro = fluoro
	var shade := StandardMaterial3D.new()
	shade.albedo_color = Color("#f2e8d5")
	shade.roughness = 0.9
	shade.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade.emission_enabled = true
	shade.emission = Color("#ffd9a0")
	shade.emission_energy_multiplier = 0.0
	w.night_glows.append({"mat": shade, "energy": 1.5})
	hm.shade = shade
	fixture_mat = StandardMaterial3D.new()
	fixture_mat.albedo_color = Color("#f6f1e7")
	fixture_mat.roughness = 0.5
	fixture_mat.emission_enabled = true
	fixture_mat.emission = Color("#ffe2b8")
	fixture_mat.emission_energy_multiplier = 0.15
	# Window glass: see-through by day; at night about two thirds of the windows glow, each a little differently
	for lit in [0.0, 0.6, 0.85, 1.1]:
		var g := StandardMaterial3D.new()
		g.albedo_color = Color(Color("#a9bfc8"), 0.22)
		g.roughness = 0.04
		g.metallic = 0.1
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		g.emission_enabled = true
		g.emission = Color("#ffc47e")
		g.emission_energy_multiplier = 0.0
		window_mats.append({"mat": g, "lit": lit})


func fabric(hex: String) -> Dictionary:
	return {"mat": hm._vc_fabric, "color": Color(hex)}


func _glaze(hex: String) -> Dictionary:
	return _vc("glossy", hex)


var _tex_mats := {}
func _picture_mat(name: String) -> StandardMaterial3D:
	if not _tex_mats.has(name):
		_tex_mats[name] = _texmat(name, 0.6 if name.begins_with("painting") else 1.0)
	return _tex_mats[name]


## Night: lit windows glow and turn nearly opaque (the web's uGlow), the rest stay clear
func set_night(on: bool) -> void:
	for e in window_mats:
		var m: StandardMaterial3D = e.mat
		var lit: float = e.lit
		m.emission_energy_multiplier = lit * 1.6 if on else 0.0
		m.albedo_color.a = 0.8 if on and lit > 0.0 else 0.22


# ---------------------------------------------------------------------------------------------- helpers
func _m(B, m):
	if m is Dictionary:
		B.color = m.color
		return m.mat
	if m is Array:
		var out := []
		for e in m:
			if e is Dictionary:
				B.color = e.color
				out.append(e.mat)
			else:
				out.append(e)
		return out
	return m


## Box (web addBox) in house space: w x h x d centred at (x, y, z)
func box(xf: Transform3D, w_: float, h: float, d: float, x: float, y: float, z: float, m, cast := false, B = null) -> void:
	if B == null:
		B = vbi if m is Dictionary and m.has("vary") else bi
	if B == null_b:
		return
	B.box(xf, Vector3(x, y, z), Vector3(w_, h, d), _m(B, m), 1.0, cast, true)


func obox(xf: Transform3D, w_: float, h: float, d: float, x: float, y: float, z: float, m, cast := true) -> void:
	box(xf, w_, h, d, x, y, z, m, cast, be)


## Solid box in house space from y0 to top (web addLocalCollider)
func col(xf: Transform3D, cx: float, cz: float, w_: float, d: float, top := 4.0, y0 := 0.0) -> void:
	if mode == 1:
		return
	w.solid(xf, Vector3(cx, (y0 + top) / 2, cz), Vector3(w_, top - y0, d))


## Furniture collider: footprint w x d, from y0 up h
func solid(xf: Transform3D, x: float, z: float, w_: float, d: float, y0 := 0.0, h := 2.2) -> void:
	col(xf, x, z, w_, d, y0 + h, y0)


func _cyl(rt: float, rb: float, h: float, segs := 12, open := false) -> Mesh:
	var key := Vector4(rt, rb, h, segs + (1000 if open else 0))
	if not _mesh.has(key):
		var m := CylinderMesh.new()
		m.top_radius = rt
		m.bottom_radius = rb
		m.height = h
		m.radial_segments = segs
		m.rings = 1
		m.cap_top = not open and rt > 0.0
		m.cap_bottom = not open
		_mesh[key] = m
	return _mesh[key]


func _sph(r: float, segs := 12, rings := 8, hemi := false) -> Mesh:
	var key := Vector4(r, segs, rings, 1 if hemi else 0) + Vector4(0, 0, 0, 2)
	if not _mesh.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * (1.0 if hemi else 2.0)
		m.radial_segments = segs
		m.rings = rings
		m.is_hemisphere = hemi
		_mesh[key] = m
	return _mesh[key]


## three.js TorusGeometry(radius, tube) lies in XY; Godot's TorusMesh in XZ (callers add Rx(pi/2))
func _tor(radius: float, tube: float, segs := 24) -> Mesh:
	var key := Vector4(radius, tube, segs, 3)
	if not _mesh.has(key):
		var m := TorusMesh.new()
		m.inner_radius = radius - tube
		m.outer_radius = radius + tube
		m.rings = segs
		m.ring_segments = 6
		_mesh[key] = m
	return _mesh[key]


## Lathe (three.js LatheGeometry): a profile of (radius, y) points spun round y
func _lathe(prof: Array, segs := 16) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var q := [Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x), Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x),
				Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x), Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)]
			for o in [0, 1, 2, 0, 2, 3]:   # outside faces clockwise
				st.add_vertex(q[o])
	st.generate_normals()
	return st.commit()


static func _rx(a: float) -> Basis:
	return Basis(Vector3.RIGHT, a)


const TORUS_FIX := Vector3(PI / 2, 0, 0)


## A mesh part in house space (web: new THREE.Mesh(geo, mat) with position / rotation / scale)
func prim(xf: Transform3D, mesh: Mesh, m, pos: Vector3, basis := Basis(), cast := false, B = null) -> void:
	if B == null:
		B = bi
	if B == null_b:
		return
	B.mesh(xf * Transform3D(basis, pos), mesh, _m(B, m), cast)


func torus(xf: Transform3D, radius: float, tube: float, m, pos: Vector3, basis := Basis(), segs := 24) -> void:
	prim(xf, _tor(radius, tube, segs), m, pos, basis * _rx(PI / 2))


## Cylinder from a to b (world.js addLimb)
func limb(xf: Transform3D, a: Vector3, c: Vector3, r0: float, r1: float, m) -> void:
	var d := c - a
	var len := d.length()
	var y := d / len
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	prim(xf, _cyl(r1, r0, len, 8), m, (a + c) / 2, Basis(x, y, z))


## Picture on a plane facing +z in frame f (rugs, paintings, book spines, the chalkboard)
func picture(f: Transform3D, w_: float, h: float, mat: Material, B = null) -> void:
	if B == null:
		B = bi
	var pts := PackedVector2Array([Vector2(-w_ / 2, -h / 2), Vector2(w_ / 2, -h / 2), Vector2(w_ / 2, h / 2), Vector2(-w_ / 2, h / 2)])
	B.polygon(f, pts, mat, 1.0, false, Rect2(-w_ / 2, -h / 2, w_, h))


func rug(xf: Transform3D, x: float, y: float, z: float, w_: float, d: float, seed: int) -> void:
	picture(xf * Transform3D(_rx(-PI / 2), Vector3(x, y, z)), w_, d, _picture_mat("rug_%d_col" % (seed % 4)), vbi)


func table_lamp(xf: Transform3D, x: float, y: float, z: float) -> void:
	prim(xf, _cyl(0.06, 0.09, 0.28, 12), hm.porcelain, Vector3(x, y + 0.14, z))
	prim(xf, _cyl(0.11, 0.17, 0.2, 16, true), hm.shade, Vector3(x, y + 0.36, z))


func painting(xf: Transform3D, x: float, y: float, z: float, rot_y: float, w_: float, h: float, seed: int) -> void:
	var g := xf * Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z))
	box(g, w_ + 0.08, h + 0.08, 0.035, 0, 0, 0.0175, hm.wood_dark)
	picture(g * Transform3D(Basis(), Vector3(0, 0, 0.037)), w_, h, _picture_mat("painting_%d_col" % (seed % 6)), vbi)


func plant(xf: Transform3D, x: float, y: float, z: float, s := 1.0) -> void:
	prim(xf, _cyl(0.22 * s, 0.17 * s, 0.4 * s, 16), hm.pot, Vector3(x, y + 0.2 * s, z))
	prim(xf, _sph(0.4 * s, 10, 6), hm.leaf, Vector3(x, y + 0.75 * s, z), Basis.from_scale(Vector3(1, 1.3, 1)))


func legs(xf: Transform3D, x: float, z: float, w_: float, d: float, h: float, m, y0 := 0.0) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(xf, 0.05, h, 0.05, x + sx * (w_ / 2 - 0.05), y0 + h / 2, z + sz * (d / 2 - 0.05), m)


# ---------------------------------------------------------------------------------------------- walls
## Window / door openings per wall: [centre u, width, bottom v, top v]
const OPEN := {
	"front": [[-4.5, 1.8, 0.9, 3.0], [4.5, 1.8, 0.9, 3.0], [-4.5, 1.6, 4.6, 6.1], [0.0, 1.6, 4.6, 6.1], [4.5, 1.6, 4.6, 6.1]],
	"back": [[-3.5, 1.8, 1.15, 2.95], [3.5, 1.8, 1.15, 2.95], [-3.5, 1.6, 4.6, 6.1], [3.5, 1.6, 4.6, 6.1]],
	"right": [[3.2, 1.8, 0.9, 3.0], [-5.0, 1.6, 1.0, 2.9], [4.0, 1.6, 4.6, 6.1], [-4.0, 1.6, 4.6, 6.1]],
	"left": [[4.0, 1.6, 4.6, 6.1], [-4.0, 1.6, 4.6, 6.1]],
}
const SIDE_ROT := {"front": 0.0, "back": PI, "right": PI / 2, "left": -PI / 2}


## Wall coordinates (u along the wall, v up, n outwards from the wall's centre plane) to house space
static func wall_point(side: String, u: float, v: float, n: float) -> Vector3:
	var fz := D / 2 - T / 2
	var fx := W / 2 - T / 2
	match side:
		"front": return Vector3(u, v, fz + n)
		"back": return Vector3(u, v, -fz - n)
		"right": return Vector3(fx + n, v, u)
	return Vector3(-fx - n, v, u)


## Box aligned to a wall: su along the wall, sv up, sn through the wall
func wall_box(xf: Transform3D, side: String, u: float, v: float, n: float, su: float, sv: float, sn: float, m, outside := true) -> void:
	var p := wall_point(side, u, v, n)
	var along := side == "front" or side == "back"
	if outside:
		obox(xf, su if along else sn, sv, sn if along else su, p.x, p.y, p.z, m, false)
	else:
		box(xf, su if along else sn, sv, sn if along else su, p.x, p.y, p.z, m)


## Straight brace in a wall plane from (u0, v0) to (u1, v1) (oldtown.js wallBrace)
func wall_brace(xf: Transform3D, side: String, u0: float, v0: float, u1: float, v1: float, n: float, bw: float, depth: float, m) -> void:
	var len := Vector2(u1 - u0, v1 - v0).length()
	var ang := atan2(v1 - v0, u1 - u0)
	var sgn := 1.0 if side == "front" or side == "left" else -1.0
	var p := wall_point(side, (u0 + u1) / 2, (v0 + v1) / 2, n)
	var f: Transform3D = xf * Transform3D(Basis(Vector3.UP, SIDE_ROT[side]) * Basis(Vector3.BACK, sgn * ang), p)
	be.box(f, Vector3.ZERO, Vector3(len, bw, depth), _m(be, m), 1.0, false)


# ---------------------------------------------------------------------------------------------- the house
func build(idx: int, xf: Transform3D, st: Dictionary, cfg: Dictionary, wall: Material) -> Dictionary:
	if tpl_ext.is_empty():
		_record_template()
	real_be.append_baked(xf, tpl_ext, {WALL_PH: wall})
	real_bi.append_baked(xf, tpl_int)
	_set_mode(2)
	_shell(xf, wall, cfg)
	_interior(xf, cfg)
	_set_mode(0)
	var roof := gable_roof(be, xf, {"cx": 0.0, "cz": 0.0, "span": W if st.ridge_z else D, "length": D if st.ridge_z else W,
		"wall_top": H, "axis": "z" if st.ridge_z else "x", "pitch": st.pitch, "eave": 0.6, "verge": 0.0 if st.gothic else 0.45,
		"roof": w.roof_mat(st.roof), "gable": wall})
	if st.gothic:
		_gothic_front(xf, st, roof, wall)
	else:
		if st.frame != "none":
			_fachwerk(xf, st, roof)
		_gable_windows(xf, st, roof)
	_front_details(xf, st, idx)
	_entrance(xf, st)
	_front_door(xf, st)
	_garage(xf, wall, idx, st)
	return roof


func _shell(xf: Transform3D, wall: Material, cfg: Dictionary) -> void:
	var inside := {"front": 5, "back": 4, "right": 1, "left": 0}
	for side in ["front", "back", "right", "left"]:
		var holes: Array = []
		for o in OPEN[side]:
			holes.append([o[0] - o[1] / 2, o[0] + o[1] / 2, o[2], o[3]])
		if side == "front":
			holes.append([-0.6, 0.6, 0.0, 2.3])
		var along: bool = side == "front" or side == "back"
		var u0 := -W / 2 if along else -IZ
		var u1 := W / 2 if along else IZ
		var faces := [wall, wall, wall, wall, wall, wall]
		faces[inside[side]] = hm.plaster
		var cuts := [u0, u1]
		for h in holes:
			cuts.append(h[0])
			cuts.append(h[1])
		cuts.sort()
		for i in cuts.size() - 1:
			var a: float = cuts[i]
			var c: float = cuts[i + 1]
			if c - a < 0.001:
				continue
			var mid := (a + c) / 2
			var hs: Array = holes.filter(func(h): return h[0] < mid and h[1] > mid)
			hs.sort_custom(func(p, q): return p[2] < q[2])
			var v := 0.0
			var spans: Array = []
			for h in hs:
				if h[2] > v:
					spans.append([v, h[2]])
				v = maxf(v, h[3])
			if v < H:
				spans.append([v, H])
			for sp in spans:
				var p := wall_point(side, mid, (sp[0] + sp[1]) / 2, 0)
				be.box(xf, p, Vector3(c - a if along else T, sp[1] - sp[0], T if along else c - a), faces, 1.0, true)
	# Wall colliders (both storeys)
	col(xf, 0, -D / 2 + T / 2, W, T, 7)
	col(xf, -W / 2 + T / 2, 0, T, D, 7)
	col(xf, W / 2 - T / 2, 0, T, D, 7)
	var seg_w := (W - 1.2) / 2
	for s in [-1.0, 1.0]:
		col(xf, s * (0.6 + seg_w / 2), D / 2 - T / 2, seg_w, T, 7)
	col(xf, 0, D / 2 - T / 2, 1.2, T, 7, 2.35)   # above the door

	# Window frames, sills, curtains, radiators, glass
	for side in OPEN:
		var k := 0
		for o in OPEN[side]:
			_window(xf, side, o, cfg, k)
			k += 1

	# Door casing (outside)
	obox(xf, 0.12, 2.4, 0.06, -0.66, 1.2, D / 2 + 0.03, hm.trim, false)
	obox(xf, 0.12, 2.4, 0.06, 0.66, 1.2, D / 2 + 0.03, hm.trim, false)
	obox(xf, 1.56, 0.14, 0.07, 0, 2.42, D / 2 + 0.035, hm.trim, false)

	# Ground floor, upper floor slab with the stairwell cut out (wood on top, ceiling underneath), upper ceiling
	box(xf, W - 2 * T, 0.04, D - 2 * T, 0, 0.02, 0, hm.floor)
	var slab := [hm.plaster, hm.plaster, hm.floor_up, hm.ceil, hm.plaster, hm.plaster]
	var slab_box := func(x0: float, x1: float, z0: float, z1: float) -> void:
		if x1 - x0 > 0.01 and z1 - z0 > 0.01:
			box(xf, x1 - x0, UP - SLAB0, z1 - z0, (x0 + x1) / 2, (UP + SLAB0) / 2, (z0 + z1) / 2, slab)
			col(xf, (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0, UP, SLAB0)
	slab_box.call(-IX, IX, -IZ, SZ0)
	slab_box.call(-IX, IX, SZ1, IZ)
	slab_box.call(-IX, SX0, SZ0, SZ1)
	slab_box.call(SX1, IX, SZ0, SZ1)
	box(xf, W - 2 * T, 0.12, D - 2 * T, 0, CEIL2 + 0.06, 0, hm.ceil)
	col(xf, 0, 0, W, D, CEIL2 + 0.12, CEIL2)

	# Sandstone base course along the outside walls (gap at the door)
	var sand: Material = w.mats.sandstone
	var ph := 0.4
	var pt := 0.06
	obox(xf, W + 2 * pt, ph, pt, 0, ph / 2, -D / 2 - pt / 2, sand, false)
	obox(xf, pt, ph, D, -W / 2 - pt / 2, ph / 2, 0, sand, false)
	obox(xf, pt, ph, D, W / 2 + pt / 2, ph / 2, 0, sand, false)
	for s in [-1.0, 1.0]:
		obox(xf, seg_w + pt, ph, pt, s * (0.6 + (seg_w + pt) / 2), ph / 2, D / 2 + pt / 2, sand, false)

	if mode != 1:
		interiors.append({"rect": w.local_rect(xf, 0, 0, W - 0.4, D - 0.4), "xf": xf})
	_stairs(xf)


## Frame, mullions, sills, curtains and (ground floor) a radiator for one opening
func _window(xf: Transform3D, side: String, o: Array, cfg: Dictionary, k: int) -> void:
	var u: float = o[0]
	var ww: float = o[1]
	var v0: float = o[2]
	var v1: float = o[3]
	var h := v1 - v0
	var vc := (v0 + v1) / 2
	var fw := 0.07
	var depth := T - 0.02
	wall_box(xf, side, u, v1 - fw / 2, 0, ww, fw, depth, hm.trim)
	wall_box(xf, side, u, v0 + fw / 2, 0, ww, fw, depth, hm.trim)
	wall_box(xf, side, u - ww / 2 + fw / 2, vc, 0, fw, h - 2 * fw, depth, hm.trim)
	wall_box(xf, side, u + ww / 2 - fw / 2, vc, 0, fw, h - 2 * fw, depth, hm.trim)
	var ar := 0.1
	var an := T / 2 + 0.012
	wall_box(xf, side, u, v1 + ar / 2, an, ww + 2 * ar, ar, 0.024, hm.trim)
	wall_box(xf, side, u - ww / 2 - ar / 2, vc, an, ar, h, 0.024, hm.trim)
	wall_box(xf, side, u + ww / 2 + ar / 2, vc, an, ar, h, 0.024, hm.trim)
	wall_box(xf, side, u, vc, 0, 0.04, h - 2 * fw, 0.05, hm.trim)
	wall_box(xf, side, u, v0 + h * 0.62, 0, ww - 2 * fw, 0.04, 0.05, hm.trim)
	wall_box(xf, side, u, v0 - 0.03, T / 2 + 0.09, ww + 0.3, 0.06, 0.17, hm.trim)
	wall_box(xf, side, u, v0 - 0.012, -T / 2 - 0.07, ww + 0.2, 0.04, 0.13, hm.trim, false)
	# glass pane: about two thirds of the windows light up at night
	var p := wall_point(side, u, vc, 0)
	var gm: Dictionary = window_mats[0] if rng.randf() >= 0.65 else window_mats[1 + rng.randi() % 3]
	var gf: Transform3D = xf * Transform3D(Basis(Vector3.UP, SIDE_ROT[side]), p)
	vbe.polygon(gf, PackedVector2Array([Vector2(-ww / 2, -h / 2), Vector2(ww / 2, -h / 2), Vector2(ww / 2, h / 2), Vector2(-ww / 2, h / 2)]), gm.mat, 1.0, false)
	# Curtains on a rod, drawn to the sides
	var palette := ["#c8b89a", "#8fa3b0", "#b67a6a", "#9aab8a", "#d9d2c3", "#7d6b8f"]
	var cm := fabric(palette[(cfg.number + k) % palette.size()])
	cm.vary = true
	var ni := -T / 2 - 0.13
	wall_box(xf, side, u, v1 + 0.28, ni, ww + 0.8, 0.03, 0.03, hm.brushed, false)
	for s in [-1.0, 1.0]:
		wall_box(xf, side, u + s * (ww / 2 + 0.05), (v1 + 0.27 + v0 - 0.25) / 2, ni, 0.42, v1 - v0 + 0.52, 0.05, cm, false)
	# Radiator under ground-floor windows (not behind the kitchen counter)
	if v1 < 3.2 and not (side == "back" and u < 0):
		var rw := minf(ww - 0.2, 1.3)
		for f in 5:
			wall_box(xf, side, u - rw / 2 + (f + 0.5) * rw / 5, 0.45, -T / 2 - 0.09, rw / 5 - 0.03, 0.55, 0.07, hm.radiator, false)


## Straight flight of 18 steps against the hall partition, banister, and railings round the stairwell
func _stairs(xf: Transform3D) -> void:
	var n := 18
	var run := (SX1 - SX0) / n
	var rise := UP / n
	var depth := SZ1 - SZ0
	var zc := (SZ0 + SZ1) / 2
	var step_mats := [hm.white, hm.white, hm.wood_mid, hm.white, hm.white, hm.white]
	for i in n:
		var top := (i + 1) * rise
		box(xf, run, top, depth, SX0 + (i + 0.5) * run, top / 2, zc, step_mats, i % 3 == 0)
		box(xf, 0.04, 0.03, depth, SX0 + i * run + 0.01, top - 0.015, zc, hm.wood_dark)
	# Walkable ramp under the treads (the web version kept its own stair heights; Godot needs a surface)
	var ang := atan2(UP, SX1 - SX0)
	var len := Vector2(SX1 - SX0, UP).length()
	var nrm := Vector3(-sin(ang), cos(ang), 0)
	var c := Vector3((SX0 + SX1) / 2, UP / 2, zc) - nrm * 0.05
	if mode != 1:
		w.solid(xf * Transform3D(Basis(Vector3.BACK, ang), c), Vector3.ZERO, Vector3(len + 0.3, 0.1, depth))
	# Banister on the open side
	var rz := SZ1 + 0.05
	limb(xf, Vector3(SX0, 0.95, rz), Vector3(SX1, UP + 0.95, rz), 0.03, 0.03, hm.wood_dark)
	box(xf, 0.1, 1.15, 0.1, SX0, 0.575, rz, hm.wood_dark, true)
	var x := SX0 + 0.25
	while x < SX1:
		var t := (x - SX0) / (SX1 - SX0)
		var y0 := ceilf(t * n) * rise
		var y1 := t * UP + 0.95
		if y1 - y0 > 0.1:
			box(xf, 0.03, y1 - y0, 0.03, x, (y0 + y1) / 2, rz, hm.white)
		x += 0.26
	# Upstairs railings round the stairwell (open side and the bottom end)
	var rail := func(x0: float, z0: float, x1: float, z1: float) -> void:
		var l := Vector2(x1 - x0, z1 - z0).length()
		var along_x := absf(x1 - x0) > absf(z1 - z0)
		box(xf, l if along_x else 0.07, 0.06, 0.07 if along_x else l, (x0 + x1) / 2, UP + 0.95, (z0 + z1) / 2, hm.wood_dark)
		var steps := maxi(1, roundi(l / 0.13))
		for i in steps + 1:
			var f := float(i) / steps
			box(xf, 0.03, 0.92, 0.03, x0 + (x1 - x0) * f, UP + 0.46, z0 + (z1 - z0) * f, hm.white)
	rail.call(SX0, rz, SX1, rz)
	rail.call(SX0 - 0.05, SZ0, SX0 - 0.05, rz)
	box(xf, 0.1, 1.1, 0.1, SX1, UP + 0.55, rz, hm.wood_dark)
	col(xf, (SX0 + SX1) / 2, rz + 0.04, SX1 - SX0, 0.12, UP + 1.1, 0)
	col(xf, SX0 - 0.06, (SZ0 + rz) / 2, 0.12, rz - SZ0, UP + 1.1, UP - 0.1)


## Five room lights for the floor the player is on: one per room plus the hall / stairs
static func room_light_spots(rec: Dictionary, upstairs: bool) -> Array:
	var spots := [[-3.5, 4.4], [4.4, 4.4], [-5.1, -3.9], [2.6, -3.9], [-1.0, 0.8]] if upstairs \
		else [[-4.5, 2.6], [4.2, 3.6], [-3.8, -4.0], [4.6, -4.0], [0.6, 1.0]]
	var y := UP + 2.0 if upstairs else 2.6
	var out: Array = []
	var xf: Transform3D = rec.xf
	for s in spots:
		var p: Vector3 = xf * Vector3(s[0], 0, s[1])
		out.append(Vector3(p.x, y, p.z))
	return out


func house_at(x: float, z: float):
	for h in interiors:
		var r: Rect2 = h.rect
		if r.has_point(Vector2(x, z)):
			return h
	return null


# ---------------------------------------------------------------------------------------------- interior
func _interior(xf: Transform3D, cfg: Dictionary) -> void:
	var n: int = cfg.number
	var sofa_colors := ["#5d6b78", "#7a5c4a", "#55684f", "#6e6a63", "#8a4f4a", "#4a5466", "#786b55", "#5f5a70"]
	var fab := fabric(sofa_colors[n % sofa_colors.size()])
	var duvet := fabric(sofa_colors[(n + 3) % sofa_colors.size()])
	var duvet2 := fabric(sofa_colors[(n + 5) % sofa_colors.size()])
	fab.vary = true
	duvet.vary = true
	duvet2.vary = true
	# ---- Partitions ----
	var wall_p := func(ww: float, dd: float, cx: float, cz: float, y0: float, hh: float) -> void:
		box(xf, ww, hh, dd, cx, y0 + hh / 2, cz, hm.plaster3, true)
	var t := 0.12
	var pz := -1.0
	# Ground: front rooms | back rooms (doorway x -0.5..0.7), kitchen | bedroom
	wall_p.call(IX - 0.6, t, (-IX - 0.6) / 2, pz, 0, SLAB0)
	col(xf, (-IX - 0.6) / 2, pz, IX - 0.6, t, 3.4)
	wall_p.call(IX - 0.8, t, (0.8 + IX) / 2, pz, 0, SLAB0)
	col(xf, (0.8 + IX) / 2, pz, IX - 0.8, t, 3.4)
	wall_p.call(1.4, t, 0.1, pz, 2.3, SLAB0 - 2.3)
	wall_p.call(t, IZ - 2.5, 1.5, (-IZ - 2.5) / 2, 0, SLAB0)
	col(xf, 1.5, (-IZ - 2.5) / 2, t, IZ - 2.5, 3.4)
	# Upper: hall | front rooms (z 2.0), hall | back rooms (z -1.0), master | study (x 1.0), bath | bedroom (x -2.5)
	var H2 := CEIL2 - UP
	var up_wall := func(x0: float, x1: float, z0: float, z1: float, door_list: Array) -> void:
		var along_x := absf(x1 - x0) > absf(z1 - z0)
		var a0 := x0 if along_x else z0
		var a1 := x1 if along_x else z1
		var fixed := z0 if along_x else x0
		var cuts := [a0]
		for dd in door_list:
			cuts.append(dd[0])
			cuts.append(dd[1])
		cuts.append(a1)
		for i in range(0, cuts.size(), 2):
			var s0: float = cuts[i]
			var s1: float = cuts[i + 1]
			var c := (s0 + s1) / 2
			var L := s1 - s0
			if L < 0.01:
				continue
			if along_x:
				wall_p.call(L, t, c, fixed, UP, H2)
				col(xf, c, fixed, L, t, 7, UP - 0.05)
			else:
				wall_p.call(t, L, fixed, c, UP, H2)
				col(xf, fixed, c, t, L, 7, UP - 0.05)
		for dd in door_list:
			var c: float = (dd[0] + dd[1]) / 2
			var L: float = dd[1] - dd[0]
			if along_x:
				wall_p.call(L, t, c, fixed, UP + 2.2, H2 - 2.2)
			else:
				wall_p.call(t, L, fixed, c, UP + 2.2, H2 - 2.2)
	up_wall.call(-IX, IX, 2.0, 2.0, [[-1.9, -0.6], [2.0, 3.3]])
	up_wall.call(-IX, IX, pz, pz, [[-4.4, -3.1], [-2.0, -0.7]])
	up_wall.call(1.0, 1.0, 2.0 + t / 2, IZ, [])
	up_wall.call(-2.5, -2.5, -IZ, pz - t / 2, [])

	# Skirting boards round the outside walls on both floors
	for y in [0.04 + 0.06, UP + 0.06]:
		box(xf, W - 2 * T, 0.12, 0.015, 0, y, -IZ + 0.008, hm.trim)
		box(xf, 0.015, 0.12, D - 2 * T, -IX + 0.008, y, 0, hm.trim)
		box(xf, 0.015, 0.12, D - 2 * T, IX - 0.008, y, 0, hm.trim)
		for s in [-1.0, 1.0]:
			box(xf, IX - 0.6, 0.12, 0.015, s * (0.6 + (IX - 0.6) / 2), y, IZ - 0.008, hm.trim)
	# Interior door casings for the ground-floor doorway
	box(xf, 0.08, 2.35, 0.16, -0.64, 1.175, pz, hm.trim)
	box(xf, 0.08, 2.35, 0.16, 0.84, 1.175, pz, hm.trim)
	box(xf, 1.56, 0.08, 0.16, 0.1, 2.34, pz, hm.trim)

	_living_room(xf, fab, n)
	_kitchen(xf)
	# ---- Guest bedroom (ground floor, back right) ----
	box(xf, 1.75, 0.32, 2.1, 5.0, 0.16, -5.7, hm.wood_dark)
	box(xf, 1.62, 0.22, 2.0, 5.0, 0.43, -5.7, hm.linen)
	box(xf, 1.66, 0.08, 1.45, 5.0, 0.57, -5.2, duvet)
	for s in [-1.0, 1.0]:
		box(xf, 0.6, 0.12, 0.35, 5.0 + s * 0.4, 0.6, -6.45, hm.linen)
	box(xf, 1.85, 0.95, 0.08, 5.0, 0.5, -6.75, hm.wood_dark)
	solid(xf, 5.0, -5.7, 1.8, 2.2)
	for nx in [3.75, 6.25]:
		box(xf, 0.45, 0.5, 0.42, nx, 0.25, -6.5, hm.wood_mid)
		table_lamp(xf, nx, 0.5, -6.5)
	box(xf, 0.6, 2.1, 1.6, 7.45, 1.05, -2.6, hm.wood_mid)
	solid(xf, 7.45, -2.6, 0.6, 1.6)
	rug(xf, 5.0, 0.045, -4.4, 2.2, 1.4, n + 1)

	_upstairs(xf, duvet, duvet2, n)

	# Ceiling lights (glow when the house light is on)
	for f in [[-4.5, 2.6, SLAB0], [4.2, 3.6, SLAB0], [-3.5, -4.0, SLAB0], [4.6, -4.0, SLAB0],
			[-3.5, 4.4, CEIL2], [4.4, 4.4, CEIL2], [-5.1, -3.9, CEIL2], [2.6, -3.9, CEIL2], [-3.0, 0.5, CEIL2]]:
		prim(xf, _cyl(0.28, 0.32, 0.08, 20), fixture_mat, Vector3(f[0], f[2] - 0.04, f[1]))


func _living_room(xf: Transform3D, fab: Dictionary, n: int) -> void:
	rug(xf, -5.0, 0.045, 2.6, 2.4, 3.2, n)
	# Sofa with seat and back cushions
	box(xf, 0.95, 0.42, 2.4, -7.25, 0.21, 2.6, fab)
	box(xf, 0.25, 0.85, 2.4, -7.6, 0.5, 2.6, fab)
	for s in [-1.0, 1.0]:
		box(xf, 0.95, 0.62, 0.22, -7.25, 0.31, 2.6 + s * 1.31, fab)
		box(xf, 0.75, 0.14, 1.12, -7.2, 0.49, 2.6 + s * 0.58, fab)
		box(xf, 0.18, 0.5, 1.05, -7.38, 0.78, 2.6 + s * 0.58, fab)
		box(xf, 0.12, 0.38, 0.38, -7.28, 0.75, 2.6 + s * 1.0, fabric("#d9c9a6"))
	solid(xf, -7.3, 2.6, 1.1, 2.8)
	painting(xf, -IX + 0.01, 1.85, 2.6, PI / 2, 1.4, 0.95, n)
	# Coffee table with books and a mug
	box(xf, 0.7, 0.05, 1.2, -5.6, 0.43, 2.6, hm.wood_mid)
	legs(xf, -5.6, 2.6, 0.7, 1.2, 0.41, hm.wood_mid)
	box(xf, 0.6, 0.02, 1.1, -5.6, 0.12, 2.6, hm.wood_mid)
	box(xf, 0.22, 0.05, 0.3, -5.5, 0.48, 2.3, fabric("#8a3b2a"))
	box(xf, 0.2, 0.04, 0.28, -5.5, 0.525, 2.3, fabric("#2f4b6b"))
	prim(xf, _cyl(0.04, 0.04, 0.09, 12), hm.porcelain, Vector3(-5.7, 0.5, 2.95))
	solid(xf, -5.6, 2.6, 0.7, 1.2)
	# Side table + lamp
	box(xf, 0.45, 0.55, 0.45, -7.25, 0.275, 4.2, hm.wood_dark)
	table_lamp(xf, -7.25, 0.55, 4.2)
	# TV on a media unit: glossy screen in a thin bezel, soundbar, console
	box(xf, 0.45, 0.5, 1.8, -3.0, 0.25, 2.6, hm.wood_dark)
	box(xf, 0.06, 0.74, 1.3, -3.08, 0.98, 2.6, hm.black)
	box(xf, 0.01, 0.68, 1.24, -3.115, 0.98, 2.6, hm.screen)
	box(xf, 0.15, 0.03, 0.35, -3.05, 0.515, 2.6, hm.black)
	box(xf, 0.08, 0.06, 0.9, -3.12, 0.53, 2.6, hm.black)
	box(xf, 0.25, 0.05, 0.3, -3.0, 0.1, 2.1, hm.black)
	solid(xf, -3.0, 2.6, 0.5, 1.8)
	# Armchair
	box(xf, 0.85, 0.42, 0.85, -5.0, 0.21, 5.7, fab)
	box(xf, 0.85, 0.85, 0.22, -5.0, 0.5, 6.1, fab)
	for s in [-1.0, 1.0]:
		box(xf, 0.16, 0.6, 0.85, -5.0 + s * 0.42, 0.3, 5.7, fab)
	solid(xf, -5.0, 5.75, 0.9, 0.9)
	# Floor lamp
	box(xf, 0.3, 0.03, 0.3, -7.3, 0.015, 5.9, hm.black)
	box(xf, 0.035, 1.5, 0.035, -7.3, 0.75, 5.9, hm.black)
	prim(xf, _cyl(0.18, 0.26, 0.32, 16, true), hm.shade, Vector3(-7.3, 1.6, 5.9))
	# Dining table and chairs, a bowl of fruit, pendant above
	box(xf, 1.8, 0.05, 1.0, 4.2, 0.75, 3.6, hm.wood_mid)
	legs(xf, 4.2, 3.6, 1.8, 1.0, 0.73, hm.wood_mid)
	solid(xf, 4.2, 3.6, 1.8, 1.0)
	for c in [[3.6, 2.75, 1.0], [4.8, 2.75, 1.0], [3.6, 4.45, -1.0], [4.8, 4.45, -1.0]]:
		box(xf, 0.45, 0.05, 0.45, c[0], 0.45, c[1], hm.wood_dark)
		legs(xf, c[0], c[1], 0.45, 0.45, 0.43, hm.wood_dark)
		box(xf, 0.45, 0.5, 0.05, c[0], 0.72, c[1] - c[2] * 0.2, hm.wood_dark)
	prim(xf, _sph(0.18, 16, 8, true), hm.porcelain, Vector3(4.2, 0.95, 3.6), Basis.from_scale(Vector3(1, -1, 1)))
	for f in [[0.0, 0.0, "#d9442b"], [0.07, 0.05, "#e3b23c"], [-0.06, 0.04, "#7aa83a"]]:
		prim(xf, _sph(0.05, 10, 8), fabric(f[2]), Vector3(4.2 + f[0], 0.84, 3.6 + f[1]))
	box(xf, 0.012, 1.1, 0.012, 4.2, SLAB0 - 0.55, 3.6, hm.black)
	prim(xf, _cyl(0.0, 0.25, 0.22, 20, true), hm.dark_steel, Vector3(4.2, SLAB0 - 1.15, 3.6))
	# Bookshelf with books on every shelf
	box(xf, 0.35, 2.0, 1.4, 7.55, 1.0, 5.4, hm.wood_dark)
	picture(xf * Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(7.37, 1.0, 5.4)), 1.3, 1.85, hm.books)
	solid(xf, 7.55, 5.4, 0.4, 1.4)
	plant(xf, 1.7, 0.04, 6.2)
	painting(xf, -2.2, 1.9, IZ - 0.01, PI, 0.8, 0.6, n + 2)
	# Coat hooks and a shoe bench by the front door
	box(xf, 0.9, 0.45, 0.35, -1.4, 0.225, 6.55, hm.wood_light)
	box(xf, 0.9, 0.06, 0.04, -1.4, 1.7, 6.78, hm.wood_dark)
	box(xf, 0.25, 0.7, 0.12, -1.65, 1.35, 6.7, fabric("#3d4a5c"))
	solid(xf, -1.4, 6.55, 0.9, 0.4)


func _kitchen(xf: Transform3D) -> void:
	var zb := -IZ
	var cab_d := 0.6
	var zc := zb + cab_d / 2
	var front := zb + cab_d
	var x0 := -7.7
	var x1 := -1.2
	# Base cabinets, worktop, toe kick
	box(xf, x1 - x0, 0.78, cab_d - 0.02, (x0 + x1) / 2, 0.47, zc - 0.01, hm.cabinet)
	box(xf, x1 - x0, 0.08, cab_d - 0.08, (x0 + x1) / 2, 0.04, zc - 0.04, hm.black)
	box(xf, x1 - x0 + 0.04, 0.04, cab_d + 0.04, (x0 + x1) / 2, 0.88, zc + 0.01, hm.counter)
	solid(xf, (x0 + x1) / 2, zc, x1 - x0, cab_d + 0.1)
	var oven_x := -6.3
	var sink_x := -3.5
	var dish_x := -2.55
	# Cabinet doors (with a drawer above each) and steel bar handles
	var x := x0 + 0.3
	while x < x1:
		if not (absf(x - oven_x) < 0.5 or absf(x - dish_x) < 0.35):
			box(xf, 0.56, 0.55, 0.02, x, 0.38, front + 0.01, hm.cabinet_door)
			box(xf, 0.56, 0.16, 0.02, x, 0.76, front + 0.01, hm.cabinet_door)
			box(xf, 0.14, 0.015, 0.025, x, 0.79, front + 0.035, hm.steel)
			box(xf, 0.015, 0.14, 0.025, x + 0.22, 0.55, front + 0.035, hm.steel)
		x += 0.6
	# Oven: steel front, dark glass window, bar handle, control knobs; induction hob above
	box(xf, 0.76, 0.72, 0.03, oven_x, 0.46, front + 0.015, hm.brushed)
	box(xf, 0.56, 0.32, 0.01, oven_x, 0.42, front + 0.035, hm.glass_dark)
	prim(xf, _cyl(0.012, 0.012, 0.6, 8), hm.steel, Vector3(oven_x, 0.68, front + 0.07), Basis(Vector3.BACK, PI / 2))
	for k in 4:
		prim(xf, _cyl(0.022, 0.022, 0.025, 12), hm.black, Vector3(oven_x - 0.24 + k * 0.16, 0.79, front + 0.035), _rx(PI / 2))
	box(xf, 0.62, 0.006, 0.52, oven_x, 0.903, zc, hm.glass_dark)
	for r in [[-0.15, -0.12, 0.09], [0.15, -0.12, 0.07], [-0.15, 0.12, 0.07], [0.15, 0.12, 0.1]]:
		torus(xf, r[2], 0.004, hm.dark_steel, Vector3(oven_x + r[0], 0.908, zc + r[1]), _rx(PI / 2), 28)
	# Cooker hood and chimney
	box(xf, 0.8, 0.1, 0.5, oven_x, 1.72, zb + 0.25, hm.brushed)
	box(xf, 0.3, SLAB0 - 1.77, 0.25, oven_x, (SLAB0 + 1.77) / 2, zb + 0.13, hm.brushed)
	# Sink under the window: steel bowl, mixer tap
	box(xf, 0.72, 0.012, 0.46, sink_x, 0.906, zc, hm.brushed)
	box(xf, 0.58, 0.004, 0.36, sink_x, 0.913, zc + 0.02, hm.dark_steel)
	prim(xf, _cyl(0.025, 0.03, 0.06, 12), hm.steel, Vector3(sink_x, 0.93, zb + 0.1))
	var bz := [Vector3(sink_x, 0.95, zb + 0.1), Vector3(sink_x, 1.3, zb + 0.1), Vector3(sink_x, 1.3, zb + 0.32), Vector3(sink_x, 1.15, zb + 0.34)]
	var prev: Vector3 = bz[0]
	for i in range(1, 7):
		var tt := i / 6.0
		var p: Vector3 = bz[0] * pow(1 - tt, 3) + bz[1] * 3 * pow(1 - tt, 2) * tt + bz[2] * 3 * (1 - tt) * tt * tt + bz[3] * pow(tt, 3)
		limb(xf, prev, p, 0.014, 0.014, hm.steel)
		prev = p
	box(xf, 0.015, 0.015, 0.1, sink_x + 0.06, 1.0, zb + 0.13, hm.steel)
	# Dishwasher
	box(xf, 0.6, 0.72, 0.03, dish_x, 0.46, front + 0.015, hm.brushed)
	box(xf, 0.5, 0.02, 0.03, dish_x, 0.76, front + 0.05, hm.steel)
	# Tiled backsplash (stops under the window)
	for bs in [[x0, -4.42, 0.9, 1.6], [-2.58, x1, 0.9, 1.6], [-4.42, -2.58, 0.9, 1.1]]:
		box(xf, bs[1] - bs[0], bs[3] - bs[2], 0.012, (bs[0] + bs[1]) / 2, (bs[2] + bs[3]) / 2, zb + 0.006, hm.tile_kitchen)
	# Wall cabinets with doors and handles
	for ab in [[-7.65, -6.95], [-5.95, -4.55], [-2.45, -1.25]]:
		var ww: float = ab[1] - ab[0]
		var cx: float = (ab[0] + ab[1]) / 2
		box(xf, ww, 0.75, 0.35, cx, 2.02, zb + 0.175, hm.cabinet)
		var nd := maxi(1, roundi(ww / 0.5))
		for k in nd:
			var dx: float = ab[0] + (k + 0.5) * ww / nd
			box(xf, ww / nd - 0.02, 0.71, 0.02, dx, 2.02, zb + 0.36, hm.cabinet_door)
			box(xf, 0.015, 0.12, 0.025, dx + (-1.0 if k % 2 else 1.0) * (ww / nd / 2 - 0.06), 1.74, zb + 0.385, hm.steel)
	# Microwave, kettle, knife block, chopping board, a plant on the sill
	box(xf, 0.5, 0.3, 0.38, -1.65, 1.05, zc - 0.04, hm.brushed)
	box(xf, 0.33, 0.22, 0.01, -1.72, 1.05, zc + 0.155, hm.glass_dark)
	box(xf, 0.1, 0.22, 0.01, -1.47, 1.05, zc + 0.155, hm.black)
	prim(xf, _cyl(0.08, 0.1, 0.22, 16), hm.steel, Vector3(-5.2, 1.01, zc - 0.05))
	box(xf, 0.12, 0.22, 0.1, -4.8, 1.01, zc - 0.12, hm.wood_dark)
	box(xf, 0.4, 0.02, 0.28, -2.0, 0.91, zc + 0.08, hm.wood_light)
	plant(xf, -3.95, 1.13, zb + 0.08, 0.35)
	# Fridge-freezer: steel doors with a gap, long bar handles, water dispenser, grille, magnets
	var fx := 0.8
	var fz := zb + 0.36
	var fw := 0.82
	var fh := 1.85
	var fd := 0.7
	box(xf, fw, fh, fd - 0.04, fx, fh / 2, fz - 0.02, hm.brushed)
	var ff := fz + fd / 2
	box(xf, fw - 0.02, 0.62, 0.05, fx, fh - 0.33, ff + 0.005, hm.steel)
	box(xf, fw - 0.02, 1.12, 0.05, fx, 0.66, ff + 0.005, hm.steel)
	box(xf, fw - 0.01, 0.012, 0.04, fx, 1.215, ff, hm.black)
	box(xf, fw - 0.06, 0.07, 0.02, fx, 0.04, ff - 0.01, hm.black)
	for yl in [[fh - 0.33, 0.45], [0.75, 0.75]]:
		prim(xf, _cyl(0.014, 0.014, yl[1], 10), hm.steel, Vector3(fx - fw / 2 + 0.07, yl[0], ff + 0.075))
		for s in [-1.0, 1.0]:
			box(xf, 0.02, 0.02, 0.05, fx - fw / 2 + 0.07, yl[0] + s * (yl[1] / 2 - 0.02), ff + 0.05, hm.steel)
	box(xf, 0.2, 0.3, 0.012, fx + 0.18, 1.0, ff + 0.035, hm.glass_dark)
	for mg in [["#e8463a", 0.1, 0.62], ["#3a8be8", -0.05, 0.5], ["#f2d04a", 0.15, 0.4], ["#ffffff", 0.0, 0.75]]:
		box(xf, 0.07, 0.09, 0.006, fx + mg[1], mg[2], ff + 0.034, fabric(mg[0]))
	solid(xf, fx, fz, fw, fd + 0.1)
	# Kitchen table, chairs, wall clock
	box(xf, 1.2, 0.05, 0.8, -4.2, 0.75, -3.4, hm.wood_mid)
	legs(xf, -4.2, -3.4, 1.2, 0.8, 0.73, hm.wood_mid)
	solid(xf, -4.2, -3.4, 1.2, 0.8)
	for s in [-1.0, 1.0]:
		box(xf, 0.42, 0.05, 0.42, -4.2 + s * 0.35, 0.45, -2.75, hm.wood_dark)
		legs(xf, -4.2 + s * 0.35, -2.75, 0.42, 0.42, 0.43, hm.wood_dark)
		box(xf, 0.42, 0.5, 0.05, -4.2 + s * 0.35, 0.72, -2.55, hm.wood_dark)
	prim(xf, _cyl(0.17, 0.17, 0.04, 24), hm.porcelain, Vector3(-4.2, 2.3, -1.08), _rx(PI / 2))
	box(xf, 0.01, 0.12, 0.01, -4.2, 2.34, -1.11, hm.black)
	box(xf, 0.09, 0.01, 0.01, -4.16, 2.3, -1.11, hm.black)


func _upstairs(xf: Transform3D, duvet: Dictionary, duvet2: Dictionary, n: int) -> void:
	var y := UP
	var S := func(x: float, z: float, ww: float, dd: float) -> void: solid(xf, x, z, ww, dd, y)
	# Hall runner and a painting
	rug(xf, -3.0, y + 0.005, 0.5, 6.5, 1.0, n + 2)
	painting(xf, -4.8, y + 1.6, 2.0 - 0.07, PI, 1.0, 0.7, n + 3)
	# ---- Master bedroom (front left) ----
	box(xf, 2.15, 0.3, 1.7, -6.65, y + 0.15, 4.0, hm.wood_dark)
	box(xf, 2.05, 0.22, 1.6, -6.65, y + 0.41, 4.0, hm.linen)
	box(xf, 1.4, 0.08, 1.66, -6.15, y + 0.55, 4.0, duvet)
	for s in [-1.0, 1.0]:
		box(xf, 0.38, 0.13, 0.62, -7.45, y + 0.58, 4.0 + s * 0.4, hm.linen)
	box(xf, 0.08, 0.9, 1.8, -IX + 0.05, y + 0.45, 4.0, hm.wood_dark)
	S.call(-6.65, 4.0, 2.2, 1.8)
	for nz in [2.75, 5.25]:
		box(xf, 0.42, 0.5, 0.42, -7.5, y + 0.25, nz, hm.wood_mid)
		table_lamp(xf, -7.5, y + 0.5, nz)
	rug(xf, -5.6, y + 0.005, 4.0, 2.4, 2.6, n + 3)
	# dresser with mirror against the hall wall
	box(xf, 1.3, 0.85, 0.48, -3.6, y + 0.425, 2.36, hm.wood_mid)
	for k in 3:
		box(xf, 1.24, 0.24, 0.02, -3.6, y + 0.15 + k * 0.27, 2.61, hm.wood_light)
	box(xf, 0.8, 0.9, 0.03, -3.6, y + 1.45, 2.12, hm.wood_dark)
	box(xf, 0.72, 0.82, 0.01, -3.6, y + 1.45, 2.14, hm.mirror)
	S.call(-3.6, 2.36, 1.3, 0.5)
	# wardrobe
	box(xf, 0.6, 2.1, 1.5, 0.62, y + 1.05, 5.6, hm.wood_mid)
	box(xf, 0.02, 2.0, 0.02, 0.31, y + 1.05, 5.6, hm.wood_dark)
	S.call(0.62, 5.6, 0.6, 1.5)
	plant(xf, -1.0, y, 6.3, 0.9)
	# ---- Study (front right) ----
	box(xf, 1.5, 0.05, 0.7, 4.5, y + 0.74, 6.35, hm.wood_light)
	legs(xf, 4.5, 6.35, 1.5, 0.7, 0.72, hm.black, y)
	box(xf, 0.6, 0.38, 0.03, 4.5, y + 1.0, 6.45, hm.black)
	box(xf, 0.56, 0.33, 0.005, 4.5, y + 1.02, 6.43, hm.screen)
	box(xf, 0.06, 0.16, 0.06, 4.5, y + 0.83, 6.5, hm.black)
	box(xf, 0.45, 0.02, 0.15, 4.5, y + 0.775, 6.15, hm.black)
	box(xf, 0.06, 0.02, 0.1, 4.85, y + 0.775, 6.15, hm.black)
	S.call(4.5, 6.35, 1.5, 0.75)
	# office chair: seat, back, gas lift, star base
	box(xf, 0.48, 0.07, 0.46, 4.5, y + 0.48, 5.65, hm.black)
	box(xf, 0.46, 0.55, 0.06, 4.5, y + 0.82, 5.42, hm.black)
	box(xf, 0.04, 0.4, 0.04, 4.5, y + 0.25, 5.65, hm.steel)
	prim(xf, _cyl(0.3, 0.3, 0.04, 5), hm.black, Vector3(4.5, y + 0.06, 5.65))
	# bookshelves on the side wall, reading chair and lamp
	box(xf, 0.35, 2.0, 1.2, 7.6, y + 1.0, 6.0, hm.wood_dark)
	picture(xf * Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(7.42, y + 1.0, 6.0)), 1.1, 1.85, hm.books)
	S.call(7.6, 6.0, 0.4, 1.2)
	var chair := fabric("#6e7f63")
	box(xf, 0.8, 0.42, 0.8, 6.8, y + 0.21, 2.8, chair)
	box(xf, 0.8, 0.8, 0.2, 6.8, y + 0.5, 2.5, chair)
	S.call(6.8, 2.75, 0.85, 0.85)
	rug(xf, 5.0, y + 0.005, 4.4, 2.4, 2.0, n)
	painting(xf, 1.0 + 0.07, y + 1.6, 4.4, PI / 2, 0.9, 0.65, n + 4)
	# ---- Bathroom (back left): tiles, bath, toilet, vanity with mirror ----
	var bx0 := -IX
	var bx1 := -2.56
	var bz0 := -IZ
	var bz1 := -1.07
	box(xf, bx1 - bx0, 0.012, bz1 - bz0, (bx0 + bx1) / 2, y + 0.006, (bz0 + bz1) / 2, hm.tile_floor)
	box(xf, bx1 - bx0, 0.95, 0.012, (bx0 + bx1) / 2, y + 0.475, bz0 + 0.006, hm.tile_bath)
	box(xf, 0.012, 0.95, bz1 - bz0, bx0 + 0.006, y + 0.475, (bz0 + bz1) / 2, hm.tile_bath)
	box(xf, 1.75, 0.56, 0.78, -6.9, y + 0.28, -6.38, hm.porcelain)
	box(xf, 1.55, 0.01, 0.58, -6.9, y + 0.565, -6.38, fabric("#bcd6dc"))
	box(xf, 0.05, 0.25, 0.05, -7.65, y + 0.68, -6.38, hm.steel)
	S.call(-6.9, -6.38, 1.75, 0.8)
	prim(xf, _cyl(0.17, 0.13, 0.38, 16), hm.porcelain, Vector3(-4.6, y + 0.19, -6.35))
	prim(xf, _cyl(0.2, 0.2, 0.05, 20), hm.porcelain, Vector3(-4.6, y + 0.41, -6.32), Basis.from_scale(Vector3(1, 1, 1.2)))
	box(xf, 0.42, 0.42, 0.18, -4.6, y + 0.62, -6.66, hm.porcelain)
	box(xf, 0.08, 0.01, 0.05, -4.6, y + 0.835, -6.66, hm.steel)
	S.call(-4.6, -6.45, 0.5, 0.7)
	box(xf, 0.5, 0.82, 1.0, -7.5, y + 0.41, -2.0, hm.wood_light)
	box(xf, 0.55, 0.04, 1.05, -7.48, y + 0.84, -2.0, hm.porcelain)
	box(xf, 0.36, 0.01, 0.5, -7.45, y + 0.865, -2.0, fabric("#d8dde0"))
	box(xf, 0.03, 0.18, 0.03, -7.7, y + 0.95, -2.0, hm.steel)
	box(xf, 0.12, 0.02, 0.02, -7.64, y + 1.03, -2.0, hm.steel)
	box(xf, 0.02, 0.85, 0.75, -IX + 0.02, y + 1.6, -2.0, hm.mirror)
	S.call(-7.5, -2.0, 0.55, 1.05)
	box(xf, 0.03, 0.03, 0.7, -IX + 0.08, y + 1.15, -5.3, hm.steel)
	box(xf, 0.05, 0.6, 0.55, -IX + 0.1, y + 0.85, -5.3, fabric("#f2efe8"))
	rug(xf, -6.9, y + 0.015, -5.6, 1.0, 0.6, n + 1)
	# ---- Second bedroom (back right) ----
	box(xf, 1.0, 0.3, 2.05, 6.95, y + 0.15, -5.75, hm.wood_light)
	box(xf, 0.92, 0.2, 1.95, 6.95, y + 0.4, -5.75, hm.linen)
	box(xf, 0.96, 0.08, 1.4, 6.95, y + 0.53, -5.3, duvet2)
	box(xf, 0.6, 0.12, 0.35, 6.95, y + 0.56, -6.5, hm.linen)
	box(xf, 1.0, 0.8, 0.06, 6.95, y + 0.4, -IZ + 0.03, hm.wood_light)
	S.call(6.95, -5.75, 1.05, 2.1)
	box(xf, 1.2, 0.05, 0.6, 3.5, y + 0.74, -6.45, hm.wood_light)
	legs(xf, 3.5, -6.45, 1.2, 0.6, 0.72, hm.wood_light, y)
	box(xf, 0.4, 0.05, 0.4, 3.5, y + 0.45, -5.85, hm.wood_mid)
	legs(xf, 3.5, -5.85, 0.4, 0.4, 0.43, hm.wood_mid, y)
	box(xf, 0.4, 0.45, 0.04, 3.5, y + 0.72, -5.65, hm.wood_mid)
	S.call(3.5, -6.3, 1.2, 0.9)
	prim(xf, _sph(0.42, 16, 10), fabric("#c9473d"), Vector3(0.8, y + 0.25, -3.2), Basis.from_scale(Vector3(1, 0.6, 1)))
	box(xf, 0.6, 0.45, 0.4, -1.5, y + 0.225, -6.5, fabric("#3f7cac"))
	box(xf, 1.2, 2.0, 0.55, 0.3, y + 1.0, -1.42, hm.wood_light)
	S.call(0.3, -1.42, 1.2, 0.55)
	rug(xf, 3.0, y + 0.005, -3.8, 2.0, 2.0, n + 2)
	painting(xf, -2.5 + 0.07, y + 1.6, -4.0, PI / 2, 0.7, 0.5, n + 5)


# ---------------------------------------------------------------------------------------------- front door
## Front door on a hinge: swings inward when opened with E
func _front_door(xf: Transform3D, st: Dictionary) -> void:
	var hinge := Node3D.new()
	hinge.transform = xf * Transform3D(Basis(), Vector3(-0.6, 0, D / 2 - 0.1))
	w.add_child(hinge)
	var db := Batch.new()
	db.box(Transform3D.IDENTITY, Vector3(0.6, 1.15, 0), Vector3(1.18, 2.28, 0.06), w.door_mat(st.door), 1.0, true, true)
	for kz in [-0.06, 0.06]:
		db.mesh(Transform3D(Basis(), Vector3(1.05, 1.0, kz)), _sph(0.045, 12, 8), w.mats.gilt)
	db.commit(hinge)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 4.0, 0.2)
	cs.shape = bs
	cs.transform = Transform3D(xf.basis, xf * Vector3(0, 2.0, D / 2 - 0.1))
	w.body.add_child(cs)
	var d := {"hinge": hinge, "base": hinge.transform, "angle": 0.0, "target": 0.0, "shape": cs}
	doors.append(d)
	var item := {"pos": xf * Vector3(0, 1.4, D / 2), "prompt": "[E] Open door", "type": "door"}
	item["call"] = func() -> Dictionary:
		var opening: bool = d.target == 0.0
		d.target = PI * 0.48 if opening else 0.0
		cs.set_deferred("disabled", opening)
		item.prompt = "[E] Close door" if opening else "[E] Open door"
		return {"sound": "door_open" if opening else "door_close"}
	w.interactables.append(item)


func update(dt: float) -> void:
	for d in doors:
		if absf(d.target - d.angle) > 0.001:
			d.angle += (d.target - d.angle) * minf(1.0, dt * 6.0)
			var hinge: Node3D = d.hinge
			hinge.transform = d.base * Transform3D(Basis(Vector3.UP, d.angle), Vector3.ZERO)


# ---------------------------------------------------------------------------------------------- outside
## Gable roof in house space (oldtown.js buildGableRoof). Ridge along x (axis "x") or z; slopes start at the
## outer wall faces; gable triangles are walls gT thick, gInset inside the ends. Returns {rise, half, ridge_y, ...}
func gable_roof(B, g: Transform3D, o: Dictionary) -> Dictionary:
	var pitch: float = o.pitch
	var tn := tan(pitch)
	var half: float = o.span / 2.0
	var rise := half * tn
	var ridge: float = o.wall_top + rise
	var eave: float = o.get("eave", 0.5)
	var verge: float = o.get("verge", 0.35)
	var t: float = o.get("thick", 0.22)
	var run := half + eave
	var S := run / cos(pitch)
	var L: float = o.length + 2 * verge
	var rot := 0.0 if o.axis == "x" else PI / 2
	var edge: Material = o.get("edge", w.mats.soffit)
	var roof: Material = o.roof
	var base: Transform3D = g * Transform3D(Basis(Vector3.UP, rot), Vector3(o.cx, 0, o.cz))
	for spin in [0.0, PI]:
		var xf: Transform3D = base * Transform3D(Basis(Vector3.UP, spin), Vector3.ZERO) \
			* Transform3D(Basis(), Vector3(0, ridge - (run / 2) * tn, run / 2)) * Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
		B.box(xf, Vector3(0, t / 2, 0), Vector3(L, t, S), [edge, edge, roof, edge, edge, edge], 1.0, true, true)
	B.box(base, Vector3(0, ridge + t / cos(pitch) - 0.02, 0), Vector3(L + 0.04, 0.26, 0.34), roof, 1.0, true)
	if o.has("gable"):
		var gT: float = o.get("gT", 0.2)
		var inset: float = o.get("inset", 0.1)
		for s in [-1.0, 1.0]:
			var gx: Transform3D = base * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(s * (o.length / 2 - inset), o.wall_top, 0))
			B.prism(gx * Transform3D(Basis(), Vector3(0, 0, -gT / 2)), PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), Vector2(0, rise)]), gT, o.gable, 1.0)
	return {"rise": rise, "half": half, "ridge_y": ridge, "tan": tn, "axis": o.axis, "cx": o.cx, "cz": o.cz}


static func roof_y(roof: Dictionary, x: float, z: float) -> float:
	var across: float = absf(z - roof.cz) if roof.axis == "x" else absf(x - roof.cx)
	return roof.ridge_y - across * roof.tan


## Half-timbered frame: sill, storey and wall plates, posts beside every opening, mid rails, corner braces and
## St. Andrew's crosses under the upper windows (oldtown.js buildFachwerk)
func _fachwerk(g: Transform3D, st: Dictionary, roof: Dictionary) -> void:
	var mat: Material = w.timber(st.timber_color)
	var PW := 0.2
	var N := T / 2 + 0.02
	var ND := 0.06
	var lens := {"front": 8.0, "back": 8.0, "left": 7.0, "right": 7.0}
	var zones := [[0.62, 3.3], [3.76, 6.3]] if st.frame == "full" else [[3.76, 6.3]]
	var beam := func(side: String, u0: float, u1: float, v0: float, v1: float) -> void:
		wall_box(g, side, (u0 + u1) / 2, (v0 + v1) / 2, N, u1 - u0, v1 - v0, ND, mat)
	for side in lens:
		var L: float = lens[side]
		if st.frame == "full":
			beam.call(side, -L, L, 0.4, 0.62)
		beam.call(side, -L, L, 3.3, 3.5)
		beam.call(side, -L, L, 3.56, 3.76)
		beam.call(side, -L, L, 6.3, 6.5)
		var holes: Array = []
		for o in OPEN[side]:
			holes.append({"u0": o[0] - o[1] / 2 - 0.1, "u1": o[0] + o[1] / 2 + 0.1, "v0": o[2], "v1": o[3], "door": false})
		if side == "front":
			holes.append({"u0": -0.72, "u1": 0.72, "v0": 0.0, "v1": 2.5, "door": true})
		for zn in zones:
			var va: float = zn[0]
			var vb: float = zn[1]
			var hs: Array = holes.filter(func(h): return h.v1 > va and h.v0 < vb)
			var ps := [-L + PW / 2, L - PW / 2]
			for h in hs:
				ps.append(h.u0 - PW / 2)
				ps.append(h.u1 + PW / 2)
			ps.sort()
			var merged: Array = []
			for p in ps:
				if merged.size() > 0 and p - merged[merged.size() - 1] < 0.35:
					merged[merged.size() - 1] = (merged[merged.size() - 1] + p) / 2
				else:
					merged.append(p)
			# split wide solid bays
			var all: Array = []
			for i in merged.size():
				all.append(merged[i])
				if i == merged.size() - 1:
					break
				var a: float = merged[i]
				var c: float = merged[i + 1]
				var in_hole := hs.any(func(h): return h.u0 < (a + c) / 2 and h.u1 > (a + c) / 2)
				if not in_hole and c - a > 1.8:
					var nn := ceili((c - a) / 1.5)
					for k in range(1, nn):
						all.append(a + (c - a) * k / nn)
			for u in all:
				beam.call(side, u - PW / 2, u + PW / 2, va, vb)
			for i in all.size() - 1:
				var a: float = all[i] + PW / 2
				var c: float = all[i + 1] - PW / 2
				var ww := c - a
				var mid := (a + c) / 2
				if ww < 0.25:
					continue
				var hit = null
				for h in hs:
					if h.u0 < mid + 0.05 and h.u1 > mid - 0.05:
						hit = h
						break
				if hit != null:
					if hit.door:
						beam.call(side, a, c, 2.5, 2.68)
						continue
					# parapet under an upper window: St. Andrew's cross
					var top: float = hit.v0 - 0.08
					if top - va > 0.45:
						beam.call(side, a, c, top - 0.16, top)
						wall_brace(g, side, a, va, c, top - 0.16, N - 0.005, 0.14, ND - 0.01, mat)
						wall_brace(g, side, a, top - 0.16, c, va, N - 0.005, 0.14, ND - 0.01, mat)
					continue
				var corner := i == 0 or i == all.size() - 2
				if ww > 0.6 and ww < 2.4:
					if corner:
						# braces rise toward the corner post (the "Mann" figure)
						if i == 0:
							wall_brace(g, side, c, va, a, vb, N - 0.005, 0.17, ND - 0.01, mat)
						else:
							wall_brace(g, side, a, va, c, vb, N - 0.005, 0.17, ND - 0.01, mat)
					elif (i + (1 if va > 3 else 0)) % 2 == 0:
						wall_brace(g, side, a, va, c, vb, N - 0.005, 0.15, ND - 0.01, mat)
						wall_brace(g, side, a, vb, c, va, N - 0.005, 0.15, ND - 0.01, mat)
					else:
						beam.call(side, a, c, (va + vb) / 2 - 0.08, (va + vb) / 2 + 0.08)
	# Gable: frame posts and a collar beam following the triangle; rafters along both edges
	var sides := ["front", "back"] if st.ridge_z else ["left", "right"]
	var half: float = roof.half
	var rise: float = roof.rise
	var v0 := 6.5
	var hc := rise * 0.45
	for side in sides:
		var L: float = lens[side]
		var k := half / rise
		wall_brace(g, side, -L + 0.12, v0, 0, v0 + rise - 0.12, N, 0.22, ND, mat)
		wall_brace(g, side, L - 0.12, v0, 0, v0 + rise - 0.12, N, 0.22, ND, mat)
		var wc := (rise - hc) * k
		beam.call(side, -wc, wc, v0 + hc - 0.1, v0 + hc + 0.1)
		beam.call(side, -PW / 2, PW / 2, v0, v0 + hc - 0.1)
		for s in [-1.0, 1.0]:
			var u: float = s * half * 0.5
			var top := v0 + minf(hc - 0.1, (rise - absf(u) * rise / half) - 0.1)
			beam.call(side, u - PW / 2, u + PW / 2, v0, top)
			if rise <= 6:
				wall_brace(g, side, s * 0.1, v0 + 0.05, u - s * 0.1, top - 0.05, N - 0.005, 0.14, ND - 0.01, mat)


## Decorative attic windows in the gable (dark panes with white frames)
func _gable_windows(g: Transform3D, st: Dictionary, roof: Dictionary) -> void:
	var sides := ["front", "back"] if st.ridge_z else ["left", "right"]
	var rise: float = roof.rise
	var v0 := 6.5
	for side in sides:
		var spots := [[0.0, v0 + rise * 0.45 + 0.35, 0.7, 0.9]]
		if rise > 6:
			spots.append([-roof.half * 0.26, v0 + 0.9, 0.9, 1.2])
			spots.append([roof.half * 0.26, v0 + 0.9, 0.9, 1.2])
		for sp in spots:
			var u: float = sp[0]
			var vb: float = sp[1]
			var ww: float = sp[2]
			var h: float = sp[3]
			var vc := vb + h / 2
			wall_box(g, side, u, vc, 0.115, ww, h, 0.02, w.mats.glass_dark)
			wall_box(g, side, u, vb + h + 0.04, 0.12, ww + 0.16, 0.08, 0.05, w.mats.frame)
			wall_box(g, side, u, vb - 0.04, 0.14, ww + 0.2, 0.08, 0.09, w.mats.frame)
			wall_box(g, side, u - ww / 2 - 0.04, vc, 0.12, 0.08, h, 0.05, w.mats.frame)
			wall_box(g, side, u + ww / 2 + 0.04, vc, 0.12, 0.08, h, 0.05, w.mats.frame)
			wall_box(g, side, u, vc, 0.125, 0.05, h, 0.03, w.mats.frame)
			wall_box(g, side, u, vb + h * 0.6, 0.125, ww, 0.05, 0.03, w.mats.frame)


## Shutters beside the front windows, window boxes under the upper ones, sandstone quoins on plain houses
func _front_details(g: Transform3D, st: Dictionary, idx: int) -> void:
	var sm: Material = w.tmat("wood_" + w.slug(st.shutter), Vector2(2, 2), {"rough": 0.7})
	var box_mat: Material = w.color_mat("#5b3b25")
	var flowers := ["#d8344a", "#d8344a", "#f08ab0", "#f3f0ea"]
	var k := 0
	for o in OPEN.front:
		var u: float = o[0]
		var ww: float = o[1]
		var v0: float = o[2]
		var v1: float = o[3]
		var h := v1 - v0
		var vc := (v0 + v1) / 2
		if st.frame == "upper" or st.frame == "none":
			for s in [-1.0, 1.0]:
				wall_box(g, "front", u + s * (ww / 2 + 0.12 + ww / 4), vc, T / 2 + 0.09, ww / 2, h + 0.08, 0.04, sm)
		if v0 > 4:
			wall_box(g, "front", u, v0 - 0.13, T / 2 + 0.3, ww + 0.1, 0.22, 0.22, box_mat)
			var fc: Material = w.color_mat(flowers[(idx + k) % flowers.size()])
			for f in 3:
				var fu := u - ww / 2 + 0.3 + f * (ww - 0.6) / 2
				wall_box(g, "front", fu, v0 + 0.08, T / 2 + 0.3, 0.22, 0.2, 0.16, fc)
		k += 1
	if st.frame == "none":
		var m: Material = w.mats.sandstone
		var v := 0.45
		var kk := 0
		while v < 6.4:
			var long := 0.45 if kk % 2 else 0.75
			var long2 := 0.75 if kk % 2 else 0.45
			for s in [-1.0, 1.0]:
				wall_box(g, "front", s * (8 - long / 2), v + 0.22, T / 2 + 0.015, long, 0.44, 0.03, m)
				wall_box(g, "right" if s > 0 else "left", 7 - long2 / 2, v + 0.22, T / 2 + 0.015, long2, 0.44, 0.03, m)
			v += 0.5
			kk += 1


## Front step and a little tiled door canopy on brackets
func _entrance(g: Transform3D, st: Dictionary) -> void:
	obox(g, 2.6, 0.16, 1.1, 0, 0.08, D / 2 + 0.55, w.mats.sandstone, false)
	if st.gothic:
		return   # the arcade shelters the door
	gable_roof(be, g, {"cx": 0.0, "cz": D / 2 + 0.7, "span": 2.4, "length": 1.4, "wall_top": 2.95, "axis": "z",
		"pitch": deg_to_rad(38), "eave": 0.12, "verge": 0.04, "thick": 0.12, "roof": w.roof_mat(st.roof)})
	var tm: Material = w.timber(st.timber_color)
	for s in [-1.0, 1.0]:
		obox(g, 0.12, 0.12, 1.35, s * 1.15, 2.92, D / 2 + 0.72, tm, false)
		be.box(g * Transform3D(Basis(Vector3.RIGHT, -atan2(0.75, 1.1)), Vector3(s * 1.15, 2.5, D / 2 + 0.58)), Vector3.ZERO, Vector3(0.1, 0.1, 1.25), tm, 1.0, false)


## Gothic town house: stepped gables front and back, string courses, hood moulds over the upper front windows,
## lancets in both gables, and an arcade across the front with a balcony on top (gothic.js buildGothicFront)
func _gothic_front(g: Transform3D, st: Dictionary, roof: Dictionary, wall: Material) -> void:
	var pale: Material = w.mats.palestone
	for s in [1.0, -1.0]:
		_stepped_gable(g, s * (D / 2 - T / 2), W / 2, roof.rise, 6.5, wall, 1.0, 0.4)
	for y in [3.5, 6.42]:
		obox(g, W + 0.16, 0.16, 0.08, 0, y, D / 2 + 0.04, pale, false)
		obox(g, W + 0.16, 0.16, 0.08, 0, y, -D / 2 - 0.04, pale, false)
		for s in [-1.0, 1.0]:
			obox(g, 0.08, 0.16, D, s * (W / 2 + 0.04), y, 0, pale, false)
	# hood moulds: a pointed tympanum with a ring of tracery over each upper front window
	for o in OPEN.front:
		if o[2] < 4:
			continue
		var ww: float = o[1]
		var rise := 0.55 * (ww + 0.2)
		be.prism(g * Transform3D(Basis(), Vector3(o[0], o[3] + 0.1, D / 2 + 0.11)), Castle.arch_pts(ww + 0.24, 0.0, rise), 0.07, pale, 3.0, false)
		var tm := TorusMesh.new()
		tm.inner_radius = minf(0.24, rise * 0.32) - 0.035
		tm.outer_radius = minf(0.24, rise * 0.32) + 0.035
		tm.rings = 16
		tm.ring_segments = 5
		be.mesh(g * Transform3D(_rx(PI / 2), Vector3(o[0], o[3] + 0.1 + rise * 0.45, D / 2 + 0.2)), tm, w.mats.dark_oak, false)
	# lancets in both gables
	for sr in [[1.0, 0.0], [-1.0, PI]]:
		var k := 0
		for uh in [[0.0, 2.9], [-2.3, 2.1], [2.3, 2.1]]:
			var f: Transform3D = g * Transform3D(Basis(Vector3.UP, sr[1]), Vector3(sr[0] * uh[0], 6.95, sr[0] * (D / 2 + 0.11)))
			_lancet(f, 0.7 if k else 0.9, uh[1], 0.14, 0.14)
			k += 1
	# arcade across the front: five pointed arches on piers with engaged columns, a balcony on top
	var AZ := D / 2 + 2.35
	var AD := 0.45
	var AW := W + 1.08
	var bays := 5
	var top := 4.15
	_arcade_wall(g * Transform3D(Basis(), Vector3(0, 0, AZ)), AW, top, bays, 2.6, 2.2, 1.43, AD, wall)
	obox(g, AW, 0.2, AZ - D / 2, 0, top - 0.1, (AZ + D / 2) / 2, wall)
	col(g, 0, (AZ + D / 2) / 2, AW, AZ - D / 2, top, top - 0.2)
	obox(g, AW + 0.12, 0.14, AD + 0.12, 0, top + 0.07, AZ + AD / 2, pale, false)
	var iron: Material = w.mats.iron
	var rz := AZ + AD - 0.1
	var depth := rz - D / 2
	for h in [0.18, 0.85]:
		obox(g, AW - 0.1, 0.04, 0.04, 0, top + h, rz, iron, false)
		for s in [-1.0, 1.0]:
			obox(g, 0.04, 0.04, depth, s * (AW / 2 - 0.08), top + h, (rz + D / 2) / 2, iron, false)
	var u := -AW / 2 + 0.08
	while u <= AW / 2 - 0.07:
		obox(g, 0.025, 0.85, 0.025, u, top + 0.43, rz, iron, false)
		u += 0.24
	for s in [-1.0, 1.0]:
		var zz := D / 2 + 0.24
		while zz < rz:
			obox(g, 0.025, 0.85, 0.025, s * (AW / 2 - 0.08), top + 0.43, zz, iron, false)
			zz += 0.24
	obox(g, AW, 0.04, AZ + AD - D / 2, 0, 0.02, (AZ + AD + D / 2) / 2, w.mats.sandstone, false)
	var bay := AW / bays
	var colm := CylinderMesh.new()
	colm.top_radius = 0.17
	colm.bottom_radius = 0.19
	colm.height = 2.0
	colm.radial_segments = 12
	for i in bays + 1:
		var uu := -AW / 2 + i * bay
		var uc := uu + 0.34 if i == 0 else (uu - 0.34 if i == bays else uu)
		be.mesh(g * Transform3D(Basis(), Vector3(uc, 1.1, AZ + AD + 0.16)), colm, pale, true)
		obox(g, 0.5, 0.2, 0.42, uc, 2.2, AZ + AD + 0.12, pale, false)
		obox(g, 0.46, 0.16, 0.42, uc, 0.08, AZ + AD + 0.12, pale, false)
		col(g, uc, AZ + AD / 2 + 0.1, 0.7, AD + 0.4, 4.2)


## A wall of pointed arches on piers (gothic.js arcadeWallGeo), from z = 0 to depth in frame f
func _arcade_wall(f: Transform3D, AW: float, top: float, bays: int, ow: float, spring: float, rise: float, depth: float, mat: Material) -> void:
	var bay := AW / bays
	var front := f * Transform3D(Basis(), Vector3(0, 0, depth))
	var back := f * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	for i in bays:
		var cx := -AW / 2 + (i + 0.5) * bay
		var arch := Castle.arch_pts(ow, spring, rise)
		var pts := PackedVector2Array()
		var tops := PackedVector2Array()
		for p in arch:
			pts.append(Vector2(p.x + cx, p.y))
			tops.append(Vector2(p.x + cx, top))
		be.strip(front, tops, pts, mat, Vector3.BACK, 3.0)
		var mpts := PackedVector2Array()
		var mtops := PackedVector2Array()
		for p in pts:
			mpts.append(Vector2(-p.x, p.y))
			mtops.append(Vector2(-p.x, top))
		be.strip(back, mtops, mpts, mat, Vector3.BACK, 3.0)
		be.ring_walls(f, pts, depth, mat, false, 3.0, true, true)
		# piers either side of the opening
		var x0 := -AW / 2 + i * bay
		for pr in [[x0, cx - ow / 2], [cx + ow / 2, x0 + bay]]:
			var pw: float = pr[1] - pr[0]
			be.box(f, Vector3((pr[0] + pr[1]) / 2, (top - 0.05) / 2, depth / 2), Vector3(pw, top + 0.05, depth), mat, 1.0, true)
		col(f, x0 + (cx - ow / 2 - x0) / 2, depth / 2, cx - ow / 2 - x0, depth, top)


## Stepped gable across x at local z = pos (gothic.js steppedGable, plane 'z')
func _stepped_gable(g: Transform3D, pos: float, half: float, rise: float, wall_top: float, mat: Material, step: float, thick: float) -> void:
	var cap: Material = w.mats.palestone
	var n := floori(half / step - 0.4)
	for k in n:
		var uo := half - k * step
		var ui := half - (k + 1) * step
		var top := wall_top + rise * (1 - ui / half) + 0.55
		var h := top - wall_top
		for s in [-1.0, 1.0]:
			obox(g, step, h, thick, s * (uo + ui) / 2, wall_top + h / 2, pos, mat)
			obox(g, step + 0.08, 0.12, thick + 0.12, s * (uo + ui) / 2, top + 0.06, pos, cap, false)
	var uc := half - n * step
	var top_c := wall_top + rise + 0.9
	obox(g, 2 * uc, top_c - wall_top, thick, 0, wall_top + (top_c - wall_top) / 2, pos, mat)
	obox(g, 2 * uc + 0.1, 0.14, thick + 0.14, 0, top_c + 0.07, pos, cap, false)


## Pointed lancet with leaded glass in a pale stone frame (churchWindow, noMullion), facing +z in f
func _lancet(f: Transform3D, ww: float, h: float, fw: float, fd: float) -> void:
	var pale: Material = w.mats.palestone
	var outer := Castle.arch_pts(ww + 2 * fw, h + fw * 1.4 - (ww + 2 * fw) * 0.866, (ww + 2 * fw) * 0.866, -fw * 0.5)
	var inner := Castle.arch_pts(ww, h - ww * 0.866, ww * 0.866, 0.0)
	var front := f * Transform3D(Basis(), Vector3(0, 0, fd))
	be.strip(front, outer, inner, pale, Vector3.BACK, 3.0, false)
	be.quad(front, Vector3(outer[0].x, outer[0].y, 0), Vector3(outer[outer.size() - 1].x, outer[0].y, 0), Vector3(inner[inner.size() - 1].x, 0, 0), Vector3(inner[0].x, 0, 0), pale, Vector3.BACK, 3.0, false)
	be.ring_walls(f, outer, fd, pale, true, 3.0, false)
	be.polygon(f * Transform3D(Basis(), Vector3(0, 0, 0.03)), inner, _leaded(), 1.0, false, Rect2(-ww / 2, 0, ww, h))


var _leaded_mat: Material
func _leaded() -> Material:
	if _leaded_mat == null:
		_leaded_mat = w.tmat("leadedglass", Vector2(1, 1), {"rough": 0.15, "metal": 0.3, "emission_tint": Color("#ffc47e")})
		w.night_glows.append({"mat": _leaded_mat, "energy": 0.9})
	return _leaded_mat


# ---------------------------------------------------------------------------------------------- garages
## Closed with a sectional door, or open with a hobby workshop
func _garage(g: Transform3D, wall: Material, idx: int, st: Dictionary) -> void:
	var GW := 7.0
	var GH := 4.2
	var GD := 9.0
	var gx := -W / 2 - GW / 2
	var gz := -1.0
	var zF := gz + GD / 2
	var zB := gz - GD / 2
	var xL := gx - GW / 2
	var xR := gx + GW / 2
	var door_mat: Material = w.tmat("wood_6b4a2e", Vector2(2, 2), {"rough": 0.7, "normal": "wood_nrm", "depth": 0.8})
	# Tiled gable roof over the flat garage roof, gable to the street like a little barn
	gable_roof(be, g, {"cx": gx, "cz": gz, "span": GW, "length": GD, "wall_top": GH + 0.22, "axis": "z", "pitch": deg_to_rad(40),
		"eave": 0.2, "verge": 0.3, "roof": w.roof_mat(st.roof), "gable": wall})
	var open := idx % 3 == 1
	if not open:
		obox(g, GW, GH, GD, gx, GH / 2, gz, wall)
		obox(g, 5.8, 3.4, 0.1, gx, 1.8, zF, door_mat)
		col(g, gx, gz, GW, GD)
		return
	open_garages += 1
	var wb := func(ww: float, hh: float, dd: float, x: float, y: float, z: float, inside_face: int) -> void:
		var faces := [wall, wall, wall, wall, wall, wall]
		faces[inside_face] = hm.plaster
		be.box(g, Vector3(x, y, z), Vector3(ww, hh, dd), faces, 1.0, true, true)
	wb.call(GW, GH, 0.2, gx, GH / 2, zB + 0.1, 4)                 # back
	wb.call(0.2, GH, GD, xL + 0.1, GH / 2, gz, 0)                 # left
	wb.call(0.35, GH, 0.2, xL + 0.375, GH / 2, zF - 0.1, 5)       # front pillars
	wb.call(0.35, GH, 0.2, xR - 0.175, GH / 2, zF - 0.1, 5)
	wb.call(GW, 0.6, 0.2, gx, GH - 0.3, zF - 0.1, 5)              # header
	be.box(g, Vector3(gx, GH + 0.11, gz), Vector3(GW, 0.22, GD), [wall, wall, wall, hm.ceil, wall, wall], 1.0, true, true)
	box(g, GW - 0.4, 0.05, GD - 0.2, gx, 0.03, gz - 0.05, hm.concrete)
	# sectional door rolled up under the ceiling, on its tracks
	box(g, 5.9, 0.06, 3.4, gx, GH - 0.45, zF - 1.9, door_mat)
	for s in [-1.0, 1.0]:
		box(g, 0.05, 0.08, 4.0, gx + s * 3.0, GH - 0.42, zF - 2.0, hm.dark_steel)
	for dz in [-1.5, 1.5]:
		box(g, 1.2, 0.05, 0.12, gx, GH - 0.03, gz + dz, hm.fluoro)
	col(g, gx, zB + 0.1, GW, 0.2)
	col(g, xL + 0.1, gz, 0.2, GD)
	col(g, xL + 0.375, zF - 0.1, 0.35, 0.2)
	col(g, xR - 0.175, zF - 0.1, 0.35, 0.2)
	var kinds := ["wood", "pottery", "repair", "brew"]
	var kind: String = kinds[(open_garages - 1) % kinds.size()]
	var c := {"g": g, "gx": gx, "gz": gz, "zB": zB + 0.2, "xL": xL + 0.2, "xR": xR, "zF": zF}
	var infos := {
		"wood": ["Woodworking bench", "A well-loved workbench: a vise, a wall of hand tools, offcuts of oak and a table saw. Someone's building a rocking chair."],
		"pottery": ["Pottery studio", "A potter's wheel still wet with clay, shelves of glazed bowls and vases, and a kiln ticking as it cools."],
		"repair": ["Repair shop", "A bike up on a repair stand, a red rolling tool chest, a stack of tyres and the smell of chain oil. Fix-it Saturday!"],
		"brew": ["Home brewery", "A steel brew kettle, carboys of amber beer bubbling through their airlocks and crates of bottles. The chalkboard says: Batch #7 - Hazy IPA."],
	}
	var info: Array = infos[kind]
	call("_workshop_" + kind, c)
	var title: String = info[0]
	var msg: String = info[1]
	w.add_interactable(g * Vector3(gx, 1.2, zF - 1.0), "[E] Look at the %s" % title.to_lower(), "garage",
		func() -> Dictionary: return {"title": title, "message": msg, "sound": "click"})


## Shared workbench along the back wall; returns its z
func _workbench(c: Dictionary, x: float, len: float, top = null) -> float:
	var g: Transform3D = c.g
	var z: float = c.zB + 0.4
	box(g, len, 0.08, 0.8, x, 0.9, z, top if top != null else hm.wood_light, true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(g, 0.08, 0.86, 0.08, x + sx * (len / 2 - 0.08), 0.43, z + sz * 0.32, hm.wood_mid)
	box(g, len - 0.1, 0.04, 0.7, x, 0.25, z, hm.wood_mid)
	col(g, x, z, len, 0.85, 1.0)
	return z


func _workshop_wood(c: Dictionary) -> void:
	var g: Transform3D = c.g
	var gx: float = c.gx
	var gz: float = c.gz
	var zB: float = c.zB
	var xL: float = c.xL
	var z := _workbench(c, gx - 0.3, 2.8)
	box(g, 0.22, 0.14, 0.18, gx - 1.4, 0.98, z + 0.42, hm.dark_steel)   # vise
	prim(g, _cyl(0.012, 0.012, 0.3, 8), hm.steel, Vector3(gx - 1.4, 0.96, z + 0.55), Basis(Vector3.BACK, PI / 2))
	box(g, 2.8, 1.2, 0.03, gx - 0.3, 1.75, zB + 0.02, hm.pegboard)   # pegboard with tools
	for k in 6:
		var tx := gx - 1.5 + k * 0.45
		box(g, 0.03, 0.3, 0.02, tx, 1.75, zB + 0.05, hm.wood_mid)
		box(g, 0.12 if k % 2 else 0.04, 0.05 if k % 2 else 0.18, 0.025, tx, 1.92 if k % 2 else 1.6, zB + 0.06, hm.dark_steel)
	box(g, 0.5, 0.18, 0.01, gx + 0.9, 1.55, zB + 0.05, hm.steel)
	box(g, 0.12, 0.12, 0.03, gx + 1.18, 1.55, zB + 0.05, hm.wood_mid)
	box(g, 0.3, 0.03, 0.02, gx + 0.8, 2.15, zB + 0.05, hm.steel)
	box(g, 0.03, 0.4, 0.02, gx + 0.66, 1.98, zB + 0.05, hm.steel)
	box(g, 0.28, 0.08, 0.07, gx - 0.5, 0.98, z, hm.wood_mid)
	box(g, 0.3, 0.06, 0.12, gx + 0.3, 0.97, z + 0.1, hm.wood_light)
	for r in 3:   # lumber rack on the side wall
		var y: float = [0.7, 1.3, 1.9][r]
		box(g, 0.35, 0.04, 0.05, xL + 0.18, y, gz - 2.5, hm.dark_steel)
		box(g, 0.35, 0.04, 0.05, xL + 0.18, y, gz + 0.5, hm.dark_steel)
		for k in 3 - (r % 2):
			box(g, 0.12, 0.04, 3.6, xL + 0.08 + k * 0.11, y + 0.04, gz - 1.0, hm.wood_light)
	col(g, xL + 0.18, gz - 1.0, 0.4, 3.6, 2.2)
	box(g, 0.6, 0.8, 0.6, gx + 0.3, 0.4, gz + 0.4, fabric("#4f6b5a"), true)   # table saw
	box(g, 1.0, 0.04, 0.8, gx + 0.3, 0.82, gz + 0.4, hm.brushed, true)
	prim(g, _cyl(0.13, 0.13, 0.004, 24), hm.steel, Vector3(gx + 0.3, 0.86, gz + 0.4), Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.BACK, PI / 2))
	box(g, 0.03, 0.08, 0.8, gx + 0.62, 0.88, gz + 0.4, hm.yellow)
	col(g, gx + 0.3, gz + 0.4, 1.0, 0.8, 1.0)
	box(g, 0.5, 0.04, 0.5, gx + 2.0, 0.45, gz + 1.8, hm.wood_light, true)   # half-built rocking chair
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(g, 0.04, 0.45, 0.04, gx + 2.0 + sx * 0.22, 0.225, gz + 1.8 + sz * 0.22, hm.wood_light)
	box(g, 0.5, 0.6, 0.04, gx + 2.0, 0.75, gz + 1.57, hm.wood_light)
	prim(g, _cyl(0.2, 0.2, 0.5, 16), hm.yellow, Vector3(c.xR - 0.4, 0.25, zB + 0.4))   # shop vac
	box(g, 0.4, 0.05, 0.1, gx - 0.8, 0.06, gz + 1.5, hm.wood_light)
	box(g, 0.3, 0.05, 0.08, gx - 0.6, 0.06, gz + 1.7, hm.wood_mid)


func _workshop_pottery(c: Dictionary) -> void:
	var g: Transform3D = c.g
	var gx: float = c.gx
	var gz: float = c.gz
	var zB: float = c.zB
	var xL: float = c.xL
	var xR: float = c.xR
	# potter's wheel: body, splash pan, head with a pot being thrown, stool
	var wx := gx + 0.2
	var wz := gz + 0.2
	box(g, 0.55, 0.42, 0.6, wx, 0.21, wz, fabric("#5b6670"), true)
	prim(g, _cyl(0.34, 0.3, 0.1, 24, true), fabric("#6c7880"), Vector3(wx, 0.47, wz))
	prim(g, _cyl(0.16, 0.16, 0.03, 24), hm.dark_steel, Vector3(wx, 0.47, wz))
	prim(g, _lathe([Vector2(0.0, 0), Vector2(0.09, 0), Vector2(0.11, 0.04), Vector2(0.1, 0.12), Vector2(0.075, 0.18), Vector2(0.085, 0.22)], 24), hm.clay, Vector3(wx, 0.485, wz))
	prim(g, _cyl(0.18, 0.18, 0.05, 16), hm.wood_mid, Vector3(wx, 0.45, wz + 0.65))
	box(g, 0.04, 0.43, 0.04, wx, 0.215, wz + 0.65, hm.dark_steel)
	col(g, wx, wz + 0.2, 0.7, 1.1, 1.0)
	# shelves of finished pots along the side wall
	var glazes := ["#2f7f86", "#e8e0cc", "#a4522f", "#2c4c8c", "#7e8f4e", "#c9a03a"]
	for r in 3:
		var y: float = [0.5, 1.1, 1.7][r]
		box(g, 0.4, 0.03, 3.4, xL + 0.2, y, gz - 1.0, hm.wood_light)
		for k in 6:
			var pr: Array
			match (k + r) % 3:
				0: pr = [Vector2(0, 0), Vector2(0.07, 0), Vector2(0.12, 0.08), Vector2(0.06, 0.2), Vector2(0.05, 0.26)]
				1: pr = [Vector2(0, 0), Vector2(0.05, 0), Vector2(0.13, 0.08), Vector2(0.14, 0.1)]
				_: pr = [Vector2(0, 0), Vector2(0.06, 0), Vector2(0.08, 0.15), Vector2(0.04, 0.3), Vector2(0.05, 0.34)]
			prim(g, _lathe(pr, 16), _glaze(glazes[(k * 2 + r) % glazes.size()]), Vector3(xL + 0.2, y + 0.015, gz - 2.5 + k * 0.58))
	col(g, xL + 0.2, gz - 1.0, 0.45, 3.4, 2.0)
	# kiln with a control box
	prim(g, _cyl(0.45, 0.45, 0.85, 8), hm.brushed, Vector3(xR - 0.7, 0.5, zB + 0.6), Basis(), true)
	prim(g, _cyl(0.46, 0.46, 0.06, 8), hm.dark_steel, Vector3(xR - 0.7, 0.96, zB + 0.6))
	box(g, 0.25, 0.3, 0.12, xR - 0.7, 0.6, zB + 1.1, hm.black)
	box(g, 0.15, 0.06, 0.01, xR - 0.7, 0.66, zB + 1.165, fabric("#3fbf5f"))
	col(g, xR - 0.7, zB + 0.6, 1.0, 1.0, 1.1)
	# wedging table with clay blocks, buckets of slip
	var z := _workbench(c, gx - 1.0, 1.6, hm.canvas_beige)
	box(g, 0.3, 0.18, 0.2, gx - 1.3, 1.03, z, hm.clay)
	box(g, 0.25, 0.15, 0.2, gx - 0.8, 1.01, z + 0.1, hm.clay)
	for dd in [[0.0, 2.3], [0.45, 2.4]]:
		prim(g, _cyl(0.15, 0.13, 0.32, 16), fabric("#e8e4dc"), Vector3(gx + 1.6 + dd[0], 0.16, gz + dd[1] - 3.5))


func _workshop_repair(c: Dictionary) -> void:
	var g: Transform3D = c.g
	var gx: float = c.gx
	var gz: float = c.gz
	var zB: float = c.zB
	var xL: float = c.xL
	var xR: float = c.xR
	# red rolling tool chest with drawers
	var tx := xL + 0.3
	var tz := gz - 2.4
	box(g, 0.5, 0.95, 1.0, tx, 0.55, tz, hm.red, true)
	box(g, 0.48, 0.45, 0.96, tx, 1.25, tz, hm.red, true)
	for k in 7:
		var y := 0.18 + k * 0.17 + (0.12 if k > 4 else 0.0)
		box(g, 0.01, 0.01, 0.92, tx + 0.255, y, tz, hm.black)
		box(g, 0.02, 0.02, 0.4, tx + 0.27, y + 0.07, tz, hm.steel)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			prim(g, _cyl(0.04, 0.04, 0.03, 12), hm.rubber, Vector3(tx + sx * 0.2, 0.04, tz + sz * 0.42), _rx(PI / 2))
	col(g, tx, tz, 0.55, 1.05, 1.5)
	# workbench with a car battery, oil cans, parts
	var z := _workbench(c, gx + 0.5, 2.6, hm.dark_steel)
	box(g, 0.3, 0.22, 0.18, gx - 0.3, 1.05, z, hm.black)
	box(g, 0.04, 0.04, 0.04, gx - 0.4, 1.18, z, hm.red)
	box(g, 0.04, 0.04, 0.04, gx - 0.2, 1.18, z, hm.black)
	for dx in [0.3, 0.45]:
		prim(g, _cyl(0.06, 0.06, 0.22, 12), hm.yellow, Vector3(gx + dx, 1.05, z + 0.15))
	torus(g, 0.1, 0.015, hm.steel, Vector3(gx + 1.1, 0.95, z), _rx(PI / 2))
	box(g, 2.6, 1.0, 0.03, gx + 0.5, 1.8, zB + 0.02, hm.pegboard)
	for k in 8:
		box(g, 0.025, 0.2 + (k % 3) * 0.04, 0.015, gx - 0.6 + k * 0.28, 1.8, zB + 0.045, hm.steel)
	# bicycle on a repair stand
	var bxx := gx + 0.4
	var bzz := gz + 0.6
	var by := 1.0
	box(g, 0.05, by + 0.1, 0.05, bxx + 0.35, (by + 0.1) / 2, bzz, hm.dark_steel)
	box(g, 0.6, 0.04, 0.4, bxx + 0.35, 0.02, bzz, hm.dark_steel)
	var frame := fabric("#2a7ab0")
	for zz in [bzz - 0.52, bzz + 0.52]:
		torus(g, 0.33, 0.022, hm.rubber, Vector3(bxx, by, zz), Basis(Vector3.UP, PI / 2), 32)
		torus(g, 0.31, 0.008, hm.steel, Vector3(bxx, by, zz), Basis(Vector3.UP, PI / 2), 32)
		for s in 8:
			prim(g, _cyl(0.002, 0.002, 0.62, 3), hm.steel, Vector3(bxx, by, zz), _rx(s / 8.0 * PI))
	var V := func(yy: float, zz: float) -> Vector3: return Vector3(bxx, yy, bzz + zz)
	for ab in [[V.call(by, -0.52), V.call(by + 0.02, -0.05)], [V.call(by + 0.02, -0.05), V.call(by + 0.45, 0.42)], [V.call(by + 0.02, -0.05), V.call(by + 0.42, -0.2)],
			[V.call(by + 0.42, -0.2), V.call(by + 0.45, 0.42)], [V.call(by + 0.42, -0.2), V.call(by, -0.52)], [V.call(by + 0.45, 0.42), V.call(by, 0.52)],
			[V.call(by + 0.45, 0.42), V.call(by + 0.65, 0.38)]]:
		limb(g, ab[0], ab[1], 0.016, 0.016, frame)
	box(g, 0.5, 0.025, 0.025, bxx, by + 0.66, bzz + 0.38, hm.black)
	box(g, 0.08, 0.04, 0.22, bxx, by + 0.5, bzz - 0.22, hm.black)
	col(g, bxx + 0.15, bzz, 0.7, 1.3, 1.6)
	# tyre stack, oil drum, jerry can
	for k in 4:
		torus(g, 0.3, 0.11, hm.rubber, Vector3(xR - 0.55, 0.11 + k * 0.21, gz + 1.8), _rx(PI / 2))
	col(g, xR - 0.55, gz + 1.8, 0.85, 0.85, 1.0)
	prim(g, _cyl(0.29, 0.29, 0.88, 20), fabric("#2d5f9a"), Vector3(xR - 0.5, 0.44, zB + 0.5))
	box(g, 0.18, 0.35, 0.3, xR - 1.1, 0.175, zB + 0.4, hm.red, true)


func _workshop_brew(c: Dictionary) -> void:
	var g: Transform3D = c.g
	var gx: float = c.gx
	var gz: float = c.gz
	var zB: float = c.zB
	var xL: float = c.xL
	var xR: float = c.xR
	var z := _workbench(c, gx + 0.6, 2.4, hm.brushed)
	# brew kettle on a propane burner, with a copper wort chiller
	var kx := gx - 1.8
	var kz := zB + 0.5
	for k in 3:
		var a := k / 3.0 * TAU
		box(g, 0.03, 0.45, 0.03, kx + cos(a) * 0.25, 0.225, kz + sin(a) * 0.25, hm.black)
	torus(g, 0.27, 0.02, hm.black, Vector3(kx, 0.45, kz), _rx(PI / 2))
	prim(g, _cyl(0.3, 0.3, 0.55, 24), hm.steel, Vector3(kx, 0.74, kz), Basis(), true)
	prim(g, _cyl(0.31, 0.31, 0.03, 24), hm.steel, Vector3(kx, 1.03, kz))
	box(g, 0.06, 0.03, 0.06, kx + 0.31, 0.6, kz, hm.brushed)
	for k in 5:
		torus(g, 0.16, 0.008, hm.copper, Vector3(kx + 0.55, 0.1 + k * 0.035, kz + 0.3), _rx(PI / 2))
	prim(g, _cyl(0.15, 0.15, 0.45, 16), hm.brushed, Vector3(kx - 0.5, 0.23, kz + 0.2))
	col(g, kx, kz, 0.8, 0.8, 1.1)
	# mash tun (orange cooler) and bags of malt on the bench
	prim(g, _cyl(0.22, 0.22, 0.45, 20), hm.orange, Vector3(gx - 0.1, 1.17, z))
	prim(g, _cyl(0.23, 0.23, 0.06, 20), hm.white, Vector3(gx - 0.1, 1.42, z))
	var k2 := 0
	for dd in [[0.6, 0.0], [1.0, 0.05], [0.8, -0.1]]:
		box(g, 0.35, 0.18, 0.25, gx + dd[0], 1.03 + (0.18 if k2 == 2 else 0.0), z + dd[1], hm.canvas_beige)
		k2 += 1
	# glass carboys of fermenting beer with airlocks
	for k in 3:
		var cx := xL + 0.3
		var cz := gz - 2.2 + k * 0.55
		prim(g, _cyl(0.15, 0.15, 0.36, 16), hm.amber, Vector3(cx, 0.2, cz))
		prim(g, _cyl(0.17, 0.17, 0.42, 16, true), hm.glass, Vector3(cx, 0.23, cz))
		prim(g, _sph(0.17, 16, 8, true), hm.glass, Vector3(cx, 0.44, cz), Basis.from_scale(Vector3(1, 0.6, 1)))
		prim(g, _cyl(0.035, 0.035, 0.1, 10), hm.glass, Vector3(cx, 0.58, cz))
		prim(g, _cyl(0.04, 0.035, 0.04, 10), fabric("#d9b48a"), Vector3(cx, 0.64, cz))
		prim(g, _cyl(0.015, 0.015, 0.12, 8), hm.glass, Vector3(cx, 0.72, cz))
	col(g, xL + 0.3, gz - 1.65, 0.45, 1.6, 0.8)
	# conical stainless fermenter on legs and two kegs
	var fx := xR - 0.6
	var fz := zB + 0.6
	prim(g, _cyl(0.3, 0.3, 0.6, 20), hm.steel, Vector3(fx, 1.15, fz), Basis(), true)
	prim(g, _cyl(0.0, 0.3, 0.35, 20), hm.steel, Vector3(fx, 0.68, fz), Basis(Vector3.RIGHT, PI))
	for k in 3:
		var a := k / 3.0 * TAU + 0.5
		box(g, 0.03, 0.9, 0.03, fx + cos(a) * 0.28, 0.45, fz + sin(a) * 0.28, hm.steel)
	col(g, fx, fz, 0.7, 0.7, 1.5)
	for dz in [0.0, 0.5]:
		prim(g, _cyl(0.2, 0.2, 0.62, 20), hm.brushed, Vector3(xR - 0.45, 0.31, gz + 0.6 + dz))
		for y in [0.08, 0.54]:
			torus(g, 0.2, 0.012, hm.steel, Vector3(xR - 0.45, y, gz + 0.6 + dz), _rx(PI / 2))
	col(g, xR - 0.45, gz + 0.85, 0.5, 1.0, 0.8)
	# crate of brown bottles
	box(g, 0.5, 0.25, 0.35, gx + 1.6, 0.125, gz + 2.3, hm.wood_mid, true)
	for i in 4:
		for j in 3:
			prim(g, _cyl(0.03, 0.03, 0.18, 8), hm.brown_glass, Vector3(gx + 1.42 + i * 0.12, 0.3, gz + 2.19 + j * 0.11))
			prim(g, _cyl(0.012, 0.02, 0.07, 8), hm.brown_glass, Vector3(gx + 1.42 + i * 0.12, 0.42, gz + 2.19 + j * 0.11))
	# chalkboard
	picture(g * Transform3D(Basis(), Vector3(gx + 0.6, 1.75, zB + 0.02)), 0.8, 0.5, hm.chalk)
	# shelf of bottles above the bench
	box(g, 2.0, 0.03, 0.25, gx + 0.8, 2.25, zB + 0.13, hm.wood_light)
	for i in 12:
		prim(g, _cyl(0.03, 0.03, 0.2, 8), hm.brown_glass, Vector3(gx - 0.1 + i * 0.16, 2.37, zB + 0.13))
