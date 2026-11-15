class_name Missions
extends Node3D
## Auntie Musu's story, defined in proto3d/game/data/missions.json. Each mission is a list
## of steps (deliver_any_car, goto, lose_police, destroy_vehicle, steal_vehicle,
## deliver_vehicle) at real places. Auntie stands at Waterside under a yellow M.

signal mission_passed(index: int)
signal mission_failed(index: int)

const GraphDriverScript := preload("res://proto3d/game/graph_driver.gd")
const CharacterScript := preload("res://proto3d/character.gd")

var state: GameState
var main                          # main_city.gd
var shops: Shops
var police: Police
var data: Dictionary
var list: Array = []
var current := {}                 # {index, step, timer, ref}
var _marker: Label3D
var _auntie: Node3D


func setup(game_state: GameState, main_node, s: Shops, pol: Police) -> void:
	state = game_state
	main = main_node
	shops = s
	police = pol
	data = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/game/data/missions.json"))
	list = data["missions"]
	var giver: Vector3 = shops.place_pos(String(data["giver"]))
	_auntie = CharacterScript.new()
	_auntie.set_outfit({"model": "Casual_Female", "skin": "#5a3825", "shirt": "#7c3aed", "pants": "#5a3825", "skirt": "#ef7d22", "wrap": "#f5c518"})
	add_child(_auntie)
	_auntie.global_position = giver
	_marker = Label3D.new()
	_marker.text = "M"
	_marker.font_size = 128
	_marker.pixel_size = 0.012
	_marker.outline_size = 20
	_marker.modulate = Color("#f5c518")
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.visibility_range_end = 400.0
	add_child(_marker)
	_marker.global_position = giver + Vector3(0, 3.0, 0)


func active() -> bool:
	return not current.is_empty()


func available() -> bool:
	return not active() and state.mission_idx < list.size()


func step() -> Dictionary:
	return list[current["index"]]["steps"][current["step"]] if active() else {}


func prompt() -> String:
	return "[E] Talk to Auntie Musu" if available() else "[E] Auntie Musu"


func open_menu() -> void:
	if state.mission_idx >= list.size():
		main.hud.open_menu("Auntie Musu", "\"You did it, Kollie. Monrovia knows your name now. Go enjoy the city.\"", [], func(_i): pass)
		return
	if active():
		main.hud.open_menu("Auntie Musu", "\"Why you standing here? Go finish the job!\"", [{"label": "Give up this mission"}], func(_i): fail("Mission abandoned."))
		return
	var m: Dictionary = list[state.mission_idx]
	main.hud.open_menu("Mission %d: %s" % [state.mission_idx + 1, m["title"]],
		"Auntie Musu: \"%s\"  Reward: %s" % [m["intro"], GameState.money_text(int(m["reward"]))],
		[{"label": "Start the mission"}], func(_i): start(state.mission_idx))


func start(i: int) -> void:
	main.taxi.stop()
	current = {"index": i, "step": 0, "timer": -1.0, "ref": null}
	state.say("Mission: " + String(list[i]["title"]), Color("#f5c518"), 4.0)
	_begin_step()


func _begin_step() -> void:
	var s := step()
	current["timer"] = float(s.get("timer", -1.0))
	if s.has("on_start"):
		state.say(String(s["on_start"]), Color("#f5c518"), 3.0)
	match String(s["type"]):
		"lose_police":
			police.add_stars(maxi(0, int(s["stars"]) - state.stars))
		"destroy_vehicle", "steal_vehicle":
			var at := shops.place_pos(String(s["spawn"]))
			var n: Dictionary = main.graph.nearest(at, 3)
			var lp: Array = main.graph.lane_point(n["edge"], 10.0, 1)
			var fwd: Vector3 = lp[1]
			var car = main.spawn_car(String(s["vehicle"]), Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), (lp[0] as Vector3) + Vector3(0, 0.6, 0)))
			car.mission_tag = String(list[current["index"]]["id"])
			car.set_meta("keep", true)
			if s.has("color"):
				_paint(car, Color(String(s["color"])))
			if s["type"] == "destroy_vehicle":
				car.controller = GraphDriverScript.new(main.graph, "wander", null, 14.0, 7)
				car.set_headlights(main.clock.darkness() > 0.35)
			current["ref"] = car


func _paint(car, col: Color) -> void:
	for mi in car.model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for k in mesh.get_surface_count():
			var mat := mesh.surface_get_material(k)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_color.r > 0.5 and (mat as BaseMaterial3D).albedo_color.g < 0.2:
				var nm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				nm.albedo_color = col
				(mi as MeshInstance3D).set_surface_override_material(k, nm)


func objective() -> String:
	if not active():
		return ("Auntie Musu has a job for you at Waterside (yellow M)." if available() else "")
	var text := String(step()["text"])
	if float(current["timer"]) >= 0.0:
		text += "  %d s left" % int(maxf(0.0, current["timer"]))
	return text


## Where the HUD should point: the step's place, or the vehicle to find.
func target() -> Variant:
	if not active():
		return shops.place_pos(String(data["giver"])) if available() else null
	var s := step()
	var ref = current["ref"]
	if s["type"] in ["destroy_vehicle", "steal_vehicle"] and ref != null and is_instance_valid(ref):
		return ref.global_position
	if s.has("target"):
		return shops.place_pos(String(s["target"]))
	return null


func _process(delta: float) -> void:
	_marker.visible = available()
	_auntie.set_speed(0.0)
	if not active():
		return
	var s := step()
	var car = main.car
	var me: Vector3 = car.global_position if car != null else main.player.global_position
	if float(current["timer"]) >= 0.0:
		current["timer"] -= delta
		if current["timer"] <= 0.0:
			fail("Too slow. The buyer left.")
			return
	var ref = current["ref"]
	var done := false
	match String(s["type"]):
		"deliver_any_car":
			var at := shops.place_pos(String(s["target"]))
			if car != null and car.kind != "police" and at.distance_to(car.global_position) < 9.0 and absf(car.speed) < 2.0:
				main.exit_car(true)
				car.mission_tag = "delivered"
				car.set_meta("keep", true)
				done = true
		"goto":
			done = shops.place_pos(String(s["target"])).distance_to(me) < 11.0
		"lose_police":
			done = state.stars == 0
		"destroy_vehicle":
			if ref == null or not is_instance_valid(ref):
				fail("The rival got away.")
				return
			done = ref.wrecked
			if not done and ref.global_position.distance_to(me) > 1500.0:
				fail("The rival got away.")
				return
		"steal_vehicle":
			if ref == null or not is_instance_valid(ref) or ref.wrecked:
				fail("The van was destroyed.")
				return
			if car == ref:
				police.add_stars(int(s.get("stars_on_take", 0)))
				done = true
		"deliver_vehicle":
			if ref == null or not is_instance_valid(ref) or ref.wrecked:
				fail("The van was destroyed.")
				return
			done = car == ref and shops.place_pos(String(s["target"])).distance_to(car.global_position) < 12.0 and absf(car.speed) < 2.5
	if done:
		current["step"] += 1
		if current["step"] >= list[current["index"]]["steps"].size():
			_complete()
		else:
			_begin_step()


func _complete() -> void:
	var i: int = current["index"]
	var m: Dictionary = list[i]
	state.add_money(int(m["reward"]))
	state.big_text.emit("MISSION PASSED", Color("#3ccf7a"))
	state.say("+%s  %s" % [GameState.money_text(int(m["reward"])), m["title"]], Color("#f5c518"), 5.0)
	var ref = current["ref"]
	if ref != null and is_instance_valid(ref):
		ref.set_meta("keep", false)
	current = {}
	state.mission_idx = maxi(state.mission_idx, i + 1)
	if i == 2:
		police.clear()
	if state.mission_idx >= list.size():
		state.say("Auntie Musu: \"%s\"" % data["finale"], Color("#3ccf7a"), 8.0)
	else:
		state.say("Auntie Musu has another job for you at Waterside.", Color.WHITE, 5.0)
	mission_passed.emit(i)
	main.save_game()


func fail(reason: String) -> void:
	if not active():
		return
	var i: int = current["index"]
	var ref = current["ref"]
	if ref != null and is_instance_valid(ref) and ref != main.car:
		main.remove_car(ref)
	current = {}
	state.big_text.emit("MISSION FAILED", Color("#f5c518"))
	state.say(reason + " Talk to Auntie Musu to try again.", Color("#ff5a6e"), 5.0)
	mission_failed.emit(i)
