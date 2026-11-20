extends SceneTree
## Playtest sweep (windowed, not part of tools/check.ps1): walks the main flows and saves a
## screenshot of each to build/screens/sweep/<tag>/ for a person to look over:
## title, sign-in panel, settings on the title, new game + tutorial, walking, driving, a
## mission, the pause menu, settings in game, save and load (Continue).
## Saves go to tests/output/sweep, never to the player's real save.
## Run:  Godot.exe --path . --resolution 844x390 --script res://tests/sweep_playtest.gd -- --device=phone --tag=phone

const OUT := "res://tests/output/sweep"

var title
var city
var tag := "desktop"
var shots := ""
var notes: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	shots = "res://build/screens/sweep/" + tag
	DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute(OUT)
	title = load("res://proto3d/title.tscn").instantiate()
	root.add_child(title)
	run()


func seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func until(cond: Callable, max_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func snap(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(shots + "/" + name + ".png"))
	print("SWEEP shot ", name)


func note(ok: bool, what: String) -> void:
	print("SWEEP %s %s" % ["ok  " if ok else "BAD ", what])
	if not ok:
		notes.append(what)


func hold(action: String, t: float) -> void:
	Input.action_press(action)
	await seconds(t)
	Input.action_release(action)


func run() -> void:
	await process_frame
	while title.city == null:
		await process_frame
	city = title.city
	if DeviceProfile.is_handheld():
		InputMode.set_scheme(2)                   # Touch: show the on-screen controls
	city.save_path = OUT + "/save.json"
	city.bug_report.dir_root = OUT + "/bug_reports"
	if FileAccess.file_exists(city.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(city.save_path))
	print("SWEEP device %s, canvas %s, window %s, input %s" % [DeviceProfile.kind, root.get_visible_rect().size,
		DisplayServer.window_get_size(), InputMode.NAMES[InputMode.active]])
	await seconds(0.3)
	await snap("01_title_loading")
	note(await until(func(): return city.ready_done, 150.0), "city loads behind the title")
	city.state.time_min = 16.5 * 60.0
	city.clock.advance(0.0)
	await seconds(4.0)
	await snap("02_title")
	var last: Control = title._buttons[-1]
	note(last.get_global_rect().end.y <= root.get_visible_rect().size.y - 36.0, "title menu clear of the credit line (last button ends at %.0f of %.0f)" % [last.get_global_rect().end.y, root.get_visible_rect().size.y])
	title._on_account()
	await seconds(0.5)
	await snap("03_sign_in")
	title.account.close()
	await seconds(0.3)
	title._on_settings()
	await seconds(0.4)
	await snap("04_settings_title")
	city.settings_menu.close()
	await seconds(0.3)
	note(title._menu.visible, "back on the title menu after settings")
	city.settings.tutorial = true
	title._on_new_game()
	await until(func(): return not city._busy and not city.title_mode, 60.0)
	await seconds(3.0)
	await snap("05_tutorial")
	note(city.tutorial.active, "tutorial running")
	await hold("p3_forward", 2.0)
	await snap("06_walking")
	city.player.global_position = city.tutorial._at + Vector3(0, 0.3, 0)
	await seconds(1.0)
	city.enter_car(city.start_car)
	await seconds(1.0)
	Input.action_press("p3_forward")
	await seconds(3.0)
	await snap("07_driving")
	Input.action_release("p3_forward")
	await hold("p3_jump", 2.0)                     # handbrake to a stop before getting out
	note(city.car.linear_velocity.length() < 1.0, "stopped (%.1f m/s)" % city.car.linear_velocity.length())
	city.exit_car()
	await seconds(1.0)
	city.tutorial.skip()
	city.missions.start(0)
	await seconds(2.0)
	await snap("08_mission")
	note(city.missions.active(), "mission 1 started: %s" % city.missions.objective())
	city._pause_menu()
	await seconds(0.4)
	await snap("09_pause")
	city.hud.close_menu()
	paused = false
	city.open_settings(func(): pass)
	await seconds(0.4)
	await snap("10_settings_game")
	city.settings_menu.close()
	await seconds(0.3)
	var hp0: float = city.state.health
	city.state.money += 123
	var money: int = city.state.money
	city.save_game()
	note(FileAccess.file_exists(city.save_path), "save written")
	city.state.money = 0
	print("SWEEP hp before load %.0f" % city.state.health)
	city.continue_game()
	await until(func(): return not city._busy, 60.0)
	await seconds(1.5)
	note(city.state.money == money, "load restores the money (%d)" % city.state.money)
	note(city.state.health >= hp0 - 0.5, "loading doesn't cost health (%.0f -> %.0f)" % [hp0, city.state.health])
	await snap("11_after_load")
	print("SWEEP DONE %s: %d notes %s" % [tag, notes.size(), str(notes)])
	quit(0)
