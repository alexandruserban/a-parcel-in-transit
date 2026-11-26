extends Node3D
## The parcel hoard: hundreds of parcels in three sizes piled up all over the town, and the depot's automatic
## storage. Port of hoard.js and the storage half of warehouse.js. Each size is one MultiMesh; every parcel is a
## record {size, slot, pos, rot, hx, hz, live, stored} that owns one instance slot. Spare slots are kept for
## parcels the player puts down or files into the depot.

const SIZES := {
	"S": {"w": 0.5, "h": 0.5, "d": 0.5, "name": "Small parcel"},    # 8 small = 1 storage block
	"M": {"w": 1.0, "h": 0.5, "d": 1.0, "name": "Medium parcel"},   # 2 medium = 1 block
	"L": {"w": 1.0, "h": 1.0, "d": 1.0, "name": "Large parcel"},    # 1 large = 1 block (1 m cube)
}
const SPARE := 260
var HIDDEN := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0))

var world
var total := 0
var records: Array = []          # every live parcel record (in the town or in the depot)
var _free := {"S": [], "M": [], "L": []}   # free instance slots per size
var _mm := {}
var rng := RandomNumberGenerator.new()

# Depot storage: 1 m blocks in 7 bays along the back wall, 2 deep x 40 long, 3 layers high
var bays: Array[float] = []
var next_block := 0
var open_m = null
var open_s = null
var counts := {"S": 0, "M": 0, "L": 0}
var bay_shapes := {}
const PER_LAYER := 80
const LAYERS := 3


func build() -> void:
	rng.seed = 777
	var WH: Dictionary = world.WH
	for i in 7:
		bays.append(WH.x0 + 0.8 + i * 3.5)

	# Pile centres: every front yard, half the back gardens, plus pavements, park and streets
	var centres: Array = []
	var yard_spots := [[-5.0, 12.5], [4.0, 12.5], [-6.5, 13.0], [6.5, 12.2], [-11.5, 12.5]]
	for i in world.houses.size():
		var h: Dictionary = world.houses[i]
		var xf: Transform3D = world.house_xf(h.x, h.z, h.rot)
		var ys: Array = yard_spots[i % yard_spots.size()]
		var p: Vector3 = xf * Vector3(ys[0], 0, ys[1])
		centres.append([p.x, p.z, true])
		if rng.randf() < 0.5:
			var q: Vector3 = xf * Vector3(-2 + rng.randf() * 8, 0, -10.5)
			centres.append([q.x, q.z, true])
	for i in 40:
		var s: Vector2 = world.random_spot(172)
		centres.append([s.x, s.y, false])

	var specs := {"S": [], "M": [], "L": []}
	for cn in centres:
		var n := 5 + rng.randi_range(0, (10 if cn[2] else 6))
		var columns: Array = []
		for k in n:
			var r := rng.randf()
			var size := "S" if r < 0.45 else ("M" if r < 0.82 else "L")
			var S: Dictionary = SIZES[size]
			var foot: float = maxf(S.w, S.d)
			var x := 0.0
			var z := 0.0
			var y := 0.0
			var col = columns[rng.randi_range(0, columns.size() - 1)] if columns.size() > 0 and rng.randf() < 0.45 else null
			if col != null and col.top < 2.2 and col.foot >= foot * 0.8:
				x = col.x + rng.randf_range(-0.05, 0.05)
				z = col.z + rng.randf_range(-0.05, 0.05)
				y = col.top + S.h / 2
				col.top += S.h
				col.foot = foot
			else:
				var ok := false
				for t in 8:
					x = cn[0] + rng.randf_range(-2.25, 2.25)
					z = cn[1] + rng.randf_range(-2.25, 2.25)
					ok = _free_spot(x, z, 0.5) and not world.in_warehouse(x, z, 2.0)
					if ok:
						break
				if not ok:
					continue
				var g0: float = world.ground_y_at(x, z)
				y = g0 + S.h / 2
				columns.append({"x": x, "z": z, "top": g0 + S.h, "foot": foot})
			specs[size].append([x, y, z, rng.randf() * PI])

	var card: Texture2D = load("res://assets/textures/cardboard_col.png")
	for size in SIZES:
		var S: Dictionary = SIZES[size]
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/cardboard.gdshader")
		mat.set_shader_parameter("card_tex", card)
		mat.set_shader_parameter("box_size", Vector3(S.w, S.h, S.d))
		var list: Array = specs[size]
		var mesh := BoxMesh.new()
		mesh.size = Vector3(S.w, S.h, S.d)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size() + SPARE
		for i in mm.instance_count:
			var tint := 0.82 + rng.randf() * 0.22
			mm.set_instance_color(i, Color(tint, tint * (0.95 + rng.randf() * 0.05), tint * (0.85 + rng.randf() * 0.12)))
			mm.set_instance_transform(i, HIDDEN)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		add_child(mi)
		_mm[size] = mm
		for i in range(mm.instance_count - 1, list.size() - 1, -1):
			_free[size].append(i)
		for i in list.size():
			var sp: Array = list[i]
			_place({"size": size, "slot": i}, sp[0], sp[1], sp[2], sp[3])
	total = records.size()


func _free_spot(x: float, z: float, r: float) -> bool:
	if absf(x) > world.FENCE - 2 or absf(z) > world.FENCE - 2:
		return false
	if world.any_rect(world.footprints, x, z, r) or world.in_lake(x, z, 3.0):
		return false
	for s in world.solids_near(x, z, r):
		if s.top > 0.5 and s.bottom < 1.0 and world.in_rect(s.rect, x, z, r):
			return false
	return true


## Position a parcel record and show its instance
func _place(rec: Dictionary, x: float, y: float, z: float, rot: float, stored := false) -> void:
	var S: Dictionary = SIZES[rec.size]
	var steps := rot / (PI / 2)
	var square := absf(round(steps) - steps) < 0.01
	var odd := int(absf(round(steps))) % 2 == 1
	rec.pos = Vector3(x, y, z)
	rec.rot = rot
	rec.hx = ((S.d if odd else S.w) / 2) if square else maxf(S.w, S.d) * 0.45
	rec.hz = ((S.w if odd else S.d) / 2) if square else maxf(S.w, S.d) * 0.45
	rec.stored = stored
	rec.live = true
	_mm[rec.size].set_instance_transform(rec.slot, Transform3D(Basis(Vector3.UP, rot), rec.pos))
	records.append(rec)


func prompt_for(rec: Dictionary) -> String:
	return "[E] Pick up %s" % String(SIZES[rec.size].name).to_lower()


## Nearest pick-up-able parcel in the view cone (same test as updateInteractions in player.js)
func nearest(eye: Vector3, dir: Vector3, max_dist: float):
	var best = null
	var best_d := max_dist
	for rec in records:
		if rec.stored:
			continue
		var p: Vector3 = rec.pos
		if absf(p.x - eye.x) > best_d or absf(p.z - eye.z) > best_d:
			continue
		var d := eye.distance_to(p)
		if d < best_d and dir.dot((p - eye).normalized()) > 0.85:
			best_d = d
			best = rec
	return best


## Remove a parcel from the town (picked up); anything stacked on it settles down
func take(rec: Dictionary) -> void:
	records.erase(rec)
	rec.live = false
	_mm[rec.size].set_instance_transform(rec.slot, HIDDEN)
	_free[rec.size].append(rec.slot)
	_settle(rec.pos.x, rec.pos.z, rec.hx, rec.hz, rec.pos.y)


func _support_top(x: float, z: float, hx: float, hz: float, ignore, below := INF) -> float:
	var top: float = world.ground_y_at(x, z)
	for p in records:
		if p == ignore:
			continue
		if absf(p.pos.x - x) < p.hx + hx - 0.03 and absf(p.pos.z - z) < p.hz + hz - 0.03:
			var t: float = p.pos.y + SIZES[p.size].h / 2
			if t > top and t <= below:
				top = t
	return top


func _settle(x: float, z: float, hx: float, hz: float, y0: float) -> void:
	var above: Array = []
	for p in records:
		if p.pos.y > y0 and absf(p.pos.x - x) < p.hx + hx + 0.05 and absf(p.pos.z - z) < p.hz + hz + 0.05:
			above.append(p)
	above.sort_custom(func(a, c): return a.pos.y < c.pos.y)
	for p in above:
		var h: float = SIZES[p.size].h
		var y := _support_top(p.pos.x, p.pos.z, p.hx, p.hz, p, p.pos.y - h / 2 + 0.02) + h / 2
		if y < p.pos.y - 0.001:
			p.pos.y = y
			_mm[p.size].set_instance_transform(p.slot, Transform3D(Basis(Vector3.UP, p.rot), p.pos))


## Where a parcel of this size would land in front of the player: {x, y, z, rot, ok}
func placement_for(size: String, cam: Vector3, yaw: float) -> Dictionary:
	var S: Dictionary = SIZES[size]
	var dist: float = 1.2 + maxf(S.w, S.d) / 2
	var x := snappedf(cam.x - sin(yaw) * dist, 0.05)
	var z := snappedf(cam.z - cos(yaw) * dist, 0.05)
	var rot: float = round(yaw / (PI / 2)) * (PI / 2)
	var odd := int(absf(round(rot / (PI / 2)))) % 2 == 1
	var hx: float = (S.d if odd else S.w) / 2
	var hz: float = (S.w if odd else S.d) / 2
	var top := _support_top(x, z, hx, hz, null)
	var ok: bool = top + S.h < 3.4 and not world.house_at(x, z) and absf(x) < world.FENCE - 0.5 and absf(z) < world.FENCE - 0.5
	return {"x": x, "y": top + S.h / 2, "z": z, "rot": rot, "ok": ok}


func drop(size: String, pl: Dictionary) -> bool:
	if _free[size].is_empty():
		return false
	_place({"size": size, "slot": _free[size].pop_back()}, pl.x, pl.y, pl.z, pl.rot)
	return true


# ------------------------------------------------------------------------------------------------
# Automatic depot storage: a large parcel fills a block, two mediums stack into one, eight smalls pack 2x2x2
# ------------------------------------------------------------------------------------------------
func _next_block():
	var per_bay := PER_LAYER * LAYERS
	var i := next_block
	next_block += 1
	var bi := i / per_bay
	var r := i % per_bay
	if bi >= bays.size():
		return null
	var level := r / PER_LAYER
	var q := r % PER_LAYER
	var zi := q / 2
	var xi := q % 2
	# the filled part of each bay is solid
	var bay_x: float = bays[bi]
	var len_z := float(zi + 1)
	var cs: CollisionShape3D = bay_shapes.get(bi)
	if cs == null:
		cs = CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		world.body.add_child(cs)
		bay_shapes[bi] = cs
	var cur: Vector3 = (cs.shape as BoxShape3D).size
	len_z = maxf(len_z, cur.z)
	(cs.shape as BoxShape3D).size = Vector3(2.0, 3.1, len_z)
	cs.position = Vector3(bay_x + 1.0, 1.55, -20.0 + len_z / 2)
	return Vector3(bay_x + xi + 0.5, 0.06 + level, -20.0 + zi + 0.5)


## File one parcel; false when the depot is completely full
func store(size: String) -> bool:
	if _free[size].is_empty():
		return false
	var x := 0.0
	var y := 0.0
	var z := 0.0
	if size == "L":
		var blk = _next_block()
		if blk == null:
			return false
		x = blk.x
		y = blk.y + 0.5
		z = blk.z
	elif size == "M":
		if open_m == null:
			var blk = _next_block()
			if blk == null:
				return false
			open_m = {"b": blk, "n": 0}
		var blk: Vector3 = open_m.b
		x = blk.x
		y = blk.y + 0.25 + open_m.n * 0.5
		z = blk.z
		open_m.n += 1
		if open_m.n == 2:
			open_m = null
	else:
		if open_s == null:
			var blk = _next_block()
			if blk == null:
				return false
			open_s = {"b": blk, "n": 0}
		var blk: Vector3 = open_s.b
		var n: int = open_s.n
		x = blk.x + (0.25 if n & 1 else -0.25)
		z = blk.z + (0.25 if n & 2 else -0.25)
		y = blk.y + (0.75 if n & 4 else 0.25)
		open_s.n += 1
		if open_s.n == 8:
			open_s = null
	_place({"size": size, "slot": _free[size].pop_back()}, x, y, z, 0.0, true)
	counts[size] += 1
	return true


func stored_total() -> int:
	return counts.S + counts.M + counts.L


## Minimap dots: positions of parcels lying about in the town
func loose_positions() -> Array:
	var out: Array = []
	for rec in records:
		if not rec.stored:
			out.append(rec.pos)
	return out
