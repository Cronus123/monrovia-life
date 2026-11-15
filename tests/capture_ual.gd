extends SceneTree
## Windowed check of the retargeted Universal Animation Library: a row of our characters,
## each frozen mid-way through one animation, saved to build/screens/ual_poses.png.
## Run: Godot.exe --path . --script res://tests/capture_ual.gd

const SHOW := [["Idle", 0.5], ["Walk", 0.3], ["Jog_Fwd", 0.25], ["Sprint", 0.2], ["Crouch_Idle", 0.5], ["Crouch_Fwd", 0.3],
	["Pistol_Aim_Neutral", 0.1], ["Pistol_Reload", 0.6], ["Punch_Cross", 0.25], ["Hit_Chest", 0.2], ["Swim_Fwd", 0.3], ["Sitting_Enter", 9.0]]


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var lib: AnimationLibrary = load("res://proto3d/models/people/ual_anims.res")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	root.add_child(sun)
	var models := ["Casual2_Male", "Casual_Female", "OldClassy_Male"]
	var chars := []
	for i in SHOW.size():
		var c = load("res://proto3d/character.gd").new()
		c.set_outfit({"model": models[i % 3]})
		root.add_child(c)
		c.position = Vector3(i * 1.3 - SHOW.size() * 0.65, 0, 0)
		chars.append(c)
	await process_frame
	for i in SHOW.size():
		var c = chars[i]
		c.tree.active = false
		var ap: AnimationPlayer = c.anim_player
		ap.add_animation_library("ual", lib)
		var nm := "ual/" + String(SHOW[i][0])
		ap.play(nm)
		ap.seek(minf(float(SHOW[i][1]), ap.get_animation(nm).length - 0.01), true)
		ap.pause()
		var l := Label3D.new()
		l.text = String(SHOW[i][0])
		l.pixel_size = 0.004
		l.position = Vector3(0, 2.1, 0)
		c.add_child(l)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.2, -8.6)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.fov = 50
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/screens/ual_poses.png"))
	print("saved")
	quit()
