extends CharacterBody3D
## On-foot player: camera-relative movement, sprint, jump and a simple
## low-poly placeholder body with a procedural walk cycle.

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.8
const ACCEL := 14.0
const JUMP_SPEED := 5.0
const TURN_SPEED := 12.0

var rig                       # camera_rig.gd
var active := true            # false while driving
var spawn_point := Vector3.ZERO
var model: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _phase := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	_build_model()


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	var shirt := _mat("#c8173a")
	var skin := _mat("#5a3825")
	var trousers := _mat("#2b3a55")
	var shoe := _mat("#1b1b1b")
	_part(model, BoxMesh.new(), Vector3(0.46, 0.6, 0.26), Vector3(0, 1.22, 0), shirt)       # torso
	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.3
	_part(model, head, Vector3.ONE, Vector3(0, 1.68, 0), skin)
	_part(model, BoxMesh.new(), Vector3(0.3, 0.05, 0.3), Vector3(0, 1.8, 0), _mat("#151515"))  # hair
	for s in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.12 * s, 0.92, 0)
		model.add_child(hip)
		_part(hip, BoxMesh.new(), Vector3(0.17, 0.82, 0.2), Vector3(0, -0.42, 0), trousers)
		_part(hip, BoxMesh.new(), Vector3(0.18, 0.1, 0.3), Vector3(0, -0.86, -0.05), shoe)
		_legs.append(hip)
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.31 * s, 1.48, 0)
		model.add_child(shoulder)
		_part(shoulder, BoxMesh.new(), Vector3(0.12, 0.34, 0.14), Vector3(0, -0.17, 0), shirt)
		_part(shoulder, BoxMesh.new(), Vector3(0.1, 0.28, 0.11), Vector3(0, -0.48, 0), skin)
		_arms.append(shoulder)


func _mat(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 0.85
	return m


func _part(parent: Node3D, mesh: PrimitiveMesh, size: Vector3, pos: Vector3, mat: Material) -> void:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)


## Where the first-person camera sits (eyes).
func first_person_point() -> Vector3:
	var fwd := Basis(Vector3.UP, model.global_rotation.y) * Vector3.FORWARD
	return global_position + Vector3(0, 1.66, 0) + fwd * 0.12


func set_active(on: bool) -> void:
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	velocity = Vector3.ZERO
	# Leave no collider behind while seated in a car.
	collision_layer = 2 if on else 0


func _physics_process(delta: float) -> void:
	if not active:
		return
	var input := Input.get_vector("p3_left", "p3_right", "p3_forward", "p3_back")
	var cam_yaw: float = rig.look_yaw() if rig != null else 0.0
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0, input.y)
	var speed := SPRINT_SPEED if Input.is_action_pressed("p3_sprint") else WALK_SPEED
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, ACCEL * delta * speed)
	velocity.z = move_toward(velocity.z, target_v.z, ACCEL * delta * speed)
	if is_on_floor():
		if Input.is_action_just_pressed("p3_jump"):
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	# Facing: match the camera in first person, otherwise turn toward movement.
	var first: bool = rig != null and rig.is_first_person()
	if first:
		model.rotation.y = cam_yaw
	elif dir.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * TURN_SPEED, 0.0, 1.0))
	# Hide the body once the first-person blend has mostly finished (no clipping into the head).
	model.visible = not (first and rig._blend_t > 0.6)

	# Walk cycle.
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat_speed > 0.3:
		_phase += delta * flat_speed * 2.2
	else:
		_phase = lerpf(_phase, roundf(_phase / PI) * PI, clampf(delta * 8.0, 0.0, 1.0))
	var swing := sin(_phase) * clampf(flat_speed / SPRINT_SPEED, 0.0, 1.0) * 0.8
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		_legs[i].rotation.x = swing * s
		_arms[i].rotation.x = -swing * s * 0.8

	if global_position.y < -12.0:
		respawn()


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
