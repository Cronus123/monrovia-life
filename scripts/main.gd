extends Node2D
## Monrovia Life: Streets — original top-down open-world crime-action game (Godot 4, 2D).
## All game state lives here; drawing is delegated to simple layer nodes.

const WG = preload("res://scripts/world.gd")
const Layer = preload("res://scripts/layer.gd")
const HudLayer = preload("res://scripts/hud_layer.gd")
const TS := 32.0
const CS := 16
const SAVE_PATH := "user://monrovia_streets_save.json"

const SPEC := {
	"keke": {"max": 9.0, "acc": 6.5, "turn": 2.7, "rad": 0.42, "hp": 60.0},
	"taxi": {"max": 13.5, "acc": 8.0, "turn": 2.3, "rad": 0.5, "hp": 100.0},
	"car": {"max": 13.0, "acc": 8.0, "turn": 2.3, "rad": 0.5, "hp": 100.0},
	"sport": {"max": 18.0, "acc": 11.0, "turn": 2.5, "rad": 0.5, "hp": 90.0},
	"suv": {"max": 12.5, "acc": 7.5, "turn": 2.1, "rad": 0.56, "hp": 140.0},
	"truck": {"max": 9.5, "acc": 5.0, "turn": 1.6, "rad": 0.66, "hp": 200.0},
	"police": {"max": 15.5, "acc": 10.0, "turn": 2.5, "rad": 0.52, "hp": 150.0},
	"van": {"max": 11.0, "acc": 6.0, "turn": 1.8, "rad": 0.62, "hp": 400.0},
}
const LINES := ["How da body?", "Ma people! How you doing?", "Ah, the sun hot today oh.", "Rain coming, find shade small.",
	"Keke business moving small small.", "The traffic by ELWA junction... ya!", "Monrovia sweet at night time.",
	"You hear? LibGamer tournament coming soon!", "I beg you, come buy my kala.", "Take your time on that road oh.",
	"Waterside market full today.", "Where you going? Red Light?", "Hello my friend!", "I just come from Bushrod.",
	"Football at SKD this weekend!", "Mind yourself, police everywhere today."]
const MISSIONS := [
	{"title": "Wheels for the Crew", "reward": 1500,
		"intro": "Welcome back to Monrovia, Kollie. My crew needs wheels. Take any car and bring it to my garage in Vai Town."},
	{"title": "Freeport Pickup", "reward": 2500,
		"intro": "A package is waiting at the Freeport. Pick it up and get it to Red Light Market. Two minutes once it's in your hands."},
	{"title": "Heat on the Bridge", "reward": 3000,
		"intro": "Police are asking questions about my garage. I told them it was you. Pull them away and lose them."},
	{"title": "Red Light Rival", "reward": 5000,
		"intro": "The Red Light Boys keep sending a red sports car to scare my drivers around Paynesville. Wreck it."},
	{"title": "The Big Score", "reward": 10000,
		"intro": "An armored van is parked in Sinkor. Take it and bring it to the Freeport docks. Police will come fast."},
]

# ------------------------------------------------------------------ nodes
var world
var cam: Camera2D
var night: CanvasModulate
var actors
var hud
var font: Font
var mini_tex: ImageTexture
var logo: Texture2D
var light_tex: GradientTexture2D
var head_light: PointLight2D
var lamp_lights: Array = []

# ------------------------------------------------------------------ state
var started := false
var money := 300
var time_min := 9.0 * 60.0
var health := 100.0
var armor := 0.0
var p_pos := Vector2.ZERO
var p_dir := 0.0
var p_walk := 0.0
var car = null
var weapon := 0
var ammo := 0
var has_pistol := false
var stars := 0
var evade_t := 0.0
var shoot_cd := 0.0
var bust_t := 0.0
var hurt_cd := 0.0
var cars: Array = []
var peds: Array = []
var bullets: Array = []
var fx: Array = []
var pickups: Array = []
var toasts: Array = []
var big_text := ""
var big_t := 0.0
var mission_idx := 0
var mission = null
var hire := false
var fare = null
var map_open := false
var menu = null
var menu_rects: Array = []
var police_cd := 0.0
var rain_until := 0.0
var rain_from := 0.0
var last_rain_day := -1
var shirts: Array = []
var skins: Array = []
var car_cols: Array = []
var spr := {}
const TINTED := ["car", "sport", "suv", "truck"]

# ================================================================== setup
func _ready() -> void:
	randomize()
	font = ThemeDB.fallback_font
	for h in ["#c8173a", "#1aa39e", "#f5c518", "#2b5fb3", "#ef7d22", "#7c3aed", "#ffffff", "#3ccf7a", "#e06aa8", "#14213d"]:
		shirts.append(Color(h))
	for h in ["#5a3825", "#6b4329", "#4a2e1e", "#7a4e30", "#3d2618"]:
		skins.append(Color(h))
	for h in ["#f5c518", "#f5c518", "#ffffff", "#c0c6cc", "#2b2b2b", "#c8173a", "#2b5fb3", "#ffffff", "#3a6b3a"]:
		car_cols.append(Color(h))
	world = WG.new()
	# Blender-rendered sprites (tools/make_sprites.py); drawn shapes are used if missing
	for n in ["veh_keke", "veh_taxi", "veh_car", "veh_sport", "veh_suv", "veh_truck", "veh_police", "veh_van",
			"ped_0", "ped_1", "ped_2", "ped_3", "ped_4", "ped_5", "ped_player", "ped_cop", "ped_auntie"]:
		var path := "res://sprites/%s.png" % n
		if ResourceLoader.exists(path):
			spr[n] = load(path)
	if ResourceLoader.exists("res://logo.webp"):
		logo = load("res://logo.webp")
	# map chunks
	for cy in range(int(ceil(float(WG.H) / CS))):
		for cx in range(int(ceil(float(WG.W) / CS))):
			var c = Layer.new()
			var ccx: int = cx
			var ccy: int = cy
			c.draw_fn = func(ci): world.draw_chunk(ci, ccx, ccy, CS)
			add_child(c)
	var roads_layer = Layer.new()
	roads_layer.draw_fn = func(ci): world.draw_roads(ci)
	add_child(roads_layer)
	var lm = Layer.new()
	lm.draw_fn = _draw_static
	add_child(lm)
	actors = Layer.new()
	actors.draw_fn = _draw_actors
	add_child(actors)
	night = CanvasModulate.new()
	add_child(night)
	# lights
	light_tex = GradientTexture2D.new()
	light_tex.width = 256
	light_tex.height = 256
	light_tex.fill = GradientTexture2D.FILL_RADIAL
	light_tex.fill_from = Vector2(0.5, 0.5)
	light_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.8, 1))
	g.set_color(1, Color(1, 0.95, 0.8, 0))
	light_tex.gradient = g
	head_light = PointLight2D.new()
	head_light.texture = light_tex
	head_light.texture_scale = 2.0
	add_child(head_light)
	for i in 10:
		var l := PointLight2D.new()
		l.texture = light_tex
		l.texture_scale = 1.6
		l.color = Color(1, 0.85, 0.55)
		add_child(l)
		lamp_lights.append(l)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	add_child(cam)
	cam.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudLayer.new()
	hud.draw_fn = _draw_hud
	hud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(hud)
	mini_tex = ImageTexture.create_from_image(world.build_minimap_image())
	p_pos = world.poi("home").pos + Vector2(0, 0.6)
	cam.position = Vector2(60, 58) * TS

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func start_game(cont: bool) -> void:
	started = true
	cars.clear(); peds.clear(); bullets.clear(); pickups.clear()
	if cont and has_save():
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			money = int(d.get("money", 300)); time_min = float(d.get("time", 540.0)); health = float(d.get("health", 100.0))
			armor = float(d.get("armor", 0.0)); has_pistol = bool(d.get("pistol", false)); ammo = int(d.get("ammo", 0))
			mission_idx = int(d.get("mission", 0)); p_pos = Vector2(float(d.get("px", p_pos.x)), float(d.get("py", p_pos.y)))
		toast("Welcome back to Monrovia.")
	else:
		toast("Welcome home, Kollie. Auntie Musu is waiting at Waterside (M on your map).", 7.0)
		toast("F: take a car   E: use   Mouse: aim and shoot   M: map", 7.0)
	cam.position = p_pos * TS
	cam.reset_smoothing()

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({"money": money, "time": time_min, "health": health, "armor": armor, "pistol": has_pistol,
		"ammo": ammo, "mission": mission_idx, "px": p_pos.x, "py": p_pos.y}))

# ================================================================== input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not started:
			start_game(has_save() and event.position.y > get_viewport_rect().size.y * 0.62)
			return
		if menu != null:
			for r in menu_rects:
				if (r.rect as Rect2).has_point(event.position):
					_choose(r.i)
					return
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.physical_keycode
	if not started:
		if k == KEY_ENTER or k == KEY_SPACE or k == KEY_N: start_game(false)
		elif k == KEY_C and has_save(): start_game(true)
		return
	if menu != null:
		if k == KEY_ESCAPE: menu = null
		elif k >= KEY_1 and k <= KEY_9: _choose(k - KEY_1)
		return
	if map_open:
		if k == KEY_M or k == KEY_ESCAPE: map_open = false
		return
	match k:
		KEY_F: enter_exit()
		KEY_E: interact()
		KEY_T: toggle_hire()
		KEY_M: map_open = true
		KEY_ESCAPE: pause_menu()
		KEY_1: weapon = 0
		KEY_2:
			if has_pistol: weapon = 1
			else: toast("You don't have a pistol. Buy one at a weapon shop.")
		KEY_Q:
			if has_pistol: weapon = 1 - weapon

func _choose(i: int) -> void:
	if menu == null: return
	var opts: Array = menu.opts
	if i < 0 or i > opts.size(): return
	if i == opts.size():
		menu = null
		return
	var o: Dictionary = opts[i]
	if o.get("disabled", false): return
	menu = null
	(o.fn as Callable).call()

func open_menu(title: String, text: String, opts: Array) -> void:
	menu = {"title": title, "text": text, "opts": opts}

func toast(msg: String, dur: float = 3.5, col: Color = Color.WHITE) -> void:
	toasts.append({"m": msg, "t": dur, "c": col})
	while toasts.size() > 4:
		toasts.pop_front()

func pause_menu() -> void:
	open_menu("Paused", "Day %d, %s. Missions done: %d of %d." % [day(), clock(), mission_idx, MISSIONS.size()], [
		{"label": "Save game", "fn": _act_save},
		{"label": "Controls", "fn": open_menu.bind("Controls", "WASD or arrows: move and drive.  Shift: run.  Mouse: aim, left click: shoot or punch.  F: get in, take or leave a car.  E: use shops and talk.  T: taxi hire light.  Q / 1 / 2: weapons.  Space: handbrake.  M: map.  Esc: pause.", [])},
		{"label": "Quit to desktop", "fn": _act_quit},
	])

# ================================================================== helpers
func day() -> int:
	return int(time_min / 1440.0) + 1

func mod_min() -> float:
	return fmod(time_min, 1440.0)

func clock() -> String:
	var m := int(mod_min())
	var h := m / 60
	return "%d:%02d %s" % [((h + 11) % 12) + 1, m % 60, "AM" if h < 12 else "PM"]

func fmt(n) -> String:
	var s := str(abs(int(n)))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if int(n) < 0 else "") + "L$ " + s + out

func pos() -> Vector2:
	return car.pos if car != null else p_pos

func solid(t: int) -> bool:
	return t == WG.OCEAN or t == WG.RIVER or t == WG.MANG or t == WG.BLD or t == WG.LMK or t == WG.TREE

func offroad(p: Vector2) -> bool:
	var t: int = world.tile_at(p)
	return t != WG.ROAD and t != WG.BRIDGE and t != WG.TARMAC

func foot_free(p: Vector2, r: float = 0.28) -> bool:
	return not (solid(world.tile_at(p + Vector2(-r, -r))) or solid(world.tile_at(p + Vector2(r, -r))) or solid(world.tile_at(p + Vector2(-r, r))) or solid(world.tile_at(p + Vector2(r, r))))

func car_hits(p: Vector2, rad: float) -> bool:
	if p.x < 0.5 or p.y < 0.5 or p.x > WG.W - 0.5 or p.y > WG.H - 0.5: return true
	for k in 8:
		var a := k * PI / 4.0
		if solid(world.tile_at(p + Vector2(cos(a), sin(a)) * rad)): return true
	return false

func walkable(p: Vector2) -> bool:
	var t: int = world.tile_at(p)
	return t == WG.GROUND or t == WG.MARKET or t == WG.SAND or t == WG.GRASS

func move_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	return v.limit_length(1.0)

func near_poi(t: String, r: float = 1.6):
	var best = null
	var bd := r
	for q in world.pois:
		if t != "" and q.t != t: continue
		var d: float = (q.pos as Vector2).distance_to(pos())
		if d < bd:
			bd = d
			best = q
	return best

func rain_amt() -> float:
	if time_min < rain_from or time_min > rain_until: return 0.0
	return clamp(min(time_min - rain_from, rain_until - time_min) / 25.0, 0.0, 1.0)

func darkness() -> float:
	var m := mod_min() / 60.0
	if m >= 7.0 and m < 17.5: return 0.0
	if m >= 17.5 and m < 19.5: return (m - 17.5) / 2.0
	if m >= 5.0 and m < 7.0: return (7.0 - m) / 2.0
	return 1.0

func roll_weather() -> void:
	if last_rain_day == day(): return
	last_rain_day = day()
	if randf() < 0.4:
		rain_from = (day() - 1) * 1440.0 + randf_range(8.0, 18.0) * 60.0
		rain_until = rain_from + randf_range(90.0, 240.0)

# ================================================================== cars
func make_car(type: String, p: Vector2, a: float, ai: String, col = null) -> Dictionary:
	var c := {"type": type, "pos": p, "a": a, "v": 0.0, "hp": SPEC[type].hp, "ai": ai, "col": col if col != null else car_cols.pick_random(),
		"road": -1, "s": 0.0, "dir": 1, "max": SPEC[type].max * 0.6, "burn": -1.0, "wreck": false, "stuck": 0.0, "rev": 0.0,
		"rev_steer": 1.0, "shoot": 0.0, "cops_out": false, "mission": "", "siren": randf() * 6.0}
	if type == "police": c.col = Color("#f4f6f8")
	if type == "keke": c.col = Color("#f5c518")
	if type == "van": c.col = Color("#6b7680")
	cars.append(c)
	return c

func road_spawn(min_d: float, max_d: float, wide_only: bool = true):
	var p := pos()
	for tries in 16:
		var ri: int = randi() % int(world.roads.size())
		var r: Dictionary = world.roads[ri]
		if wide_only and r.w < 2.0: continue
		var s: float = randf() * float(r.total)
		var q: Dictionary = world.point_on(r, s)
		var d: float = (q.pos as Vector2).distance_to(p)
		if d >= min_d and d <= max_d:
			return {"ri": ri, "s": s, "q": q}
	return null

func drive_car(c: Dictionary, thr: float, steer: float, dt: float, handbrake: bool = false) -> bool:
	var sp: Dictionary = SPEC[c.type]
	var mx: float = sp.max * (0.5 if offroad(c.pos) else 1.0) * (0.85 if rain_amt() > 0.3 else 1.0)
	if c.burn >= 0.0: mx *= 0.4
	if thr > 0.0: c.v += (sp.acc * 2.2 if c.v < 0 else sp.acc) * thr * dt
	elif thr < 0.0: c.v += (-sp.acc * 2.2 if c.v > 0 else -sp.acc * 0.6) * (-thr) * dt
	else: c.v *= pow(0.4, dt)
	if handbrake: c.v *= pow(0.02, dt)
	c.v = clamp(c.v, -mx * 0.35, mx)
	if abs(c.v) > 0.05: c.a += steer * sp.turn * dt * clamp(c.v / 3.0, -1.0, 1.0)
	var np: Vector2 = c.pos + Vector2(cos(c.a), sin(c.a)) * c.v * dt
	if not car_hits(np, sp.rad):
		c.pos = np
		return false
	var nx := Vector2(np.x, c.pos.y)
	var ny := Vector2(c.pos.x, np.y)
	if not car_hits(nx, sp.rad):
		c.pos = nx; c.v *= 0.92
	elif not car_hits(ny, sp.rad):
		c.pos = ny; c.v *= 0.92
	else:
		if abs(c.v) > 6.0: damage_car(c, abs(c.v) * 1.5, false)
		c.v *= -0.3
	return true

func damage_car(c: Dictionary, dmg: float, by_player: bool) -> void:
	if c.wreck: return
	c.hp -= dmg
	if by_player and c.type == "police": add_stars(1)
	if c.hp <= 0.0 and c.burn < 0.0:
		c.burn = 4.0
		if c.ai == "traffic": c.ai = "dead"
		if c == car: toast("Your car is on fire! Get out (F)!", 3.0, Color("#ff5a6e"))

func explode(c: Dictionary) -> void:
	c.wreck = true
	c.burn = -1.0
	c.v = 0.0
	c.ai = "dead"
	fx.append({"k": "boom", "pos": c.pos, "t": 0.0})
	panic(c.pos, 14.0)
	for q in peds:
		if q.state != "down" and (q.pos as Vector2).distance_to(c.pos) < 2.6: knock_ped(q, c == car)
	for o in cars:
		if o != c and (o.pos as Vector2).distance_to(c.pos) < 2.4: damage_car(o, 60.0, false)
	if car == c:
		hurt(200.0)
	elif p_pos.distance_to(c.pos) < 2.2 and car == null:
		hurt(60.0)
	if mission != null and mission.get("ref") == c and mission.i == 3:
		complete_mission()

func enter_exit() -> void:
	if car != null:
		if abs(car.v) > 2.5: return
		var sp: Dictionary = SPEC[car.type]
		var placed := false
		for ang in [PI / 2, -PI / 2, PI, 0.0]:
			var e: Vector2 = car.pos + Vector2(cos(car.a + ang), sin(car.a + ang)) * (sp.rad + 0.6)
			if foot_free(e):
				p_pos = e; placed = true; break
		if not placed: p_pos = car.pos
		car.v = 0.0
		if car.ai == "player": car.ai = "parked"
		car = null
		if hire:
			hire = false
			if fare != null: toast("Your passenger got out without paying.")
			fare = null
			clear_waiting()
		return
	var best = null
	var bd := 1.9
	for c in cars:
		if c.wreck: continue
		var d: float = (c.pos as Vector2).distance_to(p_pos)
		if d < bd:
			bd = d; best = c
	if best == null: return
	var c: Dictionary = best
	if c.ai == "traffic" or c.ai == "rival":
		var drv = spawn_ped(c.pos + Vector2(cos(c.a + PI / 2), sin(c.a + PI / 2)) * 0.9, "flee")
		if drv != null: drv.flee_from = p_pos
		toast("You pulled the driver out and took the " + _car_name(c.type) + ".")
		crime(1)
	elif c.ai == "police" or c.ai == "police_idle":
		toast("You stole a police car!", 3.0, Color("#ff5a6e"))
		add_stars(2)
	c.ai = "player"
	c.v = 0.0
	car = c

func _car_name(t: String) -> String:
	return {"keke": "keke", "taxi": "taxi", "car": "car", "sport": "sports car", "suv": "SUV", "truck": "truck", "police": "police car", "van": "armored van"}.get(t, "car")

# ================================================================== people
func spawn_ped(p: Vector2, state: String = "walk"):
	var q := {"pos": p, "vel": Vector2.ZERO, "t": 0.0, "shirt": shirts.pick_random(), "skin": skins.pick_random(),
		"load": randf() < 0.2, "lappa": randf() < 0.5, "phase": randf() * 6.0, "state": state, "hp": 60.0,
		"say": "", "say_t": 0.0, "pause": 0.0, "flee_t": 4.0, "flee_from": p, "down_t": 0.0, "shoot": randf(), "dest": null}
	var si := randi() % 6
	q["spr"] = "ped_%d" % si
	q.shirt = shirts[si]
	if state == "cop":
		q.shirt = Color("#2b4a7a"); q.hp = 90.0; q.load = false; q.lappa = false
		q["spr"] = "ped_cop"
	peds.append(q)
	return q

func spawn_random_ped(around: Vector2, wait: bool = false) -> void:
	for k in 20:
		var p: Vector2
		if wait:
			p = world.random_curb()
			var d := p.distance_to(around)
			if d < 10 or d > 32: continue
		else:
			var a := randf() * TAU
			p = around + Vector2(cos(a), sin(a)) * randf_range(12.0, 28.0)
			if not walkable(p): continue
		var q = spawn_ped(p, "wait" if wait else "walk")
		if wait:
			q.load = false
			for g in 30:
				var d2: Dictionary = world.dests.pick_random()
				if (d2.pos as Vector2).distance_to(p) > 18:
					q.dest = d2
					break
			if q.dest == null: q.dest = world.dests[0]
		return

func panic(at: Vector2, r: float) -> void:
	for q in peds:
		if (q.state == "walk" or q.state == "wait") and (q.pos as Vector2).distance_to(at) < r:
			q.state = "flee"; q.flee_from = at; q.flee_t = 5.0

func knock_ped(q: Dictionary, by_player: bool) -> void:
	if q.state == "down": return
	var was_cop: bool = q.state == "cop"
	q.state = "down"
	q.down_t = 25.0
	q.vel = Vector2.ZERO
	if randf() < 0.6:
		pickups.append({"pos": q.pos + Vector2(randf_range(-.3, .3), randf_range(-.3, .3)), "amt": randi_range(10, 80), "t": 30.0})
	panic(q.pos, 10.0)
	if by_player:
		if was_cop: add_stars(2)
		else: crime(1)

func hit_ped(q: Dictionary, dmg: float, by_player: bool) -> void:
	q.hp -= dmg
	if q.state != "cop" and q.state != "down":
		q.state = "flee"; q.flee_from = p_pos; q.flee_t = 6.0
	if q.hp <= 0.0: knock_ped(q, by_player)
	elif by_player and q.state == "cop": add_stars(1)

func clear_waiting() -> void:
	peds = peds.filter(func(q): return q.state != "wait")

# ================================================================== crime
func crime(n: int) -> void:
	var seen := randf() < 0.4
	for c in cars:
		if (c.ai == "police" or c.ai == "police_idle") and (c.pos as Vector2).distance_to(pos()) < 16: seen = true
	for q in peds:
		if q.state == "cop" and (q.pos as Vector2).distance_to(pos()) < 16: seen = true
	if seen or stars > 0: add_stars(n)

func add_stars(n: int) -> void:
	var before := stars
	stars = min(5, stars + n)
	evade_t = 0.0
	if stars > before and before == 0: toast("The police are after you!", 3.0, Color("#ff5a6e"))

func hurt(d: float) -> void:
	if armor > 0.0:
		var a: float = min(armor, d * 0.7)
		armor -= a
		d -= a
	health -= d
	if health <= 0.0: knocked_out()

func knocked_out() -> void:
	var fee: int = min(money, int(money * 0.1) + 100)
	money -= fee
	big_text = "DOWN AND OUT"
	big_t = 3.0
	_respawn(world.dest("JFK Medical Center"))
	toast("JFK Medical Center patched you up. Hospital bill: " + fmt(fee), 5.0)

func arrested() -> void:
	var fee: int = min(money, int(money * 0.1) + 200)
	money -= fee
	big_text = "ARRESTED"
	big_t = 3.0
	has_pistol = false; ammo = 0; weapon = 0
	_respawn(world.dest("Police HQ"))
	toast("Released from Police HQ. Fine paid: " + fmt(fee) + ". Your weapon was taken.", 5.0)

func _respawn(at: Vector2) -> void:
	if mission != null: fail_mission("Mission failed.")
	if car != null:
		car.ai = "parked"; car.v = 0.0
	car = null
	hire = false; fare = null
	stars = 0; bust_t = 0.0
	health = 100.0
	p_pos = at
	time_min += 120.0
	cars = cars.filter(func(c): return c.type != "police")
	peds = peds.filter(func(q): return q.state != "cop")
	cam.position = p_pos * TS
	cam.reset_smoothing()

# ================================================================== weapons
func fire(from: Vector2, ang: float, owner: String) -> void:
	var d := Vector2(cos(ang), sin(ang))
	bullets.append({"pos": from + d * 0.55, "vel": d * 32.0, "life": 0.6, "owner": owner})
	fx.append({"k": "flash", "pos": from + d * 0.55, "t": 0.0})
	if owner == "player": panic(from, 14.0)

func update_bullets(dt: float) -> void:
	var keep: Array = []
	for b in bullets:
		var alive := true
		var steps := 4
		for s in steps:
			b.pos += b.vel * dt / steps
			if solid(world.tile_at(b.pos)) and world.tile_at(b.pos) != WG.OCEAN and world.tile_at(b.pos) != WG.RIVER:
				alive = false; break
			if b.owner == "player":
				for q in peds:
					if q.state != "down" and (q.pos as Vector2).distance_to(b.pos) < 0.42:
						hit_ped(q, 40.0, true); alive = false; break
				if not alive: break
				for c in cars:
					if c != car and not c.wreck and (c.pos as Vector2).distance_to(b.pos) < SPEC[c.type].rad:
						damage_car(c, 18.0, true); alive = false
						if c.ai == "traffic": crime(1)
						break
			else:
				if pos().distance_to(b.pos) < 0.45:
					if car != null: damage_car(car, 8.0, false)
					else: hurt(9.0)
					alive = false
			if not alive: break
		b.life -= dt
		if alive and b.life > 0.0: keep.append(b)
	bullets = keep

# ================================================================== update
func _process(delta: float) -> void:
	var dt: float = min(delta, 0.05)
	for t in toasts: t.t -= delta
	toasts = toasts.filter(func(t): return t.t > 0.0)
	if big_t > 0.0: big_t -= delta
	for f in fx: f.t += delta
	fx = fx.filter(func(f): return f.t < (0.9 if f.k == "boom" else 0.08))
	if started and menu == null and not map_open:
		var prev_day := day()
		time_min += dt * 2.0
		if day() != prev_day: roll_weather()
		update_player(dt)
		update_traffic(dt)
		update_police(dt)
		update_peds(dt)
		update_bullets(dt)
		update_collisions(dt)
		update_cars_misc(dt)
		update_taxi(dt)
		update_mission(dt)
		update_wanted(dt)
	_update_view(dt)
	actors.queue_redraw()
	hud.queue_redraw()

func update_player(dt: float) -> void:
	var iv := move_input()
	shoot_cd -= dt
	hurt_cd -= dt
	if car != null:
		drive_car(car, -iv.y, iv.x, dt, Input.is_physical_key_pressed(KEY_SPACE))
		p_pos = car.pos
		p_dir = car.a
	else:
		var run := Input.is_physical_key_pressed(KEY_SHIFT)
		var spd := 6.5 if run else 4.0
		var d := iv * spd * dt
		if foot_free(p_pos + Vector2(d.x, 0)): p_pos.x += d.x
		if foot_free(p_pos + Vector2(0, d.y)): p_pos.y += d.y
		if iv.length() > 0.1: p_walk += dt * spd * 2.0
		var aim := get_global_mouse_position() / TS - p_pos
		if aim.length() > 0.1: p_dir = aim.angle()
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and shoot_cd <= 0.0:
			if weapon == 1 and ammo > 0:
				fire(p_pos, p_dir + randf_range(-0.04, 0.04), "player")
				ammo -= 1
				shoot_cd = 0.28
				if stars == 0 and randf() < 0.3:
					crime(1)
			elif weapon == 1:
				toast("Out of ammo. Buy more at a weapon shop.")
				weapon = 0
				shoot_cd = 0.5
			else:
				shoot_cd = 0.45
				var hit_pos := p_pos + Vector2(cos(p_dir), sin(p_dir)) * 0.8
				fx.append({"k": "flash", "pos": hit_pos, "t": 0.0})
				for q in peds:
					if q.state != "down" and (q.pos as Vector2).distance_to(hit_pos) < 0.7:
						hit_ped(q, 25.0, true)
						if q.state != "down" and q.state != "cop": crime(1)
						break
	for pk in pickups:
		if (pk.pos as Vector2).distance_to(p_pos) < 0.8:
			money += pk.amt
			pk.t = 0.0
			toast("+" + fmt(pk.amt), 1.5, Color("#f5c518"))
	for pk in pickups: pk.t -= dt
	pickups = pickups.filter(func(pk): return pk.t > 0.0)
	if car == null and health < 100.0 and stars == 0: health = min(100.0, health + dt * 0.5)

func update_traffic(dt: float) -> void:
	var p := pos()
	var limit := 14 if rain_amt() > 0.5 else 24
	cars = cars.filter(func(c): return c == car or c.mission != "" or c.ai == "parked" or (c.pos as Vector2).distance_to(p) < 60.0)
	var n_traffic := 0
	for c in cars:
		if c.ai == "traffic": n_traffic += 1
	if n_traffic < limit:
		var sp = road_spawn(14.0, 45.0)
		if sp != null:
			var roll := randf()
			var type := "keke" if roll < 0.25 else ("taxi" if roll < 0.5 else ("car" if roll < 0.75 else ("suv" if roll < 0.88 else ("truck" if roll < 0.96 else "sport"))))
			var c := make_car(type, sp.q.pos, 0.0, "traffic")
			c.road = sp.ri; c.s = sp.s; c.dir = 1 if randf() < 0.5 else -1
			c.max = SPEC[type].max * (0.62 if type != "sport" else 0.7)
			if type == "taxi": c.col = Color("#f5c518")
	for c in cars:
		if c.ai == "traffic" or c.ai == "rival": _follow_road(c, dt)

func _follow_road(c: Dictionary, dt: float) -> void:
	var r: Dictionary = world.roads[c.road]
	var lane: float = r.w * 0.26
	var look: Dictionary = world.point_on(r, c.s + c.dir * 1.8)
	var ahead: Vector2 = look.pos + look.nrm * lane * c.dir
	var block := false
	if ahead.distance_to(pos()) < 1.3 + (SPEC[car.type].rad if car != null else 0.3): block = true
	if not block:
		for o in cars:
			if o != c and (o.pos as Vector2).distance_to(ahead) < 1.1:
				block = true; break
	if not block and c.ai != "rival":
		for q in peds:
			if q.state != "down" and (q.pos as Vector2).distance_to(ahead) < 0.9:
				block = true; break
	if c.ai == "rival": block = block and (ahead.distance_to(pos()) < 1.0)
	var target: float = 0.0 if block else c.max * (0.8 if rain_amt() > 0.3 else 1.0)
	c.v += clamp(target - c.v, -14.0 * dt, 4.0 * dt)
	c.s += c.dir * c.v * dt
	if c.s > r.total or c.s < 0.0:
		c.s = clamp(c.s, 0.0, r.total)
		# hop onto a connecting road if one is close, otherwise U-turn
		var end_pt: Vector2 = world.point_on(r, c.s).pos
		var options: Array = []
		for ri in world.roads.size():
			if ri == c.road: continue
			var o: Dictionary = world.roads[ri]
			if o.w < 2.0 and c.ai != "rival": continue
			if (o.p[0] as Vector2).distance_to(end_pt) < 2.0: options.append([ri, 0.0, 1])
			elif (o.p[o.p.size() - 1] as Vector2).distance_to(end_pt) < 2.0: options.append([ri, o.total, -1])
		if options.size() > 0 and randf() < 0.85:
			var pick: Array = options.pick_random()
			c.road = pick[0]; c.s = pick[1]; c.dir = pick[2]
			r = world.roads[c.road]
			lane = r.w * 0.26
		else:
			c.dir *= -1
	var q: Dictionary = world.point_on(r, c.s)
	c.pos = q.pos + q.nrm * lane * c.dir
	c.a = (q.dir * c.dir).angle()

func update_police(dt: float) -> void:
	police_cd -= dt
	var want: int = [0, 1, 2, 3, 4, 6][stars]
	var have := 0
	for c in cars:
		if c.type == "police" and c.ai == "police": have += 1
	if have < want and police_cd <= 0.0:
		var sp = road_spawn(16.0, 30.0)
		if sp != null:
			var c := make_car("police", sp.q.pos, (pos() - sp.q.pos).angle(), "police")
			c.v = 6.0
			police_cd = 2.5
	for c in cars:
		if c.ai != "police": continue
		var sp: Dictionary = SPEC[c.type]
		var to: Vector2 = pos() - c.pos
		var dist := to.length()
		if stars == 0:
			drive_car(c, 0.0, 0.0, dt)
			if dist > 22.0:
				c.mission = ""
				c.pos = Vector2(-100, -100)
			continue
		var blocked := false
		if c.rev > 0.0:
			c.rev -= dt
			blocked = drive_car(c, -1.0, c.rev_steer, dt)
		else:
			var diff := wrapf(to.angle() - c.a, -PI, PI)
			var steer: float = clamp(diff * 2.0, -1.0, 1.0)
			var target_v: float = sp.max * (0.65 if offroad(c.pos) else 1.0)
			if dist < 2.5: target_v = 4.0
			if abs(diff) > 1.6: target_v = min(target_v, 5.0)
			var thr := 1.0 if c.v < target_v else -0.4
			blocked = drive_car(c, thr, steer, dt)
		if blocked and abs(c.v) < 1.5: c.stuck += dt
		else: c.stuck = max(0.0, c.stuck - dt)
		if c.stuck > 0.7:
			c.rev = 0.9; c.rev_steer = -1.0 if randf() < 0.5 else 1.0; c.stuck = 0.0
		if car == null and dist < 6.0 and not c.cops_out:
			c.cops_out = true
			c.ai = "police_idle"
			c.v = 0.0
			for k in min(stars + 1, 3):
				spawn_ped(c.pos + Vector2(randf_range(-.6, .6), randf_range(-.6, .6)), "cop")
		c.shoot -= dt
		if stars >= 3 and dist < 9.0 and c.shoot <= 0.0:
			fire(c.pos, to.angle() + randf_range(-0.14, 0.14), "cop")
			c.shoot = 1.5
	for c in cars:
		if c.ai == "police_idle":
			c.v *= pow(0.1, dt)
			if car != null and stars > 0 and (c.pos as Vector2).distance_to(pos()) > 8.0:
				c.ai = "police"; c.cops_out = false
				peds = peds.filter(func(q): return not (q.state == "cop" and (q.pos as Vector2).distance_to(c.pos) < 4.0))

func update_peds(dt: float) -> void:
	var p := pos()
	var dk := darkness()
	var target := int((14 if dk > 0.5 else 34) * (1.0 - rain_amt() * 0.6))
	for L in world.landmarks:
		if L.k == "market" and Vector2(L.x, L.y).distance_to(p) < 30: target += 16
	peds = peds.filter(func(q): return (q.pos as Vector2).distance_to(p) < (45.0 if q.state == "wait" else 38.0) and not (q.state == "down" and q.down_t <= 0.0))
	var normal := 0
	var waiting := 0
	for q in peds:
		if q.state == "walk" or q.state == "flee": normal += 1
		if q.state == "wait": waiting += 1
	if normal < target: spawn_random_ped(p)
	if hire and fare == null and waiting < 3 and randf() < dt * 0.8: spawn_random_ped(p, true)
	for q in peds:
		if q.say_t > 0.0: q.say_t -= dt
		match q.state:
			"down":
				q.down_t -= dt
			"wait":
				q.t += dt
			"cop":
				var to: Vector2 = p - q.pos
				var d := to.length()
				if stars == 0:
					q.state = "walk"; q.t = 0.0
					continue
				if d > 0.9:
					var step: Vector2 = to / d * 4.6 * dt
					var qp: Vector2 = q.pos
					if foot_free(qp + Vector2(step.x, 0)):
						qp.x += step.x
					if foot_free(qp + Vector2(0, step.y)):
						qp.y += step.y
					q.pos = qp
					q.vel = to / d
					q.phase += dt * 8.0
				q.shoot -= dt
				if stars >= 2 and d < 10.0 and q.shoot <= 0.0:
					fire(q.pos, to.angle() + randf_range(-0.18, 0.18), "cop")
					q.shoot = 1.1 + randf() * 0.6
			"flee":
				q.flee_t -= dt
				var away: Vector2 = (q.pos - q.flee_from).normalized()
				if away == Vector2.ZERO: away = Vector2.RIGHT
				var np: Vector2 = q.pos + away * 5.0 * dt
				if walkable(np) or world.tile_at(np) == WG.ROAD: q.pos = np
				else: q.flee_from = q.pos + Vector2(randf_range(-1, 1), randf_range(-1, 1))
				q.vel = away
				q.phase += dt * 10.0
				if q.flee_t <= 0.0: q.state = "walk"
			_:
				if q.pause > 0.0:
					q.pause -= dt
					continue
				q.t -= dt
				if q.t <= 0.0:
					var a := randf() * TAU
					q.vel = Vector2(cos(a), sin(a)) * 1.2
					q.t = randf_range(2.0, 6.0)
					if randf() < 0.25: q.vel = Vector2.ZERO
				var np: Vector2 = q.pos + q.vel * dt
				var here_road: bool = world.tile_at(q.pos) == WG.ROAD
				if walkable(np) or (here_road and not solid(world.tile_at(np))):
					q.pos = np
					q.phase += dt * 6.0
				else:
					q.t = 0.0
				if car != null and abs(car.v) > 2.0 and (q.pos as Vector2).distance_to(car.pos) < 2.0:
					q.state = "flee"; q.flee_from = car.pos; q.flee_t = 1.0

func update_collisions(dt: float) -> void:
	# car vs car
	var n := cars.size()
	for i in n:
		var a: Dictionary = cars[i]
		if (a.pos as Vector2).distance_to(pos()) > 30.0: continue
		for j in range(i + 1, n):
			var b: Dictionary = cars[j]
			var rr: float = SPEC[a.type].rad + SPEC[b.type].rad
			var d: float = (a.pos as Vector2).distance_to(b.pos)
			if d >= rr or d < 0.001: continue
			var nrm: Vector2 = (a.pos - b.pos) / d
			var push := rr - d + 0.01
			var a_mov: bool = a.ai != "traffic" and a.ai != "rival"
			var b_mov: bool = b.ai != "traffic" and b.ai != "rival"
			if a_mov and not car_hits(a.pos + nrm * push * (0.5 if b_mov else 1.0), SPEC[a.type].rad): a.pos += nrm * push * (0.5 if b_mov else 1.0)
			if b_mov and not car_hits(b.pos - nrm * push * (0.5 if a_mov else 1.0), SPEC[b.type].rad): b.pos -= nrm * push * (0.5 if a_mov else 1.0)
			var rel: float = abs(a.v) + abs(b.v)
			if rel > 6.0 and (a == car or b == car):
				var other: Dictionary = b if a == car else a
				damage_car(car, rel * 1.2, false)
				damage_car(other, rel * 2.0, true)
				if other.ai == "traffic": other.v = 0.0
				if other.type != "police" and rel > 10.0: crime(1)
			if a_mov: a.v *= 0.6
			if b_mov: b.v *= 0.6
	# car vs people
	for c in cars:
		if abs(c.v) < 3.5 or c.wreck: continue
		var cr: float = SPEC[c.type].rad + 0.25
		if c == car:
			for q in peds:
				if q.state != "down" and (q.pos as Vector2).distance_to(c.pos) < cr:
					knock_ped(q, true)
					c.v *= 0.85
		elif car == null and hurt_cd <= 0.0 and p_pos.distance_to(c.pos) < cr + 0.05:
			hurt(abs(c.v) * 2.5)
			hurt_cd = 1.0
			var away: Vector2 = (p_pos - c.pos).normalized()
			if foot_free(p_pos + away * 0.7): p_pos += away * 0.7

func update_cars_misc(dt: float) -> void:
	for c in cars:
		if c.burn >= 0.0:
			c.burn -= dt
			if c.burn < 0.0: explode(c)
	cars = cars.filter(func(c): return not (c.pos as Vector2).x < -50)

func update_wanted(dt: float) -> void:
	if stars <= 0:
		bust_t = 0.0
		return
	var seen := false
	var near := false
	for c in cars:
		if c.type == "police" and (c.ai == "police" or c.ai == "police_idle") and not c.wreck:
			var d: float = (c.pos as Vector2).distance_to(pos())
			if d < 16.0: seen = true
			if d < 1.7 and abs(c.v) < 2.0 and (car == null or (abs(car.v) < 0.6 and stars <= 2)): near = true
	for q in peds:
		if q.state == "cop":
			var d: float = (q.pos as Vector2).distance_to(pos())
			if d < 16.0: seen = true
			if d < 1.2 and car == null: near = true
	if seen: evade_t = 0.0
	else:
		evade_t += dt
		if evade_t > 5.0 + stars * 2.5:
			stars = 0
			toast("You lost the police.", 3.0, Color("#3ccf7a"))
			return
	if near: bust_t += dt
	else: bust_t = max(0.0, bust_t - dt)
	if bust_t > 1.6: arrested()

# ================================================================== interaction
func interact() -> void:
	if menu != null: return
	var q = near_poi("", 2.2 if car != null else 1.6)
	if q != null:
		if q.t == "spray":
			_spray()
			return
		if car == null:
			match q.t:
				"home": _home_menu()
				"mission": _mission_menu()
				"guns": _gun_menu()
				"food": _food_menu(q)
				"park": _park_menu(q)
			if q.t != "garage":
				return
	if car == null:
		var best = null
		var bd := 1.5
		for p in peds:
			if p.state == "walk" or p.state == "wait":
				var d: float = (p.pos as Vector2).distance_to(p_pos)
				if d < bd:
					bd = d; best = p
		if best != null:
			best.say = LINES.pick_random(); best.say_t = 3.2; best.pause = 3.0; best.vel = Vector2.ZERO

func prompt_text() -> String:
	if menu != null or map_open: return ""
	var q = near_poi("", 2.2 if car != null else 1.6)
	if q != null:
		if car != null and q.t == "spray": return "[E] Respray (clears police, repairs)"
		if car == null:
			match q.t:
				"home": return "[E] Safehouse: save and heal"
				"mission": return "[E] Talk to Auntie Musu" if mission == null and mission_idx < MISSIONS.size() else "[E] Auntie Musu"
				"guns": return "[E] Weapon shop"
				"spray": return "Bring a car here to respray it"
				"food": return "[E] Eat at " + q.n
				"park": return "[E] " + q.n
	if car != null:
		return "[F] Get out" if abs(car.v) < 2.5 else ""
	for c in cars:
		if not c.wreck and (c.pos as Vector2).distance_to(p_pos) < 1.9:
			if c.ai == "traffic" or c.ai == "rival": return "[F] Take the " + _car_name(c.type)
			return "[F] Get in the " + _car_name(c.type)
	return ""

func _home_menu() -> void:
	open_menu("Safehouse, Sinkor", "A quiet room off Tubman Boulevard. Rest here to heal fully and save your progress.", [
		{"label": "Rest and save", "fn": _act_rest},
		{"label": "Sleep until morning", "fn": _act_sleep},
	])

func _act_save() -> void:
	save_game()
	toast("Game saved.")

func _act_quit() -> void:
	save_game()
	get_tree().quit()

func _act_rest() -> void:
	health = 100.0
	time_min += 60.0
	save_game()
	toast("You feel better. Game saved.")

func _act_sleep() -> void:
	var m := mod_min()
	time_min += (1440.0 - m + 420.0) if m >= 420.0 else (420.0 - m)
	health = 100.0
	roll_weather()
	save_game()
	toast("Good morning! Day %d. Game saved." % day())

func _mission_menu() -> void:
	if mission_idx >= MISSIONS.size():
		open_menu("Auntie Musu", "\"You did it, Kollie. Monrovia knows your name now. Go enjoy the city.\"", [])
		return
	if mission != null:
		open_menu("Auntie Musu", "\"Why you standing here? Go finish the job!\"", [{"label": "Give up this mission", "fn": func(): fail_mission("Mission abandoned.")}])
		return
	var m: Dictionary = MISSIONS[mission_idx]
	open_menu("Mission %d: %s" % [mission_idx + 1, m.title], "Auntie Musu: \"" + m.intro + "\"  Reward: " + fmt(m.reward), [
		{"label": "Start the mission", "fn": func(): start_mission(mission_idx)},
	])

func _gun_menu() -> void:
	open_menu("Weapon shop", "Licensed dealer. Cash only.", [
		{"label": "Pistol with 36 rounds", "cost": 1500, "disabled": has_pistol or money < 1500, "fn": _buy.bind("pistol", 1500)},
		{"label": "36 more rounds", "cost": 300, "disabled": not has_pistol or money < 300, "fn": _buy.bind("ammo", 300)},
		{"label": "Body armor", "cost": 800, "disabled": armor >= 100.0 or money < 800, "fn": _buy.bind("armor", 800)},
	])

func _buy(what: String, cost: int) -> void:
	money -= cost
	match what:
		"pistol":
			has_pistol = true
			ammo += 36
			weapon = 1
			toast("Pistol bought. Q switches weapons.")
		"ammo":
			ammo += 36
			toast("Ammo bought.")
		"armor":
			armor = 100.0
			toast("Body armor on.")
		"food":
			toast("Sweet!")
		"keke", "taxi":
			pass

func _spray() -> void:
	if car == null: return
	if money < 400:
		toast("A respray costs " + fmt(400) + ".")
		return
	money -= 400
	car.col = car_cols.pick_random() if car.type != "keke" and car.type != "police" else car.col
	car.hp = SPEC[car.type].hp
	car.burn = -1.0
	if stars > 0: toast("New paint, new plates. The police lost you.", 3.5, Color("#3ccf7a"))
	else: toast("Car repaired and resprayed.")
	stars = 0

func _food_menu(q: Dictionary) -> void:
	var foods := [["Kala and tea", 60, 15], ["Rice and potato greens", 150, 35], ["Rice and cassava leaf", 180, 40], ["Fufu and pepper soup", 220, 50], ["Palm butter and rice", 250, 60]]
	var opts: Array = []
	for f in foods:
		var nm: String = f[0]
		var cost: int = f[1]
		var heal: int = f[2]
		opts.append({"label": nm, "cost": cost, "disabled": money < cost, "fn": _eat.bind(nm, cost, heal)})
	open_menu(q.n, "Hot food, fresh today. Eating restores your health.", opts)

func _eat(nm: String, cost: int, heal: int) -> void:
	money -= cost
	health = min(100.0, health + heal)
	toast("You ate " + nm.to_lower() + ". Sweet!")

func _park_menu(q: Dictionary) -> void:
	var spawn_at: Vector2 = q.pos
	open_menu(q.n, "Rent a vehicle the legal way. It stays where you leave it.", [
		{"label": "Rent a keke", "cost": 250, "disabled": money < 250, "fn": _spawn_rental.bind("keke", spawn_at, 250)},
		{"label": "Rent a taxi", "cost": 700, "disabled": money < 700, "fn": _spawn_rental.bind("taxi", spawn_at, 700)},
	])

func _spawn_rental(type: String, at: Vector2, cost: int) -> void:
	money -= cost
	var best := at
	var bd := 1e9
	for y in range(int(at.y) - 6, int(at.y) + 7):
		for x in range(int(at.x) - 6, int(at.x) + 7):
			if world.tile_xy(x, y) == WG.ROAD:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(at)
				if d > 1.0 and d < bd:
					bd = d; best = Vector2(x + 0.5, y + 0.5)
	var c := make_car(type, best, 0.0, "parked")
	c.col = Color("#f5c518")
	toast("Your " + type + " is parked by the road. Press F to get in, T for taxi work.")

# ================================================================== taxi side job
func toggle_hire() -> void:
	if car == null or (car.type != "taxi" and car.type != "keke"):
		toast("You need a taxi or keke for taxi work.")
		return
	if mission != null:
		toast("Finish your mission first.")
		return
	if hire and fare != null:
		toast("Drop your passenger first.")
		return
	hire = not hire
	if hire: toast("Hire light ON. Look for people waving by the road.")
	else:
		clear_waiting(); toast("Hire light OFF.")

func update_taxi(dt: float) -> void:
	if not hire or car == null: return
	if fare == null:
		for q in peds:
			if q.state == "wait" and (q.pos as Vector2).distance_to(car.pos) < 2.2 and abs(car.v) < 1.5:
				var dist: float = (q.dest.pos as Vector2).distance_to(car.pos)
				var amt := int(round((40.0 + dist * 6.0) * (1.7 if car.type == "taxi" else 1.0) / 5.0) * 5)
				fare = {"dest": q.dest, "amt": amt, "t0": time_min, "dist": dist}
				peds.erase(q)
				clear_waiting()
				toast("Passenger: \"Take me to %s, I beg you.\" Fare %s" % [q.dest.n, fmt(amt)], 5.0)
				break
	else:
		if (fare.dest.pos as Vector2).distance_to(car.pos) < 2.6 and abs(car.v) < 1.8:
			var fast: bool = time_min - fare.t0 < fare.dist * 1.6 + 20.0
			var tip: int = int(fare.amt * 0.2) if fast else 0
			money += fare.amt + tip
			toast("+" + fmt(fare.amt + tip) + ("  with a tip for a quick ride!" if tip > 0 else "  Fare paid."), 4.0, Color("#f5c518"))
			fare = null

# ================================================================== missions
func start_mission(i: int) -> void:
	if hire:
		hire = false; fare = null; clear_waiting()
	mission = {"i": i, "step": 0, "timer": 0.0, "target": null, "tname": "", "ref": null, "obj": ""}
	match i:
		0:
			mission.target = world.poi("garage").pos; mission.tname = "Crew garage"
			mission.obj = "Take any car (F) and bring it to the crew garage in Vai Town."
		1:
			mission.target = world.dest("Freeport of Monrovia"); mission.tname = "Freeport"
			mission.obj = "Go to the Freeport to pick up the package."
		2:
			add_stars(3)
			mission.obj = "Lose the police. Break their line of sight or use a respray shop."
		3:
			var sp = null
			for k in 30:
				var cand = road_spawn(0.0, 400.0)
				if cand != null and (cand.q.pos as Vector2).x > 185.0:
					sp = cand; break
			if sp == null: sp = road_spawn(0.0, 400.0)
			var c := make_car("sport", sp.q.pos, 0.0, "rival", Color("#c8173a"))
			c.road = sp.ri; c.s = sp.s; c.max = 11.0; c.mission = "rival"
			mission.ref = c; mission.tname = "Rival car"
			mission.obj = "Find the red sports car in Paynesville and wreck it (ram it or shoot it)."
		4:
			var at: Vector2 = world.nearest_curb(112, 71)
			var c := make_car("van", at, 0.0, "parked")
			c.mission = "van"
			mission.ref = c; mission.target = at; mission.tname = "Armored van"
			mission.obj = "Steal the armored van in Sinkor."
	toast("Mission: " + MISSIONS[i].title, 4.0, Color("#f5c518"))

func mission_target():
	if mission == null: return null
	if mission.ref != null and mission.i == 3: return mission.ref.pos
	if mission.i == 4 and mission.step == 0 and mission.ref != null: return mission.ref.pos
	return mission.target

func update_mission(dt: float) -> void:
	if mission == null: return
	var m: Dictionary = mission
	match m.i:
		0:
			if car != null and car.type != "police" and (m.target as Vector2).distance_to(car.pos) < 2.5 and abs(car.v) < 2.0:
				var c = car
				enter_exit()
				c.ai = "parked"; c.mission = "delivered"
				complete_mission()
		1:
			if m.step == 0 and (m.target as Vector2).distance_to(pos()) < 2.6:
				m.step = 1; m.timer = 120.0; m.target = world.dest("Red Light Market"); m.tname = "Red Light Market"
				m.obj = "Deliver the package to Red Light Market before time runs out!"
				toast("Package collected. Go, go, go!", 3.0, Color("#f5c518"))
			elif m.step == 1:
				m.timer -= dt
				if (m.target as Vector2).distance_to(pos()) < 2.6: complete_mission()
				elif m.timer <= 0.0: fail_mission("Too slow. The buyer left.")
		2:
			if stars == 0: complete_mission()
		3:
			var r: Dictionary = m.ref
			if r.wreck:
				complete_mission()
			elif (r.pos as Vector2).distance_to(pos()) > 140.0:
				fail_mission("The rival got away.")
		4:
			if m.step == 0 and car != null and car == m.ref:
				m.step = 1; m.target = world.dest("Freeport of Monrovia"); m.tname = "Freeport docks"
				m.obj = "Get the van to the Freeport docks!"
				add_stars(2)
			elif m.step == 1:
				if (m.ref as Dictionary).wreck: fail_mission("The van was destroyed.")
				elif car == m.ref and (m.target as Vector2).distance_to(car.pos) < 3.0 and abs(car.v) < 2.5:
					complete_mission()

func complete_mission() -> void:
	if mission == null: return
	var m: Dictionary = MISSIONS[mission.i]
	money += m.reward
	big_text = "MISSION PASSED"
	big_t = 3.0
	toast("+" + fmt(m.reward) + "  " + m.title, 5.0, Color("#f5c518"))
	if mission.i == 2: stars = 0
	mission = null
	mission_idx += 1
	if mission_idx >= MISSIONS.size():
		toast("Auntie Musu: \"Monrovia is yours now, Kollie.\" Thanks for playing this LibGamer demo!", 8.0, Color("#3ccf7a"))
	else:
		toast("Auntie Musu has another job for you at Waterside.", 5.0)
	save_game()

func fail_mission(reason: String) -> void:
	if mission == null: return
	if mission.ref != null and not mission.ref.wreck and mission.ref != car:
		mission.ref.mission = ""
		if mission.i == 3: mission.ref.pos = Vector2(-100, -100)
	mission = null
	big_text = "MISSION FAILED"
	big_t = 2.5
	toast(reason + " Talk to Auntie Musu to try again.", 5.0, Color("#ff5a6e"))

# ================================================================== view
func _update_view(dt: float) -> void:
	var p := pos()
	if started:
		cam.position = p * TS
	else:
		cam.position += Vector2(30, 6) * dt
		if cam.position.x > 230 * TS: cam.position.x = 20 * TS
	var spd: float = abs(car.v) if car != null else 0.0
	var z: float = lerp(1.0, 0.68, clamp(spd / 16.0, 0.0, 1.0))
	cam.zoom = cam.zoom.lerp(Vector2(z, z), clamp(dt * 2.0, 0.0, 1.0))
	var dk := clampf(darkness() + rain_amt() * 0.3, 0.0, 1.0)
	night.color = Color(1, 1, 1).lerp(Color(0.3, 0.34, 0.55), dk)
	head_light.visible = dk > 0.2
	head_light.energy = dk * 1.1
	if car != null:
		head_light.position = (car.pos + Vector2(cos(car.a), sin(car.a)) * 2.5) * TS
		head_light.texture_scale = 2.2
	else:
		head_light.position = p_pos * TS
		head_light.texture_scale = 1.2
	# nearest street lamps
	if dk > 0.2:
		var near: Array = []
		for L in world.lamps:
			var d: float = (L as Vector2).distance_to(p)
			if d < 22.0: near.append([d, L])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for i in lamp_lights.size():
			var l: PointLight2D = lamp_lights[i]
			if i < near.size():
				l.visible = true; l.position = near[i][1] * TS; l.energy = dk * 0.9
			else:
				l.visible = false
	else:
		for l in lamp_lights: l.visible = false

# ================================================================== drawing: world
func _draw_static(ci: CanvasItem) -> void:
	world.draw_landmarks(ci, font)
	_draw_pois(ci)

func _draw_pois(ci: CanvasItem) -> void:
	for q in world.pois:
		var X: Vector2 = q.pos * TS
		match q.t:
			"home":
				ci.draw_rect(Rect2(X.x - 13, X.y - 14, 26, 20), Color("#e3d3ad"))
				ci.draw_colored_polygon(PackedVector2Array([X + Vector2(-16, -12), X + Vector2(0, -24), X + Vector2(16, -12)]), Color("#a0522d"))
				ci.draw_rect(Rect2(X.x - 4, X.y - 6, 8, 12), Color("#14213d"))
			"food":
				ci.draw_rect(Rect2(X.x - 12, X.y - 4, 24, 10), Color("#7a4e30"))
				ci.draw_colored_polygon(PackedVector2Array([X + Vector2(-15, -6), X + Vector2(0, -16), X + Vector2(15, -6)]), Color("#1aa39e"))
			"guns":
				ci.draw_rect(Rect2(X.x - 12, X.y - 14, 24, 18), Color("#14213d"))
				ci.draw_rect(Rect2(X.x - 7, X.y - 8, 12, 4), Color("#c0c6cc"))
				ci.draw_rect(Rect2(X.x - 7, X.y - 6, 4, 7), Color("#c0c6cc"))
			"spray":
				ci.draw_rect(Rect2(X.x - 14, X.y - 14, 28, 22), Color("#2b5fb3"))
				ci.draw_circle(X + Vector2(-5, -3), 4, Color("#c8173a"))
				ci.draw_circle(X + Vector2(4, -3), 4, Color("#f5c518"))
			"park":
				ci.draw_rect(Rect2(X.x - 14, X.y - 14, 28, 28), Color("#f5c518"), false, 2.0)
				ci.draw_rect(Rect2(X.x - 9, X.y - 9, 18, 18), Color("#14213d"))
				ci.draw_string(font, X + Vector2(-4, 5), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#f5c518"))
			"garage":
				ci.draw_rect(Rect2(X.x - 16, X.y - 16, 32, 24), Color("#555a60"))
				for k in 4: ci.draw_line(X + Vector2(-14, -12 + k * 5), X + Vector2(14, -12 + k * 5), Color("#3a3d42"), 2.0)

func _draw_car(ci: CanvasItem, c: Dictionary, lights: bool) -> void:
	var X: Vector2 = c.pos * TS
	ci.draw_set_transform(X, c.a, Vector2.ONE)
	var col: Color = c.col
	if c.wreck: col = Color("#2a2a2a")
	var key: String = "veh_" + c.type
	if spr.has(key):
		ci.draw_rect(Rect2(-16, -8, 34, 19), Color(0, 0, 0, 0.25))
		var tint: Color = col if c.type in TINTED else Color.WHITE
		if c.wreck: tint = Color(0.22, 0.22, 0.22)
		ci.draw_texture_rect(spr[key], Rect2(-28, -14, 56, 28), false, tint)
		if c.type == "police" and not c.wreck:
			var fl := int(Time.get_ticks_msec() / 180) % 2 == 0
			ci.draw_circle(Vector2(-2, -3 if fl else 3), 3.0, Color(1, 0.2, 0.25, 0.9) if fl else Color(0.2, 0.45, 1, 0.9))
	else:
		_draw_car_shape(ci, c, col)
	if lights and not c.wreck:
		var fx_x := 12.0 if c.type == "keke" else 15.0
		ci.draw_rect(Rect2(fx_x, -6, 3, 3), Color("#fff7c2")); ci.draw_rect(Rect2(fx_x, 3, 3, 3), Color("#fff7c2"))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if c.burn >= 0.0 or c.wreck:
		var t := Time.get_ticks_msec() / 1000.0
		for k in 4:
			var o := Vector2(sin(t * 7 + k) * 5, -k * 6 - fmod(t * 20, 6))
			ci.draw_circle(X + o, 6 - k, Color(1, 0.5 - k * 0.1, 0.1, 0.8) if c.burn >= 0.0 else Color(0.2, 0.2, 0.2, 0.5))

func _draw_car_shape(ci: CanvasItem, c: Dictionary, col: Color) -> void:
	match c.type:
		"keke":
			ci.draw_rect(Rect2(-11, -8, 24, 18), Color(0, 0, 0, 0.3))
			ci.draw_rect(Rect2(8, -2, 6, 4), Color("#222222"))
			ci.draw_rect(Rect2(-10, -10, 7, 4), Color("#222222")); ci.draw_rect(Rect2(-10, 6, 7, 4), Color("#222222"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-12, -8), Vector2(6, -8), Vector2(13, -3), Vector2(13, 3), Vector2(6, 8), Vector2(-12, 8)]), col)
			ci.draw_rect(Rect2(-12, -7, 14, 14), Color("#1d5a3a") if not c.wreck else col)
			ci.draw_rect(Rect2(4, -5, 3, 10), Color("#bfe3ff"))
		"truck":
			ci.draw_rect(Rect2(-20, -10, 42, 22), Color(0, 0, 0, 0.3))
			for wx in [-16, 10]:
				ci.draw_rect(Rect2(wx, -12, 8, 4), Color("#222222")); ci.draw_rect(Rect2(wx, 9, 8, 4), Color("#222222"))
			ci.draw_rect(Rect2(-21, -10, 30, 20), col)
			ci.draw_rect(Rect2(10, -9, 11, 18), Color("#e8e8e8"))
			ci.draw_rect(Rect2(16, -7, 4, 14), Color("#1b2a3a"))
		"van":
			ci.draw_rect(Rect2(-19, -10, 40, 22), Color(0, 0, 0, 0.3))
			for wx in [-15, 8]:
				ci.draw_rect(Rect2(wx, -12, 8, 4), Color("#222222")); ci.draw_rect(Rect2(wx, 9, 8, 4), Color("#222222"))
			ci.draw_rect(Rect2(-20, -10, 40, 20), col)
			ci.draw_rect(Rect2(-16, -6, 22, 12), col.darkened(0.2))
			ci.draw_rect(Rect2(10, -8, 6, 16), Color("#1b2a3a"))
			ci.draw_rect(Rect2(-12, -2, 14, 4), Color("#f5c518"))
		_:
			var L := 34.0 if c.type == "sport" else (33.0 if c.type == "suv" else 31.0)
			var Wd := 15.0 if c.type == "sport" else (18.0 if c.type == "suv" else 16.0)
			ci.draw_rect(Rect2(-L / 2 + 1, -Wd / 2, L, Wd + 3), Color(0, 0, 0, 0.3))
			for wx in [-L / 2 + 4, L / 2 - 11]:
				ci.draw_rect(Rect2(wx, -Wd / 2 - 2, 7, 4), Color("#222222")); ci.draw_rect(Rect2(wx, Wd / 2 - 2, 7, 4), Color("#222222"))
			ci.draw_rect(Rect2(-L / 2, -Wd / 2, L, Wd), col)
			ci.draw_rect(Rect2(L / 2 - 13, -Wd / 2 + 2, 6, Wd - 4), Color("#1b2a3a"))
			ci.draw_rect(Rect2(-L / 2 + 4, -Wd / 2 + 2, 4, Wd - 4), Color("#1b2a3a"))
			ci.draw_rect(Rect2(-6, -Wd / 2 + 2, 8, Wd - 4), Color(1, 1, 1, 0.18))
			if c.type == "taxi": ci.draw_rect(Rect2(-4, -1.5, 6, 3), Color("#14213d"))
			if c.type == "sport": ci.draw_rect(Rect2(-L / 2, -1.5, L, 3), Color(1, 1, 1, 0.8))
			if c.type == "police":
				ci.draw_rect(Rect2(-L / 2, -Wd / 2, 9, Wd), Color("#14213d"))
				ci.draw_rect(Rect2(L / 2 - 6, -Wd / 2, 6, Wd), Color("#14213d"))
				var flash := int(Time.get_ticks_msec() / 180) % 2 == 0
				ci.draw_rect(Rect2(-3, -6, 4, 6), Color("#ff2a3a") if flash else Color("#2a6bff"))
				ci.draw_rect(Rect2(-3, 0, 4, 6), Color("#2a6bff") if flash else Color("#ff2a3a"))

func _draw_person(ci: CanvasItem, q: Dictionary, is_player: bool = false) -> void:
	var X: Vector2 = q.pos * TS
	var shirt: Color = q.shirt
	var skin: Color = q.skin
	if q.get("state", "") == "down":
		WG.ellipse(ci, X, 10, 5, Color(0.4, 0, 0, 0.35))
		ci.draw_set_transform(X, 0.4, Vector2.ONE)
		ci.draw_rect(Rect2(-8, -4, 14, 8), shirt)
		ci.draw_circle(Vector2(9, 0), 4.5, skin)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var dir: float = q.get("dir", (q.vel as Vector2).angle() if q.has("vel") else 0.0)
	var moving: bool = q.get("moving", false)
	var sk: String = q.get("spr", "")
	if spr.has(sk):
		WG.ellipse(ci, X + Vector2(2, 5), 9, 5, Color(0, 0, 0, 0.28))
		var bob := absf(sin(q.phase)) * 1.5 if moving else 0.0
		ci.draw_set_transform(X + Vector2(0, -4 - bob), dir, Vector2.ONE)
		ci.draw_texture_rect(spr[sk], Rect2(-13, -13, 26, 26), false)
		if is_player and weapon == 1:
			ci.draw_line(Vector2(4, 6), Vector2(16, 6), Color("#1b1b1b"), 3.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var sw := sin(q.phase) * 3.0 if moving else 0.0
	WG.ellipse(ci, X + Vector2(2, 6), 7, 4, Color(0, 0, 0, 0.28))
	ci.draw_rect(Rect2(X.x - 4, X.y + 1 + sw * 0.3, 3, 6), Color("#222222"))
	ci.draw_rect(Rect2(X.x + 1, X.y + 1 - sw * 0.3, 3, 6), Color("#222222"))
	ci.draw_rect(Rect2(X.x - 5, X.y - 1, 10, 4), Color("#ef7d22") if q.get("lappa", false) else Color("#2b3a55"))
	WG.ellipse(ci, X + Vector2(0, -4), 6.5, 5.5, shirt)
	ci.draw_circle(X + Vector2(cos(dir) * 1.2, -10), 4.5, skin)
	if q.get("state", "") == "cop":
		ci.draw_circle(X + Vector2(0, -12), 4.0, Color("#14213d"))
	if q.get("load", false):
		WG.ellipse(ci, X + Vector2(0, -14), 7, 3.5, Color("#d9a441"))
	if is_player and weapon == 1:
		ci.draw_line(X + Vector2(0, -5), X + Vector2(0, -5) + Vector2(cos(dir), sin(dir)) * 13, Color("#1b1b1b"), 3.0)

func _draw_actors(ci: CanvasItem) -> void:
	var p := pos()
	var vp := get_viewport_rect().size / cam.zoom / TS / 2.0 + Vector2(3, 3)
	var c0: Vector2 = cam.get_screen_center_position() / TS
	var vis := func(v: Vector2) -> bool: return abs(v.x - c0.x) < vp.x and abs(v.y - c0.y) < vp.y
	var t := Time.get_ticks_msec() / 1000.0
	var dark := darkness() > 0.3
	# mission giver
	var mg = world.poi("mission")
	if not mg.is_empty() and mission == null and mission_idx < MISSIONS.size():
		var X: Vector2 = mg.pos * TS + Vector2(0, -34 + sin(t * 4) * 3)
		ci.draw_circle(X, 11, Color("#f5c518"))
		ci.draw_string(font, X + Vector2(-6, 6), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#14213d"))
	if not mg.is_empty():
		_draw_person(ci, {"pos": mg.pos, "shirt": Color("#7c3aed"), "skin": skins[0], "phase": 0.0, "lappa": true, "dir": PI / 2, "spr": "ped_auntie"})
	for pk in pickups:
		if vis.call(pk.pos):
			var X: Vector2 = pk.pos * TS
			ci.draw_rect(Rect2(X.x - 7, X.y - 4, 14, 8), Color("#3ccf7a"))
			ci.draw_rect(Rect2(X.x - 7, X.y - 4, 14, 8), Color("#14532d"), false, 1.0)
	for q in peds:
		if q.state == "down" and vis.call(q.pos): _draw_person(ci, q)
	for c in cars:
		if c != car and vis.call(c.pos): _draw_car(ci, c, dark)
	for q in peds:
		if q.state == "down" or not vis.call(q.pos): continue
		q["moving"] = (q.vel as Vector2).length() > 0.05 and q.pause <= 0.0
		_draw_person(ci, q)
		if q.state == "wait":
			var Y := (q.pos as Vector2) * TS + Vector2(0, -26 + sin(t * 6) * 2)
			ci.draw_circle(Y, 8, Color("#f5c518"))
			ci.draw_string(font, Y + Vector2(-2, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#14213d"))
		if q.say_t > 0.0:
			var w := font.get_string_size(q.say, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14
			var Y := (q.pos as Vector2) * TS + Vector2(-w / 2, -48)
			ci.draw_rect(Rect2(Y, Vector2(w, 22)), Color(1, 1, 1, 0.95))
			ci.draw_string(font, Y + Vector2(7, 15), q.say, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#14213d"))
	if car != null:
		_draw_car(ci, car, dark)
		if hire:
			ci.draw_circle(car.pos * TS, 3.5, Color("#c8173a") if fare != null else Color("#3ccf7a"))
	else:
		_draw_person(ci, {"pos": p_pos, "shirt": Color("#c8173a"), "skin": skins[0], "phase": p_walk, "moving": move_input().length() > 0.1, "dir": p_dir, "spr": "ped_player"}, true)
	for b in bullets:
		var X: Vector2 = b.pos * TS
		ci.draw_line(X, X - (b.vel as Vector2).normalized() * 10, Color("#ffe27a"), 2.0)
	for f in fx:
		var X: Vector2 = f.pos * TS
		if f.k == "flash":
			ci.draw_circle(X, 6, Color(1, 0.9, 0.4, 0.9))
		else:
			var k: float = f.t / 0.9
			ci.draw_circle(X, 20 + k * 70, Color(1, 0.55, 0.1, 0.8 * (1.0 - k)))
			ci.draw_circle(X, 10 + k * 40, Color(1, 0.9, 0.5, 0.9 * (1.0 - k)))
	# target ring
	var tg = _current_target()
	if tg != null:
		ci.draw_arc(tg * TS, 26 + sin(t * 4) * 3, 0, TAU, 32, Color("#f5c518"), 3.0)

func _current_target():
	var mt = mission_target()
	if mt != null: return mt
	if hire and car != null:
		if fare != null: return fare.dest.pos
		var best = null
		var bd := 1e9
		for q in peds:
			if q.state == "wait":
				var d: float = (q.pos as Vector2).distance_to(car.pos)
				if d < bd:
					bd = d; best = q.pos
		return best
	return null

# ================================================================== drawing: HUD
func _text(ci: CanvasItem, p: Vector2, s: String, size: int = 16, col: Color = Color.WHITE, center: bool = false) -> void:
	var x := p.x
	if center: x -= font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	ci.draw_string_outline(font, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.03, 0.05, 0.1, 0.85))
	ci.draw_string(font, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _panel(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, Color(0.063, 0.102, 0.196, 0.86))
	ci.draw_rect(r, Color(0.54, 0.59, 0.64, 0.35), false, 1.0)

func _star(ci: CanvasItem, c: Vector2, r: float, filled: bool) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + k * PI / 5
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	if filled:
		ci.draw_colored_polygon(pts, Color("#f5c518"))
	else:
		ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.35))
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0.05, 0.08, 0.15, 0.9), 1.5)

func _draw_hud(ci: Control) -> void:
	var sz := ci.size
	if not started:
		_draw_title(ci, sz)
		return
	var p := pos()
	# rain
	var ra := rain_amt()
	if ra > 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		for k in int(160 * ra):
			var x := fmod(k * 97.3 + t * 60.0 * (k % 3 + 2), sz.x + 40)
			var y := fmod(k * 53.7 + t * 700.0, sz.y + 40)
			ci.draw_line(Vector2(x, y), Vector2(x - 4, y + 16), Color(0.8, 0.86, 1, 0.35 * ra), 1.0)
	# top-left panel
	_panel(ci, Rect2(12, 12, 250, 128))
	_text(ci, Vector2(24, 34), "DAY %d%s" % [day(), "  ·  RAIN" if ra > 0 else ""], 12, Color("#b9c3cc"))
	_text(ci, Vector2(250 - 60, 34), clock(), 12, Color("#b9c3cc"))
	_text(ci, Vector2(24, 60), fmt(money), 24, Color("#f5c518"))
	_text(ci, Vector2(24, 82), world.district_at(p), 15)
	_text(ci, Vector2(24, 100), world.street_at(p), 12, Color("#b9c3cc"))
	ci.draw_rect(Rect2(24, 110, 226, 7), Color(1, 1, 1, 0.12))
	ci.draw_rect(Rect2(24, 110, 226 * clamp(health / 100.0, 0.0, 1.0), 7), Color("#3ccf7a") if health > 30 else Color("#ff5a6e"))
	if armor > 0.0:
		ci.draw_rect(Rect2(24, 121, 226, 5), Color(1, 1, 1, 0.12))
		ci.draw_rect(Rect2(24, 121, 226 * armor / 100.0, 5), Color("#5aa9ff"))
	var wtxt := ("Pistol  %d" % ammo) if weapon == 1 else "Fists"
	_text(ci, Vector2(24, 136), wtxt, 11, Color("#dfe6ec"))
	# minimap
	var mr := Rect2(sz.x - 252, 12, 240, 160)
	ci.draw_rect(mr, Color("#1d6e9e"))
	var src := Rect2(p.x - 40, p.y - 26.667, 80, 53.333)
	var clip := src.intersection(Rect2(0, 0, WG.W, WG.H))
	if clip.size.x > 0 and clip.size.y > 0:
		var dst := Rect2(mr.position + (clip.position - src.position) * 3.0, clip.size * 3.0)
		ci.draw_texture_rect_region(mini_tex, dst, clip)
	var to_mini := func(v: Vector2) -> Vector2: return mr.position + (v - src.position) * 3.0
	for q in world.pois:
		var m: Vector2 = to_mini.call(q.pos)
		if mr.has_point(m):
			ci.draw_rect(Rect2(m - Vector2(2.5, 2.5), Vector2(5, 5)), _poi_color(q.t))
	for c in cars:
		if c.type == "police" and not c.wreck:
			var m: Vector2 = to_mini.call(c.pos)
			if mr.has_point(m): ci.draw_circle(m, 3.5, Color("#ff2a3a") if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color("#2a6bff"))
	var tg = _current_target()
	if tg != null:
		var m: Vector2 = to_mini.call(tg)
		m = Vector2(clamp(m.x, mr.position.x + 5, mr.end.x - 5), clamp(m.y, mr.position.y + 5, mr.end.y - 5))
		ci.draw_circle(m, 5, Color("#f5c518"))
		ci.draw_arc(m, 5, 0, TAU, 12, Color("#14213d"), 1.5)
	var cp := mr.get_center()
	var tri := PackedVector2Array([cp + Vector2(cos(p_dir), sin(p_dir)) * 9, cp + Vector2(cos(p_dir + 2.5), sin(p_dir + 2.5)) * 7, cp + Vector2(cos(p_dir - 2.5), sin(p_dir - 2.5)) * 7])
	ci.draw_colored_polygon(tri, Color("#c8173a"))
	ci.draw_rect(mr, Color(0.54, 0.59, 0.64, 0.6), false, 2.0)
	# wanted stars
	for k in 5:
		_star(ci, Vector2(sz.x - 236 + k * 26, 192), 10, k < stars)
	if stars > 0 and evade_t > 0.0:
		_text(ci, Vector2(sz.x - 132, 222), "Out of sight...", 12, Color("#b9c3cc"), true)
	# mission / job panel
	var obj := ""
	if mission != null:
		obj = mission.obj
		if mission.i == 1 and mission.step == 1: obj += "  %d s left" % int(max(0.0, mission.timer))
	elif hire and car != null:
		obj = ("Passenger to %s, fare %s" % [fare.dest.n, fmt(fare.amt)]) if fare != null else "Taxi work: pick up someone waving (yellow !)"
	elif mission_idx < MISSIONS.size():
		obj = "Auntie Musu has a job for you at Waterside (yellow M)."
	if obj != "":
		var w: float = min(560.0, font.get_string_size(obj, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 28)
		_panel(ci, Rect2(sz.x / 2 - w / 2, sz.y - 96, w, 30))
		_text(ci, Vector2(sz.x / 2, sz.y - 75), obj, 15, Color("#f5e9b0"), true)
	# off-screen target arrow
	if tg != null:
		var sp: Vector2 = (tg * TS - cam.get_screen_center_position()) * cam.zoom + sz / 2
		if sp.x < 0 or sp.y < 0 or sp.x > sz.x or sp.y > sz.y:
			var a := (sp - sz / 2).angle()
			var R: float = min(sz.x, sz.y) / 2 - 60
			var ap := sz / 2 + Vector2(cos(a), sin(a)) * R
			var arrow := PackedVector2Array([ap + Vector2(18, 0).rotated(a), ap + Vector2(-10, -12).rotated(a), ap + Vector2(-4, 0).rotated(a), ap + Vector2(-10, 12).rotated(a)])
			ci.draw_colored_polygon(arrow, Color("#f5c518"))
			_text(ci, ap + Vector2(0, 30), "%.1f km" % ((tg as Vector2).distance_to(p) * 0.06), 12, Color.WHITE, true)
	# vehicle info
	if car != null:
		var vt := "%s   %d km/h   Condition %d%%" % [_car_name(car.type).capitalize(), int(abs(car.v) * 6), int(max(0.0, car.hp / SPEC[car.type].hp * 100.0))]
		if car.type == "taxi" or car.type == "keke": vt += "   Hire: " + ("ON" if hire else "OFF") + " (T)"
		var w := font.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 28
		_panel(ci, Rect2(sz.x / 2 - w / 2, sz.y - 54, w, 30))
		_text(ci, Vector2(sz.x / 2, sz.y - 34), vt, 14, Color.WHITE, true)
	# prompt
	var pr := prompt_text()
	if pr != "":
		var w := font.get_string_size(pr, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 28
		_panel(ci, Rect2(sz.x / 2 - w / 2, sz.y - 142, w, 32))
		_text(ci, Vector2(sz.x / 2, sz.y - 120), pr, 16, Color("#8ff0ea"), true)
	# toasts
	var ty := 26.0
	for tt in toasts:
		var w := font.get_string_size(tt.m, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 28
		_panel(ci, Rect2(sz.x / 2 - w / 2, ty - 4, w, 30))
		_text(ci, Vector2(sz.x / 2, ty + 16), tt.m, 15, tt.c, true)
		ty += 36
	# bust meter
	if bust_t > 0.05:
		_panel(ci, Rect2(sz.x / 2 - 110, sz.y / 2 + 50, 220, 26))
		ci.draw_rect(Rect2(sz.x / 2 - 104, sz.y / 2 + 58, 208 * clamp(bust_t / 1.6, 0.0, 1.0), 10), Color("#2a6bff"))
		_text(ci, Vector2(sz.x / 2, sz.y / 2 + 44), "Police are grabbing you! Move!", 14, Color("#ff5a6e"), true)
	# big text
	if big_t > 0.0:
		var col := Color("#3ccf7a") if big_text == "MISSION PASSED" else (Color("#f5c518") if big_text == "MISSION FAILED" else Color("#c8173a"))
		col.a = clamp(big_t, 0.0, 1.0)
		_text(ci, Vector2(sz.x / 2, sz.y / 2 - 40), big_text, 54, col, true)
	if map_open: _draw_big_map(ci, sz)
	if menu != null: _draw_menu(ci, sz)

func _poi_color(t: String) -> Color:
	return {"home": Color.WHITE, "mission": Color("#f5c518"), "guns": Color("#c0c6cc"), "spray": Color("#2b5fb3"), "food": Color("#1aa39e"), "park": Color("#f5c518"), "garage": Color("#ef7d22")}.get(t, Color.WHITE)

func _draw_big_map(ci: Control, sz: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.04, 0.08, 0.9))
	var sc: float = min((sz.x - 40) / WG.W, (sz.y - 80) / WG.H)
	var o := (sz - Vector2(WG.W, WG.H) * sc) / 2 + Vector2(0, 10)
	ci.draw_texture_rect(mini_tex, Rect2(o, Vector2(WG.W, WG.H) * sc), false)
	# Labels are laid out so they don't overlap (downtown is crowded at map scale):
	# district names go first, then landmark names try a few slots around their marker.
	var placed: Array = []
	for L in world.landmarks:
		var m := o + Vector2(L.x + L.w / 2.0, L.y + L.h / 2.0) * sc
		ci.draw_rect(Rect2(m - Vector2(3, 3), Vector2(6, 6)), Color("#f5c518"))
		placed.append(Rect2(m - Vector2(4, 4), Vector2(8, 8)))
	for lb in WG.LABELS:
		var water: bool = "Ocean" in lb[0] or "River" in lb[0] or "Wetlands" in lb[0]
		_place_label(ci, placed, o + Vector2(lb[1], lb[2]) * sc, lb[0], 13, Color("#cfe8f5") if water else Color.WHITE,
			[Vector2(0, 0), Vector2(0, -14), Vector2(0, 14), Vector2(-30, 0), Vector2(30, 0), Vector2(0, -28), Vector2(0, 28)])
	for L in world.landmarks:
		var m := o + Vector2(L.x + L.w / 2.0, L.y + L.h / 2.0) * sc
		var hw := font.get_string_size(L.n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x / 2.0
		_place_label(ci, placed, m, L.n, 10, Color("#ffe9a8"),
			[Vector2(0, 16), Vector2(0, -8), Vector2(hw + 8, 4), Vector2(-hw - 8, 4), Vector2(0, 28), Vector2(0, -20), Vector2(hw + 8, 16), Vector2(-hw - 8, 16)])
	for q in world.pois:
		ci.draw_circle(o + q.pos * sc, 3.5, _poi_color(q.t))
	var tg = _current_target()
	if tg != null: ci.draw_arc(o + tg * sc, 8, 0, TAU, 20, Color("#f5c518"), 2.5)
	ci.draw_circle(o + pos() * sc, 6, Color("#c8173a"))
	ci.draw_arc(o + pos() * sc, 6, 0, TAU, 16, Color.WHITE, 2.0)
	_text(ci, Vector2(sz.x / 2, 34), "MONROVIA  ·  press M to close", 18, Color.WHITE, true)
	var legend := [["Safehouse", "home"], ["Auntie Musu (missions)", "mission"], ["Weapon shop", "guns"], ["Respray shop", "spray"], ["Cookshop", "food"], ["Vehicle park", "park"]]
	for i in legend.size():
		ci.draw_circle(Vector2(30, sz.y - 30 - i * 20), 5, _poi_color(legend[i][1]))
		_text(ci, Vector2(42, sz.y - 25 - i * 20), legend[i][0], 13)

## Draws a centered label at the candidate offset (from `at`) that overlaps the
## already-placed rects least, then records its rect in `placed`.
func _place_label(ci: CanvasItem, placed: Array, at: Vector2, s: String, size: int, col: Color, offsets: Array) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var best_p := at + (offsets[0] as Vector2)
	var best_rect := Rect2()
	var best_cost := INF
	for off in offsets:
		var p: Vector2 = at + off
		var r := Rect2(p.x - w / 2.0 - 3, p.y - size * 0.85 - 2, w + 6, size + 4)
		var cost := 0.0
		for q in placed:
			var inter := (q as Rect2).intersection(r)
			if inter.size.x > 0 and inter.size.y > 0: cost += inter.get_area()
		if cost < best_cost:
			best_cost = cost; best_p = p; best_rect = r
		if cost == 0.0: break
	placed.append(best_rect)
	_text(ci, best_p, s, size, col, true)

func _draw_menu(ci: Control, sz: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.04, 0.08, 0.55))
	var opts: Array = menu.opts
	var w: float = clampf(sz.x - 40.0, 240.0, 520.0)
	var lines := _wrap(menu.text, w - 40, 14)
	var h := 70 + lines.size() * 20 + (opts.size() + 1) * 46
	var r := Rect2(sz.x / 2 - w / 2, sz.y / 2 - h / 2, w, h)
	_panel(ci, r)
	ci.draw_rect(Rect2(r.position, Vector2(w, 4)), Color("#c8173a"))
	_text(ci, r.position + Vector2(20, 38), menu.title, 22)
	var y := r.position.y + 64
	for ln in lines:
		ci.draw_string(font, Vector2(r.position.x + 20, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#b9c3cc"))
		y += 20
	y += 6
	menu_rects.clear()
	var all := opts.duplicate()
	all.append({"label": "Close"})
	var mp := get_viewport().get_mouse_position()
	for i in all.size():
		var o: Dictionary = all[i]
		var br := Rect2(r.position.x + 16, y, w - 32, 38)
		var dis: bool = o.get("disabled", false)
		ci.draw_rect(br, Color(0.1, 0.64, 0.62, 0.25) if br.has_point(mp) and not dis else Color(1, 1, 1, 0.05))
		ci.draw_rect(br, Color(0.54, 0.59, 0.64, 0.35), false, 1.0)
		var tc := Color(1, 1, 1, 0.4) if dis else Color.WHITE
		ci.draw_string(font, br.position + Vector2(12, 25), "%d.  %s" % [i + 1, o.label], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tc)
		if o.has("cost"):
			var cs := fmt(o.cost)
			var cw := font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			ci.draw_string(font, br.position + Vector2(br.size.x - cw - 12, 25), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#f5c518") if not dis else Color(0.96, 0.77, 0.09, 0.4))
		menu_rects.append({"rect": br, "i": i})
		y += 46

func _wrap(s: String, width: float, size: int) -> Array:
	var out: Array = []
	var line := ""
	for word in s.split(" "):
		var test: String = word if line == "" else line + " " + word
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = test
	if line != "": out.append(line)
	return out

func _draw_title(ci: Control, sz: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.07, 0.14, 0.72))
	var cx := sz.x / 2
	var y := sz.y * 0.2
	if logo != null:
		ci.draw_texture_rect(logo, Rect2(cx - 55, y - 40, 110, 110), false)
		y += 90
	_text(ci, Vector2(cx, y), "A LIBGAMER COMMUNITY GAME", 14, Color("#1aa39e"), true)
	_text(ci, Vector2(cx, y + 58), "MONROVIA LIFE: STREETS", 46, Color.WHITE, true)
	_text(ci, Vector2(cx, y + 92), "Steal rides, run jobs for Auntie Musu, and stay ahead of the police from Mamba Point to Red Light.", 16, Color("#b9c3cc"), true)
	_text(ci, Vector2(cx, sz.y * 0.62), "Press ENTER or click to start a new game", 22, Color("#f5c518"), true)
	if has_save():
		_text(ci, Vector2(cx, sz.y * 0.62 + 40), "Press C (or click down here) to continue your saved game", 18, Color("#8ff0ea"), true)
	_text(ci, Vector2(cx, sz.y - 70), "WASD drive and walk  ·  Mouse aim and shoot  ·  F take a car  ·  E use  ·  M map  ·  Esc pause", 14, Color("#dfe6ec"), true)
	_text(ci, Vector2(cx, sz.y - 44), "Stylized map of Monrovia, Liberia. All characters are fictional.", 12, Color("#8a97a3"), true)
