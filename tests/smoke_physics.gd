extends SceneTree
## Physics checks on a flat test ground (no city): per-vehicle tuning, the tyre grip
## curve, driving and cornering, crash damage (dents, broken lights, parts coming off,
## smoke), knocking over a lamp post and a bin, ragdolls and getting up, swimming and
## drowning, and climbing a low wall.
## Run: Godot.exe --headless --path . --script res://tests/smoke_physics.gd

const CarScript := preload("res://proto3d/car.gd")
const PlayerScript := preload("res://proto3d/player.gd")
const PedScript := preload("res://proto3d/pedestrian.gd")
const PropsScript := preload("res://proto3d/props.gd")
const MODELS := {"car": preload("res://proto3d/models/veh_car.glb"), "keke": preload("res://proto3d/models/veh_keke.glb"),
	"truck": preload("res://proto3d/models/veh_truck.glb")}

var failures := 0
var checks := 0
var world: Node3D


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("SMOKEPHYS CHECK FAILED: ", what)


func _initialize() -> void:
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(0, -0.5, 0), Vector3(600, 1, 600))          # ground
	_box(Vector3(0, 1.5, -150), Vector3(30, 3, 1))           # crash wall
	_box(Vector3(60, 0.6, 0), Vector3(4, 1.2, 4))            # low wall to climb
	run()


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	b.add_child(cs)
	b.position = at
	world.add_child(b)
	return b


func seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await physics_frame


func until(cond: Callable, max_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


class Driver:
	var inp := Vector3.ZERO
	func drive_input(_c) -> Vector3:
		return inp


func car(kind: String, at: Vector3, yaw: float = 0.0):
	var c = CarScript.new()
	c.kind = kind
	c.model_scene = MODELS.get(kind, MODELS["car"])
	world.add_child(c)
	c.reset_to(Transform3D(Basis(Vector3.UP, yaw), at))
	return c


func run() -> void:
	await physics_frame
	print("tuning")
	var k = car("keke", Vector3(-40, 0.6, 40))
	var t = car("truck", Vector3(-20, 0.6, 40))
	var c = car("car", Vector3(0, 0.6, 40))
	check(k.mass < c.mass and c.mass < t.mass, "keke lighter than a car, truck heavier (%.0f / %.0f / %.0f kg)" % [k.mass, c.mass, t.mass])
	check(float(k.tune["com"]) > float(c.tune["com"]) and float(k.tune["track"]) < float(c.tune["track"]), "keke is tippy (high centre of mass, narrow track)")
	check(CarScript._grip_curve(0.0) == 0.0 and CarScript._grip_curve(CarScript.PEAK_SLIP) > 0.99, "tyre grip rises to a peak at the peak slip angle")
	check(CarScript._grip_curve(0.6) < 0.9 and CarScript._grip_curve(0.6) >= 0.75, "and falls off when sliding")
	for x in [k, t]:
		x.queue_free()

	print("driving")
	var d := Driver.new()
	c.controller = d
	await seconds(0.5)
	d.inp = Vector3(1, 0, 0)
	await seconds(4.0)
	check(c.speed > 12.0, "car accelerates (%.1f m/s after 4 s)" % c.speed)
	var heading: float = c.global_rotation.y
	d.inp = Vector3(0.6, 1, 0)
	await seconds(1.5)
	check(absf(angle_difference(heading, c.global_rotation.y)) > 0.3, "car turns when steering")
	check(c.global_basis.y.y > 0.8, "and stays on its wheels")
	d.inp = Vector3(-1, 0, 0)
	await until(func(): return absf(c.speed) < 1.0, 6.0)
	check(absf(c.speed) < 1.5, "brakes to a stop")

	print("crash")
	c.queue_free()
	var cr = car("car", Vector3(0, 0.6, -100), 0.0)
	var dr := Driver.new()
	cr.controller = dr
	cr.set_headlights(true)
	await seconds(0.3)
	var verts_before := _vertex_sum(cr)
	cr.linear_velocity = Vector3(0, 0, -24)
	dr.inp = Vector3(1, 0, 0)
	await until(func(): return cr.damage > 0.0, 5.0)
	await seconds(0.5)
	check(cr.damage > 10.0, "crash into a wall damages the car (%.0f%%)" % cr.damage)
	check(not _vertex_sum(cr).is_equal_approx(verts_before), "the body is dented")
	check(cr.lights_broken, "the headlights break on a front hit")
	check(cr._detached >= 1, "a loose part comes off (%d)" % cr._detached)
	cr.apply_damage(50.0)
	check(cr._smoke != null, "a badly damaged engine smokes")
	cr.repair()
	check(cr.damage == 0.0 and not cr.lights_broken and cr._smoke == null, "the respray shop repairs everything")
	cr.queue_free()

	print("props")
	var tile := Node3D.new()
	world.add_child(tile)
	var meta := {"poles": [[100.0, 0.0, 100.0, 0.0]], "props": [[110.0, 0.0, 100.0, "bin", 0.0], [120.0, 0.0, 100.0, "stall", 0.0]]}
	var n: int = PropsScript.spawn(tile, meta, StandardMaterial3D.new(), StandardMaterial3D.new())
	check(n == 3 and tile.get_child_count() >= 6, "props spawn from tile data (pole, bin, stall parts)")
	var pole: RigidBody3D = tile.get_child(0)
	await seconds(0.3)
	check(pole.freeze, "a lamp post stands still until hit")
	var hitter = car("car", Vector3(100, 0.6, 115), 0.0)
	hitter.controller = Driver.new()
	await seconds(0.3)
	hitter.linear_velocity = Vector3(0, 0, -15)
	await until(func(): return not pole.freeze, 4.0)
	check(not pole.freeze, "a car knocks the lamp post over")
	check(hitter.linear_velocity.length() > 5.0, "and keeps going (%.1f m/s)" % hitter.linear_velocity.length())
	check(PropsScript.Prop.knocked_lamps.size() == 1, "the knocked lamp goes dark")
	var bin: RigidBody3D = tile.get_child(1)
	var bin_at := bin.global_position
	hitter.reset_to(Transform3D(Basis.IDENTITY, Vector3(110, 0.6, 112)))
	await seconds(0.2)
	hitter.linear_velocity = Vector3(0, 0, -12)
	await until(func(): return bin.global_position.distance_to(bin_at) > 1.0, 3.0)
	check(bin.global_position.distance_to(bin_at) > 1.0, "a bin gets knocked flying")
	hitter.queue_free()

	print("ragdoll")
	var ped = PedScript.new()
	ped.setup(PackedVector3Array([Vector3(-60, 0.1, -60), Vector3(-60, 0.1, -50)]), 0, 7)
	world.add_child(ped)
	ped.global_position = Vector3(-60, 0.1, -60)
	ped.set_physics_process(false)          # no wandering: just the knock-down
	ped.set_physics_process(true)
	await seconds(0.5)
	ped.knockdown(Vector3(7, 0, 0))
	await seconds(0.2)
	check(ped.body.is_ragdolling(), "a knocked-down person goes limp (ragdoll)")
	var rd = ped.body.ragdoll
	await seconds(1.0)
	check(rd.hips_position().distance_to(Vector3(-60, 0.1, -60)) > 0.8, "and is thrown by the hit")
	await until(func(): return not ped.is_down(), 8.0)
	check(not ped.body.is_ragdolling() and not rd.is_active(), "then blends back to animation and gets up")
	check(ped.global_position.distance_to(Vector3(-60, 0.1, -60)) > 0.5, "standing where the body landed")

	print("player")
	var pl = PlayerScript.new()
	world.add_child(pl)
	pl.spawn_point = Vector3(57.5, 0.1, 0)
	pl.global_position = pl.spawn_point
	await seconds(0.5)
	pl.model.rotation.y = -PI / 2           # face +X, the wall (no stick input: climbs the way it faces)
	Input.action_press("p3_jump")
	await physics_frame
	await physics_frame
	Input.action_release("p3_jump")
	await seconds(1.0)
	check(pl.global_position.y > 1.0, "the player climbs a 1.2 m wall (y %.2f)" % pl.global_position.y)
	# water: drop into a deep spot
	var drowned := [0.0]
	pl.drowning.connect(func(a: float): drowned[0] += a)
	_box(Vector3(-400, -2.6, -400), Vector3(30, 1, 30))       # seabed 2.1 m under the surface (off the ground slab)
	pl.global_position = Vector3(-400, -1.9, -400)
	pl.velocity = Vector3.ZERO
	await seconds(0.6)
	check(pl.swimming, "the player swims in deep water")
	check(pl.global_position.y > -1.6, "and floats with the head out")
	pl.breath = 0.2
	await seconds(1.0)
	check(drowned[0] > 0.0, "running out of breath hurts (drowning)")

	print("SMOKEPHYS %s (%d checks)" % ["TEST PASSED" if failures == 0 else "TEST FAILED", checks])
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)


func _vertex_sum(c) -> Vector3:
	var s := Vector3.ZERO
	for mi in c._parts:
		if not is_instance_valid(mi):
			continue
		var am := (mi as MeshInstance3D).mesh
		for i in am.get_surface_count():
			var arr: Array = am.surface_get_arrays(i)
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				s += v
	return s
