extends CanvasLayer
## Touch controls for phones and tablets, ported from mobile.js: a floating joystick on the left half of the
## screen (push well past the rim to sprint), drag-to-look on the right half, and buttons for Use, Jump,
## Crouch, Flashlight, Drop (only while carrying parcels) and Pause. Touches are handled here directly (not
## through emulated mouse clicks) so you can walk and look, or walk and press a button, at the same time.

const JOY_RADIUS := 75.0
const BTN := 92.0

var game
var look_level := 4.0          # 1..10, like the web version's look-speed slider
var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var look_id := -1
var buttons: Array = []        # [{rect: Rect2, node: Control, action: String}]
var root: Control
var joy_base: Panel
var joy_knob: Panel
var drop_btn: Control


func _ready() -> void:
	layer = 2
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	joy_base = _circle(JOY_RADIUS * 2, Color(1, 1, 1, 0.12))
	joy_knob = _circle(64, Color(1, 1, 1, 0.35))
	joy_base.visible = false
	joy_knob.visible = false
	root.add_child(joy_base)
	root.add_child(joy_knob)
	_button("use", "Use", Vector2(-BTN * 1.35 - 24, -BTN * 1.35 - 40), BTN * 1.35)
	_button("jump", "Jump", Vector2(-BTN * 2.6 - 40, -BTN - 30), BTN)
	_button("crouch", "Crouch", Vector2(-BTN - 24, -BTN * 2.6 - 60), BTN)
	_button("light", "Light", Vector2(-BTN * 2.2 - 40, -BTN * 2.45 - 60), BTN * 0.8)
	drop_btn = _button("drop", "Drop", Vector2(-BTN * 3.5 - 56, -BTN - 30), BTN)
	_button("pause", "II", Vector2(-BTN * 0.7 - 210, 12), BTN * 0.7, true)


func _circle(d: float, col: Color) -> Panel:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(int(d / 2))
	s.border_color = Color(1, 1, 1, 0.4)
	s.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", s)
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A round button anchored to the bottom-right corner (or the top-right corner when top)
func _button(action: String, text: String, offset: Vector2, d: float, top := false) -> Control:
	var p := _circle(d, Color(0.06, 0.09, 0.16, 0.55))
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT if top else Control.PRESET_BOTTOM_RIGHT)
	p.position = offset
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(d * 0.24))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	root.add_child(p)
	buttons.append({"node": p, "action": action})
	return p


func _hit_button(pos: Vector2) -> String:
	for bt in buttons:
		var n: Control = bt.node
		if n.visible and n.get_global_rect().grow(10).has_point(pos):
			return bt.action
	return ""


func _press(action: String) -> void:
	var p = game.player
	match action:
		"use": game.interact()
		"jump":
			if not game.truck.driving:
				p.jump()
		"crouch": p.toggle_crouch()
		"light": p.toggle_flashlight()
		"drop": game.drop_one()
		"pause": game.pause()


func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var pos := _canvas_pos(event.position)
		if event.pressed:
			var act := _hit_button(pos)
			if act != "":
				_press(act)
				_flash(act)
			elif pos.x < root.size.x * 0.45 and joy_id == -1:
				joy_id = event.index
				joy_origin = pos
				joy_vec = Vector2.ZERO
				joy_base.position = pos - joy_base.size / 2
				joy_knob.position = pos - joy_knob.size / 2
				joy_base.visible = true
				joy_knob.visible = true
			elif look_id == -1:
				look_id = event.index
		else:
			if event.index == joy_id:
				joy_id = -1
				joy_vec = Vector2.ZERO
				joy_base.visible = false
				joy_knob.visible = false
			elif event.index == look_id:
				look_id = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var pos := _canvas_pos(event.position)
		if event.index == joy_id:
			var d := pos - joy_origin
			joy_vec = d / JOY_RADIUS
			var shown := d.limit_length(JOY_RADIUS)
			joy_knob.position = joy_origin + shown - joy_knob.size / 2
		elif event.index == look_id:
			var k := 0.0011 * look_level
			game.player.yaw -= event.relative.x * k
			game.player.pitch = clampf(game.player.pitch - event.relative.y * k, -PI * 0.47, PI * 0.47)
		get_viewport().set_input_as_handled()


func _canvas_pos(p: Vector2) -> Vector2:
	return p   # Godot already maps touches into the stretched canvas the HUD uses


func _flash(action: String) -> void:
	for bt in buttons:
		if bt.action == action:
			var n: Control = bt.node
			n.modulate = Color(1.6, 1.6, 1.6)
			create_tween().tween_property(n, "modulate", Color.WHITE, 0.2)


func _process(_delta: float) -> void:
	if game == null or game.player == null:
		return
	drop_btn.visible = game.backpack.size() > 0
	# Analog move: walk slower when the stick is only pushed part-way; well past the rim sprints
	var p = game.player
	p.move_input = joy_vec.limit_length(1.0)
	p.touch_sprint = joy_vec.length() > 1.35
