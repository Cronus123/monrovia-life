extends SceneTree
## World audit (windowed): measures what's wrong instead of guessing.
##  roads     - raycasts down on lane points: holes, buildings sitting on the road, steps
##  props     - street furniture floating or sunk
##  people    - pedestrians stuck, under the ground or walking into buildings
##  traffic   - cars stuck (not at a light) or off the road
##  player    - walking along sidewalks: falls through, stuck on curbs, slides
## Prints AUDIT lines and saves build/screens/audit_*.png.
## Run: Godot.exe --path . --script res://tests/world_audit.gd

var m
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 11
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func seconds(t: float) -> void:
	await create_timer(t).timeout


func until(cond: Callable, max_s: float) -> void:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func ray(from: Vector3, to: Vector3, mask: int = 1) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return m.get_world_3d().direct_space_state.intersect_ray(q)


func goto(p: Vector3) -> void:
	m.teleport_player(p)
	await process_frame
	await until(func(): return not m._busy, 60.0)
	await seconds(0.5)


func snap(name: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/screens/audit_" + name + ".png"))


func run() -> void:
	await until(func(): return m.ready_done, 90.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	m.state.time_min = 10.0 * 60.0
	var g = m.graph
	# a 4 x 4 grid over the city's road network (the nearest road node to each grid point)
	var areas: Array = []
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for nd in g.nodes:
		lo = Vector3(minf(lo.x, nd.x), 0, minf(lo.z, nd.z))
		hi = Vector3(maxf(hi.x, nd.x), 0, maxf(hi.z, nd.z))
	for gx in 4:
		for gz in 4:
			var want := Vector3(lerpf(lo.x, hi.x, (gx + 0.5) / 4.0), 0, lerpf(lo.z, hi.z, (gz + 0.5) / 4.0))
			var near: Dictionary = g.nearest(want, 3)
			if near.is_empty():
				continue
			var np: Vector3 = g.lane_point(near["edge"], 2.0, 1)[0]
			if np.distance_to(want) < 500.0 and not areas.any(func(a): return a.distance_to(np) < 300.0):
				areas.append(np)
	var totals := {"lanes": 0, "hole": 0, "building_on_road": 0, "step": 0, "terrain_over_road": 0, "seam_checks": 0, "seam_step": 0, "props": 0, "prop_float": 0, "prop_sunk": 0,
		"peds": 0, "ped_stuck": 0, "ped_under": 0, "ped_in_building": 0, "cars": 0, "car_stuck": 0, "car_off": 0,
		"walk_samples": 0, "walk_fall": 0, "walk_stuck": 0}
	var examples := {}
	for ai in areas.size():
		var c: Vector3 = areas[ai]
		await goto(c)
		await until(func(): return m.streamer.is_area_ready(c, 210.0), 30.0)     # every tile we sample is loaded
		await seconds(2.0)
		# --- roads: lane points within 200 m
		var pts: Array = []
		for e in g.edges.size():
			var L: float = g.edges[e]["len"]
			var s0 := 0.0
			while s0 < L:
				var lp: Array = g.lane_point(e, s0, 1)
				if (lp[0] as Vector3).distance_to(c) < 200.0:
					pts.append(lp[0])
				s0 += 20.0
		for p in pts:
			totals["lanes"] += 1
			var h := ray(p + Vector3(0, 40, 0), p + Vector3(0, -8, 0))
			if h.is_empty():
				totals["hole"] += 1
				examples["hole"] = p
				continue
			var col: Node = h.collider
			var owner_name := String(col.get_parent().name) if col != null and col.get_parent() != null else ""
			if owner_name.begins_with("Buildings"):
				totals["building_on_road"] += 1
				examples["building_on_road"] = p
			elif owner_name.begins_with("Terrain"):
				totals["terrain_over_road"] += 1                 # the ground shows through the road
				examples["terrain_over_road"] = p
			elif absf((h.position as Vector3).y - p.y) > 0.6:
				totals["step"] += 1
				examples["step"] = p
		# --- tile seams: ground height just either side of tile edges near here
		var ts: float = m.streamer.tile_size
		for k in 12:
			var x := floorf(c.x / ts) * ts + (ts if k % 2 == 0 else 0.0)
			var z := c.z + (k - 6) * 15.0
			var a := ray(Vector3(x - 0.3, c.y + 60, z), Vector3(x - 0.3, c.y - 60, z))
			var b := ray(Vector3(x + 0.3, c.y + 60, z), Vector3(x + 0.3, c.y - 60, z))
			if a.is_empty() or b.is_empty():
				continue
			var an := String(a.collider.get_parent().name)
			var bn := String(b.collider.get_parent().name)
			if not (an.begins_with("Terrain") and bn.begins_with("Terrain")):
				continue                                   # a roof or curb on one side: not a seam
			totals["seam_checks"] += 1
			if absf((a.position as Vector3).y - (b.position as Vector3).y) > 0.25:
				totals["seam_step"] += 1
				examples["seam_step"] = Vector3(x, (a.position as Vector3).y, z)
		# --- props near the player
		for b in m.get_tree().get_nodes_in_group("props"):
			if (b as Node3D).global_position.distance_to(c) > 150.0:
				continue
			totals["props"] += 1
			var bp: Vector3 = (b as Node3D).global_position
			# resting on another prop (produce on a stall table) isn't floating
			var below := ray(bp + Vector3(0, 0.05, 0), bp + Vector3(0, -1.2, 0), 8)
			if not below.is_empty() and below.collider != b:
				continue
			var h2 := ray(bp + Vector3(0, 3, 0), bp + Vector3(0, -6, 0), 1)
			if not h2.is_empty():
				var dy: float = bp.y - (h2.position as Vector3).y
				if dy > 0.3:
					totals["prop_float"] += 1
					examples["prop_float"] = bp
				elif dy < -0.3:
					totals["prop_sunk"] += 1
					examples["prop_sunk"] = bp
		# --- people and traffic over 25 s
		var start := {}
		for p in m.peds:
			start[p] = p.global_position
		var cstart := {}
		for tc in m.traffic.cars:
			cstart[tc] = [tc.global_position, 0.0]
		for s in 25:
			await seconds(1.0)
			for tc in m.traffic.cars:
				if cstart.has(tc) and is_instance_valid(tc):
					if tc.speed < 0.2:
						cstart[tc][1] += 1.0
		for p in m.peds:
			if not is_instance_valid(p) or not start.has(p):
				continue
			totals["peds"] += 1
			var moved: float = (p.global_position - start[p]).length()
			var gr := ray(p.global_position + Vector3(0, 30, 0), p.global_position + Vector3(0, -30, 0))
			var gname := String(gr.collider.get_parent().name) if not gr.is_empty() else ""
			if not gr.is_empty() and (gr.position as Vector3).y > p.global_position.y + 0.8 and gname.begins_with("Buildings"):
				totals["ped_in_building"] += 1
				examples["ped_in_building"] = p.global_position
			elif not gr.is_empty() and (gr.position as Vector3).y > p.global_position.y + 0.8:
				totals["ped_under"] += 1
				examples["ped_under"] = p.global_position
			elif moved < 1.0 and not p.waiting and not p.is_down():
				totals["ped_stuck"] += 1
				examples["ped_stuck"] = p.global_position
		for tc in cstart:
			if not is_instance_valid(tc):
				continue
			totals["cars"] += 1
			if float(cstart[tc][1]) > 20.0:
				totals["car_stuck"] += 1
				examples["car_stuck"] = tc.global_position
			var gr2 := ray(tc.global_position + Vector3(0, 3, 0), tc.global_position + Vector3(0, -3, 0))
			if not gr2.is_empty() and not String(gr2.collider.get_parent().name).begins_with("Roads"):
				totals["car_off"] += 1
				examples["car_off"] = tc.global_position
		# --- the player walks a sidewalk path
		var paths: Array = m.streamer.nearby(c, 150.0, "paths")
		if not paths.is_empty():
			var path: Array = paths[rng.randi() % paths.size()]
			var a: Array = path[0]
			await goto(Vector3(a[0], a[1] + 0.3, a[2]))
			for i in range(1, mini(path.size(), 25)):
				var q: Array = path[i]
				var target := Vector3(q[0], q[1], q[2])
				var before: Vector3 = m.player.global_position
				var t0 := Time.get_ticks_msec()
				while Time.get_ticks_msec() - t0 < 2500 and Vector2(target.x - m.player.global_position.x, target.z - m.player.global_position.z).length() > 1.2:
					var d: Vector3 = target - m.player.global_position
					m.rig.yaw = atan2(-d.x, -d.z)
					Input.action_press("p3_forward")
					await process_frame
				Input.action_release("p3_forward")
				totals["walk_samples"] += 1
				if m.player.global_position.y < target.y - 2.5:
					totals["walk_fall"] += 1
					examples["walk_fall"] = target
				elif (m.player.global_position - before).length() < 0.5 and Vector2(target.x - before.x, target.z - before.z).length() > 1.2:
					totals["walk_stuck"] += 1
					examples["walk_stuck"] = target
					print("AUDIT snag at %s (blocked walking to %s)" % [before.snapped(Vector3(0.01, 0.01, 0.01)), target])
					break                                  # one snag per path, not one per remaining point
			Input.action_release("p3_forward")
		await snap("area%d" % ai)
	print("AUDIT totals ", totals)
	for k in examples:
		print("AUDIT example %s at %s" % [k, examples[k]])
	# screenshots of examples
	for k in examples:
		var p: Vector3 = examples[k]
		await goto(p + Vector3(0, 0.5, 0))
		m.rig.process_mode = Node.PROCESS_MODE_DISABLED
		m.rig.cam.global_transform = Transform3D(Basis.IDENTITY, p + Vector3(6, 5, 6)).looking_at(p)
		await seconds(0.5)
		await snap("ex_" + k)
		m.rig.process_mode = Node.PROCESS_MODE_INHERIT
	m.queue_free()
	await seconds(1.0)
	quit()
