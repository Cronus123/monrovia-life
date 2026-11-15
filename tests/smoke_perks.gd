extends SceneTree
## Headless checks of skills, perks and the new street life in the 1:1 city: skills level
## up from use, perks unlock from reputation / milestones and change the game (shop prices,
## cash, tips, evasion, the B ability), stamina limits sprinting, saving and loading, and
## the street-life scenes and pedestrian behaviours (vendors, rain shelter, time of day).
## Skips (passes) if the city hasn't been generated.

var m
var st: GameState
var pk
var done := false
var failures: Array[String] = []
var passed := 0


func _initialize() -> void:
	if not FileAccess.file_exists("res://proto3d/city/manifest.json"):
		print("SMOKEPERKS TEST PASSED (skipped: city not generated)")
		done = true
		return
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func _process(_d: float) -> bool:
	return done


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  ok   ", what)
	else:
		failures.append(what)
		push_error("SMOKEPERKS CHECK FAILED: " + what)


func until(cond: Callable, max_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func seconds(t: float) -> void:
	await create_timer(t).timeout


func run() -> void:
	await until(func(): return m.ready_done, 60.0)
	st = m.state
	pk = m.perks
	print("skills")
	check(pk.data["skills"].size() == 5 and pk.data["perks"].size() == 7, "five skills and seven perks in the data file")
	check(pk.level("driving") == 0, "skills start at level 0")
	pk.add_xp("driving", 600.0)
	check(pk.level("driving") == 3, "driving xp levels the skill up (level %d)" % pk.level("driving"))
	check(pk.has("roadside_mechanic"), "driving level 3 unlocks Roadside Mechanic")
	print("stamina")
	var full: float = pk.max_stamina()
	# out on an open road, facing along it
	var n: Dictionary = m.graph.nearest(m.player.global_position, 3)
	var lp: Array = m.graph.lane_point(n["edge"], 10.0, 1)
	m.teleport_player((lp[0] as Vector3) + Vector3(0, 0.3, 0))
	await process_frame
	await until(func(): return not m._busy, 60.0)
	await seconds(0.5)
	var fw: Vector3 = lp[1]
	m.rig.yaw = atan2(-fw.x, -fw.z)
	Input.action_press("p3_sprint")
	Input.action_press("p3_forward")
	await seconds(2.0)
	check(pk.stamina < full - 10.0, "sprinting uses stamina (%.0f of %.0f)" % [pk.stamina, full])
	check(float(st.skill_xp.get("stamina", 0.0)) > 0.0, "and trains the Stamina skill")
	pk.stamina = 0.0
	await seconds(0.3)
	var v := Vector2(m.player.velocity.x, m.player.velocity.z).length()
	check(v < 6.0, "with no stamina you can't sprint (%.1f m/s)" % v)
	Input.action_release("p3_sprint")
	Input.action_release("p3_forward")
	print("reputation perks")
	var it := {"label": "Body armour", "cost": 800, "action": "armor"}
	check(m.shops.price(it) == 800, "full price before Market Mouth")
	st.rep = 39
	pk.add_rep("shop_buy")
	check(pk.has("market_mouth") and m.shops.price(it) == 680, "rep 40 unlocks Market Mouth: 15%% off (%d)" % m.shops.price(it))
	st.rep = 150
	pk.check_unlocks()
	check(pk.has("hustler") and pk.has("cool_head"), "rep 100/150 unlocks Hustler and Cool Head")
	var money: int = st.money
	m.effects.cash_picked.emit(100)
	check(st.money - money == 150, "Hustler: +50%% cash (%d)" % (st.money - money))
	for i in 10:
		pk.add_fare()
	check(pk.has("keke_king"), "ten taxi fares: Keke King")
	print("abilities")
	var c = m.spawn_car("car", Transform3D(Basis.IDENTITY, m.player.global_position + Vector3(0, 0.6, 0)))
	await seconds(0.3)
	m.enter_car(c)
	c.damage = 70.0
	pk.use_ability()
	check(c.damage <= 20.0, "B: Roadside Mechanic patches the car (damage %.0f)" % c.damage)
	c.damage = 70.0
	pk.use_ability()
	check(c.damage == 70.0, "then needs a rest before the next repair")
	check(c.grip_bonus > 0.05, "driving skill gives the car more grip (%.2f)" % c.grip_bonus)
	m.exit_car(true)
	await seconds(0.3)
	st.bt_stage = 3
	st.bt_crossed = false
	pk.check_unlocks()
	check(pk.has("big_talk_connect"), "Big Talk's Big Man stage (not crossed): Big Talk Connect")
	m.police.add_stars(3)
	pk.use_ability()
	check(st.stars == 1, "B: Big Talk's call takes two stars off (now %d)" % st.stars)
	m.police.clear()
	m.police.remove_all()
	print("save")
	var d := st.to_dict()
	var st2 := GameState.new()
	st2.from_dict(d)
	check(st2.perks.size() == st.perks.size() and int(st2.rep) == st.rep and float(st2.skill_xp.get("driving", 0)) == float(st.skill_xp.get("driving", 0)), "skills and perks are saved and loaded")
	st2.free()
	print("street life")
	st.time_min = 10.0 * 60.0
	st.rain_until = -1.0
	m.teleport_player(m.streamer.spawn_point())
	await process_frame
	await until(func(): return not m._busy, 60.0)
	await seconds(4.0)
	check(m.street_life.people_count() > 0, "street life around the player (%d people in %d scenes)" % [m.street_life.people_count(), m.street_life.scenes.size()])
	check(m.street_life.people_count() <= m.street_life.MAX_PEOPLE, "within its budget")
	st.time_min = 2.0 * 60.0
	var night: int = m.ped_target()
	st.time_min = 8.0 * 60.0
	var morning: int = m.ped_target()
	check(night < morning, "fewer people out at night (%d vs %d in the morning)" % [night, morning])
	var vendor = m.PedScript.new()
	var p0: Vector3 = m.player.global_position + Vector3(4, 0.3, 0)
	vendor.setup(PackedVector3Array([p0, p0 + Vector3(10, 0, 0)]), 0, 3)
	vendor.vendor = true
	vendor.main = m
	m.add_child(vendor)
	vendor.global_position = p0
	await seconds(0.5)
	check(vendor.body.find_children("*", "MeshInstance3D", true, false).size() > 0 and vendor.body.current_state() == "loop", "a vendor pushes a wheelbarrow")
	st.rain_from = st.time_min - 30.0
	st.rain_until = st.time_min + 200.0
	await seconds(2.0)
	var sheltering := 0
	for p in m.peds:
		if is_instance_valid(p) and p._shelter != Vector3.INF:
			sheltering += 1
	check(sheltering > 0, "in rain, people head for shop awnings (%d)" % sheltering)
	vendor.queue_free()
	if failures.is_empty():
		print("SMOKEPERKS TEST PASSED (%d checks)" % passed)
	else:
		print("SMOKEPERKS TEST FAILED: ", ", ".join(failures))
	m.queue_free()
	await seconds(1.0)
	done = true
