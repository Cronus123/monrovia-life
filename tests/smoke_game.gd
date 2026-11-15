extends SceneTree
## Headless play-through of the 3D game systems in the 1:1 city (main_city.tscn).
## One check (or more) per system: economy, save, HUD/map, clock (night lights), traffic,
## taking a car, car fire/explosion, weapons, shops, taxi job, missions, police chase and
## officers on foot, ARRESTED and DOWN AND OUT.
## Skips (passes) if the city hasn't been generated.

var m
var frame := 0
var done := false
var failures: Array[String] = []
var passed := 0


func _initialize() -> void:
	if not FileAccess.file_exists("res://proto3d/city/manifest.json") or not FileAccess.file_exists("res://proto3d/city/roads_graph.json"):
		print("SMOKEGAME TEST PASSED (skipped: city not generated)")
		done = true
		return
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func _process(_d: float) -> bool:
	frame += 1
	if frame > 2000000 and not done:
		print("SMOKEGAME TEST FAILED: timed out")
		return true
	return done


func check(cond: bool, system: String, what: String) -> void:
	if cond:
		passed += 1
	else:
		failures.append("[%s] %s" % [system, what])
		push_error("SMOKEGAME CHECK FAILED: [%s] %s" % [system, what])


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits until cond is true, up to max_seconds of real time (physics runs in real time).
func until(cond: Callable, max_seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func seconds(t: float) -> void:
	await create_timer(t).timeout


func teleport(p: Vector3) -> void:
	m.teleport_player(p)
	await frames(2)
	await until(func(): return not m._busy, 60.0)
	await seconds(0.5)


func run() -> void:
	await until(func(): return m.ready_done, 60.0)
	var st: GameState = m.state
	await frames(30)

	# --- economy
	var before := st.money
	st.add_money(500)
	check(st.money == before + 500, "economy", "earning money")
	check(st.spend(100) and st.money == before + 400, "economy", "spending money")
	check(not st.spend(10000000), "economy", "can't spend more than you have")

	# --- save system
	var path := "user://smoke_test_save.json"
	var saved_money := st.money
	check(SaveSystem.save(st, Vector3(1, 2, 3), path), "save", "writes a save")
	st.money = 1
	var pos = SaveSystem.load_into(st, path)
	check(st.money == saved_money and pos == Vector3(1, 2, 3), "save", "loads money and position back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# --- HUD and map
	check(m.hud._minimap != null, "hud", "minimap image loaded")
	m.hud.toggle_map()
	check(m.hud.map_open, "hud", "full map opens")
	m.hud.toggle_map()
	check(not m.hud.map_open, "hud", "full map closes")

	# --- audio
	for b in ["Music", "SFX", "Ambience", "Voice"]:
		check(AudioServer.get_bus_index(b) >= 0, "audio", "bus %s exists" % b)
	check(m.audio.streams.size() >= 28, "audio", "all sounds and music load (%d)" % m.audio.streams.size())

	# --- settings
	var gs := GameSettings.new()
	gs.master = 0.5
	gs.sensitivity = 1.7
	gs.fov = 80.0
	gs.save_file("user://smoke_settings.cfg")
	var gs2 := GameSettings.new()
	gs2.load_file("user://smoke_settings.cfg")
	check(is_equal_approx(gs2.master, 0.5) and is_equal_approx(gs2.sensitivity, 1.7) and is_equal_approx(gs2.fov, 80.0), "settings", "settings save and load")
	gs2.apply_system()
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) - linear_to_db(0.5)) < 0.1, "settings", "master volume applies")
	gs2.apply_world(m)
	check(is_equal_approx(m.rig.sensitivity, 1.7) and is_equal_approx(m.rig.cam.fov, 80.0), "settings", "sensitivity and field of view apply")
	m.settings.apply_system()
	m.settings.apply_world(m)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://smoke_settings.cfg"))

	# --- input map and rebinding
	var all_there := true
	for a in InputDefaults.ACTIONS:
		all_there = all_there and InputMap.has_action(a)
	check(all_there, "input", "every action is in the Input Map")
	var pad := false
	for e in InputMap.action_get_events("p3_forward"):
		pad = pad or e is InputEventJoypadMotion
	check(pad, "input", "gamepad trigger/stick drives forward")
	gs2.set_binding("p3_horn", "key:J")
	check(InputDefaults.key_text("p3_horn") == "J", "input", "rebinding a key")
	gs2.reset_bindings()
	check(InputDefaults.key_text("p3_horn") == "H", "input", "reset controls")

	# --- traffic lights and right of way
	var sig: TrafficSignals = m.signals
	check(sig.signals.size() > 0, "traffic", "traffic lights at major junctions (%d)" % sig.signals.size())
	check(sig.junctions.size() > 0, "traffic", "right-of-way junctions (%d)" % sig.junctions.size())
	var node: int = sig.signals.keys()[0]
	var by_axis := {}
	for e in sig.signals[node]["axis"]:
		by_axis[sig.signals[node]["axis"][e]] = e
	if by_axis.size() == 2:
		var opposite := true
		for tt in [1.0, 5.0, 15.0, 20.0]:
			sig._t = tt - float(sig.signals[node]["offset"])
			var a: int = sig.light(node, by_axis[0])
			var b: int = sig.light(node, by_axis[1])
			opposite = opposite and not (a == 0 and b == 0)
		check(opposite, "traffic", "the two directions never both have green")
		sig._t = 15.0 - float(sig.signals[node]["offset"])
		check(sig.must_stop(node, by_axis[0], 15.0, null), "traffic", "a red light stops traffic")

	# --- no real business names
	var names := ""
	for p in m.shops.pois + m.shops.dests:
		names += String(p["name"]) + ";"
	var real_found := false
	for real in ["Total", "Conex", "NP station", "Mama Susu", "Musa Restaurant", "Stomach Station", "Golden Beach", "Bash Restaurant", "Lila Brown", "Mamba Point Hotel"]:
		real_found = real_found or real in names
	check(not real_found, "names", "shops and restaurants use made-up names")

	# --- clock: night lights
	st.time_min = 21.0 * 60.0
	await seconds(1.2)
	check(m.clock.darkness() == 1.0, "clock", "it is dark at 9 PM")
	var lit := false
	for l in m.clock._lamps:
		lit = lit or l.light_energy > 0.0
	check(lit, "clock", "street lights switch on near the player")
	st.time_min = 9.0 * 60.0
	await frames(5)

	# --- traffic
	await until(func(): return m.traffic.cars.size() >= 4, 15.0)
	check(m.traffic.cars.size() >= 4, "traffic", "traffic spawns on the road graph (%d cars)" % m.traffic.cars.size())
	var starts := {}
	for c in m.traffic.cars:
		starts[c] = c.global_position
	await seconds(4.0)
	var moved := 0.0
	for c in starts:
		if is_instance_valid(c):
			moved = maxf(moved, c.global_position.distance_to(starts[c]))
	check(moved > 5.0, "traffic", "traffic drives (moved %.0f m)" % moved)

	# --- taking a car (pull the driver out)
	var tc = m.traffic.nearest_to(m.player.global_position, 400.0)
	if tc != null:
		m.player.global_position = tc.global_transform * Vector3(-2.6, 0.6, 0.0)
		m.enter_car(tc)
		check(m.car != null and m.car.has_method("apply_damage"), "vehicles", "a traffic car can be taken (F)")
		await frames(10)
		m.exit_car(true)
	else:
		check(false, "vehicles", "a traffic car was near enough to take")
	m.police.clear()
	m.police.remove_all()

	# --- car fire and explosion
	var boom = m.spawn_car("car", Transform3D(Basis.IDENTITY, m.player.global_position + Vector3(12, 1, 0)))
	boom.apply_damage(100.0)
	check(boom.burning > 0.0, "vehicles", "a wrecked car catches fire")
	await until(func(): return boom.wrecked, 8.0)
	check(boom.wrecked, "vehicles", "a burning car explodes")

	# --- weapons
	st.add_money(5000)
	st.give_pistol(12)
	var ammo := st.ammo
	m.weapons._cd = 0.0
	m.weapons.try_fire()
	check(st.ammo == ammo - 1, "weapons", "firing the pistol uses ammo")
	var ped = null
	for p in m.peds:
		if not p.is_down():
			ped = p
			break
	if ped != null:
		var hp: float = ped.hp
		m.weapons._hit(ped, 40.0, 0.0)
		check(ped.hp < hp or ped.is_down(), "weapons", "a shot hurts a person")
	m.police.clear()
	m.police.remove_all()
	st.lose_weapons()

	# --- shops (weapon shop at Crown Hill)
	await teleport(m.shops.place_pos("guns_crown_hill"))
	var q: Dictionary = m.shops.nearby_poi()
	check(not q.is_empty() and q["type"] == "guns", "shops", "standing at the Crown Hill weapon shop")
	m.shops.interact()
	check(m.hud.menu_open, "shops", "shop menu opens")
	m.hud.choose(0)
	check(st.has_pistol, "shops", "buying a pistol")
	get_root().get_tree().paused = false

	# --- taxi job
	var cab = m.spawn_car("taxi", Transform3D(Basis.IDENTITY, m.player.global_position + Vector3(4, 0.8, 0)))
	await frames(20)
	m.enter_car(cab)
	# drive-by: aim out of the left window
	st.give_pistol(6)
	var rounds := st.ammo
	m.rig.yaw = PI / 2
	m.rig._idle_look = -30.0                # hold the look-left (no auto recentre) for the test
	await seconds(0.6)                      # camera finishes blending into the car view
	m.weapons._cd = 0.0
	m.weapons.try_fire_from_car()
	check(st.ammo == rounds - 1, "weapons", "shooting from a car (drive-by)")
	m.rig.yaw = 0.0
	m.police.clear()
	m.police.remove_all()
	await seconds(0.3)
	check(m.audio._engines.has(cab), "audio", "the player's car has an engine sound")
	m.taxi.toggle()
	check(m.taxi.hire, "taxi", "hire light on in a taxi")
	await until(func(): return m.taxi.waiting.size() > 0, 15.0)
	check(m.taxi.waiting.size() > 0, "taxi", "people wave for a ride")
	if m.taxi.waiting.size() > 0:
		var fare_ped = m.taxi.waiting[0]
		cab.freeze = true
		cab.global_position = fare_ped.global_position + Vector3(2.5, 0.5, 0)
		await frames(10)
		check(not m.taxi.fare.is_empty(), "taxi", "a passenger gets in")
		if not m.taxi.fare.is_empty():
			var cash := st.money
			cab.global_position = (m.taxi.fare["dest"]["pos"] as Vector3) + Vector3(0, 1.0, 0)
			await frames(10)
			check(st.money > cash, "taxi", "the fare is paid at the destination")
		cab.freeze = false
	m.taxi.stop()

	# --- missions: 1 "Wheels for the Crew"
	check(m.missions.available(), "missions", "Auntie Musu has a job")
	m.missions.start(0)
	check(m.missions.active(), "missions", "mission 1 starts")
	cab.freeze = true
	cab.global_position = m.shops.place_pos("garage") + Vector3(0, 1.0, 0)
	await frames(10)
	cab.freeze = false
	check(st.mission_idx == 1 and not m.missions.active(), "missions", "delivering a car to the Slipway garage passes mission 1")
	if m.car != null:
		m.exit_car(true)
	await frames(10)

	# --- police: chase and officers on foot
	m.police.add_stars(2)
	check(st.stars == 2, "police", "wanted level rises")
	await until(func(): return m.police.cars.size() >= 1, 15.0)
	check(m.police.cars.size() >= 1, "police", "police cars are dispatched")
	if m.police.cars.size() >= 1:
		var pc = m.police.cars[0]
		var d0: float = pc.global_position.distance_to(m.player.global_position)
		await seconds(9.0)
		if is_instance_valid(pc):
			var d1: float = pc.global_position.distance_to(m.player.global_position)
			check(d1 < d0 - 15.0 or d1 < 25.0, "police", "a police car closes in (%.0f m -> %.0f m)" % [d0, d1])
			pc.global_position = m.player.global_position + Vector3(9, 0.6, 0)
			pc.linear_velocity = Vector3.ZERO
			await seconds(1.0)
			check(m.police.cops.size() >= 1, "police", "officers get out and chase on foot")
	m.police.clear()
	m.police.remove_all()

	# --- ARRESTED
	st.give_pistol(10)
	m.arrested()
	await frames(2)
	await until(func(): return not m._busy, 60.0)
	check(st.stars == 0 and not st.has_pistol, "police", "ARRESTED: wanted level cleared, weapon taken")
	check(m.player.global_position.distance_to(m.shops.place_pos("police_hq")) < 25.0, "police", "released at the Police HQ")

	# --- DOWN AND OUT
	st.hurt(500.0)
	await frames(2)
	await until(func(): return not m._busy, 60.0)
	check(st.health == 100.0, "health", "DOWN AND OUT: healed")
	check(m.player.global_position.distance_to(m.shops.place_pos("hospital")) < 25.0, "health", "wakes up at JFK Medical Center")

	if failures.is_empty():
		print("SMOKEGAME TEST PASSED (%d checks)" % passed)
	else:
		print("SMOKEGAME TEST FAILED: ", ", ".join(failures))
	# tidy shutdown: free the game and let queued frees, tweens and timers finish
	paused = false
	m.queue_free()
	await seconds(1.0)
	done = true
