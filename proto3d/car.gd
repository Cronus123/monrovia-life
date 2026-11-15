extends RigidBody3D
## Raycast car: a 1.2 t rigid body held up by four spring/damper "wheels".
## Each wheel adds suspension force, tyre grip (sideways friction, limited by the
## load on that wheel) and engine/brake force, so the car has real weight transfer,
## body roll, grip vs. handbrake drift, and pushes or gets pushed in collisions.
## Forward is -Z. W/S throttle and brake/reverse, A/D steer, Space handbrake.
##
## Driven by the player (driven = true), by an AI `controller` (any object with
## drive_input(car) -> Vector3(throttle, steer, handbrake)), or parked.
## Damage from crashes and bullets sets it on fire at 100%; it explodes 4 s later.

signal exploded(car: RigidBody3D)
signal hit_person(car: RigidBody3D, person: Node, speed: float)
signal crashed(car: RigidBody3D, other: Node, impact: float)

const WHEELS := [Vector3(-0.82, 0.45, -1.35), Vector3(0.82, 0.45, -1.35),   # front L, R
		Vector3(-0.82, 0.45, 1.35), Vector3(0.82, 0.45, 1.35)]            # rear L, R
const REST := 0.42            # suspension travel (m)
const WHEEL_R := 0.36
const SPRING := 26000.0       # N/m per wheel
const DAMP := 2600.0          # N·s/m per wheel
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
const BURN_TIME := 4.0

@export var model_scene: PackedScene
var kind := "car"             # taxi, keke, car, suv, sport, truck, van, police
var driven := false
var controller: Object = null # AI driver
var speed := 0.0              # forward speed (m/s), for the HUD and tests
var steer := 0.0
var damage := 0.0             # 0..100, from crashes and bullets
var burning := -1.0           # seconds until the explosion while on fire, else < 0
var wrecked := false
var siren := false
var mission_tag := ""
var model: Node3D
var hit_area: Area3D
var _spawn := Transform3D()
var _upside_t := 0.0
var _still_t := 0.0
var _lights: Array[SpotLight3D] = []
var _fire: CPUParticles3D
var _beacon: MeshInstance3D
var _beacon_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	add_to_group("cars")
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
	if kind == "police":
		_add_beacon()
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


func condition() -> int:
	return int(clampf(100.0 - damage, 0.0, 100.0))


func _physics_process(delta: float) -> void:
	var fwd := -global_basis.z
	speed = linear_velocity.dot(fwd)
	_update_fire(delta)
	if _beacon != null and siren:
		var on := int(Time.get_ticks_msec() / 180) % 2 == 0
		_beacon_mats[0].emission_energy_multiplier = 3.0 if on else 0.2
		_beacon_mats[1].emission_energy_multiplier = 0.2 if on else 3.0
	var ai := controller != null and not driven and not wrecked
	# Parked and settled: let the physics engine put it to sleep (a hit wakes it up).
	if not driven and not ai:
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
	var handbrake := not driven and not ai
	if driven and not wrecked:
		throttle = Input.get_axis("p3_back", "p3_forward")
		steer_in = Input.get_axis("p3_right", "p3_left")
		handbrake = Input.is_action_pressed("p3_jump")
	elif ai:
		var inp: Vector3 = controller.drive_input(self)
		throttle = inp.x
		steer_in = inp.y
		handbrake = inp.z > 0.5
	if burning >= 0.0:
		throttle *= 0.4
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
	for i in 4:
		var front := i < 2
		var origin: Vector3 = global_transform * (WHEELS[i] as Vector3)
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (REST + WHEEL_R), 1 | 8, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
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
			if not b.is_down():
				hit_person.emit(self, b, v.length())
			b.knockdown(v * 0.8 + away * 2.0)
			damage = minf(100.0, damage + 1.0)
		else:
			b.push(away * 2.5)


func _on_body_entered(other: Node) -> void:
	var impact := linear_velocity.length()
	if other is RigidBody3D:
		impact = (linear_velocity - (other as RigidBody3D).linear_velocity).length()
	if impact > 6.0:
		apply_damage(impact * 0.8)
		crashed.emit(self, other, impact)


# ------------------------------------------------------------------ damage, fire, explosion
func apply_damage(amount: float) -> void:
	if wrecked:
		return
	damage = minf(100.0, damage + amount)
	if damage >= 100.0 and burning < 0.0:
		burning = BURN_TIME
		_start_fire()


func _start_fire() -> void:
	_fire = CPUParticles3D.new()
	_fire.amount = 40
	_fire.lifetime = 0.8
	_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fire.emission_box_extents = Vector3(0.6, 0.2, 1.2)
	_fire.direction = Vector3.UP
	_fire.spread = 15.0
	_fire.gravity = Vector3(0, 2, 0)
	_fire.initial_velocity_min = 1.5
	_fire.initial_velocity_max = 3.0
	_fire.scale_amount_min = 0.5
	_fire.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.55, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.1)
	q.material = m
	_fire.mesh = q
	_fire.position = Vector3(0, 1.3, -1.0)
	add_child(_fire)


func _update_fire(delta: float) -> void:
	if burning < 0.0 or wrecked:
		return
	burning -= delta
	if burning < 0.0:
		explode()


func explode() -> void:
	if wrecked:
		return
	wrecked = true
	burning = -1.0
	siren = false
	controller = null
	if _fire != null:
		_fire.emitting = false
	apply_central_impulse(Vector3(0, mass * 6.0, 0))
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 2.0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.13, 0.12, 0.11)
		dark.roughness = 1.0
		(mi as MeshInstance3D).material_override = dark
	set_headlights(false)
	exploded.emit(self)


# ------------------------------------------------------------------ lights
func set_headlights(on: bool) -> void:
	on = on and not wrecked and (driven or controller != null)
	if on and _lights.is_empty():
		for x in [-0.6, 0.6]:
			var l := SpotLight3D.new()
			l.position = Vector3(x, 0.8, -2.2)
			l.spot_range = 32.0
			l.spot_angle = 32.0
			l.light_energy = 2.2
			l.light_color = Color(1.0, 0.96, 0.85)
			add_child(l)
			_lights.append(l)
	for l in _lights:
		l.visible = on


func _add_beacon() -> void:
	_beacon = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.12, 0.25)
	_beacon.mesh = bm
	_beacon.position = Vector3(-0.32, 1.55, 0.2)
	add_child(_beacon)
	var blue := _beacon.duplicate() as MeshInstance3D
	blue.position.x = 0.32
	add_child(blue)
	for pair in [[_beacon, Color(1, 0.15, 0.2)], [blue, Color(0.2, 0.4, 1)]]:
		var m := StandardMaterial3D.new()
		m.albedo_color = pair[1]
		m.emission_enabled = true
		m.emission = pair[1]
		m.emission_energy_multiplier = 0.2
		(pair[0] as MeshInstance3D).material_override = m
		_beacon_mats.append(m)


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
