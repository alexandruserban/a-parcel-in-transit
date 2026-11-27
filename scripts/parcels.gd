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

# Depot storage: 1 m blocks in 7 bays along the back wall, 2 columns x 32 long, 3 layers high, with gaps between
# the stacks (BLOCK_PITCH) and every block and parcel set down a little crooked
var bays: Array[float] = []
var next_block := 0
var open_m = null
var open_s = null
var counts := {"S": 0, "M": 0, "L": 0}
var stored_order: Array[String] = []   # sizes in the order they were filed (replayed when a save is loaded)
var bay_shapes := {}
const PER_LAYER := 64
const BLOCK_PITCH := Vector2(1.25, 1.25)   # x (across the bay) and z (along it): 1 m blocks with 25 cm gaps
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
			mm.set_instance_color(i, _box_color())
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


## Box colours: mostly kraft card in shades from pale to dark brown; one in six is a printed mailing box
## (alpha < 0.5 tells the shader to paint it that colour over the card's grain instead of tinting it)
const KRAFT := ["#fff1dc", "#f2dcc0", "#e6c7a0", "#d9b38a", "#c9a07a", "#b88b66", "#a87a58", "#f7e6cf"]
const PRINTED := ["#f2efe8", "#b8432f", "#3f6c94", "#5b8a4a", "#e0b23a", "#7a5a8e", "#2f3a46"]
func _box_color() -> Color:
	if rng.randf() < 0.16:
		var c := Color(PRINTED[rng.randi() % PRINTED.size()])
		c.a = 0.0
		return c
	var k := Color(KRAFT[rng.randi() % KRAFT.size()])
	return k * (0.94 + rng.randf() * 0.1)


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


# ------------------------------------------------------------------------------------------------
# Wind gusts (world.js startGust / updateWind): every loose parcel is lifted, swirled along the gust and
# dropped somewhere new. Anything filed in the depot is safe.
# ------------------------------------------------------------------------------------------------
var flights: Array = []
const BOUNCE_TIME := 0.9   # seconds a landing parcel hops before it settles
const CLIMB := 16.0        # m/s a flying parcel can rise to clear a roof ahead
const SINK := 9.0          # m/s it eases back down after


func _landing_spot(range_m := 140.0) -> Vector2:
	for t in 40:
		var x := rng.randf_range(-range_m, range_m)
		var z := rng.randf_range(-range_m, range_m)
		if world.house_at(x, z) or world.in_warehouse(x, z, 2.0) or world._near_tree(x, z, 1.0):
			continue
		if _free_spot(x, z, 0.6):
			return Vector2(x, z)
	return Vector2(rng.randf_range(-10, 10), 20 + rng.randf() * 30)


func start_gust() -> int:
	flights.clear()
	for rec in records:
		if rec.stored:
			continue
		var to := _landing_spot()
		rec.flying = true
		flights.append({"rec": rec, "from": rec.pos, "to": Vector3(to.x, 0, to.y), "delay": rng.randf() * 1.6,
			"dur": 4.0 + rng.randf() * 3.0, "apex": 12.0 + rng.randf() * 8.0,
			"swirl": (-1.0 if rng.randf() < 0.5 else 1.0) * (2.0 + rng.randf() * 4.0),
			"spin": Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5) * 9.0, "basis": Basis(Vector3.UP, rec.rot)})
	return flights.size()


## How high a flying parcel must stay over (x, z): roofs, walls, towers. Cached on a 2 m grid.
var _clear_cache := {}
func _clearance(x: float, z: float) -> float:
	var key := Vector2i(floori(x / 2.0), floori(z / 2.0))
	if _clear_cache.has(key):
		return _clear_cache[key]
	var cx := (key.x + 0.5) * 2.0
	var cz := (key.y + 0.5) * 2.0
	var top := 0.0
	for o in [Vector2.ZERO, Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(1.4, 1.4), Vector2(-1.4, 1.4)]:
		top = maxf(top, world.roof_top_at(cx + o.x, cz + o.y))   # the highest point of the roof over the cell
	for sd in world.solids_near(cx, cz, 1.6):
		if world.in_rect(sd.rect, cx, cz, 1.6):
			top = maxf(top, sd.top)
	_clear_cache[key] = top
	return top


## Where a flight is over the ground at time t (0..1): along the path with a sideways swirl
static func _flight_xz(f: Dictionary, t: float) -> Vector2:
	var e := t * t * (3.0 - 2.0 * t)
	var from: Vector3 = f.from
	var to: Vector3 = f.to
	var p := Vector2(lerpf(from.x, to.x, e), lerpf(from.z, to.z, e))
	var path := Vector2(to.x - from.x, to.z - from.z).normalized()
	return p + Vector2(-path.y, path.x) * sin(t * TAU) * f.swirl * (1.0 - t)


## Where a parcel comes to rest at (x, z): on the ground, a low plinth or pedestal, or another parcel
func _rest_y(rec: Dictionary, x: float, z: float, below := INF) -> float:
	var S: Dictionary = SIZES[rec.size]
	var hx: float = maxf(S.w, S.d) * 0.45
	var top := _support_top(x, z, hx, hx, rec, below)
	for sd in world.solids_near(x, z, hx):
		if sd.top < 1.2 and world.in_rect(sd.rect, x, z, hx - 0.05):
			top = maxf(top, sd.top)
	return top + S.h / 2 + 0.01


## gust_t: seconds since the gust began; gust: its strength 0..1
func update_gust(gust_t: float, gust: float, dt: float) -> void:
	if flights.is_empty():
		return
	var done := 0
	for f in flights:
		var rec: Dictionary = f.rec
		if not rec.live:
			done += 1
			continue
		var h: float = SIZES[rec.size].h
		var t: float = (gust_t - f.delay) / f.dur
		if t <= 0.0:   # rattling before lift-off
			_mm[rec.size].set_instance_transform(rec.slot, Transform3D(Basis(Vector3.UP, rec.rot) * Basis(Vector3.BACK, sin(gust_t * 20.0) * 0.05 * gust), rec.pos))
			continue
		if t >= 1.0:
			if rec.flying:
				var to: Vector3 = f.to
				if not f.has("rest_y"):
					var S0: Dictionary = SIZES[rec.size]
					rec.hx = maxf(S0.w, S0.d) * 0.45
					rec.hz = rec.hx
					rec.pos = Vector3(to.x, rec.pos.y, to.z)
					f.rest_y = _rest_y(rec, to.x, to.z)
					rec.rest_y = f.rest_y   # others landing here now stack on it
				var rest_y: float = f.rest_y
				if not f.has("land_t") and f.get("y", rest_y) > rest_y + 0.02:   # still above it (it cleared a roof): drop
					f.vy = f.get("vy", 0.0) - 22.0 * dt
					f.y = maxf(rest_y, f.y + f.vy * dt)
					rec.pos = Vector3(to.x, f.y, to.z)
					_mm[rec.size].set_instance_transform(rec.slot, Transform3D(f.basis, rec.pos))
					continue
				if not f.has("land_t"):   # touch down: pick the resting yaw, then bounce
					f.land_t = gust_t
					f.yaw = rng.randf() * PI
					f.tilt_axis = Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized()
				var tau: float = (gust_t - f.land_t) / BOUNCE_TIME
				if tau < 1.0:
					# three hops, each lower than the last, rocking a little as it settles
					var fade := (1.0 - tau) * (1.0 - tau)
					var hop := absf(sin(tau * PI * 3.0)) * 0.45 * fade
					var tilt := sin(tau * PI * 6.0) * 0.25 * fade
					rec.pos = Vector3(to.x, rest_y + hop, to.z)
					_mm[rec.size].set_instance_transform(rec.slot, Transform3D(Basis(f.tilt_axis, tilt) * Basis(Vector3.UP, f.yaw), rec.pos))
					continue
				rec.rot = f.yaw
				rec.pos = Vector3(to.x, rest_y, to.z)
				var S: Dictionary = SIZES[rec.size]
				rec.hx = maxf(S.w, S.d) * 0.45
				rec.hz = rec.hx
				rec.flying = false
				rec.erase("rest_y")
				_mm[rec.size].set_instance_transform(rec.slot, Transform3D(Basis(Vector3.UP, rec.rot), rec.pos))
			done += 1
			continue
		var xz := _flight_xz(f, t)
		var p := Vector3(xz.x, 0, xz.y)
		var from_y: float = (f.from as Vector3).y
		p.y = lerpf(from_y, h / 2, t) + f.apex * 4.0 * t * (1.0 - t) + sin(t * 17.0) * 0.4 * (1.0 - t)
		# keep clear of roofs and walls: look a little ahead and climb in time (at most CLIMB m/s), sink slowly after
		var need := 0.0
		for k in 5:
			var tk := minf(t + k * 0.03, 1.0)
			var q := _flight_xz(f, tk)
			var c := _clearance(q.x, q.y)
			if c > 0.0:
				need = maxf(need, c + h / 2 + 0.5 - k * 0.03 * f.dur * CLIMB)
		f.need = maxf(need, f.get("need", 0.0) - SINK * dt)
		p.y = maxf(p.y, f.need)
		f.y = p.y
		var sp: Vector3 = f.spin * dt
		f.basis = (f.basis * Basis.from_euler(sp)).orthonormalized()
		rec.pos = p
		_mm[rec.size].set_instance_transform(rec.slot, Transform3D(f.basis, p))
	if done == flights.size():
		flights.clear()


## Nearest pick-up-able parcel in the view cone (same test as updateInteractions in player.js)
func nearest(eye: Vector3, dir: Vector3, max_dist: float):
	var best = null
	var best_d := max_dist
	for rec in records:
		if rec.stored or rec.get("flying", false):
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
		var py: float = p.pos.y
		if p.get("flying", false):   # in the air it holds nothing up, unless it has touched down and is settling
			if not p.has("rest_y"):
				continue
			py = p.rest_y
		if absf(p.pos.x - x) < p.hx + hx - 0.03 and absf(p.pos.z - z) < p.hz + hz - 0.03:
			var t: float = py + SIZES[p.size].h / 2
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
	var bay_w := 1.0 + BLOCK_PITCH.x
	var bay_len := (len_z - 1.0) * BLOCK_PITCH.y + 1.0
	(cs.shape as BoxShape3D).size = Vector3(bay_w, 3.1, bay_len)
	cs.position = Vector3(bay_x + bay_w / 2, 1.55, -20.0 + bay_len / 2)
	# a slight, repeatable offset per block (the same after loading a save)
	var jx: float = (world.jhash(i, 1, 91) - 0.5) * 0.08
	var jz: float = (world.jhash(i, 2, 91) - 0.5) * 0.08
	return Vector3(bay_x + xi * BLOCK_PITCH.x + 0.5 + jx, 0.06 + level, -20.0 + zi * BLOCK_PITCH.y + 0.5 + jz)


## A small, repeatable twist for the n-th filed parcel (radians)
func _skew(n: int) -> float:
	return (world.jhash(n, 3, 91) - 0.5) * 0.1


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
		x = blk.x + (0.26 if n & 1 else -0.26)
		z = blk.z + (0.26 if n & 2 else -0.26)
		y = blk.y + (0.75 if n & 4 else 0.25)
		open_s.n += 1
		if open_s.n == 8:
			open_s = null
	_place({"size": size, "slot": _free[size].pop_back()}, x, y, z, _skew(stored_order.size()), true)
	counts[size] += 1
	stored_order.append(size)
	return true


## Everything needed to put the parcels back where they were: loose ones by position (a parcel in mid-air
## counts as already landed), filed ones by the order they went into the depot
func save_state() -> Dictionary:
	var landing := {}
	for f in flights:
		landing[f.rec] = f.to
	var loose: Array = []
	for rec in records:
		if rec.stored:
			continue
		var p: Vector3 = rec.pos
		if landing.has(rec):
			var to: Vector3 = landing[rec]
			p = Vector3(to.x, _rest_y(rec, to.x, to.z), to.z)
		loose.append([rec.size, snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001), snappedf(rec.rot, 0.001)])
	return {"total": total, "loose": loose, "stored": Array(stored_order)}


func load_state(d: Dictionary) -> void:
	flights.clear()
	records.clear()
	for size in _mm:
		var mm: MultiMesh = _mm[size]
		_free[size] = []
		for i in range(mm.instance_count - 1, -1, -1):
			mm.set_instance_transform(i, HIDDEN)
			_free[size].append(i)
	counts = {"S": 0, "M": 0, "L": 0}
	next_block = 0
	open_m = null
	open_s = null
	stored_order.clear()
	for cs in bay_shapes.values():
		(cs as CollisionShape3D).queue_free()
	bay_shapes.clear()
	for l in d.get("loose", []):
		var size: String = l[0]
		if _free.has(size) and not _free[size].is_empty():
			_place({"size": size, "slot": _free[size].pop_back()}, l[1], l[2], l[3], l[4])
	for size in d.get("stored", []):
		store(String(size))
	total = int(d.get("total", total))


func stored_total() -> int:
	return counts.S + counts.M + counts.L


## Minimap dots: positions of parcels lying about in the town
func loose_positions() -> Array:
	var out: Array = []
	for rec in records:
		if not rec.stored:
			out.append(rec.pos)
	return out
