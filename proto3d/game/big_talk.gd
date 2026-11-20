extends Node
## Honourable Kpakolo "Big Talk" Dweh - an ORIGINAL fictional character (not based on any
## real person) - and his rise through five stages, all from data:
## proto3d/game/data/bigtalk.json (stages, lines, jobs, endings) and bigtalk_spots.json
## (real map spots, from tools/place_bigtalk.py).
##   0 Nobody     shouting from a crate at Waterside; job: paste his posters downtown
##   1 Radio      his talk show on the car radio, a billboard in Sinkor; job: deliver his tape
##   2 Campaign   SUV convoy, a rally with rice and T-shirts; jobs: chase off a rival poster
##                crew, move the campaign cash past the police
##   3 Big Man    bodyguards, a walled house in Sinkor, posters all over the city; if you
##                crossed him his boys come after you and keep Auntie Musu's jobs closed
##   4 Scandal    the finale: expose his stolen road fund, or help him win
## Each stage also waits for the player's own story (Auntie Musu missions passed).
## Progress lives in GameState (bt_*) and is saved with the game.

signal stage_changed(stage: int)
signal job_passed(id: String)
signal job_failed(id: String)

const CharacterScript := preload("res://proto3d/character.gd")
const GraphDriverScript := preload("res://proto3d/game/graph_driver.gd")
const RESPECT := 2000                   # L$ to make peace with him after crossing him

var state: GameState
var main                                # main_city.gd
var shops
var police
var data: Dictionary
var spots: Dictionary
var npc: Node3D                         # character.gd
var current := {}                       # {job, steps, step, timer, refs, choice, warned}
var _root: Node3D                       # this stage's props (rebuilt on each stage)
var _posters: Node3D
var _markers: Array[Label3D] = []
var _bubble: Label3D
var _star: Label3D
var _hanky: Node3D
var _cars: Array = []                   # convoy / goon cars we spawned
var _guards: Array = []
var _rng := RandomNumberGenerator.new()
var _line_t := 3.0
var _radio_t := 0.0
var _harass_t := 90.0
var _built_for := ""


func setup(game_state: GameState, main_node, s, pol) -> void:
	state = game_state
	main = main_node
	shops = s
	police = pol
	data = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/game/data/bigtalk.json"))
	spots = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/game/data/bigtalk_spots.json"))
	_rng.seed = 4242
	_root = Node3D.new()
	add_child(_root)
	_posters = Node3D.new()
	add_child(_posters)
	_bubble = _label("", 52, Color("#fff4cc"))
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.outline_size = 14
	_bubble.visibility_range_end = 45.0
	_bubble.width = 900.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_bubble)
	_star = _label("B", 128, Color("#c070ff"))
	_star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_star.outline_size = 20
	_star.pixel_size = 0.012
	_star.visibility_range_end = 400.0
	add_child(_star)
	police.arrested.connect(func(): fail("Arrested. The job is off."))
	state.player_down.connect(func(): fail("You went down. The job is off."))
	refresh()


# ------------------------------------------------------------------ queries
func stage() -> Dictionary:
	return data["stages"][clampi(state.bt_stage, 0, data["stages"].size() - 1)]


func active() -> bool:
	return not current.is_empty()


func next_job() -> String:
	if state.bt_ending != "":
		return ""
	for j in stage()["jobs"]:
		if not state.bt_done.has(j):
			return j
	return ""


func job_available() -> bool:
	return not active() and next_job() != "" and state.mission_idx >= int(stage()["story"])


## His people keep Auntie Musu's jobs closed while you're on his bad side (stage 3+).
func blocks_missions() -> bool:
	return state.bt_crossed and state.bt_stage >= 3 and state.bt_ending == ""


func spot(id: String) -> Vector3:
	if id == "house":
		var h: Array = spots["house"]["pos"]
		return Vector3(h[0], h[1], h[2])
	if spots.has(id):
		var a: Array = spots[id]
		return Vector3(a[0], a[1], a[2])
	return shops.place_pos(id)


func house_basis() -> Basis:
	return Basis(Vector3.UP, float(spots["house"]["yaw"]))


## Ground level inside his compound (a raised yard; the plot slopes up to 2.5 m).
func yard_level() -> float:
	return spot("house").y + 2.5


func npc_spot() -> Vector3:
	match state.bt_ending:
		"expose":
			return shops.place_pos("police_hq") + Vector3(3.0, 0.1, 3.0)
		"senator":
			return spot("statue") + Basis(Vector3.UP, float(spots["statue"][3])) * Vector3(3.0, 0.0, -3.0)
	match String(stage()["where"]):
		"crate":
			return spot("crate") + Vector3(0, 0.62, 0)
		"billboard":
			return spot("billboard") + Basis(Vector3.UP, float(spots["billboard"][3])) * Vector3(2.0, 0.0, -2.5)
		"rally":
			return spot("rally") + Vector3(0, 1.0, 0)
		"house":
			var hp := spot("house")
			return Vector3(hp.x, yard_level(), hp.z) + house_basis() * Vector3(0, 0, -11.0)
	return spot("crate")


func lines() -> Array:
	if state.bt_ending != "":
		return data["endings"][state.bt_ending]["big_talk_lines"]
	if state.bt_crossed and stage().has("crossed_lines"):
		return stage()["crossed_lines"] + stage()["lines"]
	return stage()["lines"]


## Something people in the street say about him (null-safe for main._talk).
func street_line() -> String:
	if state.bt_stage < 1 and state.bt_ending == "":
		return ""
	var pool: Array = data["endings"][state.bt_ending]["street_lines"] if state.bt_ending != "" else data["street_lines"]
	return String(pool[_rng.randi() % pool.size()])


# ------------------------------------------------------------------ the world for this stage
## Rebuilds him, his props and posters for the current stage and ending.
func refresh() -> void:
	var key := "%d/%s/%s" % [state.bt_stage, state.bt_ending, str(state.bt_crossed)]
	for c in _root.get_children():
		c.queue_free()
	for c in _cars:
		if is_instance_valid(c):
			c.set_meta("keep", false)
			main.remove_car(c)
	_cars.clear()
	_guards.clear()
	if npc != null:
		npc.queue_free()
	_built_for = key
	var st := stage()
	var look: Dictionary = st["look"]
	if state.bt_ending == "senator":
		look = data["stages"][4]["look"]
	npc = CharacterScript.new()
	npc.name = "BigTalk"
	npc.set_outfit({"model": String(data["model"]), "skin": String(data["skin"]), "shirt": String(look["suit"]),
		"pants": String(look["suit"]), "hair": "#151210"})
	add_child(npc)
	npc.global_position = npc_spot()
	# the suit gets tighter as he gets richer
	var girth := 1.08 + state.bt_stage * 0.035
	npc.scale = Vector3(girth, 1.0, girth)
	_dress(npc, look, true)
	var props: Array = st["props"]
	if state.bt_ending == "expose":
		props = []
	for p in props:
		match String(p):
			"crate": _build_crate()
			"billboard": _build_billboard()
			"rally": _build_rally()
			"house": _build_house(int(st.get("guards", 2)))
			"guards": pass               # with the house
			"convoy": pass               # spawned near the player in _process
	if state.bt_ending == "senator":
		_build_billboard()
		_build_statue()
	if state.bt_ending == "expose":
		for k in 2:
			var cop := CharacterScript.new()
			cop.set_outfit({"model": "Casual3_Male", "skin": "#3d2618", "shirt": "#2b5fb3", "pants": "#14213d"})
			_root.add_child(cop)
			cop.global_position = npc.global_position + Vector3(1.4 * (k * 2 - 1), 0, 0.6)
	_build_posters()
	main.audio.set_talk_station(state.bt_stage >= 1 and state.bt_ending != "expose", "radio_bigtalk", String(data["radio"]["station"]))
	_face_npc()


## Shiny suit, dark glasses, gold watch (bigger every stage), hat later on, and a
## white handkerchief he waves about.
func _dress(who: Node3D, look: Dictionary, is_him: bool) -> void:
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(String(look["suit"]))
	suit.metallic = float(look.get("shine", 0.3)) * 0.6
	suit.roughness = 1.0 - float(look.get("shine", 0.3)) * 0.8
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = Color(String(look.get("shirt", "#ffffff")))
	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = Color(String(look["suit"])).darkened(0.25)
	for n in who.rig.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var nm: String = m.resource_name if m != null else ""
			if nm in ["Shirt", "Pants"]:
				mi.set_surface_override_material(i, suit)
			elif nm == "Detail":
				mi.set_surface_override_material(i, shirt)
			elif nm == "Hat":
				# the hat is part of the body mesh: hide just that surface
				mi.set_surface_override_material(i, hat_mat if bool(look.get("hat", false)) else _invisible())
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("#d4a017")
	gold.metallic = 1.0
	gold.roughness = 0.2
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.03)
	black.metallic = 0.5
	black.roughness = 0.1
	if bool(look.get("glasses", true)):
		_attach(who, "Head", _box_mesh(Vector3(0.62, 0.13, 0.06)), Vector3(0, 0.55, 0.43), black)
	var w := float(look.get("watch", 0.0))
	if w > 0.0:
		_attach(who, "Fist.L", _box_mesh(Vector3(0.12, 0.08, 0.12) * w), Vector3(0, 0.16, 0), gold)
	if is_him:
		var hk := QuadMesh.new()
		hk.size = Vector2(0.45, 0.45)
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.97, 0.97, 0.95)
		white.cull_mode = BaseMaterial3D.CULL_DISABLED
		_hanky = _attach(who, "Fist.R", hk, Vector3(0, -0.15, 0.1), white)


func _attach(who: Node3D, bone: String, mesh: Mesh, offset: Vector3, mat: Material) -> Node3D:
	var sk: Skeleton3D = who.skeleton
	var bi := sk.find_bone(bone)
	if bi < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	sk.add_child(ba)
	var rest := sk.get_bone_global_rest(bi)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = 75.0
	ba.add_child(mi)
	mi.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, rest.origin + offset)
	return mi


func _invisible() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.albedo_color = Color(0, 0, 0, 0)
	return m


func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _face_npc() -> void:
	match String(stage()["where"]):
		"house":
			npc.global_rotation.y = float(spots["house"]["yaw"])          # faces the gate
		"billboard":
			npc.global_rotation.y = float(spots["billboard"][3])         # faces the road
		_:
			npc.global_rotation.y = 0.0


func _mat(col: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


## A box in `parent`'s space; solid ones get a collision body.
func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, solid: bool = false, rot: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation.y = rot
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _label(text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.modulate = col
	l.outline_size = 0
	l.pixel_size = 0.006
	return l


func _holder(at: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	_root.add_child(n)
	n.global_position = at
	n.rotation.y = yaw
	return n


func _build_crate() -> void:
	var h := _holder(spot("crate"), 0.0)
	_box(h, Vector3(1.0, 0.62, 0.8), Vector3(0, 0.31, 0), Color("#a8834f"), true)
	# loudspeaker on a pole
	_box(h, Vector3(0.06, 2.4, 0.06), Vector3(0.9, 1.2, 0), Color("#555"))
	var horn := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.3
	cyl.height = 0.5
	horn.mesh = cyl
	horn.material_override = _mat(Color("#d8d8d0"), 0.4)
	horn.position = Vector3(0.9, 2.4, -0.15)
	horn.rotation.x = -PI / 2
	h.add_child(horn)
	var sign := _label("BIG TALK DWEH\nFOR SOMETHING!", 48, Color("#c8173a"))
	sign.pixel_size = 0.0035
	sign.position = Vector3(0, 0.35, -0.42)
	sign.rotation.y = PI
	h.add_child(sign)


func _build_billboard() -> void:
	var b: Array = spots["billboard"]
	var h := _holder(Vector3(b[0], b[1], b[2]), float(b[3]))
	for x in [-3.2, 3.2]:
		_box(h, Vector3(0.3, 7.0, 0.3), Vector3(x, 3.5, 0), Color("#4a4d52"), true)
	_box(h, Vector3(8.4, 4.0, 0.25), Vector3(0, 5.6, 0), Color("#f5c518"))
	_box(h, Vector3(8.0, 0.9, 0.27), Vector3(0, 4.0, 0), Color("#c8173a"))
	var senator := state.bt_ending == "senator"
	var t := _label(("SENATOR DWEH\nTHANKS YOU!" if senator else "VOTE BIG TALK DWEH"), 160, Color("#14213d"))
	t.position = Vector3(0, 6.4, -0.14)
	t.rotation.y = PI
	t.pixel_size = 0.0045
	h.add_child(t)
	var s := _label(String(data["slogan"]) + "\n" + String(data["party"]), 72, Color.WHITE)
	s.position = Vector3(0, 4.05, -0.15)
	s.rotation.y = PI
	s.pixel_size = 0.0045
	h.add_child(s)
	# his big face (a portrait made of the actual character, behind glass)
	var face := CharacterScript.new()
	face.set_outfit({"model": String(data["model"]), "skin": String(data["skin"]), "shirt": String(stage()["look"]["suit"]), "pants": "#14213d", "hair": "#151210"})
	h.add_child(face)
	face.position = Vector3(-3.0, 3.2, -0.4)
	face.scale = Vector3.ONE * 1.6
	_dress(face, stage()["look"], false)
	face.visible = state.bt_stage >= 2 or senator


func _build_rally() -> void:
	var at := spot("rally")
	var h := _holder(at, 0.0)
	_box(h, Vector3(6.0, 1.0, 4.0), Vector3(0, 0.5, 0), Color("#6b4f33"), true)              # stage
	for x in [-3.2, 3.2]:
		_box(h, Vector3(0.12, 4.5, 0.12), Vector3(x, 2.25, 1.8), Color("#555"))
	_box(h, Vector3(6.6, 1.2, 0.05), Vector3(0, 4.0, 1.8), Color("#1d4fa8"))                   # banner
	var bn := _label(String(data["party"]).to_upper(), 64, Color.WHITE)
	bn.position = Vector3(0, 4.0, 1.75)
	bn.rotation.y = PI
	h.add_child(bn)
	for x in [-2.6, 2.6]:
		_box(h, Vector3(0.7, 1.4, 0.6), Vector3(x, 1.7, -1.2), Color("#111"))                 # speakers
	# rice bags and T-shirts
	for i in 8:
		_box(h, Vector3(0.6, 0.35, 0.4), Vector3(-6.5 + (i % 4) * 0.65, 0.18 + (i / 4) * 0.36, -3.0), Color("#efeadc"), i < 4)
	_box(h, Vector3(2.0, 0.85, 1.0), Vector3(6.0, 0.43, -3.0), Color("#8a6a45"), true)
	for i in 5:
		_box(h, Vector3(0.35, 0.05, 0.4), Vector3(5.3 + i * 0.35, 0.88, -3.0), [Color("#1d4fa8"), Color("#f5c518")][i % 2])
	# the crowd, facing the stage
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in 12:
		var p := CharacterScript.new()
		p.set_outfit(CharacterScript.random_outfit(r, r.randf() < 0.5))
		_root.add_child(p)
		var a := -0.9 + i * 0.16
		var d := 8.0 + (i % 3) * 1.6
		p.global_position = at + Vector3(sin(a) * d, 0.0, -cos(a) * d)
		p.global_rotation.y = atan2(sin(a), -cos(a))          # facing the stage


func _build_house(guards: int) -> void:
	var hp := spot("house")
	var h := _holder(Vector3(hp.x, hp.y, hp.z), float(spots["house"]["yaw"]))
	var y0 := 2.5                                               # yard level above the plot's lowest corner
	_box(h, Vector3(46.0, y0 + 2.0, 46.0), Vector3(0, y0 - (y0 + 2.0) / 2.0, 0), Color("#b9b4a8"), true)   # raised yard
	_box(h, Vector3(7.0, 0.4, 7.0), Vector3(0, y0 * 0.5 - 0.2, -25.5), Color("#b9b4a8"), true, 0.0)          # ramp (as a step)
	var ramp := _box(h, Vector3(6.0, 0.3, 8.0), Vector3(0, y0 * 0.5, -26.5), Color("#a8a39a"), true)
	ramp.rotation.x = atan2(y0, 8.0)
	var wall := Color("#e8e2d0")
	# compound wall with a gate gap at the front (-Z)
	_box(h, Vector3(46.0, 3.0, 0.4), Vector3(0, y0 + 1.5, 23.0), wall, true)
	_box(h, Vector3(0.4, 3.0, 46.0), Vector3(-23.0, y0 + 1.5, 0), wall, true)
	_box(h, Vector3(0.4, 3.0, 46.0), Vector3(23.0, y0 + 1.5, 0), wall, true)
	_box(h, Vector3(20.0, 3.0, 0.4), Vector3(-13.0, y0 + 1.5, -23.0), wall, true)
	_box(h, Vector3(20.0, 3.0, 0.4), Vector3(13.0, y0 + 1.5, -23.0), wall, true)
	for x in [-3.2, 3.2]:
		_box(h, Vector3(0.9, 3.8, 0.9), Vector3(x, y0 + 1.9, -23.0), Color("#c9a227"), true)       # gate pillars
	var name_l := _label("DWEH MANSION", 96, Color("#c9a227"))
	name_l.pixel_size = 0.009
	name_l.position = Vector3(0, y0 + 3.4, -23.5)
	name_l.rotation.y = PI
	h.add_child(name_l)
	# razor wire along the top
	_box(h, Vector3(46.0, 0.25, 0.25), Vector3(0, y0 + 3.15, 23.0), Color("#888"))
	# the villa: two storeys, columns, a balcony, gold trim
	_box(h, Vector3(20.0, 7.0, 13.0), Vector3(0, y0 + 3.5, 6.0), Color("#f4efe4"), true)
	_box(h, Vector3(21.0, 0.6, 14.0), Vector3(0, y0 + 7.3, 6.0), Color("#c9a227"))
	_box(h, Vector3(10.0, 0.3, 3.0), Vector3(0, y0 + 3.6, -1.9), Color("#f4efe4"), true)             # balcony
	for x in [-4.5, -1.5, 1.5, 4.5]:
		_box(h, Vector3(0.5, 3.5, 0.5), Vector3(x, y0 + 1.75, -2.8), Color("#ffffff"), true)
	for x in [-7.5, -4.0, 4.0, 7.5]:
		for yy in [1.8, 5.2]:
			_box(h, Vector3(1.6, 1.8, 0.1), Vector3(x, y0 + yy, -0.52), Color("#20304a"))
	_box(h, Vector3(2.2, 2.8, 0.1), Vector3(0, y0 + 1.4, -0.52), Color("#5a3a20"))                   # front door
	# pool, generator, parked SUVs
	_box(h, Vector3(8.0, 0.1, 4.0), Vector3(-11.0, y0 + 0.05, -14.0), Color("#3fa7d6"))
	_box(h, Vector3(2.2, 1.6, 1.2), Vector3(17.0, y0 + 0.8, 16.0), Color("#3a5a3a"), true)
	for x in [10.0, 15.0]:
		_box(h, Vector3(2.0, 1.7, 4.6), Vector3(x, y0 + 0.85, -14.0), Color("#111111"), true)
	# bodyguards: black suits, dark glasses
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var spots_g := [Vector3(-4.5, y0, -24.6), Vector3(4.5, y0, -24.6), Vector3(-3.0, y0, -9.0), Vector3(3.0, y0, -9.0)]
	for i in mini(guards, spots_g.size()):
		var g := CharacterScript.new()
		g.set_outfit({"model": "Casual2_Male", "skin": ["#3d2618", "#4a2e1e", "#5a3825"][i % 3], "shirt": "#111111", "pants": "#111111", "hair": "#151210"})
		h.add_child(g)
		g.position = spots_g[i]
		g.scale = Vector3(1.12, 1.05, 1.12)
		_dress(g, {"suit": "#111111", "shine": 0.2, "glasses": true, "watch": 0.0}, false)
		_guards.append(g)


func _build_statue() -> void:
	var s: Array = spots["statue"]
	var h := _holder(Vector3(s[0], s[1], s[2]), float(s[3]))
	_box(h, Vector3(2.6, 2.0, 2.6), Vector3(0, 1.0, 0), Color("#d8d2c4"), true)
	var plaque := _label("SENATOR K. DWEH\n\"I AM THE DEVELOPMENT\"", 48, Color("#14213d"))
	plaque.position = Vector3(0, 1.1, -1.32)
	plaque.rotation.y = PI
	h.add_child(plaque)
	var st := CharacterScript.new()
	st.set_outfit({"model": String(data["model"])})
	h.add_child(st)
	st.position = Vector3(0, 2.0, 0)
	st.scale = Vector3(2.4, 2.2, 2.4)
	var gold := _mat(Color("#d4a017"), 0.25, 1.0)
	for n in st.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, gold)
	st.set_meta("statue", true)


func _build_posters() -> void:
	for c in _posters.get_children():
		c.queue_free()
	if state.bt_ending == "expose":
		return                                      # torn down
	var pts: Array = spots["posters"]
	for i in pts.size():
		if state.bt_posters.has(i):
			_poster(pts[i])
	if state.bt_stage >= 3:
		for p in spots["city_posters"]:
			_poster(p)


func _poster(p: Array) -> void:
	var n := Node3D.new()
	_posters.add_child(n)
	n.global_position = Vector3(p[0], p[1], p[2])
	n.rotation.y = float(p[3])
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 1.5)
	q.mesh = qm
	q.material_override = _mat(Color("#f5c518"), 0.9)
	q.position = Vector3(0, 0, 0.02)          # +Z faces out from the wall
	q.visibility_range_end = 90.0
	n.add_child(q)
	var t := _label("VOTE\nBIG TALK\nDWEH", 64, Color("#c8173a"))
	t.position = Vector3(0, 0.15, 0.03)
	t.pixel_size = 0.006
	t.visibility_range_end = 60.0
	n.add_child(t)
	var u := _label(String(data["party"]), 40, Color("#14213d"))
	u.position = Vector3(0, -0.55, 0.03)
	u.pixel_size = 0.0045
	u.visibility_range_end = 40.0
	n.add_child(u)


# ------------------------------------------------------------------ talking to him
func near_him() -> bool:
	return npc != null and main.car == null and main.player.global_position.distance_to(npc.global_position) < 3.8


func prompt() -> String:
	return "[E] Talk to Big Talk Dweh" if near_him() else ""


## E near him: his menu. Returns true if it handled the key.
func interact() -> bool:
	if not near_him():
		return false
	var title := "Hon. %s" % String(data["name"]) if state.bt_ending != "senator" else "Senator Kpakolo Dweh"
	var line := _say_line()
	if state.bt_ending != "":
		main.hud.open_menu(title, "\"%s\"" % line, [], func(_i): pass)
	elif active():
		main.hud.open_menu(title, "\"Why you standing here? My job is not finished!\"", [{"label": "Give up this job"}], func(_i): fail("You walked away from Big Talk's job."))
	elif blocks_missions():
		main.hud.open_menu(title, "\"%s\"  (Pay %s to get back on his good side.)" % [line, GameState.money_text(RESPECT)],
			[{"label": "Pay respect (%s)" % GameState.money_text(RESPECT)}, {"label": "Leave"}], func(i):
				if i == 0:
					make_peace())
	elif job_available():
		var j: Dictionary = data["jobs"][next_job()]
		var reward := ("  Pays %s." % GameState.money_text(int(j["reward"]))) if int(j["reward"]) > 0 else ""
		main.hud.open_menu("%s: %s" % [title, String(j["title"])], "\"%s\"%s" % [String(j["intro"]), reward],
			[{"label": "Take the job"}, {"label": "Not today"}], func(i):
				if i == 0:
					start_job(next_job())
				else:
					state.say("Big Talk: \"Your loss. Opportunity don't knock twice. It knock once, then it go to my cousin.\"", Color("#e0c0ff"), 4.0))
	else:
		main.hud.open_menu(title, "\"%s\"  (Big Talk has nothing for you yet. Keep working for Auntie Musu.)" % line, [], func(_i): pass)
	return true


func make_peace() -> bool:
	if not state.spend(RESPECT):
		state.say("You need %s to make peace with Big Talk." % GameState.money_text(RESPECT))
		return false
	state.bt_crossed = false
	state.say("Big Talk: \"Good. Now we are friends again. Expensive friends.\"", Color("#e0c0ff"), 4.0)
	refresh()
	main.save_game()
	return true


func _say_line() -> String:
	var l: Array = lines()
	return String(l[_rng.randi() % l.size()])


# ------------------------------------------------------------------ jobs
func start_job(id: String) -> void:
	var j: Dictionary = data["jobs"][id]
	main.taxi.stop()
	current = {"job": id, "steps": j["steps"], "step": 0, "timer": -1.0, "refs": [], "choice": "", "warned": false}
	state.say("Big Talk's job: " + String(j["title"]), Color("#c070ff"), 4.0)
	_begin_step()


func step() -> Dictionary:
	return current["steps"][current["step"]] if active() else {}


func _begin_step() -> void:
	var s := step()
	current["timer"] = float(s.get("timer", -1.0))
	current["warned"] = false
	_clear_refs()
	if s.has("on_start"):
		state.say(String(s["on_start"]), Color("#c070ff"), 3.5)
	match String(s["type"]):
		"posters":
			_show_poster_markers()
		"scare_crew":
			_spawn_crew(spot(String(s["spot"])), int(s["count"]))
		"cash_run":
			if bool(s.get("goons", false)):
				for k in 2:
					_spawn_goon(main.player.global_position, 90.0 + k * 40.0)
		"final_choice":
			var choices: Array = data["jobs"][current["job"]]["choices"]
			var opts: Array = []
			for c in choices:
				opts.append({"label": "%s (%s)" % [String(c["label"]), GameState.money_text(int(c["reward"]))]})
			main.hud.open_menu("Election Night", "Big Talk: \"So? You with me, or you with them?\"", opts, func(i): choose(i))


## The finale: pick a side (index into the finale's choices).
func choose(i: int) -> void:
	if not active() or String(step()["type"]) != "final_choice":
		return
	var c: Dictionary = data["jobs"][current["job"]]["choices"][i]
	current["choice"] = String(c["id"])
	current["steps"] = c["steps"]
	current["step"] = 0
	state.say("You chose: " + String(c["label"]), Color("#c070ff"), 3.0)
	_begin_step()


func objective() -> String:
	if not active():
		if blocks_missions():
			return "Big Talk's boys are watching Auntie Musu. Make peace with him at his house in Sinkor (%s)." % GameState.money_text(RESPECT)
		return ""
	var s := step()
	var text := String(s["text"])
	if text.contains("%d"):
		text = text % _remaining()
	if float(current["timer"]) >= 0.0:
		text += "  %d s left" % int(maxf(0.0, current["timer"]))
	return text


func target() -> Variant:
	if not active():
		return null
	var s := step()
	match String(s["type"]):
		"posters":
			var best = null
			var bd := INF
			for m in _markers:
				var d := m.global_position.distance_to(main.player.global_position)
				if d < bd:
					bd = d
					best = m.global_position
			return best
		"scare_crew":
			for r in current["refs"]:
				if is_instance_valid(r) and not r.get_meta("fled", false):
					return r.global_position
			return null
		"goto", "cash_run":
			return _target_pos(String(s["target"]))
	return null


func _target_pos(id: String) -> Vector3:
	if id == "house":
		return Vector3(spot("house").x, yard_level(), spot("house").z) + house_basis() * Vector3(0, 0, -11.0)
	return spot(id)


func _remaining() -> int:
	match String(step()["type"]):
		"posters":
			return _markers.size()
		"scare_crew":
			var n := 0
			for r in current["refs"]:
				if is_instance_valid(r) and not r.get_meta("fled", false):
					n += 1
			return n
	return 0


func _process(delta: float) -> void:
	if main == null or not main.ready_done or get_tree().paused:
		return
	if npc == null:
		return
	var me: Vector3 = main.car.global_position if main.car != null else main.player.global_position
	var near := me.distance_to(npc.global_position)
	# he talks (shouts, at the start) when you're around
	_line_t -= delta
	if _line_t <= 0.0:
		_line_t = _rng.randf_range(6.0, 10.0)
		if near < 30.0:
			_bubble.text = _say_line()
			_bubble.visible = true
			main.audio.play("bigtalk_shout", npc.global_position, -2.0 if state.bt_stage == 0 else -8.0, 0.95 + _rng.randf() * 0.1)
		else:
			_bubble.visible = false
	if _line_t < 2.5:
		_bubble.visible = false
	_bubble.global_position = npc.global_position + Vector3(0, 2.5, 0)
	if _hanky != null and is_instance_valid(_hanky):
		_hanky.rotation.z = sin(Time.get_ticks_msec() * 0.009) * 0.9
	if near > 3.0 and near < 20.0:
		npc.global_rotation.y = lerp_angle(npc.global_rotation.y, atan2(npc.global_position.x - me.x, npc.global_position.z - me.z), clampf(delta * 2.0, 0.0, 1.0))
	_star.visible = job_available() or (blocks_missions() and not active())
	_star.global_position = npc.global_position + Vector3(0, 4.2, 0)
	_radio(delta)
	_convoy(me)
	_harass(delta, me)
	_try_advance()
	if active():
		_run_step(delta, me)


func _run_step(delta: float, me: Vector3) -> void:
	var s := step()
	if float(current["timer"]) >= 0.0:
		current["timer"] -= delta
		if current["timer"] <= 0.0:
			fail("Too slow. Big Talk is not happy.")
			return
	var done := false
	match String(s["type"]):
		"posters":
			if main.car == null:
				for m in _markers.duplicate():
					if m.global_position.distance_to(main.player.global_position) < 3.2:
						paste_poster(int(m.get_meta("index")))
			done = _markers.is_empty()
		"goto":
			done = _target_pos(String(s["target"])).distance_to(me) < 11.0
		"scare_crew":
			for r in current["refs"]:
				if not is_instance_valid(r) or r.get_meta("fled", false):
					continue
				if r.global_position.distance_to(me) < 5.0:
					_flee(r, me)
			done = _remaining() == 0
		"cash_run":
			if float(s.get("spot_range", 0.0)) > 0.0 and state.stars == 0 and _police_sees(me, float(s["spot_range"])):
				police.add_stars(int(s["stars"]))
				state.say("The police saw the bag!", Color("#ff5a6e"), 3.0)
			var there := _target_pos(String(s["target"])).distance_to(me) < 12.0
			if there and state.stars > 0 and not current["warned"]:
				current["warned"] = true
				state.say("Lose the police before you hand it over!", Color("#ff5a6e"), 3.0)
			done = there and state.stars == 0
	if done:
		current["step"] += 1
		if current["step"] >= current["steps"].size():
			_complete()
		else:
			_begin_step()


## Any police (patrols, pursuit cars, officers, parked cruisers) within r of p.
func _police_sees(p: Vector3, r: float) -> bool:
	if police._police_near(p, r):
		return true
	for c in main.cars:
		if is_instance_valid(c) and c.kind == "police" and c != main.car and c.global_position.distance_to(p) < r:
			return true
	return false


func paste_poster(i: int) -> void:
	if state.bt_posters.has(i):
		return
	state.bt_posters.append(i)
	for m in _markers.duplicate():
		if int(m.get_meta("index")) == i:
			_markers.erase(m)
			m.queue_free()
	_poster(spots["posters"][i])
	main.audio.ui("ui_confirm")
	state.say("Poster up. %d to go." % _markers.size(), Color("#c070ff"), 2.0)


func _show_poster_markers() -> void:
	var pts: Array = spots["posters"]
	for i in pts.size():
		if state.bt_posters.has(i):
			continue
		var m := _label("▼", 120, Color("#c070ff"))
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.outline_size = 16
		m.visibility_range_end = 300.0
		add_child(m)
		m.global_position = Vector3(pts[i][0], pts[i][1] + 1.3, pts[i][2])
		m.set_meta("index", i)
		_markers.append(m)


func _spawn_crew(at: Vector3, n: int) -> void:
	for i in n:
		var c := CharacterScript.new()
		c.set_outfit({"model": ["Casual_Male", "Casual3_Male", "Casual_Female"][i % 3], "skin": "#4a2e1e", "shirt": "#3ccf7a", "pants": "#1b1b1b", "hair": "#151210"})
		add_child(c)
		c.global_position = at + Vector3(i * 2.2 - 2.2, 0.05, 1.5)
		c.set_meta("fled", false)
		var sign := _label(String(data["rival_party"]), 40, Color.WHITE)
		sign.position = Vector3(0, 2.1, 0)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.outline_size = 10
		c.add_child(sign)
		current["refs"].append(c)


func _flee(r: Node3D, from: Vector3) -> void:
	r.set_meta("fled", true)
	var away := r.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	r.global_rotation.y = atan2(away.x, away.z) + PI
	r.set_speed(6.0)
	var tw := create_tween()
	tw.tween_property(r, "global_position", r.global_position + away * 30.0, 4.0)
	tw.tween_callback(r.queue_free)
	state.say("\"Ay, we going, we going!\"", Color("#f5e9b0"), 2.0)


func _spawn_goon(near: Vector3, back: float) -> void:
	var n: Dictionary = main.graph.nearest(near + Vector3(back, 0, 0), 3)
	if n.is_empty():
		return
	var lp: Array = main.graph.lane_point(n["edge"], 5.0, 1)
	var fwd: Vector3 = lp[1]
	var c = main.spawn_car("suv", Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), (lp[0] as Vector3) + Vector3(0, 0.6, 0)))
	c.mission_tag = "bigtalk_goon"
	c.set_meta("keep", true)
	c.controller = GraphDriverScript.new(main.graph, "pursue", police.player_node(), 20.0, _rng.randi())
	_paint_black(c)
	_cars.append(c)
	if active():
		current["refs"].append(c)


func _paint_black(c) -> void:
	if c.has_method("set_paint"):
		c.set_paint(Color(0.04, 0.04, 0.05))
		return
	var black := _mat(Color(0.05, 0.05, 0.06), 0.25, 0.6)
	for mi in c.model.find_children("Cube*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a := m.get_aabb()
		if a.size.x * a.size.y * a.size.z > 0.5:
			m.material_override = black


func _clear_refs() -> void:
	for m in _markers:
		m.queue_free()
	_markers.clear()
	if current.is_empty():
		return
	for r in current["refs"]:
		if not is_instance_valid(r):
			continue
		if r is RigidBody3D:
			r.set_meta("keep", false)
			_cars.erase(r)
			main.remove_car(r)
		else:
			r.queue_free()
	current["refs"] = []


func _complete() -> void:
	var id: String = current["job"]
	var j: Dictionary = data["jobs"][id]
	var reward := int(j["reward"])
	var choice: String = current["choice"]
	_clear_refs()
	current = {}
	state.bt_done.append(id)
	if choice != "":
		for c in j["choices"]:
			if c["id"] == choice:
				reward = int(c["reward"])
				state.bt_ending = choice
				state.say(String(c["ending"]), Color("#c070ff"), 8.0)
		police.clear()
	state.add_money(reward)
	state.big_text.emit("JOB DONE", Color("#c070ff"))
	if reward > 0:
		state.say("+%s  %s" % [GameState.money_text(reward), String(j["title"])], Color("#f5c518"), 5.0)
	if j.has("done_say"):
		state.say(InputGlyphs.fill(String(j["done_say"])), Color("#8ff0ea"), 6.0)
	job_passed.emit(id)
	if choice != "":
		refresh()
	_try_advance()
	main.save_game()


func fail(reason: String) -> void:
	if not active():
		return
	var id: String = current["job"]
	var j: Dictionary = data["jobs"][id]
	_clear_refs()
	current = {}
	state.big_text.emit("JOB FAILED", Color("#f5c518"))
	state.say(reason, Color("#ff5a6e"), 5.0)
	if bool(j.get("cross_on_fail", false)) and not state.bt_crossed:
		state.bt_crossed = true
		state.say("Big Talk: \"You spoil my thing? I will not forget your face.\"", Color("#e0c0ff"), 5.0)
	job_failed.emit(id)


## Next stage when this stage's jobs are done and the player's story has caught up.
func _try_advance() -> void:
	if active() or state.bt_ending != "" or state.bt_stage >= data["stages"].size() - 1:
		return
	for j in stage()["jobs"]:
		if not state.bt_done.has(j):
			return
	var nxt: Dictionary = data["stages"][state.bt_stage + 1]
	if state.mission_idx < int(nxt["story"]):
		return
	state.bt_stage += 1
	state.big_text.emit("BIG TALK: " + String(nxt["title"]).to_upper(), Color("#c070ff"))
	state.say(_stage_news(), Color("#c070ff"), 6.0)
	refresh()
	stage_changed.emit(state.bt_stage)


func _stage_news() -> String:
	match state.bt_stage:
		1: return "Big Talk Dweh now has a radio show (R in a car) and a billboard in Sinkor."
		2: return "Big Talk Dweh is running for office. His rally is in Sinkor."
		3: return "Big Talk Dweh has a walled house in Sinkor, off %s. His face is on every wall." % String(spots["house"]["street"])
		4: return "Election night. Big Talk wants to see you at his house."
	return ""


# ------------------------------------------------------------------ radio, convoy, grudges
func _radio(delta: float) -> void:
	if main.audio.station_stream() != "radio_bigtalk":
		_radio_t = 1.0
		return
	_radio_t -= delta
	if _radio_t <= 0.0:
		_radio_t = 7.0
		var r: Array = data["radio"]["rants"]
		state.say("Big Talk Hour: \"%s\"" % String(r[_rng.randi() % r.size()]), Color("#e0c0ff"), 6.0)


## Stage 2: his black SUV convoy cruises around the rally while you're nearby.
func _convoy(me: Vector3) -> void:
	if state.bt_stage != 2 or state.bt_ending != "":
		return
	var rally := spot("rally")
	var live := _cars.filter(func(c): return is_instance_valid(c) and c.mission_tag == "bigtalk_convoy")
	if me.distance_to(rally) < 600.0 and live.is_empty():
		for k in 3:
			var n: Dictionary = main.graph.nearest(rally, 3)
			if n.is_empty():
				return
			var lp: Array = main.graph.lane_point(n["edge"], 6.0 + k * 9.0, 1)
			var fwd: Vector3 = lp[1]
			var c = main.spawn_car("suv", Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), (lp[0] as Vector3) + Vector3(0, 0.6, 0)))
			c.mission_tag = "bigtalk_convoy"
			c.set_meta("keep", true)
			c.controller = GraphDriverScript.new(main.graph, "wander", null, 11.0, 300 + k)
			_paint_black(c)
			_cars.append(c)
	elif me.distance_to(rally) > 1000.0 and not live.is_empty():
		for c in live:
			c.set_meta("keep", false)
			main.remove_car(c)
			_cars.erase(c)


## Crossed him at stage 3+: now and then his boys come looking for you in a black SUV.
func _harass(delta: float, me: Vector3) -> void:
	if not blocks_missions() or active():
		return
	_harass_t -= delta
	if _harass_t > 0.0:
		return
	_harass_t = 100.0
	for c in _cars.duplicate():
		if is_instance_valid(c) and c.mission_tag == "bigtalk_goon":
			c.set_meta("keep", false)
			main.remove_car(c)
			_cars.erase(c)
	_spawn_goon(me, 110.0)
	state.say("Big Talk's boys are looking for you.", Color("#ff5a6e"), 4.0)
