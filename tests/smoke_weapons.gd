extends SceneTree
## Headless checks of the weapons in the 1:1 city: the data, owning and switching weapons
## (keys and the wheel, with its slow motion), magazines and reloads, automatic fire,
## shotgun pellets, melee (bat, machete, the fists' combo), drive-by, the shop, saving and
## loading, and old saves from before the weapon update.
## Skips (passes) if the city hasn't been generated.

var m
var st: GameState
var w
var frame := 0
var done := false
var failures: Array[String] = []
var passed := 0


func _initialize() -> void:
	if not FileAccess.file_exists("res://proto3d/city/manifest.json"):
		print("SMOKEWPN TEST PASSED (skipped: city not generated)")
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
		push_error("SMOKEWPN CHECK FAILED: " + what)


func until(cond: Callable, max_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func seconds(t: float) -> void:
	await create_timer(t, true, false, true).timeout


## A pedestrian standing right in front of the player.
func target_in_front(dist: float):
	var p = m.player
	var fwd: Vector3 = Basis(Vector3.UP, p.model.rotation.y) * Vector3.FORWARD
	var ped = m.PedScript.new()
	var at: Vector3 = p.global_position + fwd * dist
	ped.setup(PackedVector3Array([at, at + Vector3(0.01, 0, 0)]), 0, 5)
	m.add_child(ped)
	ped.global_position = at
	ped.hp = 200.0
	m.peds.append(ped)
	return ped


func remove(ped) -> void:
	m.peds.erase(ped)
	ped.queue_free()


func run() -> void:
	await until(func(): return m.ready_done, 60.0)
	st = m.state
	w = m.weapons
	print("data")
	check(w.defs.size() == GameState.WEAPON_COUNT, "six weapons in the data file")
	for i in w.defs.size():
		check(ResourceLoader.exists("res://proto3d/ui/weapons/%s.png" % w.defs[i]["id"]), "icon for " + String(w.defs[i]["id"]))

	print("owning and switching")
	check(st.owned[GameState.FISTS] and not st.owned[GameState.SMG], "start with fists only")
	check(not st.select_weapon(GameState.SMG), "can't pick a weapon you don't have")
	st.give_weapon(GameState.SMG, 75)
	check(st.weapon == GameState.SMG and st.clip[GameState.SMG] == 30 and st.reserve[GameState.SMG] == 45, "SMG: a full magazine (30) and 45 spare")
	st.give_weapon(GameState.SHOTGUN, 14)
	st.give_weapon(GameState.BAT)
	st.give_weapon(GameState.MACHETE)
	st.give_pistol(20)
	Input.action_press("p3_wheel")
	await seconds(0.2)
	check(m.wheel.open and is_equal_approx(Engine.time_scale, 0.25), "holding Tab opens the wheel in slow motion")
	m.wheel.selected = GameState.SHOTGUN
	Input.action_release("p3_wheel")
	await seconds(0.1)
	check(not m.wheel.open and Engine.time_scale == 1.0 and st.weapon == GameState.SHOTGUN, "releasing picks the weapon, normal speed")

	print("guns")
	st.select_weapon(GameState.SMG)
	await seconds(0.2)
	var before: int = st.clip[GameState.SMG]
	Input.action_press("p3_fire")
	for i in 30:
		m.weapons.try_fire()
		await seconds(0.05)
	Input.action_release("p3_fire")
	check(before - int(st.clip[GameState.SMG]) >= 10, "holding fire with the SMG keeps firing (%d rounds)" % (before - int(st.clip[GameState.SMG])))
	st.clip[GameState.SMG] = 0
	await process_frame
	w._cd = 0.0
	w._trigger_down = false
	w.try_fire()
	check(w.reloading > 0.0, "empty magazine: it reloads")
	await until(func(): return w.reloading <= 0.0, 4.0)
	check(st.clip[GameState.SMG] == 30, "reload fills the magazine from the spare rounds")
	m.police.clear()
	m.police.remove_all()
	# shotgun at close range: several pellets hit
	st.select_weapon(GameState.SHOTGUN)
	await seconds(0.3)
	m.rig.yaw = m.player.model.rotation.y
	m.rig.pitch = -0.08
	await seconds(0.3)
	var ped = target_in_front(4.0)
	await seconds(0.3)
	m.rig.yaw = atan2(-(ped.global_position.x - m.player.global_position.x), -(ped.global_position.z - m.player.global_position.z))
	m.rig.pitch = -0.12
	await seconds(0.2)
	var hp0: float = ped.hp
	w._cd = 0.0
	w._trigger_down = false
	var shells: int = st.clip[GameState.SHOTGUN]
	w.try_fire()
	await process_frame
	check(st.clip[GameState.SHOTGUN] == shells - 1, "the shotgun uses one shell per shot")
	# pellets straight at the person (independent of where the camera happens to point)
	var from: Vector3 = m.player.global_position + Vector3(0, 1.2, 0)
	var dir: Vector3 = (ped.global_position + Vector3(0, 1.0, 0) - from).normalized()
	hp0 = ped.hp
	var ex: Array[RID] = [m.player.get_rid()]
	w._fire_pellets(w.defs[GameState.SHOTGUN], from - dir * 1.4, dir, from, ex)
	await process_frame
	check(ped.hp < hp0 - 30.0 or ped.is_down(), "several pellets hit a person in front (%.0f damage)" % (hp0 - ped.hp))
	remove(ped)
	m.police.clear()
	m.police.remove_all()

	print("melee")
	for wid in [GameState.BAT, GameState.MACHETE]:
		st.select_weapon(wid)
		var t = target_in_front(1.0)
		await seconds(0.2)
		var h0: float = t.hp
		w._cd = 0.0
		w._trigger_down = false
		w.try_fire()
		await process_frame
		check(t.hp < h0 or t.is_down(), String(w.defs[wid]["name"]) + " hits")
		remove(t)
		m.police.clear()
		m.police.remove_all()
	st.select_weapon(GameState.FISTS)
	var f = target_in_front(0.9)
	f.hp = 500.0
	await seconds(0.2)
	var dmg: Array = []
	for i in 3:
		var hb: float = f.hp
		w._cd = 0.0
		w._trigger_down = false
		w.try_fire()
		await process_frame
		dmg.append(hb - f.hp)
	check(dmg[2] > dmg[0], "the third punch of a combo hits harder (%s)" % str(dmg))
	remove(f)
	m.police.clear()
	m.police.remove_all()

	print("animation")
	var body = m.player.body
	await seconds(1.0)                     # let the last punch of the combo finish
	check(body.anim_player.has_animation("ual/Walk") and body.anim_player.has_animation("ual/Pistol_Aim_Neutral"), "the Universal Animation Library is loaded on the characters")
	check(m.peds.size() > 0 and m.peds[0].body.anim_player.has_animation("ual/Jog_Fwd"), "pedestrians use it too")
	Input.action_press("p3_crouch")
	await physics_frame
	await physics_frame
	Input.action_release("p3_crouch")
	await seconds(0.3)
	check(m.player.crouching and int(body.tree.get("parameters/move/stance/current_index")) == 1, "Ctrl crouches")
	Input.action_press("p3_crouch")
	await physics_frame
	await physics_frame
	Input.action_release("p3_crouch")
	await seconds(0.2)
	check(not m.player.crouching, "and stands up again")
	st.give_weapon(GameState.PISTOL, 30)
	st.clip[GameState.PISTOL] = 3
	w.start_reload()
	await seconds(0.2)
	check(bool(body.tree.get("parameters/move/reload/active")), "reloading plays the upper-body reload")
	await until(func(): return w.reloading <= 0.0, 3.0)
	Input.action_press("p3_aim")
	await seconds(0.5)
	check(float(body.tree.get("parameters/move/aim/blend_amount")) > 0.9, "aiming raises the gun in both hands")
	Input.action_release("p3_aim")

	print("shop and saves")
	st.lose_weapons()
	st.add_money(10000)
	var it := {"label": "SMG", "cost": 4500, "action": "weapon", "weapon": GameState.SMG, "rounds": 90}
	check(m.shops._can(it), "the weapon shop sells the SMG")
	m.shops._buy(it, {})
	check(st.owned[GameState.SMG] and st.ammo == 90, "bought: SMG with 90 rounds")
	var d := st.to_dict()
	var st2 := GameState.new()
	st2.from_dict(d)
	check(st2.owned[GameState.SMG] and st2.clip[GameState.SMG] + st2.reserve[GameState.SMG] == 90 and st2.weapon == GameState.SMG, "weapons are saved and loaded")
	st2.from_dict({"has_pistol": true, "ammo": 40, "weapon": 1})
	check(st2.has_pistol and st2.weapon == GameState.PISTOL and st2.ammo == 40, "old saves (pistol + ammo) still load")
	st2.free()

	if failures.is_empty():
		print("SMOKEWPN TEST PASSED (%d checks)" % passed)
	else:
		print("SMOKEWPN TEST FAILED: ", ", ".join(failures))
	paused = false
	Engine.time_scale = 1.0
	m.queue_free()
	await seconds(1.0)
	done = true
