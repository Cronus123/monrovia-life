extends SceneTree
## Playtest build checks: the title screen (menu, version, controls, credits with the OSM
## credit, the flyover), starting a new game from it, every step of the "Welcome to
## Monrovia" tutorial (walk, taxi, drive, buy, bat, dummy, weapon wheel, rest and save),
## the pause menu, and the F8 bug report (files written, nothing else).
## Saves and reports go to tests/output, never to the player's real save.
## Run: Godot.exe --headless --path . --script res://tests/smoke_playtest.gd

const OUT := "res://tests/output/playtest"

var failures := 0
var checks := 0
var title
var city


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("SMOKEPLAY CHECK FAILED: ", what)


func _initialize() -> void:
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


func run() -> void:
	await process_frame
	while title.city == null:              # the title loads the city after drawing its menu
		await process_frame
	city = title.city
	city.save_path = OUT + "/save.json"
	city.bug_report.dir_root = OUT + "/bug_reports"
	print("fast start")
	check(title._menu.visible and title.backdrop.visible and not city.ready_done,
		"the menu shows before the city has loaded, over the skyline backdrop")
	check(title._account_label.text.contains("guest") and title._account_button.text == "Sign in / Create account",
		"guest play by default, with Sign in / Create account offered")
	title._on_new_game()
	check(title._pending == 0 and title._wait_box.visible and city.title_mode,
		"New Game before the city is ready waits, with a progress bar (%s)" % title._wait_label.text)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	title._unhandled_input(esc)
	check(title._pending == -1 and not title._wait_box.visible, "Esc / B cancels the wait")
	print("title screen")
	# the Windows City export uses the "city3d" feature tag, which overrides the main scene
	var cfg := ConfigFile.new()
	cfg.load("res://project.godot")
	check(String(cfg.get_value("application", "run/main_scene")) == "res://proto3d/title.tscn" \
		and String(cfg.get_value("application", "run/main_scene.city3d")) == "res://proto3d/title.tscn",
		"the title screen is the main scene (and for the city3d export)")
	check(await until(func(): return city.ready_done, 120.0), "the city loads behind the title")
	check(await until(func(): return not title.backdrop.visible, 5.0), "and fades in over the skyline")
	await seconds(0.5)
	check(city.title_mode and city.flyover_cam != null and not city.hud.visible and not city.player.active,
		"title mode: flyover camera, no HUD, no player")
	var names: Array = []
	for b in title._buttons:
		names.append(String(b.text))
	var expect := ["New Game", "Sign in / Create account", "Settings", "Controls", "Credits", "Quit"]
	if SaveSystem.has_save():
		expect.push_front("Continue")
	check(names == expect, "menu buttons %s" % str(names))
	check(title._buttons[0].has_focus(), "the first button has focus (gamepad / keyboard ready)")
	var ver: Label = title.ui.find_child("Version", true, false)
	check(ver != null and ver.text == "v0.4-playtest" and BugReport.version() == "v0.4-playtest", "version v0.4-playtest on screen")
	var p0: Vector3 = city.flyover_cam.global_position
	await seconds(1.0)
	check(city.flyover_cam.global_position.distance_to(p0) > 1.0, "the flyover camera moves")
	title._on_controls()
	check(title._overlay.visible and title._overlay_text.get_parsed_text().contains("Get in / out of a car") \
		and title._overlay_text.get_parsed_text().contains("[F]"), "Controls lists actions with their keys")
	title._close_overlay()
	title._on_credits()
	var credits: String = title._overlay_text.get_parsed_text()
	check(credits.contains("OpenStreetMap") and credits.contains("ODbL"), "Credits include the OpenStreetMap / ODbL credit")
	title._close_overlay()
	check(title._menu.visible and not title._overlay.visible, "Back returns to the menu")
	title._on_settings()
	await process_frame
	check(city.settings_menu.visible and city.settings_menu.get_parent() == title.ui, "Settings opens over the title")
	city.settings_menu.close()
	await process_frame
	check(title._menu.visible and city.settings_menu.get_parent() == city.hud and not paused, "and closes back to it")

	print("new game + tutorial")
	city.settings.tutorial = true
	title._on_new_game()
	await until(func(): return not city._busy, 60.0)
	await seconds(0.3)
	check(not city.title_mode and city.player.active and city.hud.visible and city.flyover_cam == null, "New Game: player, HUD and game camera")
	check(city.tutorial.active and city.tutorial.step_id() == "walk", "the tutorial starts: %s" % city.tutorial.step_id())
	check(city.objective_text().contains("Walk to the marker") and city.target_pos() != null, "its objective and map target show")
	check(city.tutorial._hint.text.contains("[W A S D]"), "prompt shows keyboard keys (%s)" % city.tutorial._hint.text)
	InputGlyphs.pad = true
	city.tutorial._update_ui()
	check(city.tutorial._hint.text.contains("(Left stick)"), "and gamepad buttons after a pad is used")
	InputGlyphs.pad = false
	var tut = city.tutorial
	# walk
	city.player.global_position = tut._at + Vector3(0, 0.3, 0)
	check(await until(func(): return tut.step_id() == "car", 3.0), "walking to the marker -> get in the taxi")
	city.enter_car(city.start_car)
	check(await until(func(): return tut.step_id() == "drive", 3.0), "getting in -> drive to the cookshop")
	check(tut._at != Vector3.INF and city.shops.nearby_poi().is_empty(), "the cookshop is somewhere else (%.0f m away)" % tut._at.distance_to(city.car.global_position))
	city.car.reset_to(Transform3D(city.car.global_basis, tut._at + Vector3(0, 1.0, 0)))
	check(await until(func(): return tut.step_id() == "exit", 3.0), "driving there -> get out")
	city.exit_car()
	check(await until(func(): return tut.step_id() == "buy", 3.0), "getting out -> buy food")
	var money: int = city.state.money
	var food: Dictionary = {}
	for q in city.shops.pois:
		if (q["pos"] as Vector3).distance_to(tut._at) < 1.0:
			food = q
	city.shops._buy(city.shops.menus["food"]["items"][0], food)
	check(city.state.money < money, "buying kala and tea costs money")
	check(await until(func(): return tut.step_id() == "bat", 3.0), "buying -> pick up the bat")
	check(tut._bat != null and is_instance_valid(tut._bat), "a bat lies on the ground")
	city.player.global_position = tut._at + Vector3(0, 0.3, 0)
	check(await until(func(): return tut.step_id() == "dummy", 3.0), "walking over it -> hit the dummy")
	check(city.state.owned[GameState.BAT] and city.state.weapon == GameState.BAT, "the bat is yours and in hand")
	var d = tut.dummy
	check(d != null and d in city.all_walkers(), "a training dummy stands there")
	# up to 6 swings for 3 hits: the first can land while the player is still settling after
	# being placed (it missed on the devices commit too)
	for i in 6:
		if not is_instance_valid(d) or d.hits >= 3 or tut.step_id() != "dummy":
			break                                # (the tutorial frees the dummy after hit 3)
		var fw: Vector3 = (d.global_position - city.player.global_position) * Vector3(1, 0, 1)
		fw = fw.normalized() if fw.length() > 0.01 else Vector3.FORWARD
		city.player.global_position = d.global_position - fw * 0.95 + Vector3(0, 0.1, 0)
		city.player.model.rotation.y = atan2(-fw.x, -fw.z)
		await seconds(0.1)
		city.weapons._melee(city.weapons.def())
		await seconds(0.8)
	check(await until(func(): return tut.step_id() == "wheel", 3.0), "three bat hits -> open the weapon wheel")
	check(city.state.stars == 0, "hitting the dummy is no crime (%d stars)" % city.state.stars)
	Input.action_press("p3_wheel")
	await seconds(0.5)
	Input.action_release("p3_wheel")
	check(await until(func(): return tut.step_id() == "save", 3.0), "holding Tab -> go to the safehouse")
	check(tut._at.distance_to(city.shops.place_pos("safehouse")) < 1.0, "the marker is on the safehouse")
	var cash: int = city.state.money
	city.shops._buy(city.shops.menus["home"]["items"][0], city.shops.poi("safehouse"))
	await process_frame
	check(not tut.active and city.state.tutorial_done and city.state.money > cash, "resting saves and finishes it (+reward)")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/save.json"))
	check(saved is Dictionary and saved.get("tutorial_done") == true, "the save records it done (in tests/output, not the real save)")

	print("pause menu")
	city._pause_menu()
	await process_frame
	await process_frame
	var labels: Array = []
	for b in city.hud._menu_buttons.get_children():
		if not b.is_queued_for_deletion():
			labels.append(String(b.text))
	var joined := " | ".join(labels)
	check(joined.contains("Resume") and joined.contains("Settings") and joined.contains("Save game") and joined.contains("Quit to title"),
		"pause menu: %s" % joined)
	city.hud.close_menu()
	paused = false

	print("bug report")
	city.bug_report.open()
	check(paused and city.bug_report._panel.visible, "F8 pauses and opens the report box")
	var where: String = city.bug_report.save_report("Test report: the keke flew.")
	check(where != "", "report written")
	var txt := FileAccess.get_file_as_string(where + "/report.txt")
	check(txt.contains("Test report: the keke flew.") and txt.contains("v0.4-playtest") and txt.contains("Position:") \
		and txt.contains("FPS:") and txt.contains("Scene:"), "report.txt has the note, version, position, scene and FPS")
	check(FileAccess.file_exists(where + "/log_tail.txt"), "and a log tail")
	check(where.begins_with(ProjectSettings.globalize_path(OUT)), "saved locally (%s)" % where)
	city.bug_report.close()
	check(not paused, "closing it unpauses")

	title.queue_free()
	await seconds(1.0)
	if failures == 0:
		print("SMOKEPLAY TEST PASSED (%d checks)" % checks)
	else:
		print("SMOKEPLAY TEST FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures > 0 else 0)
