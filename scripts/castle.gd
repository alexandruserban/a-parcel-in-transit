extends RefCounted
## The Burg on a hill north-west of the town, ported from castle.js: a crag raised out of the foothills with a
## flat top, a ring of crenellated curtain walls with round towers, a gatehouse facing the town, a tall round
## keep (Bergfried) flying the town banner, a Gothic hall (Palas) with windows that light up at night, crags
## round the rim, conifers on the slopes and a gravel track winding up from the north gate.

const HILL := {"x": -290.0, "z": -175.0, "top": 80.0, "r_in": 31.0, "r_out": 88.0}

var w        # world.gd
var b        # its batch
var M := {}
var rng := RandomNumberGenerator.new()


## 0..1: how much of the castle crag replaces the natural terrain here (1 = the flat top)
static func hill_mask(x: float, z: float) -> float:
	var d := Vector2(x - HILL.x, z - HILL.z).length()
	return smoothstep(0.0, HILL.r_out - HILL.r_in, HILL.r_out - d)


func build(world) -> void:
	w = world
	b = world.b
	rng.seed = 1234
	M.stone = w.mats.wallstone
	M.pale = w.mats.palestone
	M.slate = w.mats.slate
	M.clay = w.roof_mat("#93412b")
	M.dark = w.color_mat("#2a2622")
	M.wood = w.mats.soffit
	M.iron = w.mats.iron
	M.glass = w.tmat("leadedglass", Vector2(1, 1), {"rough": 0.15, "metal": 0.3, "emission_tint": Color("#ffc47e")})
	w.night_glows.append({"mat": M.glass, "energy": 2.6})
	M.slit = w._glow(Color("#2a2622"), Color("#ffaa55"), 3.5)       # arrow slits lit from inside at night
	M.lantern = w._glow(Color("#f6e8c8"), Color("#ffb85c"), 7.0)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color("#77736c")
	rock.roughness = 1.0
	M.rock = rock
	_castle()


## A frame placed on the hill, facing outward at angle a (local +z = away from the castle centre)
static func _cg(x: float, y: float, z: float, a: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI / 2 - a), Vector3(x, y, z))


func _box(xf: Transform3D, w_: float, h: float, d: float, x: float, y: float, z: float, mat, shadow := true) -> void:
	b.box(xf, Vector3(x, y, z), Vector3(w_, h, d), mat, 1.0, shadow)


## Conical tiled roof
func _cone_roof(x: float, y: float, z: float, r: float, h: float, mat: Material, segs := 16) -> void:
	b.cylinder(Transform3D.IDENTITY, Vector3(x, y, z), r, 0.0, h, segs, mat)


func _tower(x: float, y0: float, z: float, r: float, h: float, roof: Material) -> void:
	b.cylinder(Transform3D.IDENTITY, Vector3(x, y0 - 4.0, z), r * 1.08, r, h + 4.0, 18, M.stone, false)
	b.cylinder(Transform3D.IDENTITY, Vector3(x, y0 + h - 0.25, z), r + 0.4, r + 0.4, 0.5, 18, M.pale)
	_cone_roof(x, y0 + h + 0.25, z, r + 0.7, r * 2.4, roof, 18)
	for k in 5:
		var xf := Transform3D(Basis(Vector3.UP, k / 5.0 * TAU + 0.3), Vector3(x, y0 + h * 0.6, z))
		_box(xf, 0.22, 1.2, 0.1, 0, 0, r + 0.02, M.slit, false)


## Arch outline (gothic.js archOutline): from the left foot up the jamb, over the apex, down to the right foot
static func arch_pts(w_: float, spring: float, rise: float, y0 := 0.0, n := 10) -> PackedVector2Array:
	var c := (rise * rise - w_ * w_ / 4.0) / w_
	var r := w_ / 2.0 + c
	var a := atan2(rise, c)
	var ys := y0 + spring
	var pts := PackedVector2Array([Vector2(-w_ / 2, y0)])
	if spring > 0.001:
		pts.append(Vector2(-w_ / 2, ys))
	for i in range(1, n + 1):   # left arc: centre (+c, ys), from pi down to pi - a
		var t: float = PI - a * i / n
		pts.append(Vector2(c + r * cos(t), ys + r * sin(t)))
	for i in range(1, n + 1):   # right arc: centre (-c, ys), from a down to 0
		var t: float = a - a * i / n
		pts.append(Vector2(-c + r * cos(t), ys + r * sin(t)))
	if spring > 0.001:
		pts.append(Vector2(w_ / 2, y0))
	else:
		pts[pts.size() - 1] = Vector2(w_ / 2, y0)
	return pts


## Pointed lancet in a stone frame (oldtown.js churchWindow with noMullion), built facing +z in xf
func _lancet(xf: Transform3D, w_: float, h: float, fw: float, fd: float) -> void:
	var outer := arch_pts(w_ + 2 * fw, h + fw * 1.4 - (w_ + 2 * fw) * 0.866, (w_ + 2 * fw) * 0.866, -fw * 0.5)
	var inner := arch_pts(w_, h - w_ * 0.866, w_ * 0.866, 0.0)
	var front := xf * Transform3D(Basis(), Vector3(0, 0, fd))
	b.strip(front, outer, inner, M.pale, Vector3.BACK, 3.0, false)
	b.quad(front, Vector3(outer[0].x, outer[0].y, 0), Vector3(outer[outer.size() - 1].x, outer[0].y, 0), Vector3(inner[inner.size() - 1].x, 0, 0), Vector3(inner[0].x, 0, 0), M.pale, Vector3.BACK, 3.0, false)
	b.ring_walls(xf, outer, fd, M.pale, true, 3.0, false)
	b.ring_walls(xf, inner, fd, M.pale, true, 3.0, false, true)
	b.polygon(xf * Transform3D(Basis(), Vector3(0, 0, 0.03)), inner, M.glass, 1.0, false, Rect2(-w_ / 2, 0, w_, h))


## churchWindow(x, y, z, rotY, ...) in world space
func _window_at(x: float, y: float, z: float, rot_y: float, w_: float, h: float, fw: float, fd: float) -> void:
	_lancet(Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z)), w_, h, fw, fd)


func _castle() -> void:
	var cx: float = HILL.x
	var cz: float = HILL.z
	var y0: float = w.mountain_height(cx, cz)
	var to_town := atan2(-cz, -cx)                 # the gate looks toward the town
	var R := 26.0
	var N := 12
	var step := TAU / N
	# the wall segment nearest the town direction carries the gatehouse
	var gate_seg := 0
	var best := 9.0
	for i in N:
		var a := (i + 0.5) * step
		var d := absf(wrapf(a - to_town, -PI, PI))
		if d < best:
			best = d
			gate_seg = i
	var ap := R * cos(step / 2)
	var seg_l := 2 * R * sin(step / 2)
	for i in N:
		var a := (i + 0.5) * step
		var g := _cg(cx + cos(a) * ap, y0, cz + sin(a) * ap, a)
		if i == gate_seg:
			_gatehouse(g, seg_l)
			continue
		_box(g, seg_l + 0.4, 14, 2.2, 0, 2.5, 0, M.stone)            # from 4.5 m below the top of the crag
		_box(g, seg_l + 0.4, 0.2, 2.4, 0, 9.55, 0, M.pale, false)
		_box(g, seg_l + 0.4, 1.1, 0.55, 0, 10.2, 0.85, M.stone)
		var n := floori(seg_l / 2)
		for k in n:
			_box(g, 1.0, 0.9, 0.55, -seg_l / 2 + (k + 0.5) * seg_l / n, 11.2, 0.85, M.stone)
	for i in range(0, N, 2):
		var a := i * step
		_tower(cx + cos(a) * R, y0, cz + sin(a) * R, 3.4, 15, M.clay if i % 4 else M.slate)
	# Bergfried: tall round keep at the back of the courtyard, with battlements and a slate spire
	var kx := cx - cos(to_town) * 9
	var kz := cz - sin(to_town) * 9
	var KR := 5.6
	var KH := 33.0
	b.cylinder(Transform3D.IDENTITY, Vector3(kx, y0 - 3.0, kz), KR * 1.05, KR, KH + 3, 24, M.stone, false)
	b.cylinder(Transform3D.IDENTITY, Vector3(kx, y0 + KH, kz), KR, KR + 0.7, 1.0, 24, M.pale)
	for k in 18:
		var xf := Transform3D(Basis(Vector3.UP, k / 18.0 * TAU), Vector3(kx, y0 + KH + 1.6, kz))
		_box(xf, 1.0, 1.2, 0.6, 0, 0, KR + 0.4, M.stone)
	_cone_roof(kx, y0 + KH + 1.0, kz, KR - 0.3, 12, M.slate, 20)
	# keep windows: lancets stacked up the side facing the town
	for i in 3:
		var y: float = [10.0, 17.0, 24.0][i]
		var a := to_town + (i - 1) * 0.35
		var kr := KR * 1.05 - KR * 0.05 * (y + 3.0) / (KH + 3.0)   # the keep's radius at this height (it tapers)
		_window_at(kx + cos(a) * kr, y0 + y, kz + sin(a) * kr, PI / 2 - a, 0.8, 2.4, 0.16, 0.16)
	# the town banner on a pole above the spire
	var pole_top := y0 + KH + 13.5
	_box(Transform3D.IDENTITY, 0.12, 4, 0.12, kx, pole_top + 1.5, kz, M.iron, false)
	_flag(Vector3(kx, pole_top + 2.0, kz))
	# Palas: the Gothic hall along the side of the courtyard
	_palas(cx + cos(to_town + PI / 2) * 10, y0, cz + sin(to_town + PI / 2) * 10, to_town)
	# crags breaking through round the rim of the hilltop
	var rock_mesh := SphereMesh.new()
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 3
	for k in 22:
		var a := k / 22.0 * TAU + rng.randf() * 0.2
		var r: float = HILL.r_in + 2 + rng.randf() * 10
		var x := cx + cos(a) * r
		var z := cz + sin(a) * r
		var s := 2.0 + rng.randf() * 3.5
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * 3.0).scaled(Vector3(s, s * (0.6 + rng.randf() * 0.6), s)), Vector3(x, w.mountain_height(x, z) + 0.5, z))
		b.mesh(xf, rock_mesh, M.rock, true, true)
	_night_lights(cx, cz, y0, to_town, R, kx, kz, KH)
	_track(cx + cos(to_town) * (R + 4), cz + sin(to_town) * (R + 4))
	_forest(cx, cz)


## Night: floodlights on the walls, gatehouse and keep facing the town, a light in the courtyard and one at the
## top of the keep, and lanterns on the curtain walls, so the castle shows up on its hill after dark
func _night_lights(cx: float, cz: float, y0: float, to_town: float, R: float, kx: float, kz: float, KH: float) -> void:
	var out := Vector3(cos(to_town), 0, sin(to_town))
	var side := Vector3(-out.z, 0, out.x)
	var base := Vector3(cx, y0 + 0.6, cz) + out * (R + 7.0)
	for s in [-1.0, 0.0, 1.0]:
		var at: Vector3 = base + side * s * 14.0
		var target: Vector3 = Vector3(kx, y0 + (24.0 if s == 0.0 else 9.0), kz) + side * s * 6.0
		_light(SpotLight3D.new(), at, target, Color("#ffd8a0"), 12.0, 80.0, 30.0)
	_light(OmniLight3D.new(), Vector3(cx, y0 + 8.0, cz), Vector3.ZERO, Color("#ffc98a"), 3.0, 32.0)
	_light(OmniLight3D.new(), Vector3(kx, y0 + KH + 3.0, kz), Vector3.ZERO, Color("#ffc98a"), 4.0, 14.0)
	# lanterns on the outer face of every other curtain wall
	var N := 12
	var step := TAU / N
	var ap := R * cos(step / 2)
	for i in range(1, N, 2):
		var a := (i + 0.5) * step
		var g := _cg(cx + cos(a) * ap, y0, cz + sin(a) * ap, a)
		_box(g, 0.5, 0.7, 0.5, 0, 8.6, 1.45, M.lantern, false)


func _light(l: Light3D, at: Vector3, target: Vector3, col: Color, energy: float, range_m: float, angle := 0.0) -> void:
	l.light_color = col
	l.light_energy = energy
	l.visible = false
	if l is SpotLight3D:
		(l as SpotLight3D).spot_range = range_m
		(l as SpotLight3D).spot_angle = angle
		(l as SpotLight3D).spot_angle_attenuation = 0.8
	else:
		(l as OmniLight3D).omni_range = range_m
		(l as OmniLight3D).omni_attenuation = 1.2
	w.add_child(l)
	if l is SpotLight3D:
		l.look_at_from_position(at, target, Vector3.UP)
	else:
		l.position = at
	w.night_lights.append(l)


## Gatehouse: a square tower astride the wall with a pointed archway, portcullis and battlements
func _gatehouse(g: Transform3D, seg_l: float) -> void:
	_box(g, 9, 21, 8, 0, 6, 0.6, M.stone)
	_box(g, 9.6, 0.4, 8.6, 0, 16.6, 0.6, M.pale, false)
	for k in 5:
		for s in [-1.0, 1.0]:
			_box(g, 1.0, 1.0, 0.6, -3.6 + k * 1.8, 17.3, 0.6 + s * 4.0, M.stone)
	for s in [-1.0, 1.0]:
		_box(g, (seg_l - 9) / 2 + 0.3, 14, 2.2, s * (4.5 + (seg_l - 9) / 4), 2.5, 0, M.stone)
	var inner := arch_pts(3.6, 3.0, 2.0, 0.0)
	b.polygon(g * Transform3D(Basis(), Vector3(0, 0, 4.62)), inner, M.dark, 1.0, false)
	var outer := arch_pts(4.4, 3.0, 2.5, 0.0)
	var fxf := g * Transform3D(Basis(), Vector3(0, 0, 4.6))
	b.strip(fxf * Transform3D(Basis(), Vector3(0, 0, 0.2)), outer, inner, M.pale, Vector3.BACK, 3.0)
	b.ring_walls(fxf, outer, 0.2, M.pale, false, 3.0)
	var u := -1.5
	while u <= 1.51:
		_box(g, 0.08, 2.4, 0.08, u, 3.8, 4.7, M.iron, false)
		u += 0.5
	for y in [10.0, 13.0]:
		for uu in [-2.2, 2.2]:
			_box(g, 0.5, 1.4, 0.1, uu, y, 4.62, M.dark, false)
	for s in [-1.0, 1.0]:   # lanterns either side of the gateway
		_box(g, 0.12, 0.12, 0.5, s * 2.9, 5.6, 4.85, M.iron, false)
		_box(g, 0.45, 0.65, 0.45, s * 2.9, 5.3, 5.1, M.lantern, false)
	var arms: Material = w.tmat("arms", Vector2(1, 1), {"rough": 0.8})
	b.polygon(g * Transform3D(Basis(), Vector3(0, 7.2, 4.63)), PackedVector2Array([Vector2(-0.7, -0.875), Vector2(0.7, -0.875), Vector2(0.7, 0.875), Vector2(-0.7, 0.875)]), arms, 1.0, false, Rect2(-0.7, -0.875, 1.4, 1.75))


## Palas: long stone hall with stepped gables, a steep red roof and two rows of lit lancets
func _palas(x: float, y0: float, z: float, a: float) -> void:
	var g := _cg(x, y0, z, a + PI / 2)
	var L := 20.0
	var D := 9.0
	var H := 11.0
	_box(g, L, H + 3, D, 0, (H - 3) / 2, 0, M.stone)
	_box(g, L + 0.4, 0.35, D + 0.4, 0, H, 0, M.pale, false)
	var rise := _gable_roof(g, D, L, H, deg_to_rad(55), 0.4, 0.3, M.clay, M.wood, M.stone, 0.4, 0.2)
	for s in [-1.0, 1.0]:
		_stepped_gable(g, s * (L / 2 - 0.2), D / 2, rise, H, 0.9, 0.5)
	for i in 5:
		var uu := -L / 2 + 2 + i * (L - 4) / 4
		for side in [[D / 2, 0.0], [-D / 2, PI]]:
			for yh in [[2.2, 2.6], [6.4, 3.2]]:
				var p: Vector3 = g * Vector3(uu, yh[0], side[0])
				_window_at(p.x, p.y, p.z, PI / 2 - (a + PI / 2) + side[1], 1.0, yh[1], 0.18, 0.18)


## Gable roof along local x (oldtown.js buildGableRoof): two slabs, a ridge cap and gable triangles
func _gable_roof(g: Transform3D, span: float, length: float, wall_top: float, pitch: float, eave: float, t: float,
		roof: Material, edge: Material, gable: Material, gT: float, inset: float) -> float:
	var tn := tan(pitch)
	var half := span / 2
	var rise := half * tn
	var ridge := wall_top + rise
	var run := half + eave
	var S := run / cos(pitch)
	var L := length
	for spin in [0.0, PI]:
		var xf: Transform3D = g * Transform3D(Basis(Vector3.UP, spin), Vector3.ZERO) \
			* Transform3D(Basis(), Vector3(0, ridge - (run / 2) * tn, run / 2)) * Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
		b.box(xf, Vector3(0, t / 2, 0), Vector3(L, t, S), [edge, edge, roof, edge, edge, edge], 1.0, true, true)
	_box(g, L + 0.04, 0.26, 0.34, 0, ridge + t / cos(pitch) - 0.02, 0, roof)
	for s in [-1.0, 1.0]:
		var gx: Transform3D = g * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(s * (length / 2 - inset), wall_top, 0))
		b.prism(gx * Transform3D(Basis(), Vector3(0, 0, -gT / 2)), PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), Vector2(0, rise)]), gT, gable, 3.0)
	return rise


## Stepped gable (Treppengiebel) across z at local x = pos (gothic.js steppedGable, plane 'x')
func _stepped_gable(g: Transform3D, pos: float, half: float, rise: float, wall_top: float, step: float, thick: float) -> void:
	var n := floori(half / step - 0.4)
	for k in n:
		var uo := half - k * step
		var ui := half - (k + 1) * step
		var top := wall_top + rise * (1 - ui / half) + 0.55
		var h := top - wall_top
		for s in [-1.0, 1.0]:
			_box(g, thick, h, step, pos, wall_top + h / 2, s * (uo + ui) / 2, M.stone)
			_box(g, thick + 0.12, 0.12, step + 0.08, pos, top + 0.06, s * (uo + ui) / 2, M.pale, false)
	var uc := half - n * step
	var top_c := wall_top + rise + 0.9
	_box(g, thick, top_c - wall_top, 2 * uc, pos, wall_top + (top_c - wall_top) / 2, 0, M.stone)
	_box(g, thick + 0.14, 0.14, 2 * uc + 0.1, pos, top_c + 0.07, 0, M.pale, false)


## The banner: a strip of the town arms waving in the wind (a vertex shader replaces updateCastle's CPU wave)
func _flag(at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var x0 := 2.4 * i / 8.0
		var x1 := 2.4 * (i + 1) / 8.0
		var q := [Vector3(x0, -1.5, 0), Vector3(x1, -1.5, 0), Vector3(x1, 1.5, 0), Vector3(x0, 1.5, 0)]
		var uv := [Vector2(x0 / 2.4, 1), Vector2(x1 / 2.4, 1), Vector2(x1 / 2.4, 0), Vector2(x0 / 2.4, 0)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.BACK)
			st.set_uv(uv[k])
			st.add_vertex(q[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flag.gdshader")
	mat.set_shader_parameter("albedo_tex", w.tex("arms_col"))
	mi.material_override = mat
	mi.position = at
	mi.rotation.y = -0.6
	w.add_child(mi)


## Gravel track from the north gate's bridgehead, along the meadow and in two bends up the hill
func _track(gx: float, gz: float) -> void:
	var tt := atan2(-HILL.z, -HILL.x)
	var pts: Array[Vector3] = [
		Vector3(0, 0, -217), Vector3(-20, 0, -232), Vector3(-80, 0, -246),
		Vector3(-150, 0, -244), Vector3(-205, 0, -262), Vector3(-245, 0, -252),
		Vector3(-232, 0, -222), Vector3(-252, 0, -212), Vector3(-236, 0, -186), Vector3(-252, 0, -164),
		Vector3(gx + cos(tt) * 6, 0, gz + sin(tt) * 6), Vector3(gx, 0, gz)]
	var n := 260
	var W := 3.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	var prev := _catmull(pts, 0.0)
	var rows: Array = []
	for i in n + 1:
		var t := float(i) / n
		var p := _catmull(pts, t)
		var tg := (_catmull(pts, minf(t + 0.0005, 1.0)) - _catmull(pts, maxf(t - 0.0005, 0.0))).normalized()
		var side := Vector3(-tg.z, 0, tg.x).normalized()
		dist += p.distance_to(prev)
		prev = p
		var row := []
		for s in [-1.0, 1.0]:
			var x: float = p.x + side.x * s * W / 2
			var z: float = p.z + side.z * s * W / 2
			row.append([Vector3(x, maxf(0.0, w.mountain_height(x, z)) + 0.35, z), Vector2(0.0 if s < 0 else 1.0, -dist / 3.0)])
		rows.append(row)
	for i in n:
		var q := [rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]]
		var fn: Vector3 = (q[1][0] - q[0][0]).cross(q[2][0] - q[0][0])
		var order := [0, 2, 1, 0, 3, 2] if fn.y > 0 else [0, 1, 2, 0, 2, 3]
		for k in order:
			st.set_normal(Vector3.UP)
			st.set_uv(q[k][1])
			st.add_vertex(q[k][0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = w.tmat("gravel", Vector2(1, 1), {"rough": 1.0, "tint": Color("#cfc2a8")})
	w.add_child(mi)


## Centripetal Catmull-Rom through the points (three.js CatmullRomCurve3 default), t in 0..1 over all segments
static func _catmull(p: Array[Vector3], t: float) -> Vector3:
	var l := p.size()
	var pt := (l - 1) * t
	var i := mini(floori(pt), l - 2)
	var wt := pt - i
	var p0: Vector3 = p[i - 1] if i > 0 else p[0] * 2 - p[1]
	var p1: Vector3 = p[i]
	var p2: Vector3 = p[i + 1]
	var p3: Vector3 = p[i + 2] if i + 2 < l else p[l - 1] * 2 - p[l - 2]
	var dt0 := pow(p0.distance_squared_to(p1), 0.25)
	var dt1 := pow(p1.distance_squared_to(p2), 0.25)
	var dt2 := pow(p2.distance_squared_to(p3), 0.25)
	if dt1 < 1e-4: dt1 = 1.0
	if dt0 < 1e-4: dt0 = dt1
	if dt2 < 1e-4: dt2 = dt1
	var t1 := ((p1 - p0) / dt0 - (p2 - p0) / (dt0 + dt1) + (p2 - p1) / dt1) * dt1
	var t2 := ((p2 - p1) / dt1 - (p3 - p1) / (dt1 + dt2) + (p3 - p2) / dt2) * dt1
	var w2 := wt * wt
	var w3 := w2 * wt
	return p1 * (2 * w3 - 3 * w2 + 1) + t1 * (w3 - 2 * w2 + wt) + p2 * (-2 * w3 + 3 * w2) + t2 * (w3 - w2)


## Conifers clinging to the crag's slopes (the main forest skips anything this steep)
func _forest(cx: float, cz: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	cone.cap_bottom = false
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var count := 520
	var tries := 0
	while tries < count * 4 and xfs.size() < count:
		tries += 1
		var a := rng.randf() * TAU
		var r: float = HILL.r_in + 9 + rng.randf() * (HILL.r_out - HILL.r_in - 4)
		var x := cx + cos(a) * r
		var z := cz + sin(a) * r
		if maxf(absf(x), absf(z)) < 214:      # not on the meadow by the wall
			continue
		if w._vnoise(x * 0.05 + 3, z * 0.05) < 0.3:   # clearings and bare rock
			continue
		var th := 5.0 + rng.randf() * 6.0
		xfs.append(Transform3D(Basis.from_scale(Vector3(th * 0.3, th, th * 0.3)), Vector3(x, w.mountain_height(x, z) - 0.6 + th / 2, z)))
		cols.append(_hsl(0.28 + rng.randf() * 0.06, 0.42, 0.12 + rng.randf() * 0.07))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cone
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	w.add_child(mi)


## THREE.Color.setHSL (sRGB); Color() takes sRGB in Godot, so no conversion is needed
static func _hsl(h: float, s: float, l: float) -> Color:
	var q := l * (1 + s) if l < 0.5 else l + s - l * s
	var p := 2 * l - q
	var f := func(t: float) -> float:
		t = fposmod(t, 1.0)
		if t < 1.0 / 6: return p + (q - p) * 6 * t
		if t < 0.5: return q
		if t < 2.0 / 3: return p + (q - p) * (2.0 / 3 - t) * 6
		return p
	return Color(f.call(h + 1.0 / 3), f.call(h), f.call(h - 1.0 / 3))
