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
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.78
	shape.shape = cap
	shape.position.y = 0.89
	add_child(shape)
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
	knocked_t = KNOCK_TIME + GET_UP_TIME
	knocked.emit(impulse)
	velocity = impulse + Vector3(0, minf(4.5, impulse.length() * 0.35), 0)
	if impulse.length() > 0.5:
		body.rotation.y = atan2(impulse.x, impulse.z)   # face the car: falls on the back
	body.play("knocked")


## Hit by a bullet or a punch. Falls when out of health (and stays down a while).
func shot(damage: float, from_player: bool, from_pos: Vector3 = Vector3.ZERO) -> void:
	hp -= damage
	shot_by.emit(damage, from_player)
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
		if knocked_t <= GET_UP_TIME and body.current_state() == "knocked":
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


func _try_step(dir: Vector3) -> void:
	var up := Vector3(0, STEP_HEIGHT, 0)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, dir * 0.2):
		return
	global_position += up + dir * 0.12
	apply_floor_snap()
