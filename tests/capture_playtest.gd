extends SceneTree
## Windowed screenshots of the playtest build: title screen, a tutorial prompt, driving,
## and the F8 bug report dialog, saved to build/screens/playtest/.
## Saves and reports go to tests/output. Run: Godot.exe --path . --script res://tests/capture_playtest.gd

const SHOTS := "res://build/screens/playtest"
const OUT := "res://tests/output/playtest_capture"

var title
var city


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	DirAccess.make_dir_recursive_absolute(OUT)
	title = load("res://proto3d/title.tscn").instantiate()
	root.add_child(title)
	run()


func seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func until(cond: Callable, max_s: float) -> void:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func snap(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS + "/" + name + ".png"))
	print("saved ", name)


func run() -> void:
	await process_frame
	while title.city == null:              # the title loads the city after drawing its menu
		await process_frame
	city = title.city
	city.save_path = OUT + "/save.json"
	city.bug_report.dir_root = OUT + "/bug_reports"
	await until(func(): return city.ready_done, 120.0)
	city.state.time_min = 16.5 * 60.0                # late afternoon light
	city.clock.advance(0.0)
	await seconds(6.0)
	await snap("title")
	city.settings.tutorial = true
	title._on_new_game()
	await until(func(): return not city._busy, 60.0)
	await seconds(4.0)
	await snap("tutorial")
	# the tutorial's taxi: get in and drive
	city.player.global_position = city.tutorial._at + Vector3(0, 0.3, 0)
	await seconds(1.0)
	city.enter_car(city.start_car)
	await seconds(1.5)
	Input.action_press("p3_forward")
	await seconds(3.5)
	Input.action_press("p3_left")
	await seconds(0.6)
	Input.action_release("p3_left")
	await snap("driving")
	Input.action_release("p3_forward")
	await seconds(1.0)
	city.bug_report.open()
	city.bug_report._note.text = "The taxi bounced on the kerb by the cookshop."
	await seconds(0.3)
	await snap("bug_report")
	city.bug_report.close()
	title.queue_free()
	await seconds(1.0)
	quit()
