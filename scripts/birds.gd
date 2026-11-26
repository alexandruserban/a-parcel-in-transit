extends Node3D
## Birds in the sky, ported from birds.js: three flocks fly lazy loops over the town in loose V formations
## (flapping, then gliding) and two hawks circle high up. Every bird is three instances (body, left wing,
## right wing) of three MultiMeshes, so the whole sky costs three draw calls. They roost at night.

# [anchor x, anchor z, loop radius x, loop radius z, height, speed m/s, bird count, kind]
const FLOCKS := [
	[0, 0, 120, 85, 38, 9, 9, "flock"],
	[-60, 70, 90, 60, 52, 8, 7, "flock"],
	[80, -50, 70, 100, 30, 10, 6, "flock"],
	[30, 60, 14, 14, 70, 6, 1, "hawk"],
	[-90, -80, 18, 18, 85, 6, 1, "hawk"],
]

var flocks: Array = []
var count := 0
var time := 0.0
var mat: StandardMaterial3D
var bodies: MultiMeshInstance3D
var wings_l: MultiMeshInstance3D
var wings_r: MultiMeshInstance3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for fi in FLOCKS.size():
		var f: Array = FLOCKS[fi]
		var kind: String = f[7]
		var birds: Array = []
		for i in int(f[6]):
			# V formation: leader at the front, the rest alternating left/right behind it
			var rank := ceili(i / 2.0)
			var side := 0 if i == 0 else (1 if i % 2 else -1)
			birds.append({
				"back": rank * 2.2 + rng.randf() * 0.6,
				"side": side * rank * 1.9 + (rng.randf() - 0.5) * 0.6,
				"up": (rng.randf() - 0.5) * 1.5,
				"phase": rng.randf() * TAU,
				"flap": 5.0 if kind == "hawk" else 9.0 + rng.randf() * 3.0,
				"wobble": rng.randf() * 100.0,
			})
		flocks.append({"ax": float(f[0]), "az": float(f[1]), "rx": float(f[2]), "rz": float(f[3]), "h": float(f[4]),
			"speed": float(f[5]), "kind": kind, "angle": fi * 1.7, "dir": -1.0 if fi % 2 else 1.0, "birds": birds})
		count += birds.size()

	mat = StandardMaterial3D.new()
	mat.albedo_color = Color("#2b2a2e")
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Bird local frame: forward = +x, up = +y, wings along +-z
	var body := CylinderMesh.new()
	body.top_radius = 0.0
	body.bottom_radius = 0.16
	body.height = 0.9
	body.radial_segments = 6
	body.rings = 1
	body.cap_bottom = true
	var cone := _xformed(body, Transform3D(Basis(Vector3.BACK, -PI / 2), Vector3.ZERO))   # point the cone forward
	bodies = _multi(cone)
	wings_l = _multi(_wing(1.0))
	wings_r = _multi(_wing(-1.0))


## Swept triangle from the shoulder out to the wing tip (two-sided via the material)
func _wing(s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for v in [Vector3(0.22, 0, 0), Vector3(-0.2, 0, 0), Vector3(-0.32, 0, s * 0.85)]:
		st.add_vertex(v)
	return st.commit()


func _xformed(prim: PrimitiveMesh, xf: Transform3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(prim, 0)
	var m := st.commit()
	var out := SurfaceTool.new()
	out.append_from(m, 0, xf)
	return out.commit()


func _multi(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-400, 0, -400), Vector3(800, 200, 800))   # instances span the whole sky
	add_child(mi)
	return mi


## daylight: 0 (night) .. 1 (full day)
func update(dt: float, daylight: float) -> void:
	time += dt
	var t := time
	# Fade out at dusk, back in at dawn
	var vis := clampf((daylight - 0.12) / 0.25, 0.0, 1.0)
	mat.albedo_color.a = vis
	var show := vis > 0.01
	bodies.visible = show
	wings_l.visible = show
	wings_r.visible = show
	if not show:
		return
	var k := 0
	for f in flocks:
		# Move the flock centre along an elliptical loop (constant ground speed)
		var r: float = (f.rx + f.rz) / 2.0
		f.angle += f.dir * (f.speed / r) * dt
		var cx: float = f.ax + cos(f.angle) * f.rx
		var cz: float = f.az + sin(f.angle) * f.rz
		var cy: float = f.h + sin(t * 0.13 + f.ax) * 4.0
		# Heading = direction of travel along the loop
		var vx: float = -sin(f.angle) * f.rx * f.dir
		var vz: float = cos(f.angle) * f.rz * f.dir
		var heading := atan2(vz, vx)
		var fx := cos(heading)
		var fz := sin(heading)
		var lx := -fz
		var lz := fx
		var bank: float = f.dir * (0.45 if f.kind == "hawk" else 0.18)   # lean into the turn
		var scale := 1.9 if f.kind == "hawk" else 1.3
		var basis := Basis(Vector3.UP, -heading) * Basis(Vector3.RIGHT, bank)
		for bd in f.birds:
			# Formation slot plus a gentle drift so the V breathes
			var wob: float = bd.wobble + t
			var back: float = bd.back + sin(wob * 0.7) * 0.4
			var side: float = bd.side + sin(wob * 0.5) * 0.5
			var px := cx - fx * back + lx * side
			var pz := cz - fz * back + lz * side
			var py: float = cy + bd.up + sin(wob * 0.9) * 0.6
			# Flap for a while, then glide with the wings held slightly up
			var cycle := sin(t * 0.35 + bd.phase)
			var gliding := cycle < 0.85 if f.kind == "hawk" else cycle < -0.3
			var flap := 0.12 if gliding else sin(t * bd.flap + bd.phase) * 0.7
			var bob := 0.0 if gliding else sin(t * bd.flap + bd.phase - 0.6) * 0.08
			var m := Transform3D(basis * Basis.from_scale(Vector3.ONE * scale), Vector3(px, py + bob, pz))
			bodies.multimesh.set_instance_transform(k, m)
			# Wings: rotate about the body's forward axis (+x) at the shoulder
			wings_l.multimesh.set_instance_transform(k, m * Transform3D(Basis(Vector3.RIGHT, -flap), Vector3.ZERO))
			wings_r.multimesh.set_instance_transform(k, m * Transform3D(Basis(Vector3.RIGHT, flap), Vector3.ZERO))
			k += 1
