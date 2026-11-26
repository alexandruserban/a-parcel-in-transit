extends RefCounted
## Night lighting that is not in the web version's lamp pool: floodlights on the church tower and carnival
## festoons of coloured bulbs strung across the Stadtpark. Every light is added to world.night_lights (shown
## at night only) and the bulbs glow through world.night_glows.

const CX := -45.0      # church tower
const TZ := 30.5
const BULB_COLORS := ["#ff1a1a", "#ffb000", "#19e632", "#1a6bff", "#ff19c8", "#ff6a00", "#9a2bff", "#00d9e6"]
const POLE_H := 5.0

static func _spot(w, at: Vector3, target: Vector3, col: Color, energy: float, range_m: float, angle: float) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.spot_range = range_m
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.9
	l.visible = false
	w.add_child(l)
	l.look_at_from_position(at, target, Vector3.UP)
	w.night_lights.append(l)
	return l


static func _omni(w, at: Vector3, col: Color, energy: float, range_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.3
	l.position = at
	l.visible = false
	w.add_child(l)
	w.night_lights.append(l)
	return l


## The church tower: two warm floodlights on its front, a light in the belfry (the clock faces and belfry
## openings glow through their own materials)
static func church(w) -> void:
	for s in [-1.0, 1.0]:
		_spot(w, Vector3(CX + s * 9.0, 0.4, TZ - 17.0), Vector3(CX, 26.0, TZ - 4.5), Color("#ffd9a0"), 9.0, 70.0, 20.0)
	_spot(w, Vector3(CX, 0.4, TZ - 9.0), Vector3(CX, 50.0, TZ - 1.0), Color("#ffe7c4"), 6.0, 70.0, 12.0)   # up the spire
	_omni(w, Vector3(CX, 29.0, TZ), Color("#ffcf8a"), 3.0, 7.0)


## Carnival festoons in the Stadtpark: strings of coloured bulbs zig-zagging over the two gravel paths and
## swagged round the pond on posts, with a few coloured lights below them
static func park(w) -> void:
	var b = w.b
	var pole_mat: Material = w.mats.lamp_iron
	var wire_mat: Material = w.color_mat("#1b1b1d")
	var poles: Array[Vector3] = []
	var strings: Array = []   # [from_top, to_top]
	var park: Rect2 = w.park
	# over the east-west path (z 79.5..82.5): posts on alternate sides every 8 m
	var prev = null
	var k := 0
	var x := park.position.x + 2.0
	while x < park.end.x - 1.0:
		if absf(x + 45.0) > 2.6:   # keep the crossing with the north-south path clear
			var p := Vector3(x, 0, 78.4 if k % 2 == 0 else 83.6)
			poles.append(p)
			if prev != null:
				strings.append([prev, p])
			prev = p
			k += 1
		x += 8.0
	# over the north-south path (x -46.5..-43.5) from the church square to the pond
	prev = null
	k = 0
	var z := 68.0
	while z < 96.0:
		if absf(z - 81.0) > 2.8:
			var p := Vector3(-47.6 if k % 2 == 0 else -42.4, 0, z)
			poles.append(p)
			if prev != null:
				strings.append([prev, p])
			prev = p
			k += 1
		z += 6.5
	# swagged round the pond on posts just outside its paved walk
	var lake: Dictionary = w.lakes[0]
	var a: float = lake.rw + 3.4
	var c: float = lake.rd + 3.4
	var n := 20
	var ring: Array[Vector3] = []
	for i in n:
		var t := TAU * i / n
		var p := Vector3(lake.cx + cos(t) * a, 0, lake.cz + sin(t) * c)
		if absf(p.x + 45.0) < 2.4 and p.z < lake.cz:   # the path in from the north
			p.x = -48.0 if p.x < -45.0 else -42.0
		ring.append(p)
		poles.append(p)
	for i in n:
		strings.append([ring[i], ring[(i + 1) % n]])
	# posts
	for p in poles:
		b.cylinder(Transform3D.IDENTITY, p, 0.09, 0.07, POLE_H, 8, pole_mat)
		b.cylinder(Transform3D.IDENTITY, p + Vector3(0, POLE_H, 0), 0.13, 0.0, 0.22, 8, pole_mat)
		w.solid_cyl(p.x, p.z, 0.09, POLE_H)
	# bulbs on sagging wires
	var bulbs: Array = []   # [pos, color]
	var ci := 0
	for st in strings:
		var p0: Vector3 = st[0] + Vector3(0, POLE_H - 0.15, 0)
		var p1: Vector3 = st[1] + Vector3(0, POLE_H - 0.15, 0)
		var len := p0.distance_to(p1)
		var sag := 0.35 + len * 0.06
		var segs := maxi(2, int(len / 0.45))
		var last := p0
		for i in range(1, segs + 1):
			var t := float(i) / segs
			var q := p0.lerp(p1, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
			_wire(b, last, q, wire_mat)
			last = q
			if i < segs:
				bulbs.append([q + Vector3(0, -0.07, 0), Color(BULB_COLORS[ci % BULB_COLORS.size()])])
				ci += 1
	var mesh := SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.17
	mesh.radial_segments = 8
	mesh.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = bulbs.size()
	for i in bulbs.size():
		mm.set_instance_transform(i, Transform3D(Basis(), bulbs[i][0]))
		mm.set_instance_color(i, bulbs[i][1])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bulbs.gdshader")
	w.night_glows.append({"mat": mat, "energy": 0.9})   # kept under the bloom threshold so the colours stay pure
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	# coloured light pooling under the strings
	var spots := [Vector3(-70, 4.0, 81), Vector3(-55, 4.0, 81), Vector3(-30, 4.0, 81), Vector3(-17, 4.0, 81),
		Vector3(-45, 4.0, 74), Vector3(-45, 4.0, 90), Vector3(-45 - a, 4.0, lake.cz), Vector3(-45 + a, 4.0, lake.cz),
		Vector3(-45, 4.0, lake.cz - c), Vector3(-45, 4.0, lake.cz + c)]
	for i in spots.size():
		_omni(w, spots[i], Color(BULB_COLORS[(i * 3) % BULB_COLORS.size()]), 2.4, 12.0)


static func _wire(b, p: Vector3, q: Vector3, mat: Material) -> void:
	var d := q - p
	var len := d.length()
	var ang := atan2(d.y, Vector2(d.x, d.z).length())
	var yaw := atan2(-d.z, d.x)
	b.box(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, ang), (p + q) / 2), Vector3.ZERO, Vector3(len, 0.012, 0.012), mat, 1.0, false)
