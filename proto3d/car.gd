extends CharacterBody3D
## Arcade car: simple, predictable handling that works the same on desktop and web.
## Forward is -Z. W/S throttle and brake/reverse, A/D steer, Space handbrake.

const MAX_SPEED := 26.0       # m/s (about 94 km/h)
const MAX_REVERSE := 7.0
const ACCEL := 9.0
const BRAKE := 22.0
const DRAG := 2.2
const STEER_RATE := 1.9       # rad/s at full lock and speed
const GRIP_TILT := 6.0

@export var model_scene: PackedScene
var driven := false
var speed := 0.0
var model: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _spawn := Transform3D()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(40)
	floor_snap_length = 0.6
	# A capsule lying along the car rides over kerbs and small terrain steps.
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.85
	cap.height = 4.3
	shape.shape = cap
	shape.rotation.x = PI / 2
	shape.position.y = 0.9
	add_child(shape)
	model = Node3D.new()
	add_child(model)
	if model_scene != null:
		var m := model_scene.instantiate() as Node3D
		m.rotation.y = PI / 2          # Blender models face +X; the car drives along -Z
		model.add_child(m)
	_spawn = global_transform


## Eye point for the close-up driving view: a hood camera just in front of the
## windscreen. (The low-poly cabins are solid blocks, so a true seat camera would see
## only the inside of the roof; a proper interior needs a modelled cockpit.)
func first_person_point() -> Vector3:
	return global_transform * Vector3(0.0, 1.32, -1.35)


## Where the player stands after getting out (driver's side).
func exit_point() -> Vector3:
	return global_transform * Vector3(-1.9, 0.3, 0.0)


func kmh() -> int:
	return int(absf(speed) * 3.6)


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var handbrake := false
	if driven:
		throttle = Input.get_axis("p3_back", "p3_forward")
		steer = Input.get_axis("p3_right", "p3_left")
		handbrake = Input.is_action_pressed("p3_jump")

	if throttle > 0.0:
		speed += (BRAKE if speed < 0.0 else ACCEL) * throttle * delta
	elif throttle < 0.0:
		speed -= (BRAKE if speed > 0.0 else ACCEL * 0.6) * -throttle * delta
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, BRAKE * 1.3 * delta)
	speed = clampf(speed, -MAX_REVERSE, MAX_SPEED)

	# Steering needs motion; it reverses when backing up.
	var turn := steer * STEER_RATE * clampf(speed / 5.0, -1.0, 1.0) * (1.4 if handbrake else 1.0)
	rotation.y += turn * delta

	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	# Lose speed when hitting walls or other cars.
	if get_slide_collision_count() > 0:
		var real := get_real_velocity()
		var along := Vector2(real.x, real.z).dot(Vector2(fwd.x, fwd.z))
		if absf(along) < absf(speed):
			speed = along

	# Tilt the body to the ground (ramps onto bridges) and lean a little in turns.
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	var local_n := global_basis.inverse() * n
	# Capped so seams in the road/terrain mesh can't tip the body over visibly.
	var pitch_t := clampf(atan2(local_n.z, local_n.y), -0.16, 0.16)   # nose up when the ground rises ahead (-Z)
	var roll_t := clampf(-atan2(local_n.x, local_n.y) - turn * 0.06, -0.16, 0.16)
	model.rotation.x = lerp_angle(model.rotation.x, pitch_t, clampf(delta * GRIP_TILT, 0.0, 1.0))
	model.rotation.z = lerp_angle(model.rotation.z, roll_t, clampf(delta * GRIP_TILT, 0.0, 1.0))

	if global_position.y < -12.0:
		global_transform = _spawn
		speed = 0.0
		velocity = Vector3.ZERO
