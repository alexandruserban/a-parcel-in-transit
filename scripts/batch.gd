extends RefCounted
## Static geometry collector. Every box, quad and cylinder of the town is appended to one SurfaceTool per
## material and 96 m chunk, so the whole town draws as a few hundred meshes (like batchStatic() in world.js).
## UVs are in metres (divided by uv_scale), so tiled shaders keep a real-world scale on any size of part.
## Godot treats clockwise triangles as front faces; every helper takes an `out` hint and winds to suit it.

const CHUNK := 96.0

var _tools := {}
var chunk := CHUNK
## Vertex colour for materials marked with the "vcol" meta (many plain-coloured parts share one material)
var color := Color.WHITE


var _last_mat: Material
var _last_cell := Vector3i(1 << 30, 0, 0)
var _last_st: SurfaceTool


func _tool(mat: Material, at: Vector3, shadow: bool) -> SurfaceTool:
	var cell := Vector3i(floori(at.x / chunk), floori(at.z / chunk), int(shadow))
	var s: SurfaceTool
	if mat == _last_mat and cell == _last_cell:
		s = _last_st
	else:
		var per: Dictionary = _tools.get(mat, {})
		if per.is_empty():
			_tools[mat] = per
		var entry: Variant = per.get(cell)
		if entry == null:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			entry = {"st": st, "mat": mat, "shadow": shadow}
			per[cell] = entry
		s = entry["st"]
		_last_mat = mat
		_last_cell = cell
		_last_st = s
	if mat.has_meta("vcol"):
		s.set_color(color)
	return s


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
var _arrays := {}
func mesh(xf: Transform3D, m: Mesh, mat: Material, shadow := true, flat := false, uv_mul := Vector2.ONE) -> void:
	var arr: Array = _arrays.get(m, [])
	if arr.is_empty():
		var a: Array = m.surface_get_arrays(0)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		if uvs.size() != verts.size():
			uvs.resize(verts.size())
		arr = [verts, a[Mesh.ARRAY_NORMAL], uvs, idx]
		_arrays[m] = arr
	var verts: PackedVector3Array = arr[0]
	var norms: PackedVector3Array = arr[1]
	var uvs: PackedVector2Array = arr[2]
	var idx: PackedInt32Array = arr[3]
	var nb := xf.basis.inverse().transposed()
	var mirrored := xf.basis.determinant() < 0.0
	var st := _tool(mat, xf.origin, shadow)
	var P := PackedVector3Array()
	P.resize(verts.size())
	for i in verts.size():
		P[i] = xf * verts[i]
	var i1 := 2 if mirrored else 1
	var i2 := 1 if mirrored else 2
	for t in range(0, idx.size(), 3):
		var a0 := idx[t]
		var a1 := idx[t + i1]
		var a2 := idx[t + i2]
		var fn := Vector3.ZERO
		if flat:
			fn = (P[a2] - P[a0]).cross(P[a1] - P[a0]).normalized()   # clockwise front faces
		for k in [a0, a1, a2]:
			st.set_normal(fn if flat else (nb * norms[k]).normalized())
			st.set_uv(uvs[k] * uv_mul)
			st.add_vertex(P[k])


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


## Tangents are only needed for normal-mapped materials (and generating them is the slow part of a commit)
static func _needs_tangents(mat: Material) -> bool:
	if mat is ShaderMaterial:
		return (mat as ShaderMaterial).get_shader_parameter("has_normal") == true
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).normal_enabled
	return true


## Bake what was collected into reusable meshes (no tangents): [{mat, mesh, shadow}], then clear
func bake() -> Array:
	var out: Array = []
	for per in _tools.values():
		for e in per.values():
			var m: ArrayMesh = (e["st"] as SurfaceTool).commit()
			if m != null and m.get_surface_count() > 0:
				out.append({"mat": e["mat"], "mesh": m, "shadow": e["shadow"]})
	_tools.clear()
	_last_mat = null
	return out


## Stamp baked meshes in at xf (native SurfaceTool.append_from); remap swaps placeholder materials
func append_baked(xf: Transform3D, baked: Array, remap := {}) -> void:
	for e in baked:
		var mat: Material = remap.get(e["mat"], e["mat"])
		_tool(mat, xf.origin, e["shadow"]).append_from(e["mesh"], 0, xf)


## Turn everything collected so far into MeshInstance3D children of `parent`. With vis_range each mesh is
## recentred on its own bounds and only drawn within that distance (house interiors).
func commit(parent: Node3D, vis_range := 0.0) -> int:
	var count := 0
	var entries: Array = []
	for per in _tools.values():
		entries.append_array(per.values())
	for e in entries:
		var st: SurfaceTool = e["st"]
		if _needs_tangents(e["mat"]):
			st.generate_tangents()
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var centre := Vector3.ZERO
		if vis_range > 0.0:
			centre = mesh.get_aabb().get_center()
			var arr := mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] -= centre
			arr[Mesh.ARRAY_VERTEX] = verts
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, e["mat"])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if vis_range > 0.0:
			mi.position = centre
			mi.visibility_range_end = vis_range
			mi.visibility_range_end_margin = 6.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if e["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		count += 1
	_tools.clear()
	_last_mat = null
	return count
