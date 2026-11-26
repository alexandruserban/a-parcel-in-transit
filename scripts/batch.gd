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
## UVs are in metres: u runs a->b, v runs a->d (negated, so the top of the image points from a towards d).
func quad(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, mat: Material,
		out := Vector3.ZERO, uv_scale := 1.0, shadow := true) -> void:
	var A := xf * a
	var B := xf * b
	var C := xf * c
	var D := xf * d
	var tu := (B - A).normalized()
	var tv := ((D - A) - tu * (D - A).dot(tu)).normalized()
	var ua := Vector2.ZERO
	var ub := Vector2((B - A).dot(tu), -(B - A).dot(tv)) / uv_scale
	var uc := Vector2((C - A).dot(tu), -(C - A).dot(tv)) / uv_scale
	var ud := Vector2((D - A).dot(tu), -(D - A).dot(tv)) / uv_scale
	var n := (B - A).cross(C - A)
	var flip := out != Vector3.ZERO and n.dot(xf.basis * out) < 0.0
	if flip:
		n = -n
	n = n.normalized()
	var st := _tool(mat, (A + C) * 0.5, shadow)
	if not flip:   # A,B,C,D is counter-clockwise seen from n: emit clockwise
		_v(st, A, n, ua); _v(st, C, n, uc); _v(st, B, n, ub)
		_v(st, A, n, ua); _v(st, D, n, ud); _v(st, C, n, uc)
	else:
		_v(st, A, n, ua); _v(st, B, n, ub); _v(st, C, n, uc)
		_v(st, A, n, ua); _v(st, C, n, uc); _v(st, D, n, ud)


func tri(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, mat: Material,
		out := Vector3.ZERO, uv_scale := 1.0, shadow := true) -> void:
	var A := xf * a
	var B := xf * b
	var C := xf * c
	var tu := (B - A).normalized()
	var tv := ((C - A) - tu * (C - A).dot(tu)).normalized()
	var ub := Vector2((B - A).dot(tu), -(B - A).dot(tv)) / uv_scale
	var uc := Vector2((C - A).dot(tu), -(C - A).dot(tv)) / uv_scale
	var n := (B - A).cross(C - A)
	var flip := out != Vector3.ZERO and n.dot(xf.basis * out) < 0.0
	if flip:
		n = -n
	n = n.normalized()
	var st := _tool(mat, (A + B + C) / 3.0, shadow)
	if not flip:
		_v(st, A, n, Vector2.ZERO); _v(st, C, n, uc); _v(st, B, n, ub)
	else:
		_v(st, A, n, Vector2.ZERO); _v(st, B, n, ub); _v(st, C, n, uc)


## Triangle with explicit UVs (for glass and pictures that map one image over the shape)
func tri_uv(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, mat: Material,
		out := Vector3.ZERO, shadow := true) -> void:
	var A := xf * a
	var B := xf * b
	var C := xf * c
	var n := (B - A).cross(C - A)
	var flip := out != Vector3.ZERO and n.dot(xf.basis * out) < 0.0
	if flip:
		n = -n
	n = n.normalized()
	var st := _tool(mat, (A + B + C) / 3.0, shadow)
	if not flip:
		_v(st, A, n, ua); _v(st, C, n, uc); _v(st, B, n, ub)
	else:
		_v(st, A, n, ua); _v(st, B, n, ub); _v(st, C, n, uc)


## Any mesh (a PrimitiveMesh or ArrayMesh, surface 0) placed with xf. UVs are kept (0..1 for primitives) and
## scaled by uv_mul. flat: per-face normals (faceted rocks).
func mesh(xf: Transform3D, m: Mesh, mat: Material, shadow := true, flat := false, uv_mul := Vector2.ONE) -> void:
	var arr: Array = m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs = arr[Mesh.ARRAY_TEX_UV]
	var idx = arr[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	var mirrored := xf.basis.determinant() < 0.0
	var st := _tool(mat, xf.origin, shadow)
	var count: int = idx.size() if idx != null and idx.size() > 0 else verts.size()
	for t in range(0, count, 3):
		var ids := [t, t + 1, t + 2]
		if idx != null and idx.size() > 0:
			ids = [idx[t], idx[t + 1], idx[t + 2]]
		if mirrored:
			ids = [ids[0], ids[2], ids[1]]
		var P := [xf * verts[ids[0]], xf * verts[ids[1]], xf * verts[ids[2]]]
		var fn: Vector3 = (P[2] - P[0]).cross(P[1] - P[0]).normalized()   # clockwise front faces
		for k in 3:
			var nn: Vector3 = fn if flat else (nb * norms[ids[k]]).normalized()
			var uv: Vector2 = (uvs[ids[k]] * uv_mul) if uvs != null and uvs.size() > 0 else Vector2.ZERO
			_v(st, P[k], nn, uv)


## Flat polygon (any simple outline in the xy plane of xf, facing +z), triangulated; UVs in metres / uv_scale
## or, with fit = Rect2, mapped so that rect covers the image once (v down)
func polygon(xf: Transform3D, pts: PackedVector2Array, mat: Material, uv_scale := 1.0, shadow := true, fit := Rect2()) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	for t in range(0, tris.size(), 3):
		var p := [pts[tris[t]], pts[tris[t + 1]], pts[tris[t + 2]]]
		var uv := []
		for q in p:
			if fit.size != Vector2.ZERO:
				uv.append(Vector2((q.x - fit.position.x) / fit.size.x, 1.0 - (q.y - fit.position.y) / fit.size.y))
			else:
				uv.append(Vector2(q.x, -q.y) / uv_scale)
		tri_uv(xf, Vector3(p[0].x, p[0].y, 0), Vector3(p[1].x, p[1].y, 0), Vector3(p[2].x, p[2].y, 0), uv[0], uv[1], uv[2], mat, Vector3.BACK, shadow)


## Prism: a flat outline extruded from z = 0 to z = depth (front face at +depth, back at 0, side walls)
func prism(xf: Transform3D, pts: PackedVector2Array, depth: float, mat: Material, uv_scale := 1.0, shadow := true) -> void:
	polygon(xf * Transform3D(Basis(), Vector3(0, 0, depth)), pts, mat, uv_scale, shadow)
	var back := xf * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var rev := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		rev.append(Vector2(-pts[i].x, pts[i].y))
	polygon(back, rev, mat, uv_scale, shadow)
	ring_walls(xf, pts, depth, mat, true, uv_scale, shadow)


## Side walls round an outline (closed), facing outward from its centroid (or inward)
func ring_walls(xf: Transform3D, pts: PackedVector2Array, depth: float, mat: Material, closed := true, uv_scale := 1.0, shadow := true, inward := false) -> void:
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= pts.size()
	var n := pts.size() if closed else pts.size() - 1
	for i in n:
		var a := pts[i]
		var bb := pts[(i + 1) % pts.size()]
		if a.distance_to(bb) < 1e-5:
			continue
		var mid := (a + bb) * 0.5
		var e := bb - a
		var nrm := Vector2(e.y, -e.x)
		if nrm.dot(mid - c) < 0.0:
			nrm = -nrm
		if inward:
			nrm = -nrm
		quad(xf, Vector3(a.x, a.y, 0), Vector3(bb.x, bb.y, 0), Vector3(bb.x, bb.y, depth), Vector3(a.x, a.y, depth), mat, Vector3(nrm.x, nrm.y, 0), uv_scale, shadow)


## Band between two polylines with the same number of points (an arch frame), at z = 0 facing +z (or -z)
func strip(xf: Transform3D, outer: PackedVector2Array, inner: PackedVector2Array, mat: Material, facing := Vector3.BACK, uv_scale := 1.0, shadow := true) -> void:
	for i in outer.size() - 1:
		var a := outer[i]
		var bb := outer[i + 1]
		var c := inner[i + 1]
		var d := inner[i]
		tri(xf, Vector3(a.x, a.y, 0), Vector3(bb.x, bb.y, 0), Vector3(c.x, c.y, 0), mat, facing, uv_scale, shadow)
		tri(xf, Vector3(a.x, a.y, 0), Vector3(c.x, c.y, 0), Vector3(d.x, d.y, 0), mat, facing, uv_scale, shadow)


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
		var vt := -sqrt(h * h + (r0 - r1) * (r0 - r1)) / uv_scale
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
		st.generate_tangents()
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
