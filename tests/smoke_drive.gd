extends SceneTree
## Driving check on a flat test ground with a kerb: each vehicle, driven like a player
## (key actions), does a lap: full throttle down a straight, a left and a right turn,
## a kerb hop at speed, braking to a stop, reversing, and a handbrake slide that must
## recover. Fails if it flips, gets stuck, can't reach a reasonable top speed or keeps
## spinning after the handbrake is released.
## Run: Godot.exe --headless --path . --script res://tests/smoke_drive.gd  [-- --verbose-drive]

const CarScript := preload("res://proto3d/car.gd")
const KINDS := {"car": preload("res://proto3d/models/veh_car.glb"), "taxi": preload("res://proto3d/models/veh_taxi.glb"),
	"sport": preload("res://proto3d/models/veh_sport.glb"), "suv": preload("res://proto3d/models/veh_suv.glb"),
	"pickup": preload("res://proto3d/models/veh_pickup.glb"), "keke": preload("res://proto3d/models/veh_keke.glb"),
	"truck": preload("res://proto3d/models/veh_truck.glb")}
const ACTIONS := ["p3_forward", "p3_back", "p3_left", "p3_right", "p3_jump"]

var failures := 0
var checks := 0
var world: Node3D
var verbose := false
var car
var min_up := 1.0
var top := 0.0
var peak_yaw := 0.0


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("SMOKEDRIVE CHECK FAILED: ", what)


func _initialize() -> void:
	verbose = "--verbose-drive" in OS.get_cmdline_user_args()
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(0, -0.5, 0), Vector3(3000, 1, 3000))
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


func hold(actions: Array, t: float) -> void:
	for a in ACTIONS:
		if a in actions:
			Input.action_press(a)
		else:
			Input.action_release(a)
	var n := int(t * 60.0)
	for i in n:
		await physics_frame
		if is_instance_valid(car):
			min_up = minf(min_up, car.global_basis.y.y)
			top = maxf(top, car.speed)
			peak_yaw = maxf(peak_yaw, absf(car.angular_velocity.y))


func lap(kind: String, origin: Vector3) -> void:
	car = CarScript.new()
	car.kind = kind
	car.model_scene = KINDS[kind]
	world.add_child(car)
	car.reset_to(Transform3D(Basis.IDENTITY, origin + Vector3(0, 0.6, 0)))
	car.driven = true
	await hold([], 1.0)
	min_up = 1.0
	top = 0.0
	var vmax: float = car.tune["vmax"]
	var start: Vector3 = car.global_position
	# 1. straight, full throttle
	await hold(["p3_forward"], 9.0)
	var top_straight := top
	# 2. a left turn and a right turn, part throttle (slalom-ish)
	await hold(["p3_forward", "p3_left"], 2.0)
	await hold(["p3_forward"], 1.0)
	await hold(["p3_forward", "p3_right"], 2.0)
	await hold(["p3_forward"], 1.5)
	# 3. kerb hop: a 15 cm kerb strip laid across the car's path, at speed
	var fw: Vector3 = -car.global_basis.z
	fw.y = 0.0
	fw = fw.normalized()
	var kerb := _box(car.global_position + fw * 25.0 + Vector3(0, 0.075, 0), Vector3(40, 0.15, 1.2))
	kerb.look_at(kerb.global_position + fw.cross(Vector3.UP), Vector3.UP)
	await hold(["p3_forward"], 2.5)
	var after_kerb_up: float = car.global_basis.y.y
	# 4. brake to a stop, then reverse
	var brake_from: float = car.speed
	var stopped_speed: float = absf(car.speed)
	var stop_t := 0.0
	while stop_t < 5.0 and car.speed > 0.8:
		await hold(["p3_back"], 1.0 / 60.0)
		stop_t += 1.0 / 60.0
		stopped_speed = minf(stopped_speed, absf(car.speed))
	if verbose:
		print("    %s: braked from %.1f m/s in %.1f s" % [kind, brake_from, stop_t])
	await hold(["p3_back"], 3.0)
	var rev: float = car.speed
	await hold([], 1.5)
	# 5. handbrake slide at speed, then let go: it should straighten out by itself
	await hold(["p3_forward"], 4.0)
	peak_yaw = 0.0
	await hold(["p3_forward", "p3_left", "p3_jump"], 1.2)
	var slide_yaw := peak_yaw
	await hold(["p3_forward"], 2.0)
	var spin: float = absf(car.angular_velocity.y)
	var moved: float = car.global_position.distance_to(start)
	await hold([], 0.1)
	if verbose:
		print("    %s: top %.1f / vmax %.1f, min up %.2f, after kerb %.2f, stop %.2f, reverse %.1f, spin %.2f (slide %.2f), moved %.0f" %
			[kind, top_straight, vmax, min_up, after_kerb_up, stopped_speed, rev, spin, slide_yaw, moved])
	check(min_up > 0.55, "%s: never rolls over (lowest up %.2f)" % [kind, min_up])
	check(top_straight > minf(vmax * 0.75, 24.0) and top_straight < vmax * 1.08,
		"%s: reasonable top speed (%.0f km/h, limit %.0f)" % [kind, top_straight * 3.6, vmax * 3.6])
	check(after_kerb_up > 0.8, "%s: lands a kerb hop on its wheels (up %.2f)" % [kind, after_kerb_up])
	check(stopped_speed < 1.5, "%s: brakes to a stop (%.1f m/s)" % [kind, stopped_speed])
	check(rev < -1.5, "%s: then reverses (%.1f m/s)" % [kind, rev])
	check(slide_yaw > 0.5, "%s: the handbrake turns it into a slide (yaw rate %.2f rad/s)" % [kind, slide_yaw])
	check(spin < 0.6, "%s: the handbrake slide recovers (yaw rate %.2f rad/s)" % [kind, spin])
	check(moved > 150.0, "%s: never stuck (%.0f m round the lap)" % [kind, moved])
	car.queue_free()
	kerb.queue_free()
	await hold([], 0.1)


func run() -> void:
	await process_frame
	var x := -1200.0
	for kind in KINDS:
		await lap(kind, Vector3(x, 0, 1200))
		x += 350.0
	for a in ACTIONS:
		Input.action_release(a)
	print("auto-right")
	car = CarScript.new()
	car.kind = "car"
	car.model_scene = KINDS["car"]
	world.add_child(car)
	car.reset_to(Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0, 1.5, -1200)))   # on its roof
	car.driven = true
	var t := 0.0
	while t < 6.0 and car.global_basis.y.y < 0.8:
		await physics_frame
		t += 1.0 / 60.0
	check(car.global_basis.y.y > 0.8 and t > 2.5 and t < 4.5, "a car left on its roof rights itself after about 3 s (%.1f s)" % t)
	car.queue_free()
	world.queue_free()
	await process_frame
	if failures == 0:
		print("SMOKEDRIVE TEST PASSED (%d checks)" % checks)
	else:
		print("SMOKEDRIVE TEST FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures > 0 else 0)
