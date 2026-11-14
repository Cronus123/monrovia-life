extends "res://proto3d/walker.gd"
## The on-foot player: camera-relative movement, sprint, jump with coyote time and a
## jump buffer, the get-in-car animation, and a first-person body that hides itself.

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.8
const ACCEL := 26.0
const AIR_ACCEL := 7.0
const JUMP_SPEED := 5.2
const TURN_SPEED := 12.0
const COYOTE := 0.12
const JUMP_BUFFER := 0.15

var rig                       # camera_rig.gd
var active := true            # false while driving
var model: Node3D             # the character (kept for camera/tests)
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true


func _ready() -> void:
	_setup_walker({"skin": "#5a3825", "shirt": "#c8173a", "trousers": "#2b3a55", "shoes": "#1b1b1b", "hair": "#151210"})
	model = body


## Where the first-person camera sits (eyes).
func first_person_point() -> Vector3:
	var fwd := Basis(Vector3.UP, model.global_rotation.y) * Vector3.FORWARD
	return global_position + Vector3(0, 1.66, 0) + fwd * 0.12


func set_active(on: bool) -> void:
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	velocity = Vector3.ZERO
	collision_layer = 2 if on else 0
	if on:
		body.play("move")


func _physics_process(delta: float) -> void:
	if not active:
		return
	var input := Input.get_vector("p3_left", "p3_right", "p3_forward", "p3_back")
	var cam_yaw: float = rig.look_yaw() if rig != null else 0.0
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0, input.y)
	var speed := SPRINT_SPEED if Input.is_action_pressed("p3_sprint") else WALK_SPEED

	# Jump with coyote time (just walked off an edge) and a short input buffer.
	_coyote = COYOTE if is_on_floor() else _coyote - delta
	_jump_buffer = JUMP_BUFFER if Input.is_action_just_pressed("p3_jump") else _jump_buffer - delta
	if _jump_buffer > 0.0 and _coyote > 0.0 and not is_down():
		velocity.y = JUMP_SPEED
		_jump_buffer = 0.0
		_coyote = 0.0
		body.play("jump")

	walk(dir * speed, (ACCEL if is_on_floor() else AIR_ACCEL), delta)

	if is_on_floor() and not _was_on_floor and body.current_state() == "jump":
		body.play("move")
	_was_on_floor = is_on_floor()

	# Facing: match the camera in first person, otherwise turn toward movement.
	var first: bool = rig != null and rig.is_first_person()
	if not is_down():
		if first:
			model.rotation.y = cam_yaw
		elif dir.length() > 0.1:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * TURN_SPEED, 0.0, 1.0))
	# Hide the body once the first-person blend has mostly finished.
	model.visible = not (first and rig._blend_t > 0.6)
	body.set_speed(Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0)


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
