## On-foot player: walk, jetpack, creative fly, first/third person, break/place blocks.
##
## Collision is a simple axis-separated AABB sweep against the voxel grid instead of
## physics shapes: no collision meshes to build per chunk, which keeps the web build
## light. Ships will get their own physics later (M3).
extends Node3D

const Blocks = preload("res://scripts/voxel/blocks.gd")
const VoxelWorld = preload("res://scripts/world/voxel_world.gd")

const WALK_SPEED := 5.5
const RUN_SPEED := 9.0
const FLY_SPEED := 18.0
const FLY_BOOST := 2.5
const JUMP_VELOCITY := 7.2
const GRAVITY := 20.0
const JET_ACCEL := 32.0
const JET_DURATION := 1.6   # seconds of thrust on a full tank
const MAX_FALL := 50.0
const EYE_HEIGHT := 1.62
const MIN_OFF := Vector3(-0.3, 0.0, -0.3)
const MAX_OFF := Vector3(0.3, 1.8, 0.3)
const REACH := 7.0
const MOUSE_SENS := 0.0025
const THIRD_PERSON_DISTANCE := 4.0
const PLACEABLE := [Blocks.HULL, Blocks.LIGHT, Blocks.STONE, Blocks.DIRT, Blocks.GRASS, Blocks.SAND, Blocks.ORE]

var world: VoxelWorld
var frozen := true          # true until the spawn area has loaded
var velocity := Vector3.ZERO
var on_floor := false
var fly := false
var third_person := false
var autopilot := false      # benchmark: fly forward on its own
var yaw := 0.0
var pitch := -0.2
var jet_fuel := 1.0
var slot := 0
var target: Dictionary = {}

var head: Node3D
var camera: Camera3D
var body: Node3D
var highlight: MeshInstance3D


func _ready() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_HEIGHT
	add_child(head)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = world.view_radius * 16.0 + 64.0
	head.add_child(camera)
	camera.current = true

	body = _build_body()
	body.visible = false
	add_child(body)

	highlight = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.02
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.18)
	box.material = mat
	highlight.mesh = box
	highlight.top_level = true
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.visible = false
	add_child(highlight)


func selected_block() -> int:
	return PLACEABLE[slot]


# --- Input -------------------------------------------------------------------

func _unhandled_input(event) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := event as InputEventMouseMotion
			yaw -= motion.relative.x * MOUSE_SENS
			pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.55, 1.55)
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # click to play (needs a user gesture on web)
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_break_block()
			MOUSE_BUTTON_RIGHT:
				_place_block()
			MOUSE_BUTTON_WHEEL_UP:
				_select_slot(slot - 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_select_slot(slot + 1)
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
			_select_slot(key.physical_keycode - KEY_1)
		elif key.is_action_pressed("toggle_camera"):
			third_person = not third_person
		elif key.is_action_pressed("toggle_fly"):
			fly = not fly
			velocity = Vector3.ZERO


func _select_slot(i: int) -> void:
	slot = posmod(i, PLACEABLE.size())


# --- Movement ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	rotation.y = yaw
	head.rotation.x = pitch
	if frozen:
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if autopilot:
		input = Vector2(0.0, -1.0)
	var wish := transform.basis * Vector3(input.x, 0.0, input.y)
	wish.y = 0.0
	if wish.length_squared() > 1.0:
		wish = wish.normalized()

	if fly:
		var fly_speed := FLY_SPEED * (FLY_BOOST if Input.is_action_pressed("sprint") else 1.0)
		var vertical := float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("descend"))
		velocity = (wish + Vector3.UP * vertical) * fly_speed
		position += velocity * delta
		position.x = clampf(position.x, 0.5, world.size_xz - 0.5)
		position.z = clampf(position.z, 0.5, world.size_xz - 0.5)
		position.y = clampf(position.y, 1.0, world.height_blocks + 64.0)
		on_floor = false
		return

	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var accel := 60.0 if on_floor else 12.0
	velocity.x = move_toward(velocity.x, wish.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, accel * delta)
	velocity.y -= GRAVITY * delta

	var jumping := Input.is_action_pressed("jump")
	if on_floor:
		jet_fuel = minf(1.0, jet_fuel + delta * 0.8)
		if jumping:
			velocity.y = JUMP_VELOCITY
	elif jumping and velocity.y < 2.0 and jet_fuel > 0.0:
		velocity.y += JET_ACCEL * delta
		jet_fuel = maxf(0.0, jet_fuel - delta / JET_DURATION)
	velocity.y = maxf(velocity.y, -MAX_FALL)

	_move(velocity * delta)


func _move(motion: Vector3) -> void:
	var largest := maxf(absf(motion.x), maxf(absf(motion.y), absf(motion.z)))
	var steps := maxi(1, ceili(largest / 0.45))  # never skip through a block
	var step := motion / steps
	on_floor = false
	for _i in steps:
		_move_axis(0, step.x)
		_move_axis(2, step.z)
		_move_axis(1, step.y)


func _move_axis(axis: int, amount: float) -> void:
	if amount == 0.0:
		return
	var p := position
	p[axis] += amount
	if not _collides(p):
		position = p
		return
	# Snap flush against the block we ran into.
	if amount > 0.0:
		p[axis] = floorf(p[axis] + MAX_OFF[axis]) - MAX_OFF[axis] - 0.001
	else:
		p[axis] = floorf(p[axis] + MIN_OFF[axis]) + 1.0 - MIN_OFF[axis] + 0.001
		if axis == 1:
			on_floor = true
	velocity[axis] = 0.0
	if not _collides(p):
		position = p


func _collides(p: Vector3) -> bool:
	var mn := p + MIN_OFF
	var mx := p + MAX_OFF
	for x in range(floori(mn.x), floori(mx.x - 0.0001) + 1):
		for y in range(floori(mn.y), floori(mx.y - 0.0001) + 1):
			for z in range(floori(mn.z), floori(mx.z - 0.0001) + 1):
				if world.is_solid(x, y, z):
					return true
	return false


# --- Camera & interaction ----------------------------------------------------

func _process(_delta: float) -> void:
	body.visible = third_person
	if third_person:
		var origin := head.global_position
		var back := head.global_transform.basis.z
		var hit := world.raycast(origin, back, THIRD_PERSON_DISTANCE)
		var dist := THIRD_PERSON_DISTANCE
		if not hit.is_empty():
			dist = maxf(0.4, float(hit["distance"]) - 0.3)
		camera.position = Vector3(0.0, 0.3, dist)
	else:
		camera.position = Vector3.ZERO
	_update_target()


func _update_target() -> void:
	if frozen:
		target = {}
		highlight.visible = false
		return
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var reach := REACH + (camera.position.z if third_person else 0.0)
	target = world.raycast(origin, dir, reach)
	if target.is_empty():
		highlight.visible = false
		return
	var b: Vector3i = target["block"]
	highlight.visible = true
	highlight.global_position = Vector3(b) + Vector3(0.5, 0.5, 0.5)


func _break_block() -> void:
	if target.is_empty():
		return
	var b: Vector3i = target["block"]
	world.set_block(b, Blocks.AIR)


func _place_block() -> void:
	if target.is_empty():
		return
	var b: Vector3i = target["block"]
	var n: Vector3i = target["normal"]
	var p := b + n
	if world.get_block(p.x, p.y, p.z) != Blocks.AIR:
		return
	var mn := position + MIN_OFF
	var mx := position + MAX_OFF
	var overlaps := p.x + 1 > mn.x and p.x < mx.x and p.y + 1 > mn.y and p.y < mx.y and p.z + 1 > mn.z and p.z < mx.z
	if overlaps and not fly:
		return
	world.set_block(p, selected_block())


# --- Visuals -----------------------------------------------------------------

func _build_body() -> Node3D:
	var root := Node3D.new()
	root.name = "Body"
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.92, 0.93, 0.95)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.55, 0.2)
	var visor := StandardMaterial3D.new()
	visor.albedo_color = Color(0.2, 0.8, 1.0)
	visor.emission_enabled = true
	visor.emission = Color(0.2, 0.8, 1.0)
	visor.emission_energy_multiplier = 1.5
	# Player faces -Z.
	_add_box(root, Vector3(0.5, 0.7, 0.3), Vector3(0.0, 1.05, 0.0), suit)        # torso
	_add_box(root, Vector3(0.2, 0.7, 0.24), Vector3(-0.13, 0.35, 0.0), suit)     # legs
	_add_box(root, Vector3(0.2, 0.7, 0.24), Vector3(0.13, 0.35, 0.0), suit)
	_add_box(root, Vector3(0.15, 0.62, 0.18), Vector3(-0.33, 1.07, 0.0), suit)   # arms
	_add_box(root, Vector3(0.15, 0.62, 0.18), Vector3(0.33, 1.07, 0.0), suit)
	_add_box(root, Vector3(0.42, 0.42, 0.42), Vector3(0.0, 1.62, 0.0), suit)     # helmet
	_add_box(root, Vector3(0.32, 0.18, 0.04), Vector3(0.0, 1.64, -0.22), visor)  # visor
	_add_box(root, Vector3(0.42, 0.5, 0.2), Vector3(0.0, 1.1, 0.25), accent)     # jetpack
	return root


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
