extends SceneTree
## Headless play-through of the Big Talk Dweh storyline (proto3d/game/big_talk.gd) in the
## 1:1 city: data, all five stages and their props, every job type, the story gate,
## crossing him (Auntie Musu blocked, his goons, making peace), the radio show, both
## endings, and saving/loading his progress.
## Skips (passes) if the city hasn't been generated.

var m
var bt
var st: GameState
var frame := 0
var done := false
var failures: Array[String] = []
var passed := 0


func _initialize() -> void:
	if not FileAccess.file_exists("res://proto3d/city/manifest.json"):
		print("SMOKEBT TEST PASSED (skipped: city not generated)")
		done = true
		return
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func _process(_d: float) -> bool:
	frame += 1
	return done


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  ok   ", what)
	else:
		failures.append(what)
		push_error("SMOKEBT CHECK FAILED: " + what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


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
	await seconds(0.3)


## Puts the player right by him on foot.
func go_to_him() -> void:
	await teleport(bt.npc.global_position + Vector3(1.5, 0.3, 1.5))


## Walks through the current job's goto / cash_run steps (losing any police on the way).
func finish_steps() -> void:
	var guard := 0
	while bt.active() and guard < 6:
		guard += 1
		var stp: int = bt.current["step"]
		var t = bt.target()
		if t == null:
			break
		await teleport(t)
		m.police.clear()
		m.police.remove_all()
		await until(func(): return not bt.active() or bt.current["step"] != stp, 4.0)


func run() -> void:
	await until(func(): return m.ready_done, 60.0)
	bt = m.big_talk
	st = m.state
	# fresh story
	st.bt_stage = 0
	st.bt_done = []
	st.bt_posters = []
	st.bt_crossed = false
	st.bt_ending = ""
	st.mission_idx = 0
	bt.refresh()
	await frames(2)

	print("data")
	check(bt.data["stages"].size() == 5, "five stages in the data file")
	check(String(bt.data["party"]) == "Big Talk Progress Party", "fictional party name")
	var all_lines := 0
	for s in bt.data["stages"]:
		all_lines += s["lines"].size()
	check(all_lines >= 20, "plenty of lines (%d)" % all_lines)
	check(String(bt.spots["house"]["street"]) != "", "house plot is on a named street (%s)" % bt.spots["house"]["street"])

	print("stage 0: nobody")
	check(bt.npc != null and bt.npc.global_position.distance_to(bt.spot("crate")) < 2.0, "he stands on his crate at Waterside")
	check(bt.job_available() and bt.next_job() == "posters", "the poster job is offered")
	await go_to_him()
	check(m.prompt_text().contains("Big Talk"), "talk prompt when next to him")
	bt.interact()
	check(m.hud.menu_open, "his job menu opens")
	m.hud.choose(0)
	get_root().get_tree().paused = false
	await frames(2)
	check(bt.active() and bt.current["job"] == "posters", "took the poster job")
	check(bt._markers.size() == 6, "six poster spots marked")
	for i in 6:
		var p: Array = bt.spots["posters"][i]
		await teleport(Vector3(p[0], p[1] - 1.0, p[2]) + Vector3(sin(float(p[3])), 0, cos(float(p[3]))) * 1.6)
		await until(func(): return st.bt_posters.has(i), 3.0)
	await until(func(): return not bt.active(), 3.0)
	check(st.bt_posters.size() == 6 and st.bt_done.has("posters"), "all six posters pasted, job done")
	check(bt._posters.get_child_count() >= 6, "posters stay on the walls")
	check(st.bt_stage == 0, "next stage waits for the story (Auntie Musu)")
	st.mission_idx = 1
	bt._try_advance()
	check(st.bt_stage == 1, "story progress moves him to stage 1 (radio)")

	print("stage 1: radio")
	check(m.audio.stations.any(func(s): return s[0] == "radio_bigtalk"), "the Big Talk Hour is on the car radio")
	check(bt.npc.global_position.distance_to(bt.spot("billboard")) < 6.0, "he stands by his Sinkor billboard")
	bt.start_job("tape")
	check(bt.target() != null, "tape job has a target")
	await teleport(bt.target())
	await until(func(): return not bt.active(), 3.0)
	check(st.bt_done.has("tape"), "tape delivered to Hot Pepper FM")
	st.mission_idx = 2
	bt._try_advance()
	check(st.bt_stage == 2, "stage 2: the campaign")

	print("stage 2: campaign")
	await teleport(bt.spot("rally") + Vector3(0, 0.5, -14))
	await until(func(): return bt._cars.size() >= 3, 5.0)
	check(bt._cars.size() >= 3, "his SUV convoy is out near the rally")
	check(bt._root.find_children("*", "Node3D", false, false).size() >= 10, "rally stage, banner and crowd are built")
	bt.start_job("rival_crew")
	check(bt._remaining() == 3, "three rival poster boys")
	for r in bt.current["refs"].duplicate():
		if is_instance_valid(r):
			await teleport(r.global_position + Vector3(1.0, 0.3, 0))
			await frames(3)
	await until(func(): return not bt.active(), 3.0)
	check(st.bt_done.has("rival_crew"), "rival crew chased off")
	bt.start_job("cash_run")
	await teleport(bt.target())
	await until(func(): return bt.current.get("step", 0) == 1, 3.0)
	check(bt.active() and bt.current["step"] == 1, "cash picked up")
	# a police car sees the bag
	var pc = m.spawn_car("police", Transform3D(Basis.IDENTITY, m.player.global_position + Vector3(6, 1, 0)))
	await until(func(): return st.stars > 0, 3.0)
	check(st.stars >= 2, "police spot the bag: wanted level")
	m.remove_car(pc)
	m.police.clear()
	m.police.remove_all()
	await teleport(bt.target())
	await until(func(): return not bt.active(), 3.0)
	check(st.bt_done.has("cash_run"), "cash delivered once the police are lost")
	st.mission_idx = 3
	bt._try_advance()
	check(st.bt_stage == 3, "stage 3: big man")

	print("stage 3: big man")
	check(bt._guards.size() >= 2, "bodyguards at his house")
	check(bt._posters.get_child_count() >= 60, "his posters cover the city (%d)" % bt._posters.get_child_count())
	var hp: Vector3 = bt.spot("house")
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(hp + Vector3(0, 40, 0) + bt.house_basis() * Vector3(0, 0, 6), hp + Vector3(0, -5, 0) + bt.house_basis() * Vector3(0, 0, 6))
	check(not space.intersect_ray(q).is_empty(), "his walled house is solid")
	# cross him: fail a crossing job
	bt.start_job("cash_run")
	bt.fail("test")
	check(st.bt_crossed and bt.blocks_missions(), "failing his job crosses him")
	check(not m.missions.available(), "his boys keep Auntie Musu's jobs closed")
	bt._harass_t = 0.0
	await frames(3)
	check(bt._cars.any(func(c): return is_instance_valid(c) and c.mission_tag == "bigtalk_goon"), "his goons come after you")
	st.add_money(5000)
	check(bt.make_peace() and not st.bt_crossed and m.missions.available(), "paying respect makes peace")
	bt.start_job("meeting")
	await teleport(bt.target())
	await until(func(): return not bt.active(), 3.0)
	st.mission_idx = 4
	bt._try_advance()
	check(st.bt_stage == 4, "stage 4: the scandal")

	print("stage 4: finale")
	var saved := st.to_dict()
	var money0 := st.money
	bt.start_job("finale")
	check(m.hud.menu_open, "the finale asks you to choose")
	m.hud.choose(0)                                        # expose
	get_root().get_tree().paused = false
	await frames(2)
	await finish_steps()
	check(st.bt_ending == "expose" and st.money > money0, "EXPOSE: he's arrested, reward paid")
	check(bt._posters.get_child_count() == 0 or bt._posters.get_children().all(func(c): return c.is_queued_for_deletion()), "his posters are torn down")
	check(not m.audio.stations.any(func(s): return s[0] == "radio_bigtalk"), "his radio show is off the air")
	check(bt.street_line() != "", "people talk about it")
	# the other ending, from the same point
	st.from_dict(saved)
	bt.refresh()
	bt.start_job("finale")
	m.hud.choose(1)                                        # help him win
	get_root().get_tree().paused = false
	await frames(2)
	await finish_steps()
	check(st.bt_ending == "senator", "SENATOR: he wins")
	var statue := false
	for n in bt._root.find_children("*", "Node3D", true, false):
		if n.has_meta("statue"):
			statue = true
	check(statue, "a gold statue of Senator Dweh goes up")

	print("save")
	var d := st.to_dict()
	var st2 := GameState.new()
	st2.from_dict(d)
	check(st2.bt_stage == 4 and st2.bt_ending == "senator" and st2.bt_posters.size() == 6 and st2.bt_done.has("finale"), "his story is saved and loaded")
	st2.free()

	if failures.is_empty():
		print("SMOKEBT TEST PASSED (%d checks)" % passed)
	else:
		print("SMOKEBT TEST FAILED: ", ", ".join(failures))
	paused = false
	m.queue_free()
	await seconds(1.0)
	done = true
