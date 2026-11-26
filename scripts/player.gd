extends CharacterBody3D
## First-person player: walk / sprint / crouch / jump, mouse look, head bob and footsteps, flashlight, and the
## "what am I looking at" scan for interactions. Port of player.js on top of Godot physics (the web version had
## its own collision code); kerbs and steps up to 0.45 m are climbed automatically.

const WALK := 6.5
const SPRINT := 11.0
const CROUCH := 3.5
const JUMP := 7.5
const GRAVITY := 22.0
const EYE := 1.7
const EYE_CROUCH := 1.05
const STEP := 0.45
const SENSITIVITY := 0.0022
const MAP_LIMIT := 184.0

var world
var game
var yaw := 0.0
var pitch := 0.0
var crouching := false
var head: Node3D
var camera: Camera3D
var flashlight: SpotLight3D
var capsule: CapsuleShape3D
var shape: CollisionShape3D
var eye := EYE
var step_cycle := 0.0
var stepped := false
var fall_speed := 0.0
var current = null          # Dictionary: world interactable, or a parcel record (has "slot")


func _ready() -> void:
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	shape = CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.1
	camera.far = 2600.0
	head.add_child(camera)
	camera.current = true
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color("#fff7ed")
	flashlight.spot_range = 30.0
	flashlight.spot_angle = 30.0
	flashlight.spot_angle_attenuation = 0.8
	flashlight.light_energy = 3.0
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.3, -0.2, -0.1)
	flashlight.visible = false
	camera.add_child(flashlight)
	floor_snap_length = STEP
	floor_max_angle = deg_to_rad(50)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.screen_relative
		yaw -= rel.x * SENSITIVITY
		pitch = clampf(pitch - rel.y * SENSITIVITY, -PI * 0.47, PI * 0.47)


func toggle_crouch() -> void:
	if crouching:
		# stand up only if there is room above
		var t := global_transform
		if test_move(t, Vector3(0, 0.6, 0)):
			return
	crouching = not crouching
	capsule.height = 1.2 if crouching else 1.8
	shape.position.y = capsule.height / 2


func jump() -> void:
	if is_on_floor() and not crouching:
		velocity.y = JUMP
		game.sfx.play("jump", -10.0)


func toggle_flashlight() -> bool:
	flashlight.visible = not flashlight.visible
	game.sfx.play("click")
	return flashlight.visible


func _key(a: Key, b := KEY_NONE) -> bool:
	return Input.is_physical_key_pressed(a) or (b != KEY_NONE and Input.is_physical_key_pressed(b))


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if _key(KEY_W, KEY_UP): input.y -= 1
	if _key(KEY_S, KEY_DOWN): input.y += 1
	if _key(KEY_A, KEY_LEFT): input.x -= 1
	if _key(KEY_D, KEY_RIGHT): input.x += 1
	var sprint := _key(KEY_SHIFT)
	var speed := CROUCH if crouching else (SPRINT if sprint else WALK)
	var moving := input.length_squared() > 0.01
	if moving:
		var dir := Vector3(input.x, 0, input.y).normalized().rotated(Vector3.UP, yaw)
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x *= 0.7
		velocity.z *= 0.7
	velocity.y -= GRAVITY * delta
	var was_floor := is_on_floor()
	var climbed := false
	if was_floor and moving:
		climbed = _try_step(Vector3(velocity.x, 0, velocity.z) * delta)
	if climbed:
		velocity.y = 0
	else:
		var vy := velocity.y
		move_and_slide()
		if is_on_floor() and not was_floor and vy < -3.0:
			game.sfx.play("land", -6.0)
	_keep_out_of_lakes()
	var p := global_position
	if absf(p.x) > MAP_LIMIT or absf(p.z) > MAP_LIMIT:
		global_position = Vector3(clampf(p.x, -MAP_LIMIT, MAP_LIMIT), p.y, clampf(p.z, -MAP_LIMIT, MAP_LIMIT))

	# Eye height, head bob and footsteps
	var target_eye := EYE_CROUCH if crouching else EYE
	eye = lerpf(eye, target_eye, minf(1.0, delta * 12.0))
	head.rotation.y = yaw
	camera.rotation.x = pitch
	if is_on_floor() and moving:
		var freq := 14.0 if sprint else 9.0
		step_cycle += delta * freq
		var bob_y := sin(step_cycle) * (0.07 if sprint else 0.04)
		var bob_x := cos(step_cycle * 0.5) * (0.04 if sprint else 0.02)
		head.position = Vector3(0, eye + bob_y, 0) + head.basis.x * bob_x
		if sin(step_cycle) < -0.95 and not stepped:
			stepped = true
			game.sfx.footstep(world.surface_at(global_position.x, global_position.z), sprint)
		elif sin(step_cycle) >= -0.95:
			stepped = false
	else:
		head.position = Vector3(0, eye, 0)


## Climb kerbs and steps: lift, move, and settle back down if the way is clear up there
func _try_step(motion: Vector3) -> bool:
	var t := global_transform
	if not test_move(t, motion):
		return false
	var up := Vector3(0, STEP, 0)
	if test_move(t, up):
		return false
	t.origin += up
	if test_move(t, motion):
		return false
	t.origin += motion
	var col := KinematicCollision3D.new()
	if not test_move(t, Vector3(0, -STEP - 0.05, 0), col):
		return false
	if col.get_normal().y < 0.7:
		return false
	t.origin += col.get_travel()
	if t.origin.y - global_position.y < 0.03:
		return false
	global_transform = t
	return true


## Ponds: stay on the coping (same ellipse push-out as the 'lake' collider in player.js)
func _keep_out_of_lakes() -> void:
	for l in world.lakes:
		var a: float = l.rw + 0.25
		var c: float = l.rd + 0.25
		var dx: float = global_position.x - l.cx
		var dz: float = global_position.z - l.cz
		var k := sqrt(dx * dx / (a * a) + dz * dz / (c * c))
		if k < 1.0:
			var s := 1.0 / maxf(k, 0.001)
			global_position = Vector3(l.cx + dx * s, global_position.y, l.cz + dz * s)


func eye_position() -> Vector3:
	return camera.global_position


func look_dir() -> Vector3:
	return -camera.global_basis.z


func _process(_delta: float) -> void:
	# What is the crosshair on? Nearest interactable within 3.5 m in a narrow cone
	var eye_p := eye_position()
	var dir := look_dir()
	var best_d := 3.5
	var found = null
	for item in world.interactables:
		var p: Vector3 = item.pos
		var d := eye_p.distance_to(p)
		if d < best_d and dir.dot((p - eye_p).normalized()) > 0.85:
			best_d = d
			found = item
	var parcel = game.parcels.nearest(eye_p, dir, best_d)
	if parcel != null:
		found = parcel
	current = found
