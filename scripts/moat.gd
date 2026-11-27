extends RefCounted
## The moat round the city wall, ported from moat.js: water between two stone banks with coping, a wet band
## at the waterline, lily pads and reeds; a timber drawbridge on chains in front of the Nordtor, raised and
## lowered by a lever in the gate passage; and a small walled bridgehead across the water with two round
## towers and a barred outer gate. The player may walk out through the gate onto the bridge and the landing.

const WY := -1.3        # water level
const FY := -2.4        # moat floor
const BW := 5.0         # bridge width

var w
var b
var m0: float
var m1: float
var bridge := {}        # {hinge, angle, target, chains, shut, lever, len}
var rng := RandomNumberGenerator.new()


func build(world) -> void:
	w = world
	b = world.b
	m0 = world.MOAT_M0
	m1 = world.MOAT_M1
	rng.seed = 2601
	var I := Transform3D.IDENTITY
	var stone: Material = w.mats.wallstone
	var pale: Material = w.mats.palestone
	var strips := [Rect2(-m1, -m1, 2 * m1, m1 - m0), Rect2(-m1, m0, 2 * m1, m1 - m0), Rect2(-m1, -m0, m1 - m0, 2 * m0), Rect2(m0, -m0, m1 - m0, 2 * m0)]
	# the ponds' water shader in ring mode: its edge shading follows the two bank walls
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/pond_water.gdshader")
	wm.set_shader_parameter("noise_tex", w.tex("water_height"))
	wm.set_shader_parameter("axes", Vector2(m0 + 0.6, m1 - 0.6))
	wm.set_shader_parameter("ring", true)
	w.water_mats.append(wm)
	var floor_mat: Material = w.color_mat("#2a3326")
	for r in strips:
		w.flat(r, FY, floor_mat)
		w.flat(r, WY, wm)
	# wet, mossy waterline along both bank walls
	var wet: Material = w._std(Color("#2e3a26"), 0.6)
	for c in [m0 + 0.62, m1 - 0.62]:
		for sd in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
			var along_x: bool = sd[0] == 0
			w.bx(I, sd[0] * c, WY + 0.12, sd[1] * c, 2 * c if along_x else 0.04, 0.45, 0.04 if along_x else 2 * c, wet, false, false)
	# retaining walls with coping on both banks (the inner one stands in the moat side of m0)
	for bank in [[m0, true], [m1, false]]:
		var c: float = bank[0]
		var t := 0.6
		var off: float = c + t / 2 if bank[1] else c - t / 2
		for sd in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
			var along_x: bool = sd[0] == 0
			var x: float = sd[0] * off
			var z: float = sd[1] * off
			if sd[1] == -1:   # north banks: a gap where the bridge lands, with a seat under the deck (its top used
				# to be level with the deck's and flickered through it at both ends)
				for half in [-1.0, 1.0]:
					var l2 := c - BW / 2
					w.bx(I, half * (BW / 2 + l2 / 2), (0.06 + FY) / 2, z, l2, 0.06 - FY, t, stone, false, true, 1.0)
				w.bx(I, 0, (-0.3 + FY) / 2, z, BW, -0.3 - FY, t, stone, false, true, 1.0)
			else:
				w.bx(I, x, (0.06 + FY) / 2, z, 2 * c if along_x else t, 0.06 - FY, t if along_x else 2 * c, stone, false, true, 1.0)
			# coping, with a gap where the drawbridge lands on each bank
			if sd[1] == -1:
				for half in [-1.0, 1.0]:
					var l := c - BW / 2 - 0.2
					w.bx(I, half * (BW / 2 + 0.2 + l / 2), 0.1, z, l + 0.4, 0.14, 0.9, pale)
			else:
				w.bx(I, x, 0.1, z, 2 * c + 0.8 if along_x else 0.9, 0.14, 0.9 if along_x else 2 * c + 0.8, pale)
	_pads_and_reeds(strips)
	_drawbridge()
	_bridgehead()


func _pads_and_reeds(strips: Array) -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 0.45
	pad.bottom_radius = 0.45
	pad.height = 0.01
	pad.radial_segments = 10
	var pads: Array[Transform3D] = []
	for cl in 40:
		var r: Rect2 = strips[cl % 4]
		var cx := r.position.x + 1.5 + rng.randf() * (r.size.x - 3)
		var cz := r.position.y + 1.5 + rng.randf() * (r.size.y - 3)
		if absf(cx) < 12 and cz < 0 and absf(cz) < m1 + 1 and absf(cz) > m0 - 1:
			continue   # keep clear of the bridge
		for k in 7:
			var p := Vector3(cx + (rng.randf() - 0.5) * 3, WY + 0.02, cz + (rng.randf() - 0.5) * 3)
			var mc := maxf(absf(p.x), absf(p.z))
			if mc < m0 + 0.6 or mc > m1 - 0.6:
				continue
			var s := 0.6 + rng.randf() * 0.7
			pads.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1, s)), p))
	_multi(pad, pads, w._std(Color("#3f6b2e"), 0.7))
	var reed := CylinderMesh.new()
	reed.top_radius = 0.0
	reed.bottom_radius = 0.035
	reed.height = 1.0
	reed.radial_segments = 4
	reed.rings = 1
	var reeds: Array[Transform3D] = []
	for cl in 70:
		var t := rng.randf() * 8 * m1 - 4 * m1
		var side := cl % 4
		var off := m1 - 1.0 - rng.randf() * 0.8
		var x := t / 2 if side < 2 else (-off if side == 2 else off)
		var z := (-off if side == 0 else off) if side < 2 else t / 2
		if absf(x) < 10 and z < -m0 + 1:
			continue   # not by the drawbridge
		for k in 24:
			var p := Vector3(x + (rng.randf() - 0.5) * 2.5, WY - 0.2, z + (rng.randf() - 0.5) * 2.5)
			var mc := maxf(absf(p.x), absf(p.z))
			if mc > m1 - 0.7 or mc < m0 + 1:
				continue
			var hgt := 1.2 + rng.randf()
			reeds.append(Transform3D(Basis.from_euler(Vector3((rng.randf() - 0.5) * 0.3, 0, (rng.randf() - 0.5) * 0.3)).scaled(Vector3(1, hgt, 1)), p + Vector3(0, hgt / 2, 0)))
	_multi(reed, reeds, w._std(Color("#6d7f3c"), 0.9))


func _multi(mesh: Mesh, xfs: Array[Transform3D], mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)


## Timber drawbridge hinged at the foot of the gate tower, chains up to the tower face, lever in the passage
func _drawbridge() -> void:
	var zH := -m0
	var len := m1 - m0 + 0.6
	var hinge := Node3D.new()
	hinge.position = Vector3(0, -0.22, zH)   # deck top flush with the gate passage
	w.add_child(hinge)
	var db := preload("res://scripts/batch.gd").new()
	var deck: Material = w.tmat("wood_6b4a2e", Vector2(1.6, 4.0), {"rough": 0.85, "normal": "wood_nrm", "depth": 0.8})
	var beam: Material = w.timber("#3e2c1e")
	var iron: Material = w.mats.iron
	var I := Transform3D.IDENTITY
	db.box(I, Vector3(0, 0.14, -len / 2), Vector3(BW, 0.28, len), deck, 1.0, true, true)
	for s in [-1.0, 1.0]:
		db.box(I, Vector3(s * (BW / 2 - 0.15), 0.32, -len / 2), Vector3(0.3, 0.45, len), beam, 1.0, true, true)
		db.cylinder(I, Vector3(s * (BW / 2 - 0.15), 0.4, -len + 0.3), 0.09, 0.09, 0.4, 8, iron)
	for k in 4:
		db.box(I, Vector3(0, 0.3, -1 - k * (len - 2) / 3), Vector3(BW - 0.2, 0.05, 0.12), iron, 1.0, false)
	db.commit(hinge)
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(BW, 0.28, len)
	cs.shape = bs
	cs.position = Vector3(0, 0.14, -len / 2)
	body.add_child(cs)
	hinge.add_child(body)
	# chains (stretched every frame between the bridge end and the tower face)
	var chain_mat: Material = w._std(Color("#2a2a2c"), 0.4, 0.8)
	var chains: Array = []
	for s in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 1.0
		cm.radial_segments = 6
		c.mesh = cm
		c.material_override = chain_mat
		w.add_child(c)
		chains.append({"mesh": c, "anchor": Vector3(s * 3.0, 8.4, zH - 0.05), "end": Vector3(s * (BW / 2 - 0.15), 0.6, -len + 0.3)})
		var ring := TorusMesh.new()
		ring.inner_radius = 0.15
		ring.outer_radius = 0.29
		b.mesh(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(s * 3.0, 8.4, zH - 0.08)), ring, iron, false)
	# stone abutment on the far bank
	w.bx(I, 0, -0.14, -m1 - 0.3, BW + 1.6, 0.25, 1.2, w.mats.palestone)   # top just under the deck's end
	# rails along the bridge sides (players can't step off into the water)
	for s in [-1.0, 1.0]:
		w.solid(I, Vector3(s * BW / 2, 0.65, (zH - m1) / 2), Vector3(0.3, 1.3, m1 - m0 + 0.4))
	# the raised bridge shuts the gate arch
	var shut := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(BW, 7, 0.8)
	shut.shape = sb
	shut.position = Vector3(0, 3.5, zH - 0.3)
	shut.disabled = true
	w.body.add_child(shut)
	# lever in the gate passage
	w.bx(I, -2.4, 0.5, zH + 3.2, 0.3, 1.0, 0.3, iron, true)
	var lever := Node3D.new()
	lever.position = Vector3(-2.4, 1.0, zH + 3.2)
	w.add_child(lever)
	var lb := preload("res://scripts/batch.gd").new()
	lb.box(I, Vector3(0, 0.55, 0), Vector3(0.07, 1.1, 0.07), iron, 1.0, true)
	var knob := SphereMesh.new()
	knob.radius = 0.08
	knob.height = 0.16
	lb.mesh(Transform3D(Basis(), Vector3(0, 1.1, 0)), knob, w.mats.gilt)
	lb.commit(lever)
	bridge = {"hinge": hinge, "angle": 0.0, "target": 0.0, "chains": chains, "shut": shut, "lever": lever, "len": len}
	var item := {"pos": Vector3(-2.2, 1.2, zH + 3.2), "prompt": "[E] Pull the lever: raise the drawbridge", "type": "lever"}
	item["call"] = func() -> Dictionary:
		var pl = w.get_parent().player
		if bridge.target == 0.0 and pl != null and pl.global_position.z < zH + 0.5:
			return {"title": "Drawbridge", "message": "Not while you are standing on it!"}
		bridge.target = PI / 2 * 0.98 if bridge.target == 0.0 else 0.0
		var up: bool = bridge.target != 0.0
		item.prompt = "[E] Pull the lever: lower the drawbridge" if up else "[E] Pull the lever: raise the drawbridge"
		return {"title": "Drawbridge", "sound": "drawbridge_up" if up else "drawbridge_down",
			"message": "Chains clank and the drawbridge swings up, shutting the Nordtor." if up else "The drawbridge creaks down across the moat. The bridgehead and its towers are open again."}
	w.interactables.append(item)
	update(0.0)


## Little walled landing across the moat: cobbles, crenellated walls, two round towers, a barred outer gate
func _bridgehead() -> void:
	var I := Transform3D.IDENTITY
	var stone: Material = w.mats.wallstone
	var pale: Material = w.mats.palestone
	var z0 := -m1
	var z1 := -m1 - 13
	var hw := 8.0
	w.flat(Rect2(-hw, z1, 2 * hw, z0 - 0.5 - z1), 0.03, w.mats.cobble)
	w.paved_rects.append(Rect2(-hw, z1, 2 * hw, z0 - z1))
	var wall := func(x0: float, za: float, x1: float, zb: float) -> void:
		var along_x := absf(x1 - x0) > absf(zb - za)
		var len := absf(x1 - x0) if along_x else absf(zb - za)
		var cx := (x0 + x1) / 2
		var cz := (za + zb) / 2
		w.bx(I, cx, 1.6, cz, len if along_x else 0.9, 3.2, 0.9 if along_x else len, stone, true)
		var n := floori(len / 1.8)
		for k in n:
			var d := -len / 2 + (k + 0.5) * len / n
			w.bx(I, cx + d if along_x else cx, 3.55, cz if along_x else cz + d, 0.8 if along_x else 0.9, 0.7, 0.9 if along_x else 0.8, stone)
	wall.call(-hw, z0, -hw, z1)
	wall.call(hw, z0, hw, z1)
	wall.call(-hw, z1, -2.4, z1)
	wall.call(2.4, z1, hw, z1)
	# low parapet along the moat either side of the bridge
	for s in [-1.0, 1.0]:
		w.bx(I, s * (2.7 + (hw - 2.7) / 2), 0.5, z0 - 0.3, hw - 2.7, 1.0, 0.5, stone, true)
		w.bx(I, s * (2.7 + (hw - 2.7) / 2), 1.06, z0 - 0.3, hw - 2.6, 0.12, 0.62, pale)
	# outer gate: a pointed arch over shut oak doors, between two little towers
	w.house_parts._arcade_wall(Transform3D(Basis(), Vector3(0, 0, z1 - 0.5)), 4.8, 5.0, 1, 3.6, 2.4, 2.0, 1.0, stone)
	b.polygon(Transform3D(Basis(), Vector3(0, 0.01, z1 + 0.55)), w.Castle.arch_pts(3.6, 2.4, 2.0), w.mats.oak, 1.2)
	w.bx(I, 0, 2.1, z1 + 0.58, 0.07, 4.2, 0.07, w.mats.iron, false, false)
	for y in [1.0, 2.4, 3.6]:
		w.bx(I, 0, y, z1 + 0.58, 3.2, 0.1, 0.05, w.mats.iron, false, false)
	w.solid(I, Vector3(0, 2.5, z1), Vector3(4.8, 5, 1.0))
	for s in [-1.0, 1.0]:
		var x: float = s * hw
		var r := 1.9
		b.cylinder(I, Vector3(x, -1.0, z1), r * 1.06, r, 7.5, 20, stone, false)
		b.cylinder(I, Vector3(x, 6.5 - 0.22, z1), r + 0.3, r + 0.3, 0.45, 20, pale)
		b.cylinder(I, Vector3(x, 6.7, z1), r + 0.6, 0.0, r * 2.3, 20, w.roof_mat("#93412b"))
		w.solid_cyl(x, z1, r, 6.5)
	w.add_interactable(Vector3(0, 1.5, z1 + 1.2), "[E] Try the outer gate", "gate",
		func() -> Dictionary: return {"title": "Outer gate", "message": "Barred from the far side. Beyond it the road winds up to the castle - but there are still parcels to deliver in town.", "sound": "click"})
	# the player may walk out through the gate passage, over the bridge and onto this landing
	w.outer_zones = [Rect2(-2.6, z0 - 1.0, 5.2, -w.FENCE + 2.0 - (z0 - 1.0)), Rect2(-hw + 0.4, z1 + 0.6, 2 * hw - 0.8, z0 + 0.2 - (z1 + 0.6))]


func update(dt: float) -> void:
	if bridge.is_empty():
		return
	bridge.angle += (bridge.target - bridge.angle) * minf(1.0, dt * 1.2)
	if absf(bridge.target - bridge.angle) < 0.002:
		bridge.angle = bridge.target
	var hinge: Node3D = bridge.hinge
	hinge.rotation.x = bridge.angle
	(bridge.shut as CollisionShape3D).disabled = bridge.angle < 0.6
	(bridge.lever as Node3D).rotation.x = 0.7 if bridge.target != 0.0 else -0.7
	var hx := hinge.global_transform if hinge.is_inside_tree() else hinge.transform
	for c in bridge.chains:
		var a: Vector3 = c.anchor
		var e: Vector3 = hx * c.end
		var d := e - a
		var L := d.length()
		var y := d / L
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		(c.mesh as MeshInstance3D).transform = Transform3D(Basis(x, y * L, x.cross(y)), a + d * 0.5)
