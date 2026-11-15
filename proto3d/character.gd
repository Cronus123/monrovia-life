extends Node3D
## A person built from Quaternius's CC0 "Ultimate Animated Character Pack"
## (third_party/quaternius-ultimate-animated-character-pack): casual modern clothes,
## recoloured with the 2D game's skin tones and clothing palette, optionally with a
## lappa and head wrap. Its built-in animations drive an AnimationTree:
## Idle / Walk / Run blended by speed, plus Jump, SitDown (getting into a car),
## Death (knocked down) and Death played backwards (getting up).
##
## Interface used by walker.gd / player.gd / pedestrian.gd:
##   set_outfit(dict)   random_outfit(rng, female)   set_speed(v)   play(state)   current_state()

const PEOPLE_DIR := "res://proto3d/models/people/%s.gltf"
const MALE_MODELS := ["Casual_Male", "Casual2_Male", "Casual3_Male", "OldClassy_Male"]
const FEMALE_MODELS := ["Casual_Female", "Casual2_Female", "Casual3_Female"]
const SCALE := 0.55           # pack models are ~3.2 units tall; people here are ~1.75 m
const STATES := {"jump": "Jump", "get_in": "SitDown", "knocked": "Death", "punch": "Punch", "shoot": "Shoot_OneHanded"}

# Palette shared with the 2D game.
const SKIN_TONES := ["#5a3825", "#6b4329", "#4a2e1e", "#7a4e30", "#3d2618"]
const CLOTH := ["#c8173a", "#1aa39e", "#f5c518", "#2b5fb3", "#ef7d22", "#7c3aed", "#ffffff", "#3ccf7a", "#e06aa8", "#14213d"]
const TROUSERS := ["#2b3a55", "#1b1b1b", "#4a4f57", "#6b5a3e", "#2f4a2f", "#d8cfbd"]

static var _scenes := {}
static var ragdolls_active := 0          # running ragdolls (capped for the CPU)
static var max_ragdolls := 8             # Settings: fewer on Low
const RagdollScript := preload("res://proto3d/ragdoll.gd")

var rig: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var _speed := 0.0
var _outfit := {}
var _extras: Array[MeshInstance3D] = []
var ragdoll                              # ragdoll.gd, built on the first knock-down
var _ragdolling := false


## Call before adding to the tree (walker.gd does), or later to recolour.
func set_outfit(o: Dictionary) -> void:
	_outfit = o
	if rig != null:
		_apply_outfit()


func _ready() -> void:
	var model: String = _outfit.get("model", "Casual2_Male")
	if not _scenes.has(model):
		_scenes[model] = load(PEOPLE_DIR % model)
	rig = (_scenes[model] as PackedScene).instantiate() as Node3D
	rig.name = "Rig"
	rig.scale = Vector3.ONE * SCALE
	rig.rotation.y = PI            # pack models face +Z; the game's forward is -Z
	add_child(rig)
	skeleton = rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	anim_player = rig.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 75.0
	_add_extras()
	_apply_outfit()
	_build_tree()


static func random_outfit(rng: RandomNumberGenerator, female: bool) -> Dictionary:
	var skin: String = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	var o := {"skin": skin, "shirt": CLOTH[rng.randi() % CLOTH.size()],
		"pants": TROUSERS[rng.randi() % TROUSERS.size()], "hair": "#151210"}
	if female:
		o["model"] = FEMALE_MODELS[rng.randi() % FEMALE_MODELS.size()]
		if rng.randf() < 0.6:
			o["skirt"] = CLOTH[rng.randi() % CLOTH.size()]      # lappa
		if rng.randf() < 0.55:
			o["wrap"] = CLOTH[rng.randi() % CLOTH.size()]       # head wrap
	else:
		o["model"] = MALE_MODELS[rng.randi() % MALE_MODELS.size()]
	return o


# ------------------------------------------------------------------ looks
func _apply_outfit() -> void:
	var colors := {"Skin": _outfit.get("skin", ""), "Shirt": _outfit.get("shirt", ""),
		"Pants": _outfit.get("pants", ""), "Hair": _outfit.get("hair", ""), "Belt": "#2a1a10"}
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi in _extras:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var n: String = src.resource_name if src != null else ""
			var col: String = colors.get(n, "")
			if n == "Hair" and _outfit.has("wrap"):
				col = String(_outfit["wrap"])          # hair tucked under the wrap
			if col == "":
				continue
			mi.set_surface_override_material(i, _flat(col, 0.5 if n == "Skin" else 0.85))
	for e in _extras:
		var key: String = e.get_meta("outfit_key")
		e.visible = _outfit.has(key)
		if e.visible:
			e.material_override = _flat(String(_outfit[key]), 0.85)


func _flat(col: String, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col)
	m.roughness = rough
	return m


## Lappa (wrap skirt) on the hips and a head wrap on the head, for a West African look.
func _add_extras() -> void:
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.44
	skirt.bottom_radius = 0.6
	skirt.height = 0.72
	skirt.radial_segments = 12
	skirt.rings = 1
	_attach("Hips", skirt, Vector3(0, -0.28, 0), Vector3(1.0, 1.0, 0.85), "skirt")
	var wrap := SphereMesh.new()
	wrap.radius = 0.7
	wrap.height = 0.95
	wrap.radial_segments = 12
	wrap.rings = 6
	_attach("Head", wrap, Vector3(0, 0.82, -0.05), Vector3(1.0, 1.0, 1.0), "wrap")


func _attach(bone: String, mesh: Mesh, offset: Vector3, scl: Vector3, key: String) -> void:
	var bi := skeleton.find_bone(bone)
	if bi < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	var rest := skeleton.get_bone_global_rest(bi)
	ba.transform = rest
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_meta("outfit_key", key)
	mi.visibility_range_end = 75.0
	ba.add_child(mi)
	# Place it in skeleton space (upright, offset from the bone), then keep it bone-relative.
	mi.transform = rest.affine_inverse() * Transform3D(Basis.from_scale(scl), rest.origin + offset)
	_extras.append(mi)


# ------------------------------------------------------------------ animation
func set_speed(v: float) -> void:
	_speed = lerpf(_speed, v, 0.25)
	if tree == null:
		return
	tree.set("parameters/move/blend/blend_position", _speed)
	tree.set("parameters/move/scale/scale", clampf(0.75 + _speed * 0.11, 0.85, 1.5))


func play(state: String) -> void:
	if playback != null:
		playback.travel(state)


func current_state() -> String:
	return String(playback.get_current_node()) if playback != null else ""


func _build_tree() -> void:
	for a in ["Idle", "Walk", "Run"]:
		anim_player.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	var sm := AnimationNodeStateMachine.new()
	var move := AnimationNodeBlendTree.new()
	var blend := AnimationNodeBlendSpace1D.new()
	blend.min_space = 0.0
	blend.max_space = 8.0
	for p in [["Idle", 0.0], ["Walk", 1.6], ["Run", 5.0]]:
		var n := AnimationNodeAnimation.new()
		n.animation = p[0]
		blend.add_blend_point(n, p[1], -1, String(p[0]).to_lower())
	move.add_node("blend", blend)
	move.add_node("scale", AnimationNodeTimeScale.new())
	move.connect_node("scale", 0, "blend")
	move.connect_node("output", 0, "scale")
	sm.add_node("move", move)
	for s in STATES:
		var n := AnimationNodeAnimation.new()
		n.animation = STATES[s]
		sm.add_node(s, n)
	var up := AnimationNodeAnimation.new()        # get up = fall played backwards
	up.animation = "Death"
	up.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
	sm.add_node("get_up", up)
	var states := ["move", "jump", "get_in", "knocked", "get_up", "punch", "shoot"]
	for a in states:
		for b in states:
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = 0.15 if b != "knocked" else 0.08
			if b == "move" and a in ["get_up", "punch", "shoot"]:
				t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
				t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			sm.add_transition(a, b, t)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Start", "move", start)
	tree = AnimationTree.new()
	tree.tree_root = sm
	rig.add_child(tree)                    # same parent as the AnimationPlayer: track paths match
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	playback = tree.get("parameters/playback")
	tree.set("parameters/move/scale/scale", 1.0)


## Knocked down: go limp (physics ragdoll) if one is free. Returns false if not (then
## the fall animation plays instead).
func start_ragdoll(impulse: Vector3) -> bool:
	if _ragdolling:
		ragdoll.start(impulse)
		return true
	if ragdolls_active >= max_ragdolls or skeleton == null:
		return false
	if ragdoll == null:
		ragdoll = RagdollScript.new(skeleton)
	ragdolls_active += 1
	_ragdolling = true
	ragdoll.start(impulse)
	return true


func is_ragdolling() -> bool:
	return _ragdolling


## Back to animation: the get-up starts from where the ragdoll lies, and the ragdoll
## pose fades into it. Returns where the hips ended up and which way the head points.
func end_ragdoll() -> Array:
	if not _ragdolling:
		return []
	var hips: Vector3 = ragdoll.hips_position()
	var head_dir := Vector3.ZERO
	if ragdoll.bones.has("Head"):
		head_dir = (ragdoll.bones["Head"] as Node3D).global_position - hips
	head_dir.y = 0.0
	_ragdolling = false
	ragdolls_active = maxi(0, ragdolls_active - 1)
	return [hips, head_dir]


func blend_out_ragdoll(t: float) -> void:
	if ragdoll != null:
		if playback != null:
			playback.start("get_up")
		ragdoll.blend_out(t)


func _exit_tree() -> void:
	if _ragdolling:
		_ragdolling = false
		ragdolls_active = maxi(0, ragdolls_active - 1)


## Length of the fall/get-up animation (walker.gd uses it for timing).
func get_up_time() -> float:
	return anim_player.get_animation("Death").length if anim_player != null else 1.2
