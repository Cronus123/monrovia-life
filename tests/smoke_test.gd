extends SceneTree
## Headless smoke test: starts a new game and drives it through the main systems
## (driving, taxi work, police, map, menus, every mission, knock-out, arrest, shops)
## for a few hundred frames. Any script error shows up in the log; tools/check.ps1
## fails the run if one appears or if the final "SMOKE TEST PASSED" line is missing.
##
## Run: Godot_console.exe --headless --path . --script res://tests/smoke_test.gd
## It never saves, so it leaves the player's save file alone.

const MAX_FRAMES := 400

var m
var frame := 0
var failures: Array[String] = []

func _initialize() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)

func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)
		push_error("SMOKE CHECK FAILED: " + what)

func _process(_d: float) -> bool:
	frame += 1
	match frame:
		5:
			m.start_game(false)
			check(m.started, "game starts")
			check(m.spr.size() == 17, "all 17 sprites load (got %d)" % m.spr.size())
		30:
			m.time_min = 20.0 * 60.0  # night: lights and lamps
			m.rain_from = m.time_min - 30.0
			m.rain_until = m.time_min + 200.0
		60:
			var c = m.make_car("taxi", m.p_pos + Vector2(1, 0), 0.0, "traffic")
			c.road = 0
			m.enter_exit()
			check(m.car != null, "player can take a car")
			m.toggle_hire()
			check(m.hire, "taxi hire light turns on")
		120:
			var before: int = m.stars  # pulling out a driver may already have added a star
			m.add_stars(4)
			check(m.stars == mini(5, before + 4), "wanted level rises")
		200:
			m.enter_exit()
			check(m.car == null, "player can leave the car")
			m.map_open = true
		230:
			m.map_open = false
			m.pause_menu()
			check(m.menu != null, "pause menu opens")
		240:
			m.menu = null
			for i in m.MISSIONS.size():
				m.mission = null
				m.start_mission(i)
				check(m.mission != null, "mission %d starts" % i)
		300:
			m.knocked_out()
			check(m.health == 100.0, "respawn after knock-out")
			m.arrested()
			check(m.stars == 0, "wanted level clears after arrest")
			m._gun_menu()
			check(m.menu != null, "weapon shop opens")
			m.menu = null
		360:
			check(m.cars.size() > 0, "traffic spawns")
			check(m.peds.size() > 0, "pedestrians spawn")
			if failures.is_empty():
				print("SMOKE TEST PASSED (frames=%d cars=%d peds=%d)" % [frame, m.cars.size(), m.peds.size()])
			else:
				print("SMOKE TEST FAILED: ", ", ".join(failures))
			return true
	return frame >= MAX_FRAMES
