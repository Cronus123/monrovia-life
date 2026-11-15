extends SceneTree
## Windowed frame strip of the walk cycle: the player walking (fists), sprinting,
## crouch-walking and walking with a gun up, plus a pedestrian, 6 frames each, side on.
## Saves build/screens/walk_strip.png (one row per gait).
## Run: Godot.exe --path . --script res://tests/capture_walk.gd

const PlayerScript := preload("res://proto3d/player.gd")
const PedScript := preload("res://proto3d/pedestrian.gd")
const W := 260
const H := 300
const SHOTS := 6

var world: Node3D
var cam: Camera3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	world.add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	(cs.shape as BoxShape3D).size = Vector3(2000, 1, 40)
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	(mi.mesh as BoxMesh).size = Vector3(2000, 1, 40)
	ground.add_child(mi)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.current = true

	var rows: Array[Image] = []
	var pl = PlayerScript.new()
	world.add_child(pl)
	pl.global_position = Vector3(0, 0.1, 0)
	for _i in 20:
		await physics_frame
	for g in [["walk", false, false, false], ["sprint", true, false, false], ["crouch", false, true, false], ["gun up", false, false, true]]:
		rows.append(await _gait(pl, g[1], g[2], g[3]))
	pl.queue_free()
	var ped = PedScript.new()
	ped.setup(PackedVector3Array([Vector3(-300, 0.1, 0), Vector3(300, 0.1, 0)]), 0, 7)
	world.add_child(ped)
	ped.global_position = Vector3(-300, 0.1, 0)
	for _i in 60:
		await physics_frame
	rows.append(await _strip(func(): return ped.global_position))
	var out := Image.create(W * SHOTS, H * rows.size(), false, Image.FORMAT_RGB8)
	for r in rows.size():
		out.blit_rect(rows[r], Rect2i(0, 0, W * SHOTS, H), Vector2i(0, r * H))
	out.save_png(ProjectSettings.globalize_path("res://build/screens/walk_strip.png"))
	print("saved walk_strip.png")
	quit()


func _gait(pl, sprint: bool, crouch: bool, gun: bool) -> Image:
	pl.velocity = Vector3.ZERO
	if crouch:
		await _tap("p3_crouch")
	pl.arm_up = gun
	if sprint:
		Input.action_press("p3_sprint")
	Input.action_press("p3_right")
	for _i in 45:
		await physics_frame
	var img: Image = await _strip(func(): return pl.global_position)
	Input.action_release("p3_right")
	Input.action_release("p3_sprint")
	pl.arm_up = false
	if crouch:
		await _tap("p3_crouch")
	for _i in 30:
		await physics_frame
	return img


func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)


## SHOTS frames ~0.12 s apart, the camera side on and following the character.
func _strip(pos: Callable) -> Image:
	var row := Image.create(W * SHOTS, H, false, Image.FORMAT_RGB8)
	for s in SHOTS:
		for _i in 7:
			var p: Vector3 = pos.call()
			cam.global_transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.0, 5.2)).looking_at(p + Vector3(0, 0.85, 0))
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(W, H)
		row.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(s * W, 0))
	return row
