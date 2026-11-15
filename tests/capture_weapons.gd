extends SceneTree
## Windowed screenshots of the weapons (build/screens/wpn_*.png): the weapon wheel, aiming
## each gun over the shoulder, firing the SMG, a bat swing, and the dodge roll.
## Run: Godot.exe --path . --script res://tests/capture_weapons.gd

const OUT := "res://build/screens"
var m


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func seconds(t: float) -> void:
	await create_timer(t, true, false, true).timeout


func until(cond: Callable, max_s: float) -> void:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func snap(name: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/wpn_" + name + ".png"))
	printerr("saved ", name)


func run() -> void:
	await until(func(): return m.ready_done, 90.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var st: GameState = m.state
	st.time_min = 10.5 * 60.0
	st.rain_until = -1.0
	for w in [GameState.PISTOL, GameState.BAT, GameState.MACHETE, GameState.SMG, GameState.SHOTGUN]:
		st.give_weapon(w, 60)
	st.select_weapon(GameState.SMG)
	await seconds(2.0)
	# the wheel
	Input.action_press("p3_wheel")
	await seconds(0.3)
	m.wheel.selected = GameState.SHOTGUN
	m.wheel.queue_redraw()
	await seconds(0.2)
	await snap("wheel")
	Input.action_release("p3_wheel")
	await seconds(0.3)
	# aiming each gun (over the shoulder), facing down the street
	m.rig.yaw = m.player.model.rotation.y
	for w in [GameState.PISTOL, GameState.SMG, GameState.SHOTGUN]:
		st.select_weapon(w)
		Input.action_press("p3_aim")
		await seconds(0.8)
		await snap("aim_" + String(m.weapons.defs[w]["id"]))
		if w == GameState.SMG:
			var p: Vector3 = m.player.global_position
			var f: Vector3 = Basis(Vector3.UP, m.player.model.rotation.y) * Vector3.FORWARD
			var r: Vector3 = Basis(Vector3.UP, m.player.model.rotation.y) * Vector3.RIGHT
			m.rig.process_mode = Node.PROCESS_MODE_DISABLED
			m.rig.cam.global_transform = Transform3D(Basis.IDENTITY, p + r * 2.6 + f * 1.4 + Vector3(0, 1.6, 0)).looking_at(p + Vector3(0, 1.2, 0) + f * 0.3)
			await seconds(0.3)
			await snap("aim_side")
			m.rig.process_mode = Node.PROCESS_MODE_INHERIT
	# firing the SMG while aiming
	st.select_weapon(GameState.SMG)
	await seconds(0.5)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("p3_fire")
	await seconds(0.32)
	await snap("fire_smg")
	Input.action_release("p3_fire")
	Input.action_release("p3_aim")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await seconds(0.6)
	# reload
	st.select_weapon(GameState.PISTOL)
	st.clip[GameState.PISTOL] = 2
	m.weapons.start_reload()
	await seconds(0.55)
	await snap("reload")
	await seconds(1.0)
	# bat swing, from the side
	st.select_weapon(GameState.BAT)
	await seconds(0.3)
	m.rig.yaw = m.player.model.rotation.y + PI / 2
	await seconds(0.6)
	m.weapons._cd = 0.0
	m.weapons._trigger_down = false
	m.weapons.try_fire()
	await seconds(0.32)
	await snap("swing_bat")
	# crouched, aiming the pistol, seen from the side
	await seconds(1.5)
	st.select_weapon(GameState.PISTOL)
	m.player.crouching = true
	m.player.body.set_stance("crouch")
	Input.action_press("p3_aim")
	await seconds(0.8)
	var pp: Vector3 = m.player.global_position
	var ff: Vector3 = Basis(Vector3.UP, m.player.model.rotation.y) * Vector3.FORWARD
	var rr: Vector3 = Basis(Vector3.UP, m.player.model.rotation.y) * Vector3.RIGHT
	m.rig.process_mode = Node.PROCESS_MODE_DISABLED
	m.rig.cam.global_transform = Transform3D(Basis.IDENTITY, pp + rr * 2.8 + ff * 1.2 + Vector3(0, 1.2, 0)).looking_at(pp + Vector3(0, 0.8, 0) + ff * 0.3)
	await seconds(0.3)
	await snap("crouch_aim")
	m.rig.process_mode = Node.PROCESS_MODE_INHERIT
	Input.action_release("p3_aim")
	m.player.crouching = false
	m.player.body.set_stance("stand")
	await seconds(0.5)
	# dodge roll
	await seconds(0.8)
	Input.action_press("p3_dodge")
	await process_frame
	await process_frame
	Input.action_release("p3_dodge")
	await seconds(0.3)
	await snap("roll")
	m.queue_free()
	await seconds(1.0)
	quit()
