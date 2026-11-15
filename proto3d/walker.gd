extends CharacterBody3D
## Shared on-foot physics for the player and pedestrians:
## gravity, smooth acceleration, stepping up curbs, pushback from cars,
## knock-down (thrown, lies on the ground, gets up) and out-of-world respawn.

signal knocked(impulse: Vector3)        # hit by a car (the player turns this into damage)
signal shot_by(damage: float, from_player: bool)

const CharacterScript := preload("res://proto3d/character.gd")
const STEP_HEIGHT := 0.36
const KNOCK_TIME := 1.4
var GET_UP_TIME := 1.2           # set from the character's fall animation

var body                        # character.gd
var spawn_point := Vector3.ZERO
var knocked_t := 0.0            # > 0 while down or getting up
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _push := Vector3.ZERO
var hp := 60.0


func _setup_walker(outfit: Dictionary) -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(48)
	# body: a capsule that stops 0.38 m above the feet...
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.4
	shape.shape = cap
	shape.position.y = 1.08
	add_child(shape)
	# ...standing on a separation ray: curbs, ramps, seams between road, sidewalk and tile
	# meshes and other small steps (up to ~0.4 m) are stepped over smoothly, not snagged on
	var feet := CollisionShape3D.new()
	var ray := SeparationRayShape3D.new()
	ray.length = 0.42
	ray.slide_on_slope = true
	feet.shape = ray
	feet.position.y = 0.42
	feet.rotation.x = PI / 2                       # the ray points down
	add_child(feet)
	body = CharacterScript.new()
	body.set_outfit(outfit)          # before adding: the outfit picks the model
	add_child(body)
	GET_UP_TIME = minf(body.get_up_time(), 1.4)


func is_down() -> bool:
	return knocked_t > 0.0


## Hit by a car: thrown along `impulse` (m/s), falls, then gets up.
func knockdown(impulse: Vector3) -> void:
	if knocked_t > GET_UP_TIME:
		return
	knocked.emit(impulse)
	velocity = impulse + Vector3(0, minf(4.5, impulse.length() * 0.35), 0)
	if body.start_ragdoll(velocity):
		knocked_t = KNOCK_TIME + GET_UP_TIME
		return
	knocked_t = KNOCK_TIME + GET_UP_TIME
	if impulse.length() > 0.5:
		body.rotation.y = atan2(impulse.x, impulse.z)   # face the car: falls on the back
	body.play("knocked")


## Hit by a bullet or a punch. Falls when out of health (and stays down a while).
func shot(damage: float, from_player: bool, from_pos: Vector3 = Vector3.ZERO) -> void:
	hp -= damage
	shot_by.emit(damage, from_player)
	if hp > 0.0 and knocked_t <= 0.0:
		body.play("hit")                     # flinch
	if hp <= 0.0 and knocked_t <= GET_UP_TIME:
		var away := global_position - from_pos
		away.y = 0.0
		knockdown(away.normalized() * 2.0 if from_pos != Vector3.ZERO else Vector3.ZERO)
		hp = 60.0


## Slow nudge from a car or another body.
func push(v: Vector3) -> void:
	_push = Vector3(v.x, 0, v.z)


## Move with `wish` (world-space horizontal velocity). Call from _physics_process.
func walk(wish: Vector3, accel: float, delta: float) -> void:
	if knocked_t > 0.0:
		knocked_t -= delta
		wish = Vector3.ZERO
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)
		if knocked_t <= GET_UP_TIME and body.is_ragdolling():
			_get_up_from_ragdoll()
		elif knocked_t <= GET_UP_TIME and body.current_state() == "knocked":
			body.play("get_up")
	else:
		velocity.x = move_toward(velocity.x, wish.x, accel * delta)
		velocity.z = move_toward(velocity.z, wish.z, accel * delta)
	velocity += _push
	_push = Vector3.ZERO
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var before := global_position
	move_and_slide()
	# Step up curbs and small ledges instead of sticking to them.
	var flat := Vector3(wish.x, 0, wish.z)
	if flat.length() > 0.5 and is_on_floor() and is_on_wall():
		var moved := (global_position - before)
		moved.y = 0.0
		if moved.length() < flat.length() * delta * 0.5:
			_try_step(flat.normalized())
	if global_position.y < -12.0:
		global_position = spawn_point
		velocity = Vector3.ZERO


## Move the (invisible) capsule to where the ragdoll came to rest, turn the body so the
## get-up animation starts lying the same way, then blend the pose into it.
func _get_up_from_ragdoll() -> void:
	var r: Array = body.end_ragdoll()
	if r.is_empty():
		return
	var hips: Vector3 = r[0]
	var head_dir: Vector3 = r[1]
	var to := Vector3(hips.x, global_position.y, hips.z)
	if not test_move(global_transform, to - global_position):
		global_position = to
	velocity = Vector3.ZERO
	if head_dir.length() > 0.1:
		body.global_rotation.y = atan2(head_dir.x, head_dir.z)
	body.blend_out_ragdoll(0.45)


func _try_step(dir: Vector3) -> void:
	var up := Vector3(0, STEP_HEIGHT, 0)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, dir * 0.2):
		return
	global_position += up + dir * 0.12
	apply_floor_snap()
