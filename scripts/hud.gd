extends CanvasLayer
## HUD and menus (the HTML overlay of index.html): top bar, depot task, backpack, minimap, crosshair,
## interaction prompt, toasts, the resident dialogue box and the start / pause menu.

const Minimap := preload("res://scripts/minimap.gd")

var game
var mobile := false
var score_label: Label
var clock_label: Label
var weather_label: Label
var sound_label: Label
var quest_label: Label
var bp_cap: Label
var bp_fill: ColorRect
var bp_bar: ColorRect
var bp_icons: HBoxContainer
var bp_mode: Label
var prompt: Label
var toast_label: Label
var dialogue: PanelContainer
var dialogue_title: Label
var dialogue_text: Label
var menu: Control
var stats_grid: GridContainer
var stats_title: Label
var play_btn: Button
var new_btn: Button
var minimap: Control
var music_value: Label
var _toast_t := 0.0
var _dialogue_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top bar
	var top_l := HBoxContainer.new()
	top_l.position = Vector2(16, 14)
	top_l.add_theme_constant_override("separation", 10)
	root.add_child(top_l)
	top_l.add_child(_pill("Altstadt"))
	score_label = _pill_label(top_l, "Score: 0")
	var top_r := HBoxContainer.new()
	top_r.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_r.position = Vector2(-820, 14)
	top_r.size = Vector2(800, 30)
	top_r.alignment = BoxContainer.ALIGNMENT_END
	top_r.add_theme_constant_override("separation", 10)
	root.add_child(top_r)
	weather_label = _pill_label(top_r, "[B] Weather: clear")
	clock_label = _pill_label(top_r, "[N] 14:00 Day")
	sound_label = _pill_label(top_r, "[K] Sound: on")
	var map_pill := _pill_label(top_r, "[M] Map")
	if mobile:   # keyboard hints mean nothing on a phone, and the pause button sits up there
		weather_label.get_parent().visible = false
		sound_label.get_parent().visible = false
		map_pill.get_parent().visible = false

	# Depot task and backpack (left)
	var left := VBoxContainer.new()
	left.position = Vector2(16, 60)
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	var quest := _panel(left)
	var qv := VBoxContainer.new()
	quest.add_child(qv)
	qv.add_child(_label("Town tasks", 13, Color("#94a3b8")))
	quest_label = _label("Parcels in the depot: 0/0", 16)
	qv.add_child(quest_label)
	var bp := _panel(left)
	bp.custom_minimum_size = Vector2(250, 0)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bp.add_child(bv)
	var bh := HBoxContainer.new()
	bv.add_child(bh)
	var bt := _label("Backpack", 16)
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(bt)
	bp_cap = _label("0/10", 16)
	bh.add_child(bp_cap)
	bp_bar = ColorRect.new()
	bp_bar.color = Color(1, 1, 1, 0.12)
	bp_bar.custom_minimum_size = Vector2(0, 8)
	bv.add_child(bp_bar)
	bp_fill = ColorRect.new()
	bp_fill.color = Color("#22c55e")
	bp_fill.size = Vector2(0, 8)
	bp_bar.add_child(bp_fill)
	bp_icons = HBoxContainer.new()
	bp_icons.custom_minimum_size = Vector2(0, 16)
	bp_icons.alignment = BoxContainer.ALIGNMENT_BEGIN
	bv.add_child(bp_icons)
	bp_mode = _label("Pick up parcels with [E]", 13, Color("#cbd5e1"))
	bp_mode.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(bp_mode)

	# Minimap (top right)
	minimap = Minimap.new()
	minimap.game = game
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-186, 56)
	minimap.size = Vector2(170, 170)
	minimap.clip_contents = true
	root.add_child(minimap)

	# Crosshair
	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.85)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.size = Vector2(4, 4)
	cross.position = Vector2(-2, -2)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)

	# Prompt, toast, dialogue (bottom centre)
	prompt = _centre_label(root, -170, 18)
	toast_label = _centre_label(root, -120, 16)
	dialogue = PanelContainer.new()
	dialogue.add_theme_stylebox_override("panel", _box(Color(0.06, 0.09, 0.16, 0.9), 12))
	dialogue.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue.position = Vector2(-300, -330)
	dialogue.custom_minimum_size = Vector2(600, 0)
	dialogue.visible = false
	root.add_child(dialogue)
	var dv := VBoxContainer.new()
	dialogue.add_child(dv)
	dialogue_title = _label("", 18, Color("#fbbf24"))
	dv.add_child(dialogue_title)
	dialogue_text = _label("", 16)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.custom_minimum_size = Vector2(570, 0)
	dv.add_child(dialogue_text)

	# Controls hint (bottom left)
	var hint := _label("[WASD] Walk  |  [Shift] Sprint  |  [Space] Jump  |  [C] Crouch\n[E] Interact / Pick up / Store in depot  |  [G] Drop a parcel\n[F] Flashlight  |  [B] Weather  |  [N] Skip time  |  [M] Map  |  [Esc] Menu", 12, Color(1, 1, 1, 0.7))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(16, -70)
	hint.visible = not mobile
	root.add_child(hint)

	_build_menu(root)


func _box(col: Color, radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


func _label(text: String, size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.06, 0.09, 0.16, 0.78)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _pill(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.06, 0.09, 0.16, 0.78), 16))
	p.add_child(_label(text, 15))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _pill_label(parent: Control, text: String) -> Label:
	var p := _pill(text)
	parent.add_child(p)
	return p.get_child(0)


func _centre_label(root: Control, y: float, size: int) -> Label:
	var l := _label("", size)
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(-400, y)
	l.size = Vector2(800, 30)
	l.add_theme_stylebox_override("normal", _box(Color(0.06, 0.09, 0.16, 0.8), 14))
	l.visible = false
	root.add_child(l)
	return l


func _build_menu(root: Control) -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(centre)
	var panel := PanelContainer.new()
	var st := _box(Color(0.06, 0.09, 0.16, 0.95), 18)
	st.content_margin_left = 40
	st.content_margin_right = 40
	st.content_margin_top = 30
	st.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", st)
	centre.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title := _label("PARCELS IN TRANSIT", 52, Color("#fbbf24"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("First-person old-town explorer & tidy-up quest", 17, Color("#cbd5e1"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var rows := [["Move around", "W A S D"], ["Look around", "MOUSE"], ["Jump / Crouch", "SPACE / C"], ["Sprint", "SHIFT"],
		["Interact / Pick up / Store", "E / ENTER"], ["Drop a parcel", "G"], ["Flashlight", "F"], ["Skip time / Weather", "N / B"]]
	if mobile:
		rows = [["Move", "LEFT THUMB"], ["Sprint", "PUSH TO THE EDGE"], ["Look around", "DRAG RIGHT SIDE"], ["Pick up / Store", "USE"],
			["Jump / Crouch", "BUTTONS"], ["Drop a parcel", "DROP"], ["Flashlight", "LIGHT"], ["Pause", "II / BACK"]]
	for r in rows:
		grid.add_child(_label(r[0], 15, Color("#e2e8f0")))
		grid.add_child(_label(r[1], 15, Color("#fbbf24")))
	var task := _label("The town is buried in parcels. Carry them (10 at a time) to the Parcel Depot at the west end of the Ahornallee and press E inside.", 15, Color("#cbd5e1"))
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.custom_minimum_size = Vector2(640, 0)
	v.add_child(task)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 12)
	v.add_child(mrow)
	mrow.add_child(_label("Music", 16))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(300, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(slider)
	music_value = _label("40%", 16)
	mrow.add_child(music_value)
	slider.value = round(game.sfx.music_volume * 100)
	music_value.text = "%d%%" % int(slider.value)
	slider.value_changed.connect(func(val: float) -> void:
		game.sfx.set_music_volume(val / 100.0)
		music_value.text = "%d%%" % int(val))
	# your progress (filled in by set_stats when the menu opens)
	stats_title = _label("YOUR PROGRESS", 15, Color("#94a3b8"))
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats_title)
	stats_grid = GridContainer.new()
	stats_grid.columns = 4
	stats_grid.add_theme_constant_override("h_separation", 24)
	stats_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(stats_grid)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	v.add_child(brow)
	var play := Button.new()
	play.text = "TAP TO START EXPLORING" if mobile else "CLICK TO START EXPLORING"
	play.add_theme_font_size_override("font_size", 20)
	play.custom_minimum_size = Vector2(0, 52)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(func() -> void: game.resume())
	brow.add_child(play)
	play_btn = play
	new_btn = Button.new()
	new_btn.text = "New game"
	new_btn.add_theme_font_size_override("font_size", 15)
	new_btn.custom_minimum_size = Vector2(130, 52)
	var confirm := [false]
	new_btn.pressed.connect(func() -> void:
		if not confirm[0]:   # ask once more: this throws away the save
			confirm[0] = true
			new_btn.text = "Sure? Tap again" if mobile else "Sure? Click again"
			return
		game.new_game())
	brow.add_child(new_btn)
	var note := _label("Walk into the houses, drive the delivery truck, and watch out for the wind.", 13, Color("#94a3b8"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if menu.visible:
			game.resume()
		else:
			game.pause()
		get_viewport().set_input_as_handled()


func show_menu(on: bool) -> void:
	menu.visible = on


## The progress panel and the play button's wording (continue a saved game, or start)
func set_stats(rows: Array, has_progress: bool) -> void:
	for c in stats_grid.get_children():
		c.queue_free()
	for r in rows:
		stats_grid.add_child(_label(r[0], 14, Color("#cbd5e1")))
		stats_grid.add_child(_label(r[1], 14, Color("#fbbf24")))
	stats_title.visible = has_progress
	stats_grid.visible = has_progress
	new_btn.visible = has_progress
	if has_progress:
		play_btn.text = "TAP TO CONTINUE" if mobile else "CLICK TO CONTINUE"


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			toast_label.visible = false
	if _dialogue_t > 0.0:
		_dialogue_t -= delta
		if _dialogue_t <= 0.0:
			dialogue.visible = false


func set_score(v: int) -> void:
	score_label.text = "Score: %d" % v


func set_clock(text: String) -> void:
	if clock_label.text != text:
		clock_label.text = text


func set_quest(done: int, total: int) -> void:
	quest_label.text = "Parcels in the depot: %d/%d" % [done, total]


func set_prompt(text: String) -> void:
	prompt.visible = text != ""
	prompt.text = text


func toast(text: String, warn := false) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", Color("#fca5a5") if warn else Color.WHITE)
	toast_label.visible = true
	_toast_t = 2.2


func show_dialogue(title: String, text: String) -> void:
	dialogue_title.text = title
	dialogue_text.text = text
	dialogue.visible = true
	_dialogue_t = 5.5


func set_backpack(items: Array, cap: int) -> void:
	var used := items.size()
	bp_cap.text = "%d/%d" % [used, cap]
	bp_fill.size = Vector2(bp_bar.size.x * used / cap, 8)
	bp_fill.color = Color("#ef4444") if used >= cap else (Color("#f59e0b") if used >= cap * 0.75 else Color("#22c55e"))
	for c in bp_icons.get_children():
		c.queue_free()
	for s in items:
		var r := ColorRect.new()
		r.color = Color("#c08a55")
		r.custom_minimum_size = {"S": Vector2(9, 9), "M": Vector2(15, 9), "L": Vector2(15, 15)}[s]
		r.size_flags_vertical = Control.SIZE_SHRINK_END
		bp_icons.add_child(r)
	if used >= cap:
		bp_mode.text = "Full! Store them at the Parcel Depot (west end of the Ahornallee)"
	elif used > 0:
		bp_mode.text = "[E] in the depot stores them  |  [G] drops one here"
	else:
		bp_mode.text = "Pick up parcels with [E]"
