class_name Shops
extends Node3D
## Points of interest at real places (proto3d/city/places.json): weapon shops, cookshops,
## vehicle parks (rentals), respray shops (fuel stations), the safehouse, the hospital
## and the police HQ. Draws a marker over each, offers the interaction prompt, and runs
## the menus from proto3d/game/data/shops.json.

const COLORS := {"home": Color.WHITE, "mission": Color("#f5c518"), "guns": Color("#c0c6cc"), "spray": Color("#2b5fb3"),
	"food": Color("#1aa39e"), "park": Color("#f5c518"), "garage": Color("#ef7d22"), "hospital": Color("#ff5a6e"),
	"police": Color("#5aa9ff")}
const ICON := {"home": "SAFEHOUSE", "guns": "GUNS", "spray": "RESPRAY", "food": "FOOD", "park": "RENT", "garage": "GARAGE"}

var state: GameState
var main                          # main_city.gd
var police: Police
var pois: Array = []              # {id, type, name, pos: Vector3}
var dests: Array = []             # taxi / mission destinations
var districts: Array = []
var menus: Dictionary = {}


func setup(game_state: GameState, main_node, pol: Police) -> void:
	state = game_state
	main = main_node
	police = pol
	var places: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/city/places.json"))
	for group in ["poi", "dest", "district"]:
		for e in places[group]:
			var p: Array = e["pos"]
			var d: Dictionary = e.duplicate()
			d["pos"] = Vector3(p[0], p[1], p[2])
			(pois if group == "poi" else (dests if group == "dest" else districts)).append(d)
	menus = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/game/data/shops.json"))
	for p in pois:
		if ICON.has(p["type"]):
			_marker(p)


func poi(id: String) -> Dictionary:
	for p in pois:
		if p["id"] == id:
			return p
	for d in dests:
		if d["id"] == id:
			return d
	return {}


func place_pos(id: String) -> Vector3:
	var p := poi(id)
	return p["pos"] if not p.is_empty() else Vector3.ZERO


func district_at(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for d in districts:
		var dd := Vector2(p.x - d["pos"].x, p.z - d["pos"].z).length()
		if dd < bd:
			bd = dd
			best = d["name"]
	return best


func _marker(p: Dictionary) -> void:
	var col: Color = COLORS.get(p["type"], Color.WHITE)
	var root := Node3D.new()
	add_child(root)
	root.global_position = p["pos"]
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.1
	cyl.height = 0.05
	ring.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.position.y = 0.05
	ring.visibility_range_end = 120.0
	root.add_child(ring)
	var lab := Label3D.new()
	lab.text = ICON[p["type"]]
	lab.font_size = 64
	lab.pixel_size = 0.01
	lab.outline_size = 12
	lab.modulate = col
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position.y = 3.2
	lab.visibility_range_end = 160.0
	root.add_child(lab)


## The point of interest within reach of the player (on foot) or the car (respray only).
func nearby_poi() -> Dictionary:
	var in_car: bool = main.car != null
	var p: Vector3 = main.car.global_position if in_car else main.player.global_position
	for q in pois:
		var r := 6.0 if in_car else 2.4
		if (q["pos"] as Vector3).distance_to(p) < r:
			if in_car and q["type"] != "spray":
				continue
			return q
	return {}


func prompt() -> String:
	var q := nearby_poi()
	if q.is_empty():
		return ""
	match q["type"]:
		"spray":
			return "[E] Respray (%s): new paint, repairs, police lose you" % GameState.money_text(int(menus["spray"]["cost"])) if main.car != null else "Bring a car here to respray it"
		"home":
			return "[E] Safehouse: rest and save"
		"guns":
			return "[E] Weapon shop"
		"food":
			return "[E] Eat at " + q["name"]
		"park":
			return "[E] " + q["name"]
		"mission":
			return main.missions.prompt()
	return ""


func interact() -> bool:
	var q := nearby_poi()
	if q.is_empty():
		return false
	var t: String = q["type"]
	if t == "spray":
		_respray()
		return true
	if t == "mission":
		main.missions.open_menu()
		return true
	if not menus.has(t):
		return false
	var m: Dictionary = menus[t]
	var items: Array = m["items"]
	var opts: Array = []
	for it in items:
		opts.append({"label": it["label"], "cost": int(it["cost"]), "disabled": not _can(it)})
	var title: String = m["title"] if String(m["title"]) != "" else String(q["name"])
	main.hud.open_menu(title, m["text"], opts, func(i: int): _buy(items[i], q))
	return true


func _can(it: Dictionary) -> bool:
	if not state.can_afford(int(it["cost"])):
		return false
	match it["action"]:
		"pistol":
			return not state.has_pistol
		"weapon":
			return not state.owned[int(it["weapon"])]
		"ammo":
			return state.owned[int(it.get("weapon", GameState.PISTOL))]
		"armor":
			return state.armor < 100.0
	return true


func _buy(it: Dictionary, q: Dictionary) -> void:
	if not state.spend(int(it["cost"])):
		return
	match String(it["action"]):
		"pistol":
			state.give_pistol(int(it["rounds"]))
			state.say("Pistol bought. Hold Tab for the weapon wheel, right mouse to aim.")
		"weapon":
			state.give_weapon(int(it["weapon"]), int(it.get("rounds", 0)))
			state.say(String(it["label"]) + " bought. Hold Tab for the weapon wheel.")
		"ammo":
			state.add_ammo(int(it["rounds"]), int(it.get("weapon", GameState.PISTOL)))
			state.say("Ammo bought.")
		"armor":
			state.set_armor(100.0)
			state.say("Body armour on.")
		"eat":
			state.heal(float(it["heal"]))
			state.say("You ate " + String(it["label"]).to_lower() + ". Sweet!")
		"rent":
			main.rent_vehicle(String(it["vehicle"]), q["pos"])
		"rest":
			state.heal(100.0)
			main.clock.advance(60.0)
			main.save_game()
			state.say("You feel better. Game saved.")
		"sleep":
			var m := state.minute_of_day()
			main.clock.advance((1440.0 - m + 420.0) if m >= 420.0 else (420.0 - m))
			state.heal(100.0)
			main.save_game()
			state.say("Good morning! Day %d. Game saved." % state.day())


func _respray() -> void:
	var cost := int(menus["spray"]["cost"])
	if main.car == null:
		return
	if not state.spend(cost):
		state.say("A respray costs %s." % GameState.money_text(cost))
		return
	var car = main.car
	car.repair()
	if car.kind not in ["taxi", "keke", "police"]:
		car.set_paint(Color.from_hsv(randf(), 0.65, 0.75))
	if state.stars > 0:
		police.clear()
		state.say("New paint, new plates. The police lost you.", Color("#3ccf7a"))
	else:
		state.say("Car repaired and resprayed.")
