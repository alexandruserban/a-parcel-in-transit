extends RefCounted
## Static geometry collector. Every box, quad and cylinder of the town is appended to one SurfaceTool per
## material and 96 m chunk, so the whole town draws as a few hundred meshes (like batchStatic() in world.js).
## UVs are in metres (divided by uv_scale), so tiled shaders keep a real-world scale on any size of part.
## Godot treats clockwise triangles as front faces; every helper takes an `out` hint and winds to suit it.

const CHUNK := 96.0

var _tools := {}


func _tool(mat: Material, at: Vector3, shadow: bool) -> SurfaceTool:
	var key := "%d:%d:%d:%d" % [mat.get_instance_id(), floori(at.x / CHUNK), floori(at.z / CHUNK), int(shadow)]
	var entry: Variant = _tools.get(key)
	if entry == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		entry = {"st": st, "mat": mat, "shadow": shadow}
		_tools[key] = entry
	return entry["st"]


static func _v(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


## Quad a-b-c-d (a loop, either winding). `out` (local space) is the side it should face.
func quad(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, mat: Material,
		out := Vector3.ZERO, uv_scale := 1.0, shadow := true) -> void:
	var A := xf * a
	var B := xf * b
	var C := xf * c
	var D := xf * d
	var n := (B - A).cross(C - A)
	if out != Vector3.ZERO and n.dot(xf.basis * out) < 0.0:
		var t := B
		B = D
		D = t
		n = -n
	n = n.normalized()
	var tu := (B - A).normalized()
	var tv := ((D - A) - tu * (D - A).dot(tu)).normalized()
	var ua := Vector2.ZERO
	var ub := Vector2((B - A).dot(tu), (B - A).dot(tv)) / uv_scale
	var uc := Vector2((C - A).dot(tu), (C - A).dot(tv)) / uv_scale
	var ud := Vector2((D - A).dot(tu), (D - A).dot(tv)) / uv_scale
	var st := _tool(mat, (A + C) * 0.5, shadow)
	# A,B,C,D is counter-clockwise seen from n: emit clockwise
	_v(st, A, n, ua); _v(st, C, n, uc); _v(st, B, n, ub)
	_v(st, A, n, ua); _v(st, D, n, ud); _v(st, C, n, uc)


func tri(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, mat: Material,
		out := Vector3.ZERO, uv_scale := 1.0, shadow := true) -> void:
	var A := xf * a
	var B := xf * b
	var C := xf * c
	var n := (B - A).cross(C - A)
	if out != Vector3.ZERO and n.dot(xf.basis * out) < 0.0:
		var t := B
		B = C
		C = t
		n = -n
	n = n.normalized()
	var tu := (B - A).normalized()
	var tv := n.cross(tu)
	var st := _tool(mat, (A + B + C) / 3.0, shadow)
	_v(st, A, n, Vector2.ZERO)
	_v(st, C, n, Vector2((C - A).dot(tu), (C - A).dot(tv)) / uv_scale)
	_v(st, B, n, Vector2((B - A).dot(tu), (B - A).dot(tv)) / uv_scale)


static func _ext(v: Vector3, h: Vector3) -> float:
	return absf(v.x) * h.x + absf(v.y) * h.y + absf(v.z) * h.z


# Faces in the order +x, -x, +y, -y, +z, -z (as in the web version): [normal, u axis, v axis]
const FACES := [
	[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP],
	[Vector3.LEFT, Vector3.BACK, Vector3.UP],
	[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	[Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
]


## Box centred at `center` (in xf's space). mat: one Material or an Array of 6 (+x,-x,+y,-y,+z,-z; null skips a face).
func box(xf: Transform3D, center: Vector3, size: Vector3, mat, uv_scale := 1.0, shadow := true, bottom := false) -> void:
	var h := size * 0.5
	for i in 6:
		if i == 3 and not bottom:
			continue
		var m: Material = mat[i] if mat is Array else mat
		if m == null:
			continue
		var f: Array = FACES[i]
		var n: Vector3 = f[0]
		var t1: Vector3 = f[1]
		var t2: Vector3 = f[2]
		var c := center + n * _ext(n, h)
		var e1 := t1 * _ext(t1, h)
		var e2 := t2 * _ext(t2, h)
		quad(xf, c - e1 - e2, c + e1 - e2, c + e1 + e2, c - e1 + e2, m, n, uv_scale, shadow)


## Cylinder or cone (r1 = 0) standing on `base`, with smooth side normals.
func cylinder(xf: Transform3D, base: Vector3, r0: float, r1: float, h: float, segs: int, mat: Material,
		top_cap := true, uv_scale := 1.0, shadow := true, start := 0.0, sweep := TAU) -> void:
	var st := _tool(mat, xf * base, shadow)
	var slope := (r0 - r1) / h
	var circ := sweep * maxf(r0, r1)
	for i in segs:
		var a0 := start + sweep * i / segs
		var a1 := start + sweep * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var P0 := xf * (base + d0 * r0)
		var P1 := xf * (base + d1 * r0)
		var P2 := xf * (base + d1 * r1 + Vector3(0, h, 0))
		var P3 := xf * (base + d0 * r1 + Vector3(0, h, 0))
		var n0 := (xf.basis * (d0 + Vector3(0, slope, 0))).normalized()
		var n1 := (xf.basis * (d1 + Vector3(0, slope, 0))).normalized()
		var u0 := circ * i / segs / uv_scale
		var u1 := circ * (i + 1) / segs / uv_scale
		var vt := sqrt(h * h + (r0 - r1) * (r0 - r1)) / uv_scale
		var outward := xf.basis * (d0 + d1)
		var fn := (P1 - P0).cross(P2 - P0)
		if r1 == 0.0:
			fn = (P1 - P0).cross(P3 - P0)
		if fn.dot(outward) > 0.0:   # counter-clockwise from outside: emit reversed
			_v(st, P0, n0, Vector2(u0, 0)); _v(st, P2, n1, Vector2(u1, vt)); _v(st, P1, n1, Vector2(u1, 0))
			if r1 > 0.0:
				_v(st, P0, n0, Vector2(u0, 0)); _v(st, P3, n0, Vector2(u0, vt)); _v(st, P2, n1, Vector2(u1, vt))
		else:
			_v(st, P0, n0, Vector2(u0, 0)); _v(st, P1, n1, Vector2(u1, 0)); _v(st, P2, n1, Vector2(u1, vt))
			if r1 > 0.0:
				_v(st, P0, n0, Vector2(u0, 0)); _v(st, P2, n1, Vector2(u1, vt)); _v(st, P3, n0, Vector2(u0, vt))
		if top_cap and r1 > 0.0:
			var top := base + Vector3(0, h, 0)
			tri(xf, top, base + d0 * r1 + Vector3(0, h, 0), base + d1 * r1 + Vector3(0, h, 0), mat, Vector3.UP, uv_scale, shadow)


## Flat ellipse (fan) or elliptical ring band at height y.
func ellipse_ring(xf: Transform3D, cx: float, cz: float, a0: float, b0: float, a1: float, b1: float, y: float,
		mat: Material, segs := 64, uv_scale := 1.0, shadow := false) -> void:
	for i in segs:
		var t0 := TAU * i / segs
		var t1 := TAU * (i + 1) / segs
		var p0 := Vector3(cx + cos(t0) * a0, y, cz + sin(t0) * b0)
		var p1 := Vector3(cx + cos(t1) * a0, y, cz + sin(t1) * b0)
		var q0 := Vector3(cx + cos(t0) * a1, y, cz + sin(t0) * b1)
		var q1 := Vector3(cx + cos(t1) * a1, y, cz + sin(t1) * b1)
		if a0 <= 0.0:
			tri(xf, Vector3(cx, y, cz), q0, q1, mat, Vector3.UP, uv_scale, shadow)
		else:
			quad(xf, p0, q0, q1, p1, mat, Vector3.UP, uv_scale, shadow)


## Vertical band round an ellipse from y0 to y1, facing outward (or inward).
func ellipse_wall(xf: Transform3D, cx: float, cz: float, a: float, b: float, y0: float, y1: float,
		mat: Material, inward := false, segs := 64, uv_scale := 1.0, shadow := true) -> void:
	for i in segs:
		var t0 := TAU * i / segs
		var t1 := TAU * (i + 1) / segs
		var d := Vector3(cos((t0 + t1) * 0.5), 0, sin((t0 + t1) * 0.5))
		var p0 := Vector3(cx + cos(t0) * a, y0, cz + sin(t0) * b)
		var p1 := Vector3(cx + cos(t1) * a, y0, cz + sin(t1) * b)
		quad(xf, p0, p1, p1 + Vector3(0, y1 - y0, 0), p0 + Vector3(0, y1 - y0, 0), mat, -d if inward else d, uv_scale, shadow)


## Turn everything collected so far into MeshInstance3D children of `parent`.
func commit(parent: Node3D) -> int:
	var count := 0
	for key in _tools:
		var e: Dictionary = _tools[key]
		var st: SurfaceTool = e["st"]
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		mesh.surface_set_material(0, e["mat"])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if e["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		count += 1
	_tools.clear()
	return count
