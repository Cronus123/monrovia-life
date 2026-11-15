extends SceneTree
## Leg animation check: the player walks, sprints and crouch-walks on flat ground and on a
## slope, with fists and with each gun up, and the thigh / shin / foot bones must swing.
## A pedestrian walking must swing its legs too. Fails if the legs stay still while moving.
## Run: Godot.exe --headless --path . --script res://tests/smoke_legs.gd

const PlayerScript := preload("res://proto3d/player.gd")
const PedScript := preload("res://proto3d/pedestrian.gd")
const LEGS := ["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R"]

var failures := 0
var checks := 0
var world: Node3D
var verbose := false


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("SMOKELEGS CHECK FAILED: ", what)


func _initialize() -> void:
	verbose = "--verbose-legs" in OS.get_cmdline_user_args()
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(0, -0.5, 0), Vector3(400, 1, 400), Vector3.ZERO)
	# a 10 degree street slope, and a 15 cm curb
	_box(Vector3(120, -0.5, 0), Vector3(60, 1, 60), Vector3(0, 0, deg_to_rad(10)))
	_box(Vector3(-40, 0.075, 0), Vector3(20, 0.15, 40), Vector3.ZERO)
	run()


func _box(at: Vector3, size: Vector3, rot: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	b.add_child(cs)
	b.position = at
	b.rotation = rot
	world.add_child(b)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## Largest change (radians) of any leg bone's pose over ~1 second of samples.
func leg_swing(c) -> Dictionary:
	var sk: Skeleton3D = c.skeleton
	var first := {}
	var most := {}
	for b in LEGS:
		var i := sk.find_bone(b)
		first[b] = sk.get_bone_global_pose(i).basis.get_rotation_quaternion()
		most[b] = 0.0
	for k in 30:
		await frames(2)
		for b in LEGS:
			var q: Quaternion = sk.get_bone_global_pose(sk.find_bone(b)).basis.get_rotation_quaternion()
			most[b] = maxf(most[b], (first[b] as Quaternion).angle_to(q))
	return most


func walk_case(pl, label: String, at: Vector3, sprint: bool, crouch: bool, slot: int) -> void:
	pl.global_position = at
	pl.velocity = Vector3.ZERO
	await frames(10)
	if crouch:
		Input.action_press("p3_crouch")
		await frames(2)
		Input.action_release("p3_crouch")
	pl.arm_up = slot > 0
	if sprint:
		Input.action_press("p3_sprint")
	Input.action_press("p3_forward")
	await frames(40)
	var spd := Vector2(pl.velocity.x, pl.velocity.z).length()
	var swing: Dictionary = await leg_swing(pl.body)
	Input.action_release("p3_forward")
	Input.action_release("p3_sprint")
	if crouch:
		Input.action_press("p3_crouch")
		await frames(2)
		Input.action_release("p3_crouch")
	pl.arm_up = false
	var thigh := maxf(swing["UpperLeg.L"], swing["UpperLeg.R"])
	var shin := maxf(swing["LowerLeg.L"], swing["LowerLeg.R"])
	var foot := maxf(swing["Foot.L"], swing["Foot.R"])
	if verbose:
		print("    %s: state %s aim %.2f stance %s speed %.2f floor %s blend %.2f thigh %.2f shin %.2f foot %.2f" % [label, pl.body.current_state(), pl.body.tree.get("parameters/move/aim/blend_amount"), pl.body.tree.get("parameters/move/stance/current_state"), spd, pl.is_on_floor(),
			pl.body.tree.get("parameters/move/blend/blend_position"), thigh, shin, foot])
	check(spd > 0.8, "%s: the player moves (%.1f m/s)" % [label, spd])
	check(thigh > 0.25 and shin > 0.15 and foot > 0.15,
		"%s: the legs swing (thigh %.2f, shin %.2f, foot %.2f rad)" % [label, thigh, shin, foot])
	await frames(30)


func run() -> void:
	await process_frame
	var pl = PlayerScript.new()
	world.add_child(pl)
	pl.spawn_point = Vector3(0, 0.1, 0)
	pl.global_position = pl.spawn_point
	await frames(30)
	pl.model.rotation.y = 0.0
	print("player")
	await walk_case(pl, "walk", Vector3(0, 0.1, 60), false, false, 0)
	await walk_case(pl, "sprint", Vector3(20, 0.1, 60), true, false, 0)
	await walk_case(pl, "crouch-walk", Vector3(40, 0.1, 60), false, true, 0)
	await walk_case(pl, "walk, gun up", Vector3(60, 0.1, 60), false, false, 1)
	await walk_case(pl, "sprint, gun up", Vector3(80, 0.1, 60), true, false, 1)
	await walk_case(pl, "walk uphill", Vector3(110, 3.0, 20), false, false, 0)
	await walk_case(pl, "walk over a curb", Vector3(-40, 0.3, 18), false, false, 0)
	await walk_case(pl, "walk again, fists", Vector3(-100, 0.1, 60), false, false, 0)

	print("pedestrian")
	var ped = PedScript.new()
	ped.setup(PackedVector3Array([Vector3(-80, 0.1, -60), Vector3(-80, 0.1, 60)]), 0, 7)
	world.add_child(ped)
	ped.global_position = Vector3(-80, 0.1, 0)
	await frames(20)
	var swing: Dictionary = {}
	var spd := 0.0
	for k in 3:
		swing = await leg_swing(ped.body)
		spd = Vector2(ped.velocity.x, ped.velocity.z).length()
		if spd > 0.5:
			break
	var thigh := maxf(swing["UpperLeg.L"], swing["UpperLeg.R"])
	if verbose:
		print("    ped: speed %.2f thigh %.2f" % [spd, thigh])
	check(spd > 0.5, "the pedestrian walks its path (%.1f m/s)" % spd)
	check(thigh > 0.25, "a walking pedestrian swings its legs (speed %.1f, thigh %.2f)" % [spd, thigh])

	world.queue_free()
	await frames(5)
	if failures == 0:
		print("SMOKELEGS TEST PASSED (%d checks)" % checks)
	else:
		print("SMOKELEGS TEST FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures > 0 else 0)
