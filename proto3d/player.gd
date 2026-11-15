extends "res://proto3d/walker.gd"
## The on-foot player: camera-relative movement, sprint, jump with coyote time and a
## jump buffer, the get-in-car animation, and a first-person body that hides itself.
## Climbs onto low walls and ledges (jump facing one), swims in the sea and the river
## (slowly, with limited breath: stay out too long and you drown and wake in hospital).

signal drowning(amount: float)

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.8
const ACCEL := 26.0
const AIR_ACCEL := 7.0
const JUMP_SPEED := 5.2
const TURN_SPEED := 12.0
const COYOTE := 0.12
const JUMP_BUFFER := 0.15
const SEA_LEVEL := 0.0
const SWIM_SPEED := 2.3
const BREATH := 30.0           # seconds of swimming before drowning starts
const CLIMB_MIN := 0.7         # ledge heights the player can climb (m above the feet)
const CLIMB_MAX := 2.1

var rig                       # camera_rig.gd
var active := true            # false while driving
var model: Node3D             # the character (kept for camera/tests)
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true
var swimming := false
var breath := BREATH
var climbing := false
var aiming := false                # set by the weapons system (right mouse with a gun)
var arm_up := false                # gun arm raised (aiming or just fired; set by weapons.gd)
var _roll_t := 0.0
var _roll_dir := Vector3.ZERO
var _aim_blend := 0.0
const AIM_SPEED := 2.6             # walking while aiming
const ROLL_TIME := 0.7


func _ready() -> void:
	_setup_walker({"model": "Casual2_Male", "skin": "#5a3825", "shirt": "#c8173a", "pants": "#2b3a55", "hair": "#151210"})
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
	if climbing:
		return
	var input := Input.get_vector("p3_left", "p3_right", "p3_forward", "p3_back")
	var cam_yaw: float = rig.look_yaw() if rig != null else 0.0
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0, input.y)
	var speed := SPRINT_SPEED if Input.is_action_pressed("p3_sprint") else WALK_SPEED
	if aiming:
		speed = AIM_SPEED
	if _update_swim(delta, dir):
		return
	# Dodge roll: a quick burst along the stick (or forward), can't be interrupted.
	if _roll_t <= 0.0 and Input.is_action_just_pressed("p3_dodge") and is_on_floor() and not is_down():
		_roll_t = ROLL_TIME
		_roll_dir = dir.normalized() if dir.length() > 0.1 else Basis(Vector3.UP, model.rotation.y) * Vector3.FORWARD
		model.rotation.y = atan2(-_roll_dir.x, -_roll_dir.z)
		body.play("roll")
	if _roll_t > 0.0:
		_roll_t -= delta
		walk(_roll_dir * 6.5, 40.0, delta)
		body.set_speed(0.0)
		return
	# Jump at a wall: climb it if it's a low ledge.
	if Input.is_action_just_pressed("p3_jump") and is_on_floor() and not is_down() and _try_climb(dir):
		return

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
		if first or aiming:
			# aiming: face where the camera looks and strafe (walk sideways / backwards)
			model.rotation.y = lerp_angle(model.rotation.y, cam_yaw, clampf(delta * 18.0, 0.0, 1.0)) if aiming else cam_yaw
		elif dir.length() > 0.1:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * TURN_SPEED, 0.0, 1.0))
	# Hide the body once the first-person blend has mostly finished.
	model.visible = not (first and rig._blend_t > 0.6)
	body.set_speed(Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0)
	# the gun arm comes up when aiming (and a little while after a shot)
	_aim_blend = move_toward(_aim_blend, 1.0 if arm_up else 0.0, delta * 8.0)
	body.set_aim(_aim_blend)


## In deep water: float with the head out, swim slowly, use up breath. Returns true while
## swimming (the normal walking update is skipped).
func _update_swim(delta: float, dir: Vector3) -> bool:
	var depth := SEA_LEVEL - global_position.y
	var was := swimming
	swimming = depth > 1.25 and not is_down()
	if not swimming:
		if was:
			body.play("move")
		breath = minf(BREATH, breath + delta * 4.0)
		return false
	velocity.x = move_toward(velocity.x, dir.x * SWIM_SPEED, 6.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * SWIM_SPEED, 6.0 * delta)
	# buoyancy: hold the body so the head stays just above the surface
	var target_y := SEA_LEVEL - 1.35
	velocity.y = clampf((target_y - global_position.y) * 4.0, -3.0, 3.0)
	move_and_slide()
	if dir.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 6.0, 0.0, 1.0))
	body.set_speed(1.2 if dir.length() > 0.1 else 0.0)
	breath -= delta
	if breath < 0.0:
		drowning.emit(delta * 12.0)
	return true


## Climb a wall in front if its top is between CLIMB_MIN and CLIMB_MAX above the feet
## and there's room to stand on it.
func _try_climb(dir: Vector3) -> bool:
	var fwd := dir.normalized() if dir.length() > 0.1 else Basis(Vector3.UP, model.global_rotation.y) * Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized()
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 0.75, 1 | 8, [get_rid()])
	if space.intersect_ray(q).is_empty():
		return false                    # nothing to climb
	var top_from := global_position + fwd * 0.65 + Vector3(0, CLIMB_MAX + 0.4, 0)
	q = PhysicsRayQueryParameters3D.create(top_from, top_from - Vector3(0, CLIMB_MAX + 0.4 - CLIMB_MIN, 0), 1 | 8, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.7:
		return false
	var stand: Vector3 = hit.position + Vector3(0, 0.05, 0)
	if test_move(Transform3D(Basis.IDENTITY, stand + Vector3(0, 0.1, 0)), Vector3(0, 0.05, 0)):
		return false                    # no room up there
	climbing = true
	velocity = Vector3.ZERO
	model.rotation.y = atan2(-fwd.x, -fwd.z)
	body.play("jump")
	var up := Vector3(global_position.x, stand.y + 0.1, global_position.z)
	var tw := create_tween()
	tw.tween_property(self, "global_position", up, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "global_position", stand + Vector3(0, 0.05, 0), 0.2)
	tw.tween_callback(func():
		climbing = false
		body.play("move"))
	return true


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	breath = BREATH
	swimming = false
	climbing = false
