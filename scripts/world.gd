extends Node3D
## Builds the old German town: valley floor, cobbled streets and slab pavements, 50 houses (half-timbered or
## Gothic stone with stepped gables), St. Marien, the Parcel Depot, the city wall with the Nordtor, the park and
## ponds, squares, linden avenues, street lanterns and the mountains round the valley.
## Godot port of world.js / oldtown.js / gothic.js / warehouse.js / citywall.js / townsquares.js.
## First iteration: the layout and dimensions match the web version; many details are simpler.

const Batch := preload("res://scripts/batch.gd")
const Trees := preload("res://scripts/trees.gd")
const Castle := preload("res://scripts/castle.gd")
const Houses := preload("res://scripts/houses.gd")
const WATER_Y := -0.32        # pond water level, below the lawn (world.js WATER_Y)

const FENCE := 185.0          # inner face of the city wall
const GROUND := 300.0
const NS_HALF := 5.5
const EW_HALF := 5.0
const WALK := 4.0
const NS_STREETS := [{"x": -90.0, "name": "Eichengasse"}, {"x": 0.0, "name": "Ulmenstraße"}, {"x": 90.0, "name": "Kiefernweg"}]
const EW_STREETS := [{"z": -165.0, "name": "Birkenweg"}, {"z": 0.0, "name": "Ahornallee"}, {"z": 165.0, "name": "Zedernweg"}]
const WH := {"x0": -182.0, "x1": -150.0, "z0": -22.0, "z1": 22.0, "h": 7.2, "door": 6.0}
const HOUSE_W := 16.0
const HOUSE_D := 14.0
const HOUSE_H := 6.5

var ns_len := 165.0 + EW_HALF
var ew_len := 90.0 + NS_HALF

# Layout data (Rect2 uses x = world x, y = world z)
var road_rects: Array[Rect2] = []
var paved_rects: Array[Rect2] = []
var footprints: Array[Rect2] = []     # house + garage, depot: no trees, no parcel piles
var tree_block: Array[Rect2] = []     # driveways, front gardens, squares: no trees
var house_rects: Array[Rect2] = []    # house bodies
var solids: Array = []                # {rect: Rect2, bottom: float, top: float} for everything solid
var houses: Array = []                # {x, z, rot, number, name}
var interactables: Array = []         # {pos: Vector3, prompt: String, type: String, call: Callable}
var lamp_sources: Array[Vector3] = []
var lakes: Array = []                 # {cx, cz, rw, rd, name}
var church_rects: Array[Rect2] = []
var small_squares: Array[Rect2] = []
var church_square: Rect2
var park: Rect2
var park_blocked: Array[Rect2] = []
var gate_spots: Array[Vector2] = []
var tree_spots: Array[Vector2] = []

var trees: Trees
var tree_detail := 1.0       # leaf clusters in the big trees (GFX.treeDetail: 0.5 on phones)
var water_mats: Array[ShaderMaterial] = []
var night_glows: Array = []           # [{mat, energy}] emissive materials that light up at night
var mats := {}
var b: Batch
var house_parts: Houses
var body: StaticBody3D
var rng := RandomNumberGenerator.new()


var house_colors: Array = []
var dialogue := {}


func build() -> void:
	rng.seed = 20251126
	body = StaticBody3D.new()
	body.name = "Solids"
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	body.add_child(floor_shape)
	b = Batch.new()
	_make_materials()
	house_parts = Houses.new()
	house_parts.setup(self)
	trees = Trees.new(self)
	_residents()
	_plan()
	_terrain_and_roads()
	_houses()
	_church()
	_warehouse()
	_squares()
	_park_and_lakes()
	_city_wall()
	_street_lights()
	_avenue_trees()
	_vegetation()
	_mountains()
	Castle.new().build(self)
	trees.build_forest(self)
	var cards: int = trees.commit(self)
	add_child(body)   # only now: adding thousands of shapes to a body already in the tree rebuilds it every time
	var n := b.commit(self)
	n += house_parts.commit(self)
	print("World built: %d batched meshes, %d leaf cards, %d trees, %d solids, %d interactables" % [n, cards, trees.spots.size(), solids.size(), interactables.size()])


# ----------------------------------------------------------------------------------------------
# Materials
# ----------------------------------------------------------------------------------------------
func _shader_mat(path: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _std(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(color: Color, emission: Color, energy: float, always := false) -> StandardMaterial3D:
	var m := _std(color, 0.35)
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy if always else 0.0
	if not always:
		night_glows.append({"mat": m, "energy": energy})
	return m


func _make_materials() -> void:
	# Surfaces use the web game's own textures (tools/export_textures.py), tiled at the same size in metres
	mats.grass = tmat("grass", Vector2(5, 5), {"rough": 0.95, "macro": 2, "depth": 0.6})
	mats.cobble = tmat("cobble", Vector2(2, 2), {"rough": 1.0, "macro": 1})
	mats.pavers = tmat("pavers", Vector2(6.5 / 3.0, 16.6 / 6.0), {"rough": 0.9, "depth": 0.6})
	mats.slab = tmat("slab", Vector2(1.5, 1.5), {"rough": 1.0, "depth": 0.6})
	mats.gravel = tmat("gravel", Vector2(2, 2), {"rough": 0.95, "tint": Color("#e6dccb")})
	mats.kerb = tmat("sett", Vector2(1, 1), {"rough": 0.85, "tint": Color("#d6d4d0"), "depth": 0.4})
	mats.gutter = tmat("sett", Vector2(1, 1), {"rough": 1.0, "depth": 0.8})
	mats.sandstone = tmat("ashlar_c9b08a", Vector2(3, 3), {"rough": 0.92, "depth": 0.6})
	mats.palestone = tmat("ashlar_d6c29b", Vector2(3, 3), {"rough": 0.88, "depth": 0.6})
	mats.redstone = tmat("ashlar_a8634f", Vector2(3, 3), {"rough": 0.9, "depth": 0.7})
	mats.wallstone = tmat("ashlar_a89a84", Vector2(3, 3), {"rough": 0.93, "depth": 0.8})
	mats.slate = tmat("slate", Vector2(1.2, 1.0), {"rough": 0.6, "metal": 0.05, "two_sided": true, "depth": 0.8})
	mats.clay = roof_mat("#a0492f")
	mats.copper = tmat("copper", Vector2(2, 2), {"rough": 0.55, "metal": 0.35})
	mats.oak = wood("#4a2e1a")
	mats.soffit = timber("#6b4c33")
	mats.dark_oak = _std(Color("#2f2018"), 0.8)
	mats.frame = _std(Color("#f1eee8"), 0.55)
	mats.iron = _std(Color("#1f2a24"), 0.5, 0.6)
	mats.brass = _std(Color("#d4a537"), 0.25, 0.95)
	mats.recess = _std(Color("#121214"), 0.95)
	mats.glass_lit = _glow(Color("#2a343c"), Color("#ffc27a"), 1.6)
	mats.glass_dark = _std(Color("#2a343c"), 0.15, 0.3)
	mats.glass_dark.emission_enabled = true
	mats.glass_dark.emission = Color("#ffc27a")
	night_glows.append({"mat": mats.glass_dark, "energy": 0.18})
	mats.leaded = tmat("leadedglass", Vector2(0.8, 2.0), {"rough": 0.2, "metal": 0.2, "emission_tint": Color("#ffc27a")})
	night_glows.append({"mat": mats.leaded, "energy": 1.4})
	mats.church_glass = []
	for k in 5:
		var g := tmat("stainedglass_%d" % k, Vector2(1.6, 6.0), {"rough": 0.2})
		night_glows.append({"mat": g, "energy": 1.8})
		mats.church_glass.append(g)
	mats.lamp = _glow(Color("#e9e1cf"), Color("#ffd09a"), 4.0)
	mats.lamp.roughness = 0.15
	mats.lamp_iron = _std(Color("#1f3229"), 0.5, 0.55)
	mats.gilt = _std(Color("#b8913a"), 0.35, 0.9)
	mats.hedge = tmat("foliage_bush", Vector2(2, 2), {"rough": 0.95, "tint": Color("#8fa77c"), "depth": 0.8})
	mats.water = _shader_mat("res://shaders/water.gdshader")
	mats.lily = _std(Color("#4f7a33"), 0.7)
	mats.steel = _std(Color("#3c4146"), 0.5, 0.7)
	mats.corrugated = tmat("corrugated_7d8b93", Vector2(2.5, 2.5), {"rough": 0.55, "metal": 0.55})
	mats.corr_inner = tmat("corrugated_b9c0c4", Vector2(2.5, 2.5), {"rough": 0.7, "metal": 0.3})
	mats.trim = _std(Color("#2f5d7c"), 0.5, 0.4)
	mats.depot_floor = tmat("depotfloor", Vector2(4, 4), {"rough": 0.75})
	mats.depot_lamp = _glow(Color("#ffffff"), Color("#fff4dc"), 2.0, true)
	mats.enamel = _std(Color("#1d4f91"), 0.3, 0.1)
	mats.white = _std(Color("#f4f1ea"), 0.5)


const TEX := "res://assets/textures/%s.png"
const TEXTURED := preload("res://shaders/textured.gdshader")
const TEXTURED_2S := preload("res://shaders/textured_2s.gdshader")
var _tex_cache := {}

func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load(TEX % name) if ResourceLoader.exists(TEX % name) else null
	return _tex_cache[name]


var _tmat_cache := {}
## Material from an exported texture set (<name>_col / _nrm / _rgh); tile = metres per texture repeat
func tmat(name: String, tile: Vector2, o := {}) -> ShaderMaterial:
	var key := name + str(tile) + str(o)
	if _tmat_cache.has(key):
		return _tmat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = TEXTURED_2S if o.get("two_sided", false) else TEXTURED
	m.set_shader_parameter("albedo_tex", tex(name + "_col"))
	var nrm := tex(o.get("normal", name + "_nrm"))
	if nrm != null:
		m.set_shader_parameter("normal_tex", nrm)
		m.set_shader_parameter("has_normal", true)
		m.set_shader_parameter("normal_depth", o.get("depth", 1.0))
	var rgh := tex(name + "_rgh")
	if rgh != null:
		m.set_shader_parameter("rough_tex", rgh)
		m.set_shader_parameter("has_rough", true)
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("roughness", o.get("rough", 0.9))
	m.set_shader_parameter("metallic", o.get("metal", 0.0))
	m.set_shader_parameter("tint", o.get("tint", Color.WHITE))
	m.set_shader_parameter("emission_tint", o.get("emission_tint", Color.WHITE))
	if o.has("macro"):
		m.set_shader_parameter("macro_mode", o.macro)
		m.set_shader_parameter("macro_tex", tex("ground_macro"))
	_tmat_cache[key] = m
	return m


static func slug(hex: String) -> String:
	return hex.trim_prefix("#").to_lower()


func plaster(hex: String) -> ShaderMaterial:
	return tmat("plaster_" + slug(hex), Vector2(6.5, 6.5), {"rough": 0.93})


func stone(hex: String) -> ShaderMaterial:
	return tmat("ashlar_" + slug(hex), Vector2(3, 3), {"rough": 0.9, "depth": 0.6})


func roof_mat(hex: String) -> ShaderMaterial:
	return tmat("roof_" + slug(hex), Vector2(1.44, 1.2), {"rough": 1.0, "two_sided": true, "depth": 0.8})


func timber(hex: String) -> ShaderMaterial:
	return tmat("timber_" + slug(hex), Vector2(2, 2), {"rough": 0.85})


func wood(hex: String) -> ShaderMaterial:
	return tmat("wood_" + slug(hex), Vector2(2, 2), {"rough": 0.7, "normal": "wood_nrm", "depth": 0.5})


## Front door: the web stretches one copy of the plank texture over the whole door (BoxGeometry UVs)
func door_mat(hex: String) -> ShaderMaterial:
	return tmat("wood_" + slug(hex), Vector2(1.18, 2.28), {"rough": 0.55, "normal": "wood_nrm", "depth": 0.5})


var _std_cache := {}
func color_mat(hex: String) -> StandardMaterial3D:
	if not _std_cache.has(hex):
		_std_cache[hex] = _std(Color(hex), 0.7)
	return _std_cache[hex]


# ----------------------------------------------------------------------------------------------
# Residents (same households and lines as world.js)
# ----------------------------------------------------------------------------------------------
func _residents() -> void:
	var first := [
		[101, "The Millers", "Hello neighbor! Nice day for a stroll. Watch out for stray packages!"],
		[102, "Dr. Henderson", "Good afternoon! Please don't step on Mrs. Henderson's prize petunias."],
		[103, "The Parkers", "Hey there! Lost my basketball near the driveway earlier, have you seen it?"],
		[104, "Tech Startup Bros", "Yo! We're building an AI app for suburban lawn management. Super disruptive!"],
		[105, "Artist Studio", "Ah, the light today is simply sublime! Feel free to explore the backyard garden."],
		[106, "Grandma Betty", "Oh deary, thank you for checking on me! Help yourself to some freshly baked cookies!"],
		[107, "The Wilsons", "Afternoon! Beautiful weather in the cul-de-sac today, isn't it?"],
		[108, "Mayor Higgins", "Greetings citizen! As honorary neighborhood mayor, I applaud your civic tidy-up duty!"],
	]
	for r in first:
		house_colors.append({"number": r[0], "name": r[1]})
		dialogue[r[0]] = r[2]
	var surnames := ["Abbott", "Baker", "Carter", "Dalton", "Ellis", "Fischer", "Garcia", "Hughes", "Ingram", "Jensen", "Kowalski", "Lambert",
		"Morales", "Nakamura", "Olsen", "Patel", "Quinn", "Reyes", "Sato", "Turner", "Underwood", "Vasquez", "Walsh", "Young", "Zimmer",
		"Bennett", "Collins", "Duarte", "Evans", "Foster", "Grant", "Hayes", "Iverson", "Keller", "Lindqvist", "Murphy", "Novak",
		"Okafor", "Price", "Rossi", "Stewart", "Thornton"]
	var lines := [
		"Lovely to see you! The park fountain is beautiful this time of day.",
		"Morning! Have you seen the mountains today? Not a cloud on the peak.",
		"Hi there! Mind the flower beds, they took me all spring.",
		"Oh, hello! If you find a parcel with my name on it, the wind took it.",
		"Hey neighbour! Fancy a game of hoops at the playground later?",
		"Good day! The ducks on the pond are getting rather fat, aren't they?",
		"Hello! I'm told the willow by the lake is over a hundred years old.",
		"Thanks for keeping the streets tidy, it really shows!",
	]
	for i in surnames.size():
		var number := 109 + i
		house_colors.append({"number": number, "name": "The " + surnames[i] + "s"})
		dialogue[number] = lines[i % lines.size()]


# ----------------------------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------------------------
static func rect(min_x: float, min_z: float, max_x: float, max_z: float) -> Rect2:
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


static func in_rect(r: Rect2, x: float, z: float, m := 0.0) -> bool:
	return x > r.position.x - m and x < r.end.x + m and z > r.position.y - m and z < r.end.y + m


static func any_rect(list: Array, x: float, z: float, m := 0.0) -> bool:
	for r in list:
		if in_rect(r, x, z, m):
			return true
	return false


## Solid box in `xf` space: collision shape + an axis-aligned record for placement tests
func solid(xf: Transform3D, center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	var wc := xf * center
	cs.transform = Transform3D(xf.basis, wc)
	body.add_child(cs)
	var ex := xf.basis.x * size.x * 0.5
	var ey := xf.basis.y * size.y * 0.5
	var ez := xf.basis.z * size.z * 0.5
	var hx := absf(ex.x) + absf(ey.x) + absf(ez.x)
	var hy := absf(ex.y) + absf(ey.y) + absf(ez.y)
	var hz := absf(ex.z) + absf(ey.z) + absf(ez.z)
	solids.append({"rect": rect(wc.x - hx, wc.z - hz, wc.x + hx, wc.z + hz), "bottom": wc.y - hy, "top": wc.y + hy})


## Solids within r of (x, z), from a 16 m grid (rebuilt when solids were added since the last query)
var _solid_grid := {}
var _solid_grid_n := -1
func solids_near(x: float, z: float, r: float) -> Array:
	if _solid_grid_n != solids.size():
		_solid_grid.clear()
		_solid_grid_n = solids.size()
		for s in solids:
			var rr: Rect2 = s.rect
			for cx in range(floori(rr.position.x / 16.0), floori(rr.end.x / 16.0) + 1):
				for cz in range(floori(rr.position.y / 16.0), floori(rr.end.y / 16.0) + 1):
					var key := Vector2i(cx, cz)
					if not _solid_grid.has(key):
						_solid_grid[key] = []
					_solid_grid[key].append(s)
	var out: Array = []
	for cx in range(floori((x - r) / 16.0), floori((x + r) / 16.0) + 1):
		for cz in range(floori((z - r) / 16.0), floori((z + r) / 16.0) + 1):
			out.append_array(_solid_grid.get(Vector2i(cx, cz), []))
	return out


func solid_cyl(x: float, z: float, r: float, h: float, y0 := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = Vector3(x, y0 + h * 0.5, z)
	body.add_child(cs)
	solids.append({"rect": rect(x - r, z - r, x + r, z + r), "bottom": y0, "top": y0 + h})


## Visible box (+ optional collision)
func bx(xf: Transform3D, cx: float, cy: float, cz: float, w: float, h: float, d: float, mat, collide := false, shadow := true, uv := 1.0) -> void:
	b.box(xf, Vector3(cx, cy, cz), Vector3(w, h, d), mat, uv, shadow)
	if collide:
		solid(xf, Vector3(cx, cy, cz), Vector3(w, h, d))


static func house_xf(x: float, z: float, rot: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot), Vector3(x, 0, z))


static func local_rect(xf: Transform3D, cx: float, cz: float, w: float, d: float) -> Rect2:
	var c := xf * Vector3(cx, 0, cz)
	var swap := absf(xf.basis.x.z) > 0.5
	var sw := d if swap else w
	var sd := w if swap else d
	return rect(c.x - sw / 2, c.z - sd / 2, c.x + sw / 2, c.z + sd / 2)


## Flat ground patch. The texture's v axis runs along z, or along x when along_x (cobble arcs follow the street).
func flat(r: Rect2, y: float, mat: Material, uv := 1.0, along_x := false) -> void:
	var p0 := Vector3(r.position.x, y, r.end.y)
	var p1 := Vector3(r.end.x, y, r.end.y)
	var p2 := Vector3(r.end.x, y, r.position.y)
	var p3 := Vector3(r.position.x, y, r.position.y)
	if along_x:
		b.quad(Transform3D.IDENTITY, p3, p0, p1, p2, mat, Vector3.UP, uv, false)
	else:
		b.quad(Transform3D.IDENTITY, p0, p1, p2, p3, mat, Vector3.UP, uv, false)


func label(text: String, xf: Transform3D, size := 64, color := Color.WHITE, px := 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	l.transform = xf
	l.double_sided = false
	add_child(l)
	return l


func add_interactable(pos: Vector3, prompt: String, type: String, call: Callable) -> void:
	interactables.append({"pos": pos, "prompt": prompt, "type": type, "call": call})


func is_on_road(x: float, z: float, margin := 0.0) -> bool:
	return any_rect(road_rects, x, z, margin)


func in_lake(x: float, z: float, margin := 0.0) -> bool:
	for l in lakes:
		var dx: float = (x - l.cx) / (l.rw + margin)
		var dz: float = (z - l.cz) / (l.rd + margin)
		if dx * dx + dz * dz < 1.0:
			return true
	return false


func in_warehouse(x: float, z: float, m := 0.0) -> bool:
	return x > WH.x0 + 0.2 - m and x < WH.x1 - 0.2 + m and z > WH.z0 + 0.2 - m and z < WH.z1 - 0.2 + m


func house_at(x: float, z: float) -> bool:
	return any_rect(house_rects, x, z)


## Free for a tree or bush: not on a road, building, driveway, garden or pond, inside the wall
func is_clear(x: float, z: float, r := 1.0) -> bool:
	if absf(x) > FENCE - 2 or absf(z) > FENCE - 2:
		return false
	if is_on_road(x, z, r) or any_rect(footprints, x, z, r) or any_rect(tree_block, x, z, r):
		return false
	if in_lake(x, z, 2.6 + r) or any_rect(park_blocked, x, z, r) or any_rect(church_rects, x, z, r + 2):
		return false
	return true


## Ground height under a parcel (pavements are 0.25 m up, the depot floor 6 cm)
func ground_y_at(x: float, z: float) -> float:
	if in_warehouse(x, z):
		return 0.06
	if is_on_road(x, z):
		return 0.03
	if is_on_road(x, z, WALK):
		return 0.25
	return 0.0


func surface_at(x: float, z: float) -> String:
	if house_at(x, z) or is_on_road(x, z, WALK) or any_rect(paved_rects, x, z) or in_warehouse(x, z):
		return "hard"
	return "grass"


func random_spot(range_m: float) -> Vector2:
	for i in 40:
		var x := rng.randf_range(-range_m, range_m)
		var z := rng.randf_range(-range_m, range_m)
		if any_rect(footprints, x, z, 1.0) or in_lake(x, z, 3.0) or in_warehouse(x, z, 3.0) or any_rect(church_rects, x, z, 1.0):
			continue
		return Vector2(x, z)
	return Vector2(0, 3)


func set_night(on: bool) -> void:
	house_parts.set_night(on)
	for g in night_glows:
		var e: float = g.energy if on else 0.0
		if g.mat is ShaderMaterial:
			g.mat.set_shader_parameter("emission", e)
		else:
			g.mat.emission_energy_multiplier = e


# ----------------------------------------------------------------------------------------------
# Village plan: three N-S streets joined by the Ahornallee and two loop roads; 50 house lots
# ----------------------------------------------------------------------------------------------
var lots: Array = []

func _plan() -> void:
	for s in NS_STREETS:
		road_rects.append(rect(s.x - NS_HALF, -ns_len, s.x + NS_HALF, ns_len))
	for s in EW_STREETS:
		road_rects.append(rect(-ew_len, s.z - EW_HALF, ew_len, s.z + EW_HALF))
	# The Ulmenstraße carries on north to the Nordtor
	road_rects.append(rect(-NS_HALF, -FENCE + 0.5, NS_HALF, -ns_len))
	park = rect(-90 + NS_HALF + WALK, EW_HALF + WALK, -NS_HALF - WALK, 165 - EW_HALF - WALK)
	for st in NS_STREETS:
		for side in [-1, 1]:
			for g in [-1, 1]:
				for i in 5:
					var hx: float = st.x + side * 30
					var lz: float = g * (12.5 + 14 + i * 28)
					if in_rect(park, hx, lz):
						continue
					lots.append({"hx": hx, "lz": lz, "side": side, "sx": st.x})
	# The original eight residents keep their homes on the Ulmenstraße, closest to the middle of the town
	lots.sort_custom(_lot_less)
	# Delivery truck spot on the Ahornallee (kept clear for later)
	tree_block.append(rect(-30, 0.4, -20, 4.6))
	lakes.append({"cx": -45.0, "cz": 112.0, "rw": 22.0, "rd": 16.0, "name": "Park Pond"})
	lakes.append({"cx": 150.0, "cz": 60.0, "rw": 18.0, "rd": 13.0, "name": "Lake Maple"})


static func _lot_less(a: Dictionary, c: Dictionary) -> bool:
	var ka := [absf(a.sx), absf(a.lz), a.lz, a.side]
	var kc := [absf(c.sx), absf(c.lz), c.lz, c.side]
	for k in 4:
		if ka[k] != kc[k]:
			return ka[k] < kc[k]
	return false


# ----------------------------------------------------------------------------------------------
# Ground, streets, pavements
# ----------------------------------------------------------------------------------------------
func _terrain_and_roads() -> void:
	var G := GROUND
	_ground_with_ponds(G)

	for s in NS_STREETS:
		flat(rect(s.x - NS_HALF, -ns_len, s.x + NS_HALF, ns_len), 0.02, mats.cobble)
	for s in EW_STREETS:
		flat(rect(-ew_len, s.z - EW_HALF, ew_len, s.z + EW_HALF), 0.025, mats.cobble, 1.0, true)
	flat(rect(-NS_HALF, -FENCE - 6, NS_HALF, -ns_len), 0.02, mats.cobble)
	# Junctions: a cobbled patch on top wherever two roads meet
	for n in NS_STREETS:
		for e in EW_STREETS:
			flat(rect(n.x - NS_HALF, e.z - EW_HALF, n.x + NS_HALF, e.z + EW_HALF), 0.03, mats.cobble)

	# Pavements along each street between the junctions, so they never sit on a road
	var NS := NS_HALF
	var EW := EW_HALF
	var W := WALK
	var z_cuts := [-165.0, 0.0, 165.0]
	for s in NS_STREETS:
		for side in [-1, 1]:
			var x: float = s.x + side * (NS + W / 2)
			for i in z_cuts.size() - 1:
				var z0: float = z_cuts[i] + EW
				var z1: float = z_cuts[i + 1] - EW
				_sidewalk(x, (z0 + z1) / 2, W, z1 - z0, 0.25, "x", s.x + side * (NS + 0.11))
	var x_cuts := [-90.0, 0.0, 90.0]
	var x_edge := ew_len + W
	for e in EW_STREETS:
		for side in [-1, 1]:
			var z: float = e.z + side * (EW + W / 2)
			var kz: float = e.z + side * (EW + 0.11)
			var outer: bool = absf(z) > absf(e.z) and absf(e.z) > 1
			if outer:
				if e.z < 0:
					_sidewalk((-x_edge - NS) / 2, z, x_edge - NS, W, 0.245, "z", kz)
					_sidewalk((NS + x_edge) / 2, z, x_edge - NS, W, 0.245, "z", kz)
				else:
					_sidewalk(0, z, x_edge * 2, W, 0.245, "z", kz)
				continue
			var stops := [-x_edge]
			for xc in x_cuts:
				stops.append(xc - NS)
				stops.append(xc + NS)
			stops.append(x_edge)
			for i in range(0, stops.size(), 2):
				var a: float = stops[i]
				var c: float = stops[i + 1]
				if c - a > 0.5:
					_sidewalk((a + c) / 2, z, c - a, W, 0.245, "z", kz)
	# Outer corners where the loop roads end against the outer streets
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var x: float = sx * (ew_len + W / 2)
			var z0: float = sz * (165 - EW)
			var z1: float = sz * (165 + EW + W)
			_sidewalk(x, (z0 + z1) / 2, W, absf(z1 - z0), 0.248, "", 0)


## The lawn, with a hole for each pond (the water sits 0.32 m down inside a masonry wall). The valley floor is a
## grid of 20 m cells; cells round a pond are left out and filled with a ring from the pond's edge to the cells.
func _ground_with_ponds(G: float) -> void:
	var cell := 20.0
	var holes: Array[Rect2] = []
	for l in lakes:
		var a: float = l.rw + 3.0
		var c: float = l.rd + 3.0
		var r := rect(floorf((l.cx - a) / cell) * cell, floorf((l.cz - c) / cell) * cell, ceilf((l.cx + a) / cell) * cell, ceilf((l.cz + c) / cell) * cell)
		holes.append(r)
		l["hole"] = r
	var x := -G
	while x < G:
		var z := -G
		while z < G:
			var r := Rect2(x, z, cell, cell)
			var skip := false
			for h in holes:
				if h.encloses(r):
					skip = true
			if not skip:
				flat(r, 0.0, mats.grass)
			z += cell
		x += cell
	# Fill from the pond's edge (just inside the coping) out to the rectangle of left-out cells
	for l in lakes:
		var hr: Rect2 = l.hole
		var cx: float = l.cx
		var cz: float = l.cz
		var a: float = l.rw + 0.4
		var c: float = l.rd + 0.4
		var angles: Array[float] = []
		for i in 96:
			angles.append(TAU * i / 96.0)
		for corner in [hr.position, Vector2(hr.end.x, hr.position.y), hr.end, Vector2(hr.position.x, hr.end.y)]:
			angles.append(fposmod(atan2(corner.y - cz, corner.x - cx), TAU))
		angles.sort()
		for i in angles.size():
			var t0: float = angles[i]
			var t1: float = angles[(i + 1) % angles.size()]
			if i == angles.size() - 1:
				t1 += TAU
			if t1 - t0 < 1e-5:
				continue
			var p0 := Vector3(cx + cos(t0) * a, 0, cz + sin(t0) * c)
			var p1 := Vector3(cx + cos(t1) * a, 0, cz + sin(t1) * c)
			var q0 := _ray_rect(cx, cz, t0, hr)
			var q1 := _ray_rect(cx, cz, t1, hr)
			b.quad(Transform3D.IDENTITY, p0, q0, q1, p1, mats.grass, Vector3.UP, 1.0, false)


static func _ray_rect(cx: float, cz: float, t: float, r: Rect2) -> Vector3:
	var dx := cos(t)
	var dz := sin(t)
	var k := INF
	if dx > 1e-6: k = minf(k, (r.end.x - cx) / dx)
	if dx < -1e-6: k = minf(k, (r.position.x - cx) / dx)
	if dz > 1e-6: k = minf(k, (r.end.y - cz) / dz)
	if dz < -1e-6: k = minf(k, (r.position.y - cz) / dz)
	return Vector3(cx + dx * k, 0, cz + dz * k)


## Pavement of sandstone slabs with a granite kerb along the road edge (axis "x": kerb runs along z at x = k)
func _sidewalk(x: float, z: float, w: float, l: float, h: float, axis: String, k: float) -> void:
	var I := Transform3D.IDENTITY
	b.box(I, Vector3(x, h / 2, z), Vector3(w, h, l), mats.slab, 1.0, false)
	solid(I, Vector3(x, h / 2, z), Vector3(w, h, l))
	# granite kerb, and a gutter of three rows of setts along it on the road side
	if axis == "x":
		b.box(I, Vector3(k, (h + 0.015) / 2, z), Vector3(0.24, h + 0.015, l), mats.kerb, 1.0, false)
		var gx := k - signf(x - k) * 0.30
		flat(rect(gx - 0.1875, z - l / 2, gx + 0.1875, z + l / 2), 0.034, mats.gutter)
	elif axis == "z":
		b.box(I, Vector3(x, (h + 0.015) / 2, k), Vector3(w, h + 0.015, 0.24), mats.kerb, 1.0, false)
		var gz := k - signf(z - k) * 0.30
		flat(rect(x - w / 2, gz - 0.1875, x + w / 2, gz + 0.1875), 0.034, mats.gutter, 1.0, true)


# ----------------------------------------------------------------------------------------------
# Houses
# ----------------------------------------------------------------------------------------------
## Deterministic 0..1 hash of up to four integers: the same function as `hash` in oldtown.js
static func jhash(a: int, b := 0, c := 0, d := 0) -> float:
	var M := 0xffffffff
	var h := (((a & M) * 374761393) & M) + (((b & M) * 668265263) & M) + (((c & M) * 1274126177) & M) + (((d & M) * 1103515245) & M)
	h &= M
	h = (((h ^ (h >> 13)) & M) * 1274126177) & M
	h ^= h >> 16
	return float(h) / 4294967296.0


static func hash01(a: int, c: int) -> float:
	return jhash(a, c, 77)


## House style, ported from townStyle() in oldtown.js so every house gets the same look as on the web
func _style(idx: int) -> Dictionary:
	var plasters := ["#f1e7d2", "#efe2c0", "#e9c98f", "#e8b79c", "#dfe3c9", "#f2e9da", "#e6cfc2", "#d9dee0", "#efd9a6", "#e4d4b8"]
	var timbers := ["#3a2416", "#4a2a1a", "#2c2420", "#5a2a1c", "#3e2c1e"]
	var roofs := ["#a0492f", "#93412b", "#ad5a38", "#7c3d2b", "#8e4b34", "#a95234"]
	var shutters := ["#3f6b4a", "#2f506e", "#7a3b2e", "#55452f", "#4a6b6b"]
	var doors := ["#5a3a22", "#3f4f3a", "#6b2f24", "#2f3f52", "#704a2a"]
	var stones := ["#cbb38b", "#b8b1a3", "#a8634f", "#d6c4a0", "#9a5a46"]
	var f := jhash(idx, 1, 501)
	var gothic := jhash(idx, 10, 501) < 0.34
	var frame := "gothic" if gothic else ("full" if f < 0.6 else ("upper" if f < 0.85 else "none"))
	return {
		"gothic": gothic,
		"frame": frame,
		"timber": frame == "full" or frame == "upper",
		"plaster": plasters[int(jhash(idx, 2, 501) * plasters.size())],
		"timber_color": timbers[int(jhash(idx, 3, 501) * timbers.size())],
		"roof": roofs[int(jhash(idx, 4, 501) * roofs.size())],
		"shutter": shutters[int(jhash(idx, 5, 501) * shutters.size())],
		"door": doors[int(jhash(idx, 6, 501) * doors.size())],
		"ridge_z": gothic or jhash(idx, 7, 501) < 0.65,
		"pitch": deg_to_rad(55.0 if gothic else 47.0 + jhash(idx, 8, 501) * 7.0),
		"stone": stones[int(jhash(idx, 11, 501) * stones.size())],
		"hedge": jhash(idx, 9, 501) < 0.5,
	}


func _houses() -> void:
	for idx in lots.size():
		var lot: Dictionary = lots[idx]
		var rot := PI / 2 if lot.side < 0 else -PI / 2
		var z: float = lot.lz - 2 if lot.side < 0 else lot.lz + 2
		_house(idx, lot.hx, z, rot, house_colors[idx % house_colors.size()])


## Facade frame: the wall plane at z = 0 facing +z, u along +x. face: 0 front, 1 right (+x), 2 back, 3 left
static func face_xf(xf: Transform3D, face: int) -> Transform3D:
	var angles := [0.0, PI / 2, PI, -PI / 2]
	var ang: float = angles[face]
	var depth := HOUSE_D if face % 2 == 0 else HOUSE_W
	var basis := Basis(Vector3.UP, ang)
	return xf * Transform3D(basis, basis * Vector3(0, 0, depth / 2))


func _house(idx: int, x: float, z: float, rot: float, cfg: Dictionary) -> void:
	var xf := house_xf(x, z, rot)
	var st := _style(idx)
	var W := HOUSE_W
	var D := HOUSE_D
	var H := HOUSE_H
	var gothic: bool = st.gothic
	var wall: Material = stone(st.stone) if gothic else plaster(st.plaster)
	houses.append({"x": x, "z": z, "rot": rot, "number": cfg.number, "name": cfg.name})
	footprints.append(local_rect(xf, -3.5, 1.6, 23.5, 17.8))
	tree_block.append(local_rect(xf, -11.5, D / 2 + 5, 6.5, 16))
	tree_block.append(local_rect(xf, 0, 12.0, 16, 10))
	house_rects.append(local_rect(xf, 0, 0, W, D))

	# Hollow two-storey shell with furnished rooms, stairs, front door, garage, roof and facade (houses.gd)
	var roof: Dictionary = house_parts.build(idx, xf, st, cfg, wall)
	var front := face_xf(xf, 0)

	# Chimney through the roof
	var ch_x := W * 0.3
	var ch_z := D * 0.2
	var ch_top: float = Houses.roof_y(roof, ch_x, ch_z) + 1.3
	bx(xf, ch_x, (ch_top + H - 0.2) / 2, ch_z, 1.1, ch_top - H + 0.2, 1.1, plaster("#d9d2c4"))
	bx(xf, ch_x, ch_top + 0.07, ch_z, 1.35, 0.14, 1.35, mats.palestone)

	# Number plate, doorbell and porch lantern by the front door
	bx(front, 0, 2.98, 0.05, 0.8, 0.4, 0.04, mats.enamel, false, false)
	label(str(cfg.number), front * Transform3D(Basis(), Vector3(0, 2.98, 0.075)), 72, Color.WHITE, 0.0045)
	bx(front, 0.95, 1.3, 0.06, 0.2, 0.3, 0.12, mats.brass, false, false)
	var bell_pos := front * Vector3(0.95, 1.3, 0.1)
	var number: int = cfg.number
	var owner: String = cfg.name
	add_interactable(bell_pos, "[E] Ring doorbell (#%d - %s)" % [number, owner], "doorbell",
		func() -> Dictionary: return {"title": "#%d - %s" % [number, owner], "message": dialogue.get(number, "Hello there!"), "sound": "doorbell", "score": 50})
	bx(front, -1.2, 2.25, 0.33, 0.3, 0.5, 0.3, mats.iron, false, false)
	bx(front, -1.2, 2.25, 0.33, 0.26, 0.4, 0.37, mats.lamp, false, false)
	bx(front, -1.2, 2.55, 0.2, 0.05, 0.05, 0.3, mats.iron, false, false)
	lamp_sources.append(front * Vector3(-1.2, 2.3, 0.6))
	var gx := -W / 2 - 3.5

	# Driveway of pavers to the pavement, garden path, front garden wall or hedge with a gate gap
	var dl := 16.6
	b.quad(xf, Vector3(gx - 3.25, 0.05, D / 2 - 3), Vector3(gx + 3.25, 0.05, D / 2 - 3), Vector3(gx + 3.25, 0.05, D / 2 - 3 + dl), Vector3(gx - 3.25, 0.05, D / 2 - 3 + dl), mats.pavers, Vector3.UP, 1.0, false)
	paved_rects.append(local_rect(xf, gx, D / 2 - 3 + dl / 2, 6.5, dl))
	b.quad(xf, Vector3(-0.7, 0.04, D / 2), Vector3(0.7, 0.04, D / 2), Vector3(0.7, 0.04, 17), Vector3(-0.7, 0.04, 17), mats.slab, Vector3.UP, 1.0, false)
	for seg in [[-W / 2, -1.1], [1.1, W / 2]]:
		var c: float = (seg[0] + seg[1]) / 2
		var len: float = seg[1] - seg[0]
		if st.hedge:
			bx(xf, c, 0.55, 17, len, 1.1, 0.7, mats.hedge, true)
		else:
			bx(xf, c, 0.4, 17, len, 0.8, 0.35, mats.sandstone, true)
			bx(xf, c, 0.85, 17, len + 0.05, 0.1, 0.45, mats.palestone)
	var gate := xf * Vector3(0, 0, 17)
	gate_spots.append(Vector2(gate.x, gate.z))


# ----------------------------------------------------------------------------------------------
# St. Marien on the Kirchplatz
# ----------------------------------------------------------------------------------------------
func _church() -> void:
	var I := Transform3D.IDENTITY
	var CX := -45.0
	var rs: Material = mats.redstone
	church_square = rect(-66, EW_HALF + WALK, -24, 26)
	paved_rects.append(church_square)
	flat(church_square, 0.035, mats.cobble)
	park_blocked.append(rect(-70, 7, -20, 68))
	# Tower
	bx(I, CX, 17, 30.5, 9, 34, 9, rs, true)
	church_rects.append(rect(CX - 4.5, 26, CX + 4.5, 35))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			bx(I, CX + sx * 4.3, 13, 30.5 + sz * 4.3, 1.5, 26, 1.5, rs)
			bx(I, CX + sx * 4.3, 26.6, 30.5 + sz * 4.3, 1.1, 1.2, 1.1, rs)
			b.cylinder(I, Vector3(CX + sx * 4.1, 34, 30.5 + sz * 4.1), 0.6, 0.0, 3.5, 6, rs)
	bx(I, CX, 34.1, 30.5, 9.4, 0.25, 9.4, mats.palestone)
	# belfry openings and clock faces
	var faces := [[Vector3(0, 0, -1), Vector3(1, 0, 0)], [Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1)]]
	for fc in faces:
		var n: Vector3 = fc[0]
		var t: Vector3 = fc[1]
		for s in [-1.3, 1.3]:
			var c: Vector3 = Vector3(CX, 29, 30.5) + n * 4.52 + t * s
			b.box(I, c, Vector3(1.0, 3.2, 1.0) * (Vector3.ONE - n.abs()) + n.abs() * 0.05, mats.recess, 1.0, false)
		var cc := Vector3(CX, 23.5, 30.5) + n * 4.55
		var cxf := Transform3D(Basis.looking_at(-n, Vector3.UP), cc)
		b.cylinder(cxf * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO), Vector3.ZERO, 1.5, 1.5, 0.06, 20, mats.white, true, 1.0, false)
		b.box(cxf, Vector3(0, 0.45, 0.08), Vector3(0.1, 1.0, 0.03), mats.iron, 1.0, false)
		b.box(cxf, Vector3(0.3, 0, 0.09), Vector3(0.7, 0.08, 0.03), mats.iron, 1.0, false)
	# Copper spire with a gilded cross
	b.cylinder(I, Vector3(CX, 34.2, 30.5), 4.0, 0.0, 29, 8, mats.copper)
	bx(I, CX, 64.2, 30.5, 0.12, 2.4, 0.12, mats.brass)
	bx(I, CX, 64.6, 30.5, 1.2, 0.12, 0.12, mats.brass)
	# Door in the tower
	bx(I, CX, 2.0, 25.98, 2.4, 4.0, 0.08, mats.dark_oak)
	b.tri(I, Vector3(CX - 1.2, 4.0, 25.97), Vector3(CX + 1.2, 4.0, 25.97), Vector3(CX, 5.4, 25.97), mats.dark_oak, Vector3.FORWARD)
	add_interactable(Vector3(CX, 1.6, 25.6), "[E] Look at St. Marien", "church",
		func() -> Dictionary: return {"title": "St. Marien", "message": "A red sandstone Gothic church with a 63 m copper spire. Its bells and the inside come in a later version of the Godot port.", "sound": "click"})
	# Nave
	bx(I, CX, 7, 48, 14, 14, 26, rs, true)
	church_rects.append(rect(CX - 7, 35, CX + 7, 61))
	var rise := 10.0
	b.quad(I, Vector3(CX - 7.6, 13.6, 34.6), Vector3(CX - 7.6, 13.6, 61.4), Vector3(CX, 14 + rise, 61.4), Vector3(CX, 14 + rise, 34.6), mats.slate, Vector3(-1, 1, 0))
	b.quad(I, Vector3(CX + 7.6, 13.6, 34.6), Vector3(CX + 7.6, 13.6, 61.4), Vector3(CX, 14 + rise, 61.4), Vector3(CX, 14 + rise, 34.6), mats.slate, Vector3(1, 1, 0))
	b.tri(I, Vector3(CX - 7, 14, 35), Vector3(CX + 7, 14, 35), Vector3(CX, 14 + rise, 35), rs, Vector3.FORWARD)
	b.tri(I, Vector3(CX - 7, 14, 61), Vector3(CX + 7, 14, 61), Vector3(CX, 14 + rise, 61), rs, Vector3.BACK)
	# Apse
	b.cylinder(I, Vector3(CX, 0, 61), 5.6, 5.6, 13, 8, rs, false)
	b.cylinder(I, Vector3(CX, 13, 61), 6.0, 0.0, 6.5, 8, mats.slate)
	solid_cyl(CX, 61, 5.6, 13)
	church_rects.append(rect(CX - 5.6, 61, CX + 5.6, 66.6))
	# Lancets and stepped buttresses along the nave
	for sx in [-1, 1]:
		var f := Transform3D(Basis(Vector3.UP, sx * PI / 2), Vector3(CX + sx * 7, 0, 0))
		var wk := 0
		for zc in [38.5, 43.5, 48.5, 53.5, 58.5]:
			var u: float = -zc * sx
			var gm: Material = mats.church_glass[wk % 5]
			wk += 1
			bx(f, u, 7, 0.02, 1.6, 6.0, 0.06, gm, false, false)
			b.tri(f, Vector3(u - 0.8, 10, 0.05), Vector3(u + 0.8, 10, 0.05), Vector3(u, 11.6, 0.05), gm, Vector3.BACK, 1.0, false)
			bx(f, u, 7, 0.06, 0.08, 6.0, 0.06, mats.palestone, false, false)
		for zc in [36.0, 41.0, 46.0, 51.0, 56.0, 60.6]:
			var u: float = -zc * sx
			bx(f, u, 5, 0.8, 1.2, 10, 1.6, rs, true)
			bx(f, u, 11, 0.5, 1.0, 2.5, 1.0, rs)
			b.cylinder(f, Vector3(u, 12.25, 0.5), 0.45, 0.0, 2.2, 4, rs)


# ----------------------------------------------------------------------------------------------
# Parcel Depot at the west end of the Ahornallee
# ----------------------------------------------------------------------------------------------
var depot_lights: Array[OmniLight3D] = []

func _warehouse() -> void:
	var I := Transform3D.IDENTITY
	var x0: float = WH.x0
	var x1: float = WH.x1
	var z0: float = WH.z0
	var z1: float = WH.z1
	var H: float = WH.h
	var door: float = WH.door
	var cx := (x0 + x1) / 2
	var cz := (z0 + z1) / 2
	# Access road with pavements
	road_rects.append(rect(x1, -EW_HALF, -ew_len, EW_HALF))
	flat(rect(x1, -EW_HALF, -ew_len, EW_HALF), 0.025, mats.cobble, 1.0, true)
	var walk_len := (-ew_len - WALK) - x1
	for s in [-1, 1]:
		_sidewalk(x1 + walk_len / 2, s * (EW_HALF + WALK / 2), walk_len, WALK, 0.245, "z", s * (EW_HALF + 0.11))
	tree_block.append(rect(x1 - 1, -12.5, -ew_len, 12.5))
	footprints.append(rect(x0 - 1, z0 - 1, x1 + 4, z1 + 1))
	paved_rects.append(rect(x0, z0, x1, z1))

	var t := 0.25
	var wall: Material = mats.corrugated
	var inner: Material = mats.corr_inner
	bx(I, cx, 0.03, cz, x1 - x0, 0.06, z1 - z0, mats.depot_floor, false, false)
	bx(I, x0 + t / 2, H / 2, cz, t, H, z1 - z0, [inner, wall, wall, wall, wall, wall], true)
	bx(I, cx, H / 2, z0 + t / 2, x1 - x0, H, t, [wall, wall, wall, wall, inner, wall], true)
	bx(I, cx, H / 2, z1 - t / 2, x1 - x0, H, t, [wall, wall, wall, wall, wall, inner], true)
	var seg := (z1 - z0) / 2 - door
	for s in [-1, 1]:
		bx(I, x1 - t / 2, H / 2, s * (door + seg / 2), t, H, seg, [wall, inner, wall, wall, wall, wall], true)
	bx(I, x1 - t / 2, (H + 5.5) / 2, 0, t, H - 5.5, door * 2, [wall, inner, wall, wall, wall, wall])
	bx(I, cx, H + 0.15, cz, x1 - x0 + 1.2, 0.3, z1 - z0 + 1.2, [mats.trim, mats.trim, mats.steel, inner, mats.trim, mats.trim], false, true, 3.0)
	b.box(I, Vector3(cx, H + 0.15, cz), Vector3(x1 - x0 + 1.2, 0.3, z1 - z0 + 1.2), [null, null, null, inner, null, null], 3.0, false, true)
	for c in [[x0, z0], [x0, z1], [x1, z0], [x1, z1]]:
		bx(I, c[0], H / 2, c[1], 0.35, H, 0.35, mats.trim)
	for s in [-1, 1]:
		bx(I, x1 + 0.05, 2.75, s * door, 0.35, 5.5, 0.35, mats.trim)
	bx(I, x1 + 0.05, 5.5, 0, 0.35, 0.35, door * 2 + 0.35, mats.trim)
	b.cylinder(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(x1 - 0.6, 5.95, 0)), Vector3(0, -door, 0), 0.45, 0.45, door * 2, 16, mats.steel)
	var z := z0 + 5.5
	while z < z1 - 1:
		bx(I, cx, H - 0.35, z, x1 - x0 - 0.6, 0.35, 0.2, mats.steel, false, false)
		for xx in [x0 + 0.4, x1 - 0.4]:
			bx(I, xx, (H - 0.2) / 2, z, 0.25, H - 0.2, 0.2, mats.steel, false, false)
		z += 5.5
	z = z0 + 5.5
	while z < z1 - 1:
		for xx in [cx - 6, cx + 6]:
			bx(I, xx, H - 1.0, z, 0.03, 1.0, 0.03, mats.steel, false, false)
			b.cylinder(I, Vector3(xx, H - 1.78, z), 0.5, 0.12, 0.35, 12, mats.steel, false, 1.0, false)
			bx(I, xx, H - 1.78, z, 0.6, 0.04, 0.6, mats.depot_lamp, false, false)
		z += 11.0
	for lz in [-9.0, 9.0]:
		var l := OmniLight3D.new()
		l.light_color = Color("#fff1d8")
		l.light_energy = 2.2
		l.omni_range = 30.0
		l.position = Vector3(cx, H - 2, lz)
		add_child(l)
		depot_lights.append(l)
	var xw := x0 + 3
	while xw < x1 - 2:
		for zw in [z0 - 0.01, z1 + 0.01]:
			bx(I, xw + 1.5, H - 1.4, zw, 3.0, 0.7, 0.04, mats.depot_lamp, false, false)
		xw += 5.0
	# Sign over the door
	bx(I, x1 + 0.2, 6.5, 0, 0.12, 1.6, 8.5, mats.trim)
	bx(I, x1 + 0.27, 5.85, 0, 0.02, 0.16, 8.5, color_mat("#f2c230"), false, false)
	label("PARCEL DEPOT", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(x1 + 0.27, 6.6, 0)), 200, Color.WHITE, 0.0065)
	# Pallets and the ledger desk
	var pallet := wood("#a9865c")
	for i in 4:
		var px := x0 + 3 + i * 1.4
		for dy in [0.0, 0.15]:
			bx(I, px, 0.13 + dy, z0 + 1.2, 1.2, 0.14, 1.0, pallet)
	bx(I, x1 - 2.2, 0.475, door + 3.5, 2.2, 0.95, 0.8, color_mat("#8a6a46"), true)
	bx(I, x1 - 2.2, 1.15, door + 3.25, 0.5, 0.35, 0.04, color_mat("#111316"), false, false)
	add_interactable(Vector3(x1 - 2.2, 1.2, door + 3.0), "[E] Check the depot ledger", "ledger", Callable())


# ----------------------------------------------------------------------------------------------
# Small cobbled squares at the block corners (townsquares.js)
# ----------------------------------------------------------------------------------------------
func _squares() -> void:
	var defs := [
		{"x": 45.0, "z": 0.0, "side": 1, "kind": "fountain", "name": "Gänsebrunnen"},
		{"x": -45.0, "z": 0.0, "side": -1, "kind": "linden", "name": "Lindenplatz"},
		{"x": 45.0, "z": 0.0, "side": -1, "kind": "maypole", "name": "Maibaumplatz"},
		{"x": -45.0, "z": -165.0, "side": 1, "kind": "well", "name": "Brunnenhof"},
		{"x": 45.0, "z": -165.0, "side": 1, "kind": "column", "name": "Theaterplatz"},
		{"x": 45.0, "z": 165.0, "side": -1, "kind": "linden", "name": "Kirchgasse"},
	]
	var I := Transform3D.IDENTITY
	for d in defs:
		var z0: float = d.z + d.side * (EW_HALF + WALK)
		var z1: float = z0 + d.side * 12
		var r := rect(d.x - 6.5, minf(z0, z1), d.x + 6.5, maxf(z0, z1))
		flat(r, 0.035, mats.cobble)
		small_squares.append(r)
		paved_rects.append(r)
		tree_block.append(r.grow(1.0))
		park_blocked.append(r.grow(1.0))
		var cx: float = d.x
		var cz: float = z0 + d.side * 6.6
		var nm: String = d.name
		match d.kind:
			"fountain":
				b.cylinder(I, Vector3(cx, 0, cz), 2.4, 2.4, 0.6, 24, mats.palestone)
				b.ellipse_ring(I, cx, cz, 0.0, 0.0, 2.2, 2.2, 0.5, mats.water, 24)
				b.cylinder(I, Vector3(cx, 0, cz), 0.35, 0.3, 2.4, 10, mats.palestone)
				b.cylinder(I, Vector3(cx, 2.4, cz), 0.25, 0.0, 0.8, 8, mats.brass)
				solid_cyl(cx, cz, 2.4, 0.6)
			"linden":
				_tree(cx, cz, "linden", 1.45)
				b.cylinder(I, Vector3(cx, 0, cz), 2.0, 2.0, 0.45, 16, color_mat("#6b5040"), true)
			"maypole":
				b.cylinder(I, Vector3(cx, 0, cz), 0.18, 0.12, 18, 8, mats.white)
				for k in 4:
					bx(I, cx, 6 + k * 2.5, cz, 1.6, 0.6, 0.05, color_mat(["#2d4a6b", "#6b2a24", "#2f5d3a", "#d4a537"][k]), false, false)
				b.cylinder(I, Vector3(cx, 15.5, cz), 1.4, 1.4, 0.15, 12, color_mat("#3d5a2a"))
				solid_cyl(cx, cz, 0.3, 18)
			"well":
				b.cylinder(I, Vector3(cx, 0, cz), 1.3, 1.3, 0.9, 16, mats.palestone)
				b.ellipse_ring(I, cx, cz, 0.0, 0.0, 1.05, 1.05, 0.6, mats.water, 16)
				for s in [-1, 1]:
					bx(I, cx + s * 1.15, 1.6, cz, 0.15, 2.4, 0.15, mats.oak)
				b.cylinder(I, Vector3(cx, 2.7, cz), 1.6, 0.0, 1.0, 4, mats.clay, true, 1.0, true, PI / 4)
				solid_cyl(cx, cz, 1.3, 0.9)
			"column":
				b.cylinder(I, Vector3(cx, 0, cz), 0.75, 0.75, 3.6, 16, color_mat("#3d5a4a"))
				b.cylinder(I, Vector3(cx, 3.6, cz), 0.85, 0.0, 0.7, 16, color_mat("#3d5a4a"))
				solid_cyl(cx, cz, 0.75, 3.6)
		if d.kind != "linden":
			for sx in [-1, 1]:
				_tree(d.x + sx * 4.6, z0 + d.side * 10.6, "linden", 1.0)
		var msg := "%s: one of the six little squares of the old town." % nm
		add_interactable(Vector3(cx, 1.2, cz), "[E] %s" % nm, "square",
			func() -> Dictionary: return {"title": nm, "message": msg, "sound": "click"})


# ----------------------------------------------------------------------------------------------
# Stadtpark: paths and ponds
# ----------------------------------------------------------------------------------------------
func _park_and_lakes() -> void:
	var I := Transform3D.IDENTITY
	flat(rect(-46.5, 67, -43.5, 96.4), 0.03, mats.gravel, 1.0)
	flat(rect(park.position.x, 79.5, park.end.x, 82.5), 0.032, mats.gravel, 1.0)
	park_blocked.append(rect(-47.5, 66, -42.5, 97))
	park_blocked.append(rect(park.position.x, 78.5, park.end.x, 83.5))
	var noise := tex("water_height")
	var masonry := tex("masonry_col")
	var dry := _std(Color("#b9b2a6"), 0.9)
	dry.albedo_texture = masonry
	dry.uv1_scale = Vector3(0.5, 0.5, 1)
	var wet := _std(Color("#5e5a50"), 0.45)
	wet.albedo_texture = masonry
	wet.uv1_scale = Vector3(0.5, 0.5, 1)
	var coping := tmat("concrete", Vector2(1, 1), {"tint": Color("#d9d1c1"), "rough": 0.85, "depth": 0.5})
	var edge := tmat("concrete", Vector2(1, 1), {"tint": Color("#c8c0b0"), "rough": 0.9})
	var path := tmat("pavers", Vector2(2, 2), {"tint": Color("#d6cfc4"), "rough": 0.9, "depth": 0.5})
	var brick := tmat("brick_7a4a36", Vector2(0.5, 0.5), {"tint": Color("#bbbbbb"), "rough": 0.9})
	for l in lakes:
		var cx: float = l.cx
		var cz: float = l.cz
		var rw: float = l.rw
		var rd: float = l.rd
		var pier_dir := 1.0 if l.name == "Park Pond" else -1.0
		# Water: the ellipse just inside the masonry wall
		var wm := ShaderMaterial.new()
		wm.shader = load("res://shaders/pond_water.gdshader")
		wm.set_shader_parameter("noise_tex", noise)
		wm.set_shader_parameter("center", Vector2(cx, cz))
		wm.set_shader_parameter("axes", Vector2(rw, rd))
		water_mats.append(wm)
		b.ellipse_ring(I, cx, cz, 0.0, 0.0, rw + 0.05, rd + 0.05, WATER_Y, wm, 96)
		# Masonry wall from below the waterline up to the coping, darker where wet
		_band(cx, cz, rw, rd, Vector2(0, WATER_Y - 0.2), Vector2(0, WATER_Y + 0.09), wet, true)
		_band(cx, cz, rw, rd, Vector2(0, WATER_Y + 0.09), Vector2(0, -0.04), dry, true)
		# Coping slabs overhanging the wall, their edges, the paved walk and its brick edging
		var lip := -0.18
		var back := 0.62
		var top := 0.14
		b.ellipse_ring(I, cx, cz, rw + lip, rd + lip, rw + back, rd + back, top, coping, 96, 1.0, true)
		_band(cx, cz, rw, rd, Vector2(lip, -0.04), Vector2(lip, top), edge, true)
		b.ellipse_ring(I, cx, cz, rw + lip, rd + lip, rw, rd, -0.04, edge, 96)   # underside of the overhang (seen from the water)
		_band(cx, cz, rw, rd, Vector2(back, 0.0), Vector2(back, top), edge, false)
		b.ellipse_ring(I, cx, cz, rw + back, rd + back, rw + 2.4, rd + 2.4, 0.025, path, 96)
		b.ellipse_ring(I, cx, cz, rw + 2.4, rd + 2.4, rw + 2.52, rd + 2.52, 0.07, brick, 96)
		_band(cx, cz, rw, rd, Vector2(2.52, 0.0), Vector2(2.52, 0.07), brick, false)
		paved_rects.append(rect(cx - rw - 2.4, cz - rd - 2.4, cx + rw + 2.4, cz + rd + 2.4))
		_lily_pads(cx, cz, rw, rd, pier_dir)
		_cattails(cx, cz, rw, rd, pier_dir)
		trees.build_willow(cx - pier_dir * (rw + 4.2), cz + rd * 0.35)
		var nm: String = l.name
		add_interactable(Vector3(cx, 0.8, cz - rd - 0.8), "[E] %s" % nm, "lake",
			func() -> Dictionary: return {"title": nm, "message": "Mallards paddle about the pond, tipping up to dabble for weed.", "sound": "click"})


## Vertical band round a pond from (radial offset, y) a to b; faces into the pond, or out of it
func _band(cx: float, cz: float, rw: float, rd: float, a: Vector2, c: Vector2, mat: Material, inward: bool) -> void:
	for i in 96:
		var t0 := TAU * i / 96.0
		var t1 := TAU * (i + 1) / 96.0
		var p := func(t: float, o: Vector2) -> Vector3: return Vector3(cx + cos(t) * (rw + o.x), o.y, cz + sin(t) * (rd + o.x))
		var d := Vector3(cos((t0 + t1) / 2), 0, sin((t0 + t1) / 2))
		b.quad(Transform3D.IDENTITY, p.call(t0, a), p.call(t1, a), p.call(t1, c), p.call(t0, c), mat, -d if inward else d, 1.0, true)


func _lily_pads(cx: float, cz: float, rw: float, rd: float, pier_dir: float) -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 0.32
	pad.bottom_radius = 0.32
	pad.height = 0.01
	pad.radial_segments = 18
	pad.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = pad
	mm.instance_count = 46
	var colonies := []
	for k in 3:
		colonies.append((PI if pier_dir > 0 else 0.0) + (k - 1) * 0.9 + (rng.randf() - 0.5) * 0.3)
	var I := Transform3D.IDENTITY
	for i in 46:
		var t: float = colonies[i % 3] + (rng.randf() - 0.5) * 0.45
		var r := 0.68 + rng.randf() * 0.24
		var p := Vector3(cx + cos(t) * rw * r, WATER_Y + 0.012 + rng.randf() * 0.004, cz + sin(t) * rd * r)
		var sc := 0.6 + rng.randf() * 0.8
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, 1, sc)), p))
		mm.set_instance_color(i, Color.from_hsv(0.24 + rng.randf() * 0.05, 0.6, 0.3 + rng.randf() * 0.12))
		if rng.randf() < 0.15:
			b.cylinder(I, p + Vector3(0.08, 0.1, 0), 0.0, 0.09, 0.1, 7, color_mat("#f6e9ef"), false)
			b.cylinder(I, p + Vector3(0.08, 0.04, 0), 0.03, 0.03, 0.06, 6, color_mat("#f2c94c"))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := _std(Color.WHITE, 0.55)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	add_child(mi)


## Clumps of reeds standing in the shallows along the wall, the pier's stretch of shore kept clear
func _cattails(cx: float, cz: float, rw: float, rd: float, pier_dir: float) -> void:
	var stalk := color_mat("#5b7a3a")
	var head := _std(Color("#5a3a1e"), 0.95)
	var blade_m := _std(Color("#6c8a45"), 0.8)
	blade_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c in 6:
		var t := (c / 6.0) * TAU + rng.randf() * 0.5
		if absf(atan2(sin(t), cos(t) * pier_dir)) < 0.35:
			t += 0.8
		for i in 6 + rng.randi_range(0, 5):
			var tt := t + (rng.randf() - 0.5) * 0.09
			var r := 1.0 - (0.25 + rng.randf() * 0.9) / rw
			var x := cx + cos(tt) * rw * r
			var z := cz + sin(tt) * rd * r
			var h := 1.2 + rng.randf() * 0.6
			var lean := Basis.from_euler(Vector3((rng.randf() - 0.5) * 0.12, 0, (rng.randf() - 0.5) * 0.12))
			var xf := Transform3D(lean, Vector3(x, WATER_Y, z))
			b.cylinder(xf, Vector3.ZERO, 0.018, 0.012, h, 5, stalk, false)
			if rng.randf() < 0.7:
				b.cylinder(xf, Vector3(0, h - 0.31, 0), 0.035, 0.035, 0.22, 8, head)
			for k in 2:
				var bxf := Transform3D(Basis.from_euler(Vector3((rng.randf() - 0.5) * 0.5, rng.randf() * PI, (rng.randf() - 0.5) * 0.5)), Vector3(x, WATER_Y, z))
				var bh := h * (0.7 + rng.randf() * 0.3)
				b.tri(bxf, Vector3(-0.025, 0, 0), Vector3(0.025, 0, 0), Vector3(0, bh, 0), blade_m, Vector3.BACK, 1.0, false)


## Live sky for the pond water (linkSky / updateLakeWater in world.js)
func set_water_sky(p: Dictionary, sun_dir: Vector3, moon_dir: Vector3, moon_vis: float, day: float, sun_vis: float) -> void:
	for m in water_mats:
		m.set_shader_parameter("zenith", p.zenith)
		m.set_shader_parameter("horizon", p.horizon)
		m.set_shader_parameter("sun_color", p.sun)
		m.set_shader_parameter("sun_glow", p.glow)
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("moon_dir", moon_dir)
		m.set_shader_parameter("moon_vis", moon_vis)
		m.set_shader_parameter("day", day)
		m.set_shader_parameter("sun_vis", sun_vis)


# ----------------------------------------------------------------------------------------------
# City wall with round towers and the Nordtor
# ----------------------------------------------------------------------------------------------
func _city_wall() -> void:
	var I := Transform3D.IDENTITY
	var st: Material = mats.wallstone
	var T := 2.4
	var HT := 8.0
	var F := FENCE
	var full := F + T
	# [centre, length, along_x]
	var runs := [
		[Vector3(-(full + 6.5) / 2, 0, -F - T / 2), full - 6.5, true],
		[Vector3((full + 6.5) / 2, 0, -F - T / 2), full - 6.5, true],
		[Vector3(0, 0, F + T / 2), 2 * full, true],
		[Vector3(-F - T / 2, 0, 0), 2 * full, false],
		[Vector3(F + T / 2, 0, 0), 2 * full, false],
	]
	for r in runs:
		var c: Vector3 = r[0]
		var L: float = r[1]
		var ax: bool = r[2]
		var size := Vector3(L, HT, T) if ax else Vector3(T, HT, L)
		bx(I, c.x, HT / 2, c.z, size.x, size.y, size.z, st, true, true, 1.0)
		# merlons on the outer edge, walkway parapet inside
		var out_dir := Vector3(0, 0, signf(c.z)) if ax else Vector3(signf(c.x), 0, 0)
		var along := Vector3.RIGHT if ax else Vector3.BACK
		var n := int(L / 2.2)
		for k in n:
			var p := c + along * (-L / 2 + 1.1 + k * 2.2) + out_dir * (T / 2 - 0.3)
			var ms := Vector3(1.2, 1.3, 0.6) if ax else Vector3(0.6, 1.3, 1.2)
			b.box(I, Vector3(p.x, HT + 0.65, p.z), ms, st, 1.0, true)
		var ps := Vector3(L, 0.6, 0.4) if ax else Vector3(0.4, 0.6, L)
		var pc := c - out_dir * (T / 2 - 0.2)
		b.box(I, Vector3(pc.x, HT + 0.3, pc.z), ps, st, 1.0, true)
	# Round towers: corners and along each side
	var towers: Array = []
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			towers.append([sx * (F + 1.2), sz * (F + 1.2), 5.2, 15.0])
	for p in [-120.0, -60.0, 60.0, 120.0]:
		towers.append([p, -(F + 1.2), 3.8, 12.5])
		towers.append([p, F + 1.2, 3.8, 12.5])
		towers.append([-(F + 1.2), p, 3.8, 12.5])
		towers.append([F + 1.2, p, 3.8, 12.5])
	for p in [0.0]:
		towers.append([p, F + 1.2, 3.8, 12.5])
		towers.append([-(F + 1.2), p, 3.8, 12.5])
		towers.append([F + 1.2, p, 3.8, 12.5])
	for tw in towers:
		var x: float = tw[0]
		var z: float = tw[1]
		var r: float = tw[2]
		var h: float = tw[3]
		b.cylinder(I, Vector3(x, 0, z), r * 1.05, r, h, 20, st, false, 1.0)
		b.cylinder(I, Vector3(x, h, z), r + 0.6, 0.0, r * 1.9, 20, mats.clay, false, 1.0)
		solid_cyl(x, z, r, h)
		for k in 3:
			var a := k * TAU / 3 + 0.4
			bx(I, x + cos(a) * r * 1.01, h * 0.6, z + sin(a) * r * 1.01, 0.3, 1.0, 0.3, mats.recess, false, false)
	# Nordtor: gate tower over a pointed archway at the north end of the Ulmenstraße
	var gz0 := -F - 6.0
	var gz1 := -F + 3.5
	var gzc := (gz0 + gz1) / 2
	var gd := gz1 - gz0
	var GH := 24.0
	var stn: Material = mats.palestone
	for s in [-1, 1]:
		bx(I, s * 4.5, GH / 2, gzc, 4.0, GH, gd, stn, true)
	bx(I, 0, (GH + 7.5) / 2, gzc, 5.0, GH - 7.5, gd, stn)
	for zf in [gz0 - 0.02, gz1 + 0.02]:
		var o := Vector3(0, 0, -1) if zf < gzc else Vector3(0, 0, 1)
		b.tri(I, Vector3(-2.5, 6.2, zf), Vector3(2.5, 6.2, zf), Vector3(0, 7.5, zf), mats.recess, o)
	bx(I, 0, 6.85, gzc, 5.0, 1.3, gd - 0.1, mats.recess, false, false)
	bx(I, 0, 0.03, gzc, 5.0, 0.04, gd, mats.cobble, false, false)
	# shut oak gates (the moat and drawbridge come later)
	bx(I, 0, 3.1, gz0 + 0.6, 5.0, 6.2, 0.3, mats.dark_oak, true)
	for k in 6:
		bx(I, 0, 0.6 + k * 1.0, gz0 + 0.42, 5.0, 0.1, 0.05, mats.iron, false, false)
	add_interactable(Vector3(0, 1.6, gz0 + 1.2), "[E] Try the Nordtor gates", "gate",
		func() -> Dictionary: return {"title": "Nordtor", "message": "The gates are barred. The moat, the drawbridge and the castle on its crag come in a later version of the Godot port.", "sound": "click"})
	# spire and corner turrets
	var ov := 0.5
	var apex := Vector3(0, GH + 15, gzc)
	var c4 := [Vector3(-6.5 - ov, GH, gz0 - ov), Vector3(6.5 + ov, GH, gz0 - ov), Vector3(6.5 + ov, GH, gz1 + ov), Vector3(-6.5 - ov, GH, gz1 + ov)]
	for k in 4:
		var a: Vector3 = c4[k]
		var c: Vector3 = c4[(k + 1) % 4]
		var mid := (a + c) / 2
		b.tri(I, a, c, apex, mats.slate, Vector3(mid.x, 0, mid.z - gzc).normalized() + Vector3(0, 0.3, 0))
	for sx in [-1, 1]:
		for zc in [gz0, gz1]:
			b.cylinder(I, Vector3(sx * 6.5, GH - 4, zc), 1.0, 1.0, 6.5, 12, stn, false)
			b.cylinder(I, Vector3(sx * 6.5, GH + 2.5, zc), 1.25, 0.0, 3.2, 12, mats.slate)
	# clock on the town side
	var cxf := Transform3D(Basis(), Vector3(0, 17, gz1 + 0.05))
	b.cylinder(cxf * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO), Vector3.ZERO, 1.6, 1.6, 0.06, 20, mats.white, true, 1.0, false)
	b.box(cxf, Vector3(0, 0.45, 0.08), Vector3(0.1, 1.0, 0.03), mats.iron, 1.0, false)
	b.box(cxf, Vector3(-0.3, 0, 0.09), Vector3(0.7, 0.08, 0.03), mats.iron, 1.0, false)


# ----------------------------------------------------------------------------------------------
# Cast-iron street lanterns
# ----------------------------------------------------------------------------------------------
func _street_lights() -> void:
	# Street lamps along every street, alternating sides (buildStreetFurniture in world.js)
	var near := func(v: float, cuts: Array, m: float) -> bool:
		for c in cuts:
			if absf(v - c) < m:
				return true
		return false
	var z_cuts := [-165.0, 0.0, 165.0]
	var x_cuts := [-90.0, 0.0, 90.0]
	for si in NS_STREETS.size():
		var sx: float = NS_STREETS[si].x
		var k := si
		for z in [-138.5, -110.5, -82.5, -54.5, -26.5, 26.5, 54.5, 82.5, 110.5, 138.5]:
			if near.call(z, z_cuts, 14.0):
				continue
			var side := 1 if k % 2 == 1 else -1
			k += 1
			_lantern(sx + side * (NS_HALF + 1), z)
	for ei in EW_STREETS.size():
		var ez: float = EW_STREETS[ei].z
		var k := ei
		for x in [-58.0, -32.0, 32.0, 58.0]:
			if near.call(x, x_cuts, 14.0):
				continue
			var side := 1 if k % 2 == 1 else -1
			k += 1
			# an outer loop road only has houses on one side: keep its lamps on the town side
			var sd := -int(signf(ez)) if absf(ez) > 1 else side
			_lantern(x, ez + sd * (EW_HALF + 1))
	# Lanterns at the corners of the small squares
	for r in small_squares:
		var front := r.position.y if absf(r.position.y) < absf(r.end.y) else r.end.y
		var inward := 1.0 if front == r.position.y else -1.0
		for sx in [-1, 1]:
			_lantern(r.get_center().x + sx * 5.6, front + inward * 1.0)


## Cast-iron street lantern, ported from buildStreetLight() in world.js: stepped octagonal base, fluted shaft
## with a gilt ring, lamplighter's ladder bar, and a tapered glass lantern (wider at the top) in an iron frame
## under a pyramid hood with a gilt finial.
func _lantern(x: float, z: float) -> void:
	var I := Transform3D(Basis(), Vector3(x, 0, z))
	var iron: Material = mats.lamp_iron
	var gilt: Material = mats.gilt
	var lens: Material = mats.lamp
	var cyl := func(r_top: float, r_bot: float, h: float, segs: int, mat: Material, y_mid: float, square := false) -> void:
		b.cylinder(I, Vector3(0, y_mid - h / 2, 0), r_bot, r_top, h, segs, mat, true, 1.0, true, PI / 4 if square else 0.0)
	cyl.call(0.26, 0.3, 0.5, 8, iron, 0.25)
	cyl.call(0.19, 0.24, 0.35, 8, iron, 0.67)
	cyl.call(0.085, 0.12, 3.4, 12, iron, 2.5)
	cyl.call(0.14, 0.14, 0.05, 12, gilt, 0.95)
	cyl.call(0.13, 0.1, 0.18, 12, iron, 4.2)
	b.box(I, Vector3(0, 3.9, 0), Vector3(0.7, 0.05, 0.05), iron, 1.0, false)
	for dx in [-0.35, 0.35]:
		b.cylinder(I, Vector3(dx, 3.86, 0), 0.045, 0.045, 0.08, 8, gilt)
	# Lantern: tapered glass box, iron frame top and bottom, corner posts, hood and finial
	cyl.call(0.3, 0.2, 0.62, 4, lens, 4.62, true)
	cyl.call(0.33, 0.33, 0.06, 4, iron, 4.95, true)
	cyl.call(0.22, 0.16, 0.12, 4, iron, 4.27, true)
	for k in 4:
		var a := k * PI / 2
		b.box(I, Vector3(cos(a) * 0.25, 4.62, sin(a) * 0.25), Vector3(0.03, 0.64, 0.03), iron, 1.0, false)
	cyl.call(0.0, 0.42, 0.34, 4, iron, 5.15, true)
	b.cylinder(I, Vector3(0, 5.31, 0), 0.06, 0.0, 0.1, 8, gilt)
	b.cylinder(I, Vector3(0, 5.3, 0), 0.06, 0.06, 0.04, 8, gilt)
	solid_cyl(x, z, 0.35, 4.3)
	lamp_sources.append(Vector3(x, 4.5, z))


# ----------------------------------------------------------------------------------------------
# Trees (collected as instances, drawn as MultiMeshes)
# ----------------------------------------------------------------------------------------------
## Plant one tree (types as in world.js: deciduous, linden, flowering, pine)
func _tree(x: float, z: float, kind: String, s := 1.0) -> void:
	tree_spots.append(Vector2(x, z))
	trees.build_tree(x, z, kind, s)


func _near_tree(x: float, z: float, d: float) -> bool:
	for p in tree_spots:
		if absf(p.x - x) < d and absf(p.y - z) < d and p.distance_to(Vector2(x, z)) < d:
			return true
	return false


func _near(list: Array, x: float, z: float, d: float) -> bool:
	for p in list:
		if p.distance_to(Vector2(x, z)) < d:
			return true
	return false


## Linden avenues on the verges between the pavements and the front gardens
func _avenue_trees() -> void:
	var off := WALK + 2.1
	var k := 0
	for s in NS_STREETS:
		for side in [-1, 1]:
			var z := -ns_len + 4
			while z < ns_len - 4:
				if absf(z) > EW_HALF + WALK + 3 and absf(absf(z) - 165) > EW_HALF + WALK + 3:
					_plant(s.x + side * (NS_HALF + off), z, k)
					k += 1
				z += 9.5
	for e in EW_STREETS:
		for side in [-1, 1]:
			if absf(e.z) > 1 and signf(side) == signf(e.z):
				continue
			var x := -ew_len + 4
			while x < ew_len - 4:
				if absf(x) > NS_HALF + WALK + 3 and absf(absf(x) - 90) > NS_HALF + WALK + 3:
					_plant(x, e.z + side * (EW_HALF + off), k)
					k += 1
				x += 9.5


func _plant(x: float, z: float, k: int) -> void:
	if in_rect(park, x, z, 1.0) or not is_clear(x, z, 1.4):
		return
	if _near(gate_spots, x, z, 2.4) or _near_tree(x, z, 6.0):
		return
	var blossom := hash01(int(round(x)), int(round(z)) + 7) < 0.18
	_tree(x, z, "flowering" if blossom else "linden", 1.25 if blossom else 1.15 + hash01(k, 3) * 0.3)


## buildVegetation(), buildPark() trees and the front-yard trees from world.js
func _vegetation() -> void:
	var try_tree := func(x: float, z: float, kind: String, sc: float, r: float) -> void:
		if in_rect(park, x, z) or not is_clear(x, z, r):
			return
		_tree(x, z, kind, sc)
	# A tree in every front lawn
	var kinds := ["deciduous", "flowering", "deciduous", "pine"]
	for i in houses.size():
		var h: Dictionary = houses[i]
		var p: Vector3 = house_xf(h.x, h.z, h.rot) * Vector3(6.0, 0, HOUSE_D / 2 + 5.6)
		_tree(p.x, p.z, kinds[i % 4])
	# Woodland strips between the outer houses and the wall (round Lake Maple too)
	var x := 134.0
	while x < 182.0:
		var z := -178.0
		while z < 178.0:
			for sx in [1, -1]:
				var r := rng.randf()
				try_tree.call(sx * (x + (rng.randf() - 0.5) * 6), z + (rng.randf() - 0.5) * 7,
					"pine" if r < 0.45 else ("deciduous" if r < 0.85 else "flowering"), 0.9 + rng.randf() * 0.4, 2.2)
			z += 14.0
		x += 13.0
	# Back gardens: the strips between back-to-back houses
	for bx_ in [-45.0, 45.0]:
		var z := -150.0
		while z <= 150.0:
			if rng.randf() < 0.65:
				try_tree.call(bx_ + (rng.randf() - 0.5) * 5, z + (rng.randf() - 0.5) * 8, "deciduous" if rng.randf() < 0.6 else "flowering", 0.9, 2.2)
			z += 21.0
	# Stadtpark: trees scattered over the lawns, the paths and the pond kept clear
	var planted := 0
	var tries := 0
	while tries < 400 and planted < 34:
		tries += 1
		var px := park.position.x + 4 + rng.randf() * (park.size.x - 8)
		var pz := park.position.y + 4 + rng.randf() * (park.size.y - 8)
		if not is_clear(px, pz, 2.5) or _near_tree(px, pz, 7.0):
			continue
		var r := rng.randf()
		_tree(px, pz, "pine" if r < 0.25 else ("deciduous" if r < 0.7 else "flowering"), 1.0 + rng.randf() * 0.3)
		planted += 1
	# Two lindens at the back of the Kirchplatz
	for p in [[church_square.position.x + 2.6, church_square.end.y - 2.4], [church_square.end.x - 2.6, church_square.end.y - 2.4]]:
		_tree(p[0], p[1], "linden", 1.15)


# ----------------------------------------------------------------------------------------------
# Mountains round the valley (port of mountainHeight in world.js) with forested foothills
# ----------------------------------------------------------------------------------------------
static func _hash2(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


static func _vnoise(x: float, y: float) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var xf := x - xi
	var yf := y - yi
	var u := xf * xf * (3 - 2 * xf)
	var v := yf * yf * (3 - 2 * yf)
	var a := _hash2(xi, yi)
	var bb := _hash2(xi + 1, yi)
	var c := _hash2(xi, yi + 1)
	var d := _hash2(xi + 1, yi + 1)
	return a + (bb - a) * u + (c - a) * v + (a - bb - c + d) * u * v


static func _ridged(x: float, y: float, oct: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var f := 1.0
	var w := 1.0
	for i in oct:
		var n := 1.0 - absf(_vnoise(x * f, y * f) * 2 - 1)
		n = n * n * w
		w = minf(1.0, n * 2)
		sum += n * amp
		f *= 2.03
		amp *= 0.5
	return sum


static func mountain_height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var r0 := 245.0
	var rise := smoothstep(r0, r0 + 330, r)
	var ridge := _ridged(x * 0.0042 + 11.3, z * 0.0042 - 4.1, 5)
	var broad := _vnoise(x * 0.0016 + 3.7, z * 0.0016 + 9.2)
	var h := rise * (20 + ridge * 170 * (0.5 + broad * 0.9))
	h += smoothstep(r0, r0 + 60, r) * (1 - rise) * 22 * _vnoise(x * 0.02, z * 0.02)
	var dx := x - 60
	var dz := z + 980
	h += 470 * exp(-(dx * dx + dz * dz) / (2 * 230 * 230)) * (0.75 + 0.35 * ridge)
	h *= smoothstep(214, 252, maxf(absf(x), absf(z)))
	# the castle crag north-west of town, with its flat top (castle.gd)
	var cm := Castle.hill_mask(x, z)
	if cm > 0.0:
		h = h * (1.0 - cm) + Castle.HILL.top * cm
	return h - 0.6


func _mountains() -> void:
	var NA := 288
	var NR := 70
	var r_in := 205.0
	var r_out := 1700.0
	var pts := PackedVector3Array()
	pts.resize(NA * NR)
	for j in NR:
		var r := r_in * pow(r_out / r_in, float(j) / (NR - 1))
		for i in NA:
			var a := TAU * i / NA
			var x := cos(a) * r
			var z := sin(a) * r
			pts[j * NA + i] = Vector3(x, mountain_height(x, z), z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normals := PackedVector3Array()
	normals.resize(NA * NR)
	for j in NR:
		for i in NA:
			var pa := pts[j * NA + (i + 1) % NA] - pts[j * NA + (i + NA - 1) % NA]
			var pr := pts[mini(j + 1, NR - 1) * NA + i] - pts[maxi(j - 1, 0) * NA + i]
			var n := pr.cross(pa).normalized()
			if n.y < 0:
				n = -n
			normals[j * NA + i] = n
	for j in NR - 1:
		for i in NA:
			var i1 := (i + 1) % NA
			var q := [j * NA + i, j * NA + i1, (j + 1) * NA + i1, (j + 1) * NA + i]
			var A: Vector3 = pts[q[0]]
			var B: Vector3 = pts[q[1]]
			var C: Vector3 = pts[q[2]]
			var fn := (B - A).cross(C - A)
			var order := [0, 2, 1, 0, 3, 2] if fn.y > 0 else [0, 1, 2, 0, 2, 3]
			for o in order:
				st.set_normal(normals[q[o]])
				st.add_vertex(pts[q[o]])
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _shader_mat("res://shaders/mountain.gdshader")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
