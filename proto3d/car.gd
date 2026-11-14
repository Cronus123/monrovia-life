extends RigidBody3D
## Raycast car: a 1.2 t rigid body held up by four spring/damper "wheels".
## Each wheel adds suspension force, tyre grip (sideways friction, limited by the
## load on that wheel) and engine/brake force, so the car has real weight transfer,
## body roll, grip vs. handbrake drift, and pushes or gets pushed in collisions.
## Forward is -Z. W/S throttle and brake/reverse, A/D steer, Space handbrake.

const WHEELS := [Vector3(-0.82, 0.45, -1.35), Vector3(0.82, 0.45, -1.35),   # front L, R
		Vector3(-0.82, 0.45, 1.35), Vector3(0.82, 0.45, 1.35)]            # rear L, R
const REST := 0.42            # suspension travel (m)
const WHEEL_R := 0.36
const SPRING := 26000.0       # N/m per wheel
const DAMP := 2600.0          # NÂ·s/m per wheel
const ENGINE := 8800.0        # N at the rear axle
const BRAKE := 11000.0        # N total
const MAX_SPEED := 31.0       # m/s (about 110 km/h)
const MAX_REVERSE := 8.0
const GRIP := 1.35            # tyre friction coefficient
const DRIFT_GRIP := 0.38      # rear grip with the handbrake on
const ROLLING := 45.0         # rolling resistance per wheel (N per m/s)
const AIR_DRAG := 0.95
const STEER_MAX := 0.55       # rad at walking pace
const STEER_MIN := 0.13       # rad at top speed
const STEER_RATE := 2.6       # rad/s the wheels turn

@export var model_scene: PackedScene
var driven := false
var speed := 0.0              # forward speed (m/s), for the HUD and tests
var steer := 0.0
var damage := 0.0             # 0..100, from crashes
var model: Node3D
var hit_area: Area3D
var _spawn := Transform3D()
var _upside_t := 0.0
var _still_t := 0.0


func _ready() -> void:
	mass = 1200.0
	collision_layer = 4
	collision_mask = 1 | 4 | 8          # world, cars, props (people are handled by hit_area)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.45, 0.1)
	angular_damp = 1.2
	linear_damp = 0.02
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.85, 0.8, 4.3)
	shape.shape = box
	shape.position.y = 0.75
	add_child(shape)
	var cabin := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1.6, 0.5, 2.2)
	cabin.shape = cbox
	cabin.position = Vector3(0, 1.4, 0.2)
	add_child(cabin)
	model = Node3D.new()
	model.position.y = -0.22           # wheels on the ground at the spring's rest load
	add_child(model)
	if model_scene != null:
		var m := model_scene.instantiate() as Node3D
		m.rotation.y = PI / 2          # Blender models face +X; the car drives along -Z
		model.add_child(m)
	# Detects people the car runs into (they aren't solid to the car).
	hit_area = Area3D.new()
	hit_area.collision_layer = 0
	hit_area.collision_mask = 2
	var hs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(2.1, 1.2, 4.7)
	hs.shape = hbox
	hs.position.y = 1.0
	hit_area.add_child(hs)
	add_child(hit_area)
	_spawn = global_transform


## Close-up driving view: a hood camera just in front of the windscreen.
func first_person_point() -> Vector3:
	return global_transform * Vector3(0.0, 1.1, -1.35)


## Where the player stands after getting out (driver's side).
func exit_point() -> Vector3:
	var p := global_transform * Vector3(-2.0, 0.6, 0.0)
	return Vector3(p.x, maxf(p.y, global_position.y + 0.3), p.z)


func kmh() -> int:
	return int(absf(speed) * 3.6)


func reset_to(t: Transform3D) -> void:
	_spawn = t
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var fwd := -global_basis.z
	speed = linear_velocity.dot(fwd)
	# Parked and settled: let the physics engine put it to sleep (a hit wakes it up).
	if not driven:
		if sleeping:
			return
		if linear_velocity.length() < 0.08 and angular_velocity.length() < 0.08:
			_still_t += delta
			if _still_t > 1.0:
				sleeping = true
				return
		else:
			_still_t = 0.0
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := not driven
	if driven:
		throttle = Input.get_axis("p3_back", "p3_forward")
		steer_in = Input.get_axis("p3_right", "p3_left")
		handbrake = Input.is_action_pressed("p3_jump")
	# Speed-sensitive steering, turned smoothly.
	var lock := lerpf(STEER_MAX, STEER_MIN, clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))
	steer = move_toward(steer, steer_in * lock, STEER_RATE * delta)

	# Throttle forward, or brake then reverse.
	var drive := 0.0
	var braking := 0.0
	if throttle > 0.0:
		if speed < -0.5:
			braking = BRAKE * throttle
		elif speed < MAX_SPEED:
			drive = ENGINE * throttle * (1.0 - 0.6 * clampf(speed / MAX_SPEED, 0.0, 1.0))
	elif throttle < 0.0:
		if speed > 0.5:
			braking = BRAKE * -throttle
		elif speed > -MAX_REVERSE:
			drive = ENGINE * 0.55 * throttle
	if handbrake:
		braking = maxf(braking, BRAKE * 0.6)

	var space := get_world_3d().direct_space_state
	var up := global_basis.y
	var grounded := 0
	for i in 4:
		var front := i < 2
		var origin: Vector3 = global_transform * (WHEELS[i] as Vector3)
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (REST + WHEEL_R), 1 | 8, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		grounded += 1
		var contact: Vector3 = hit.position
		var compression := (REST + WHEEL_R) - origin.distance_to(contact)
		var r := contact - global_position
		var pv := linear_velocity + angular_velocity.cross(r)
		var load := maxf(0.0, compression * SPRING - pv.dot(up) * DAMP)
		apply_force(up * load, r)
		# Tyre directions: the front wheels turn with the steering.
		var wheel_basis := global_basis * (Basis(Vector3.UP, steer) if front else Basis.IDENTITY)
		var wfwd := -wheel_basis.z
		var wside := wheel_basis.x
		# Forces act at axle height so cornering leans the body without flipping it.
		var at := r + up * 0.25
		var mu := DRIFT_GRIP if (handbrake and not front and driven) else GRIP
		var limit := mu * load
		var side_v := pv.dot(wside)
		var side_f := clampf(-side_v * mass * 0.25 / maxf(delta, 0.001) * 0.35, -limit, limit)
		var long_v := pv.dot(wfwd)
		var long_f := -long_v * ROLLING
		if not front:
			long_f += drive * 0.5
		if braking > 0.0 and absf(long_v) > 0.05:
			long_f -= signf(long_v) * braking * 0.25
		elif braking > 0.0:
			long_f -= long_v * mass * 0.25 / maxf(delta, 0.001) * 0.5   # hold still
		long_f = clampf(long_f, -limit, limit)
		apply_force(wside * side_f + wfwd * long_f, at)
	apply_central_force(-linear_velocity * linear_velocity.length() * AIR_DRAG)

	_hit_people()
	_recover(delta)


## People aren't solid to the car: fast hits knock them down, slow ones push them aside.
func _hit_people() -> void:
	var v := linear_velocity
	for b in hit_area.get_overlapping_bodies():
		if not b.has_method("knockdown"):
			continue
		var rel: Vector3 = b.global_position - global_position
		rel.y = 0.0
		var away := rel.normalized()
		if v.length() > 4.0 and v.dot(away) > 0.0:
			b.knockdown(v * 0.8 + away * 2.0)
			damage = minf(100.0, damage + 1.0)
		else:
			b.push(away * 2.5)


func _on_body_entered(other: Node) -> void:
	var impact := linear_velocity.length()
	if other is RigidBody3D:
		impact = (linear_velocity - (other as RigidBody3D).linear_velocity).length()
	if impact > 6.0:
		damage = minf(100.0, damage + impact * 0.8)


## Fell out of the world or stuck on the roof: put it back on its wheels.
func _recover(delta: float) -> void:
	if global_position.y < -12.0:
		reset_to(_spawn)
		return
	if global_basis.y.y < 0.35 and linear_velocity.length() < 2.0:
		_upside_t += delta
		if _upside_t > 2.5:
			_upside_t = 0.0
			var yaw := global_rotation.y
			reset_to(Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 1.2, 0)))
	else:
		_upside_t = 0.0
