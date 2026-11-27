extends Control
## Radar minimap, north up, centred on the player (port of renderMinimap in game.js).

const SCALE := 0.85   # metres -> pixels

var game


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if game == null or game.player == null:
		return
	var W: Node = game.world
	var sz := size
	var c := sz / 2
	var pp: Vector3 = game.player.global_position
	draw_rect(Rect2(Vector2.ZERO, sz), Color("#0f172a"))
	var to_map := func(x: float, z: float) -> Vector2: return c + Vector2(x - pp.x, z - pp.z) * SCALE
	var r2 := func(r: Rect2, col: Color) -> void:
		var a: Vector2 = to_map.call(r.position.x, r.position.y)
		draw_rect(Rect2(a, r.size * SCALE), col)
	r2.call(W.park, Color("#1f4d2c"))
	for l in W.lakes:
		var pts := PackedVector2Array()
		for i in 24:
			var t := TAU * i / 24
			pts.append(to_map.call(l.cx + cos(t) * l.rw, l.cz + sin(t) * l.rd))
		draw_colored_polygon(pts, Color("#1e5a7a"))
	for r in W.road_rects:
		r2.call(r, Color("#334155"))
	for r in W.house_rects:
		r2.call(r, Color("#64748b"))
	r2.call(W.rect(W.WH.x0, W.WH.z0, W.WH.x1, W.WH.z1), Color("#2f6f9c"))
	r2.call(W.church_square, Color("#4b5563"))
	for r in W.small_squares:
		r2.call(r, Color("#4b5563"))
	for r in W.church_rects:
		r2.call(r, Color("#b4604a"))
	var F: float = W.FENCE
	var a: Vector2 = to_map.call(-F, -F)
	draw_rect(Rect2(a, Vector2(2 * F, 2 * F) * SCALE), Color("#a8a29e"), false, 3.0)
	for p in game.parcels.loose_positions():
		var m: Vector2 = to_map.call(p.x, p.z)
		if m.x >= 0 and m.y >= 0 and m.x <= sz.x and m.y <= sz.y:
			draw_circle(m, 1.6, Color("#f59e0b"))
	_depot_marker(W, to_map, sz)
	# Player arrow and view cone
	var yaw: float = game.player.yaw
	draw_set_transform(c, -yaw, Vector2.ONE)
	var cone := PackedVector2Array([Vector2.ZERO])
	for i in 9:
		var t := -PI / 2 - 0.45 + 0.9 * i / 8.0
		cone.append(Vector2(cos(t), sin(t)) * 32.0)
	draw_colored_polygon(cone, Color(0.23, 0.51, 0.96, 0.25))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -7), Vector2(5, 5), Vector2(-5, 5)]), Color("#3b82f6"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_string(get_theme_default_font(), Vector2(sz.x / 2 - 4, 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ef4444"))


## The Parcel Depot: a gold badge at its door; when it is off the map, the badge waits at the edge with an arrow
## pointing the way
func _depot_marker(W: Node, to_map: Callable, sz: Vector2) -> void:
	var door: Vector2 = to_map.call(W.WH.x1, 0.0)
	var c := sz / 2
	var margin := 14.0
	var inside := door.x >= margin and door.y >= margin and door.x <= sz.x - margin and door.y <= sz.y - margin
	var p := door
	if not inside:   # slide along the line from the centre until it touches the edge band
		var d := door - c
		var k := minf((c.x - margin) / maxf(absf(d.x), 0.001), (c.y - margin) / maxf(absf(d.y), 0.001))
		p = c + d * k
		var dir := d.normalized()
		var side := Vector2(-dir.y, dir.x)
		var tip := p + dir * 11.0
		draw_colored_polygon(PackedVector2Array([tip, p + dir * 3.0 + side * 5.0, p + dir * 3.0 - side * 5.0]), Color("#fbbf24"))
	var gold := Color("#fbbf24")
	draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color("#1e293b"))
	draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), gold, false, 2.0)
	draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), gold)   # a parcel
	var font := get_theme_default_font()
	var label := "DEPOT"
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var lp := p + Vector2(-tw / 2, 18)
	if lp.y > sz.y - 2:
		lp.y = p.y - 10
	lp.x = clampf(lp.x, 2.0, sz.x - tw - 2.0)
	draw_string(font, lp + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.7))
	draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gold)
