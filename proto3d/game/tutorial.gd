class_name Tutorial
extends Node3D
## "Welcome to Monrovia": Auntie Musu's first mission on a new game, step by step from
## proto3d/game/data/tutorial.json. Shows a panel at the top of the screen with her line
## and the objective (key or gamepad button names follow the last device used), a
## marker in the world and on the map (main.target_pos()), and spawns what a step needs
## (a bat to pick up, a training dummy to hit). Skippable from Settings or the panel.

signal finished(skipped: bool)

const DATA := "res://proto3d/game/data/tutorial.json"
const BAT_MODEL := "res://proto3d/models/weapons/bat.glb"

var main
var state: GameState
var data: Dictionary
var steps: Array = []
var idx := -1
var active := false
var dummy: TrainingDummy = null
var _at := Vector3.INF
var _marker: Node3D
var _bat: Node3D
var _bought := ""
var _wheel_was_open := false
var _ui: CanvasLayer
var _panel: PanelContainer
var _title: Label
var _say: Label
var _hint: Label
var _skip: Label
var _refresh := 0.0


func setup(main_node) -> void:
	main = main_node
	state = main.state
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	steps = data["steps"]
	main.shops.bought.connect(func(action: String, _poi: String): _bought = action)
	_build_ui()


func start() -> void:
	if steps.is_empty():
		return
	active = true
	idx = -1
	_panel.visible = true
	_next()


func skip() -> void:
	if active:
		_finish(true)


func step_id() -> String:
	return String(steps[idx]["id"]) if active and idx >= 0 and idx < steps.size() else ""


## Map / compass target for main.target_pos(), or null.
func target():
	return _at if active and _at != Vector3.INF else null


func objective() -> String:
	return InputGlyphs.fill(String(steps[idx]["hint"])) if active else ""


# ------------------------------------------------------------------ steps
func _next() -> void:
	_clear_step()
	idx += 1
	if idx >= steps.size():
		_finish(false)
		return
	var s: Dictionary = steps[idx]
	_at = _resolve(String(s.get("at", "")), float(s.get("offset", 0.0)))
	match String(s["kind"]):
		"pickup":
			_spawn_bat(_at)
		"hit_target":
			dummy = TrainingDummy.new()
			add_child(dummy)
			dummy.global_position = _at
			dummy.look_at(main.player.global_position * Vector3(1, 0, 1) + Vector3(0, _at.y, 0), Vector3.UP)
		"open_wheel":
			_wheel_was_open = main.wheel.open
	if _at != Vector3.INF and String(s["kind"]) in ["reach", "drive_to", "pickup", "save_at", "buy"]:
		_place_marker(_at)
	_bought = ""
	_update_ui()
	_say.visible = s.has("say")
	if s.has("say"):
		_say.text = "%s: \"%s\"" % [String(data["giver"]), String(s["say"])]
	main.audio.ui("ui_confirm")


func _process(delta: float) -> void:
	if not active or get_tree().paused or not main.ready_done or main._busy:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_update_ui()                       # glyphs follow the device in use
	if _marker != null:
		_marker.rotation.y += delta * 1.5
	if _done(steps[idx]):
		_next()


func _input(event: InputEvent) -> void:
	InputGlyphs.note(event)


func _done(s: Dictionary) -> bool:
	var p: Vector3 = main.player.global_position
	var flat := func(a: Vector3, b: Vector3) -> float: return Vector2(a.x - b.x, a.z - b.z).length()
	match String(s["kind"]):
		"reach":
			return main.car == null and flat.call(p, _at) < float(s.get("radius", 2.5))
		"enter_vehicle":
			return main.car != null
		"drive_to":
			return main.car != null and flat.call(main.car.global_position, _at) < float(s.get("radius", 12.0))
		"exit_vehicle":
			return main.car == null and main.player.active
		"buy", "save_at":
			return _bought in s.get("actions", [])
		"pickup":
			if main.car == null and flat.call(p, _at) < 1.6:
				var w := int(s.get("weapon", GameState.BAT))
				state.give_weapon(w, 0)
				state.select_weapon(w)
				main.audio.ui("ui_confirm")
				return true
		"hit_target":
			return dummy != null and dummy.hits >= int(s.get("hits", 3))
		"open_wheel":
			if main.wheel.open and not _wheel_was_open:
				return true
			_wheel_was_open = main.wheel.open
	return false


## Where a step happens: "start_car" (beside the taxi you start next to), "poi:<id>",
## "nearest:<poi type>", "behind_player:<metres>" (where you're standing, away from the
## counter you face), or "" (nowhere in particular).
func _resolve(spec: String, offset: float) -> Vector3:
	var p: Vector3 = main.player.global_position
	if spec == "start_car":
		var c = main.start_car
		if c == null or not is_instance_valid(c):
			c = main.nearest_car()
		if c == null:
			return p + Vector3(0, 0, -6)
		var side: Vector3 = (c.global_basis.x * Vector3(1, 0, 1)).normalized()
		var spot: Vector3 = c.global_position + side * offset
		if spot.distance_to(p) > (c.global_position - side * offset).distance_to(p):
			spot = c.global_position - side * offset        # the kerb side nearer you
		return Vector3(spot.x, c.global_position.y, spot.z)
	if spec.begins_with("poi:"):
		return main.shops.place_pos(spec.substr(4))
	if spec.begins_with("nearest:"):
		var t := spec.substr(8)
		var best := Vector3.INF
		for q in main.shops.pois:
			if String(q["type"]) == t and (q["pos"] as Vector3).distance_to(p) < best.distance_to(p):
				best = q["pos"]
		return best
	if spec.begins_with("behind_player:"):
		var d := float(spec.substr(14))
		var fwd: Vector3 = Basis(Vector3.UP, main.player.model.rotation.y) * Vector3.FORWARD
		var spot := p - fwd * d + fwd.cross(Vector3.UP) * 0.8
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3(0, 3, 0), spot + Vector3(0, -6, 0), 1))
		return hit.position if not hit.is_empty() else Vector3(spot.x, p.y - 0.9, spot.z)
	return Vector3.INF


func _finish(skipped: bool) -> void:
	_clear_step()
	active = false
	idx = steps.size()
	state.tutorial_done = true
	_panel.visible = false
	if not skipped:
		state.add_money(int(data.get("reward", 0)))
		state.say("%s complete! +%s. Auntie Musu has more work for you at Waterside (M on the map)." %
			[String(data["title"]), GameState.money_text(int(data.get("reward", 0)))], Color("#f5c518"), 7.0)
	if not skipped and String(steps.back()["kind"]) == "save_at":
		main.save_game()                  # the rest already saved, but before "done" was set
	finished.emit(skipped)


func _clear_step() -> void:
	_at = Vector3.INF
	for n in [_marker, _bat, dummy]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_marker = null
	_bat = null
	dummy = null


# ------------------------------------------------------------------ world bits
func _place_marker(at: Vector3) -> void:
	_marker = Node3D.new()
	add_child(_marker)
	_marker.global_position = at
	var ring := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 1.1
	m.bottom_radius = 1.1
	m.height = 0.05
	ring.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.77, 0.09, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.96, 0.77, 0.09)
	ring.material_override = mat
	ring.position.y = 0.05
	_marker.add_child(ring)
	var arrow := Label3D.new()
	arrow.text = "▼"
	arrow.font_size = 96
	arrow.pixel_size = 0.01
	arrow.outline_size = 16
	arrow.modulate = Color("#f5c518")
	arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	arrow.no_depth_test = true
	arrow.position.y = 2.6
	_marker.add_child(arrow)


func _spawn_bat(at: Vector3) -> void:
	_bat = Node3D.new()
	add_child(_bat)
	_bat.global_position = at + Vector3(0, 0.15, 0)
	var scene := load(BAT_MODEL) as PackedScene
	if scene != null:
		var m := scene.instantiate() as Node3D
		m.rotation = Vector3(0, 0, PI / 2)            # lying on the ground
		m.scale = Vector3.ONE * 1.8
		_bat.add_child(m)


# ------------------------------------------------------------------ on screen
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.063, 0.102, 0.196, 0.86)
	sb.border_color = Color("#f5c518")
	sb.border_width_left = 4
	sb.set_content_margin_all(12)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = 14
	_panel.visible = false
	_ui.add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color("#f5c518"))
	v.add_child(_title)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint)
	_say = Label.new()                       # Auntie Musu's line for this step
	_say.add_theme_font_size_override("font_size", 16)
	_say.add_theme_color_override("font_color", Color("#f5e9b0"))
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_say)
	_skip = Label.new()
	_skip.add_theme_font_size_override("font_size", 12)
	_skip.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	_skip.text = "Skip: Settings > Gameplay > Tutorial on a new game"
	v.add_child(_skip)


func _update_ui() -> void:
	if not active or idx < 0 or idx >= steps.size():
		return
	_title.text = "%s   ·   %d / %d" % [String(data["title"]).to_upper(), idx + 1, steps.size()]
	_hint.text = objective()
	_panel.visible = not main.hud.menu_open and not main.hud.map_open
	relayout()


## Width and text size for the screen: on a phone the panel fits between the status panel
## and the minimap (it used to cover both), with slightly smaller text.
func relayout() -> void:
	if _panel == null or main == null:
		return
	var compact: bool = main.hud.compact
	var w: float = main.hud.top_band_width(660.0)
	_panel.offset_left = -w / 2.0
	_panel.offset_right = w / 2.0
	_hint.add_theme_font_size_override("font_size", 16 if compact else 20)
	_say.add_theme_font_size_override("font_size", 13 if compact else 16)
	_title.add_theme_font_size_override("font_size", 13 if compact else 15)
	_skip.visible = not compact          # (unwrapped, it widened the panel past the minimap)


## A straw training dummy on a post: counts hits and wobbles. Melee finds it through
## main.all_walkers(); is_dummy keeps the police out of it.
class TrainingDummy extends Node3D:
	var is_dummy := true
	var hits := 0
	var _wobble := 0.0
	var _body: Node3D

	func _ready() -> void:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.06
		pm.height = 1.0
		post.mesh = pm
		post.position.y = 0.5
		post.material_override = _mat(Color("#6b4a2b"))
		add_child(post)
		_body = Node3D.new()
		_body.position.y = 0.9
		add_child(_body)
		var sack := MeshInstance3D.new()
		var sm := CapsuleMesh.new()
		sm.radius = 0.26
		sm.height = 0.95
		sack.mesh = sm
		sack.position.y = 0.4
		sack.material_override = _mat(Color("#c8a96a"))
		_body.add_child(sack)
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.17
		hm.height = 0.34
		head.mesh = hm
		head.position.y = 1.02
		head.material_override = _mat(Color("#d9bf86"))
		_body.add_child(head)

	func _mat(c: Color) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.95
		return m

	func _process(delta: float) -> void:
		_wobble = move_toward(_wobble, 0.0, delta * 2.5)
		_body.rotation.x = sin(Time.get_ticks_msec() * 0.02) * _wobble * 0.35

	func is_down() -> bool:
		return false

	func shot(_dmg: float, _melee: bool = false, _from: Vector3 = Vector3.ZERO) -> void:
		hits += 1
		_wobble = 1.0

	func push(_v: Vector3) -> void:
		_wobble = 1.0

	func knockdown(_v: Vector3) -> void:
		_wobble = 1.0
