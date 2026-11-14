extends Node3D
## A rigged low-poly person (models/character.glb from tools/make_characters.py) with
## an outfit and an AnimationTree: idle / walk / run blended by speed, plus jump,
## get-in-car, knocked-down and get-up states.
##
## Animations are keyframed here from the bone layout: every limb and spine bone's
## local X axis is its swing axis (positive = forward, negative knee = bend back).

const MODEL := preload("res://proto3d/models/character.glb")

# Palette shared with the 2D game.
const SKIN_TONES := ["#5a3825", "#6b4329", "#4a2e1e", "#7a4e30", "#3d2618"]
const CLOTH := ["#c8173a", "#1aa39e", "#f5c518", "#2b5fb3", "#ef7d22", "#7c3aed", "#ffffff", "#3ccf7a", "#e06aa8", "#14213d"]
const TROUSERS := ["#2b3a55", "#1b1b1b", "#4a4f57", "#6b5a3e", "#2f4a2f", "#d8cfbd"]

var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var _speed := 0.0
var _parts := {}


func _ready() -> void:
	var m := MODEL.instantiate() as Node3D
	m.name = "Rig"
	add_child(m)
	skeleton = m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		_parts[mi.name] = mi
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(mi as MeshInstance3D).visibility_range_end = 75.0
	_build_animations(m)


## outfit keys: skin, shirt, trousers, shoes, hair, skirt, wrap, cap (colour strings or "" to hide)
func set_outfit(o: Dictionary) -> void:
	for part in ["Skin", "Shirt", "Trousers", "Shoes", "Hair", "Skirt", "HeadWrap", "Cap"]:
		var key: String = {"Skin": "skin", "Shirt": "shirt", "Trousers": "trousers", "Shoes": "shoes",
			"Hair": "hair", "Skirt": "skirt", "HeadWrap": "wrap", "Cap": "cap"}[part]
		var mi := _parts.get(part) as MeshInstance3D
		if mi == null:
			continue
		var col: String = o.get(key, "")
		mi.visible = col != ""
		if col != "":
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(col)
			mat.roughness = 0.55 if part == "Skin" else 0.85
			mi.material_override = mat


static func random_outfit(rng: RandomNumberGenerator, female: bool) -> Dictionary:
	var skin: String = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	var o := {"skin": skin, "shirt": CLOTH[rng.randi() % CLOTH.size()], "shoes": ["#1b1b1b", "#5a3a22", "#e8e8e8"][rng.randi() % 3]}
	if female:
		o["skirt"] = CLOTH[rng.randi() % CLOTH.size()]          # lappa
		o["trousers"] = skin                                     # bare legs under the lappa
		if rng.randf() < 0.6:
			o["wrap"] = CLOTH[rng.randi() % CLOTH.size()]        # head wrap
		else:
			o["hair"] = "#151210"
	else:
		o["trousers"] = TROUSERS[rng.randi() % TROUSERS.size()]
		o["hair"] = "#151210"
		if rng.randf() < 0.3:
			o["cap"] = CLOTH[rng.randi() % CLOTH.size()]
	return o


func set_speed(v: float) -> void:
	_speed = lerpf(_speed, v, 0.25)
	tree.set("parameters/move/blend/blend_position", _speed)
	tree.set("parameters/move/scale/scale", clampf(0.75 + _speed * 0.1, 0.8, 1.5))


func play(state: String) -> void:
	if playback != null:
		playback.travel(state)


func current_state() -> String:
	return String(playback.get_current_node()) if playback != null else ""


# ------------------------------------------------------------------ animations
func _build_animations(rig_root: Node3D) -> void:
	anim_player = AnimationPlayer.new()
	add_child(anim_player)
	var base := String(get_path_to(skeleton))
	var lib := AnimationLibrary.new()
	var L := {"l": 1.0, "r": -1.0}

	# idle: breathing, arms relaxed
	var idle := _anim(2.0, true)
	_rot(idle, base, "chest", [0.0, 1.0, 2.0], [Vector3.ZERO, Vector3(-0.035, 0, 0), Vector3.ZERO])
	for s in L:
		_rot(idle, base, "upper_arm." + s, [0.0, 1.0, 2.0], [Vector3(0, 0, -0.1 * L[s]), Vector3(0.03, 0, -0.12 * L[s]), Vector3(0, 0, -0.1 * L[s])])
		_rot(idle, base, "forearm." + s, [0.0], [Vector3(0.18, 0, 0)])
	lib.add_animation("idle", idle)

	lib.add_animation("walk", _gait(base, 1.0, 0.45, 0.4, 0.65, 0.35, 0.25, 0.04, 0.025))
	lib.add_animation("run", _gait(base, 0.66, 0.85, 0.65, 1.35, 0.75, 1.25, 0.2, 0.05))

	# jump: tuck legs, arms up
	var jump := _anim(0.45, false)
	for s in L:
		var lead := 1.0 if s == "l" else 0.4
		_rot(jump, base, "thigh." + s, [0.0, 0.2], [Vector3(0.2, 0, 0), Vector3(0.9 * lead, 0, 0)])
		_rot(jump, base, "shin." + s, [0.0, 0.2], [Vector3(-0.3, 0, 0), Vector3(-1.1, 0, 0)])
		_rot(jump, base, "upper_arm." + s, [0.0, 0.2], [Vector3.ZERO, Vector3(1.1, 0, -0.35 * L[s])])
		_rot(jump, base, "forearm." + s, [0.0], [Vector3(0.5, 0, 0)])
	_rot(jump, base, "spine", [0.0, 0.2], [Vector3.ZERO, Vector3(0.15, 0, 0)])
	lib.add_animation("jump", jump)

	# get in car: duck and sit
	var get_in := _anim(0.5, false)
	for s in L:
		_rot(get_in, base, "thigh." + s, [0.0, 0.5], [Vector3.ZERO, Vector3(1.45, 0, 0)])
		_rot(get_in, base, "shin." + s, [0.0, 0.5], [Vector3.ZERO, Vector3(-1.45, 0, 0)])
		_rot(get_in, base, "upper_arm." + s, [0.0, 0.5], [Vector3.ZERO, Vector3(0.7, 0, 0)])
	_rot(get_in, base, "spine", [0.0, 0.25, 0.5], [Vector3.ZERO, Vector3(0.45, 0, 0), Vector3(0.1, 0, 0)])
	_pos(get_in, base, "hips", [0.0, 0.5], [0.0, -0.42])
	lib.add_animation("get_in", get_in)

	# knocked down: fall on the back, arms out; get_up reverses it
	var knocked := _anim(0.7, false)
	var up := _anim(0.9, false)
	var kt := [0.0, 0.25, 0.7]
	_rot(knocked, base, "hips", kt, [Vector3.ZERO, Vector3(-0.6, 0, 0), Vector3(-1.5, 0, 0)])
	_pos(knocked, base, "hips", kt, [0.0, -0.35, -0.78])
	_rot(up, base, "hips", [0.0, 0.5, 0.9], [Vector3(-1.5, 0, 0), Vector3(-0.5, 0, 0), Vector3.ZERO])
	_pos(up, base, "hips", [0.0, 0.5, 0.9], [-0.78, -0.45, 0.0])
	for s in L:
		_rot(knocked, base, "upper_arm." + s, kt, [Vector3.ZERO, Vector3(1.2, 0, -0.4 * L[s]), Vector3(0.4, 0, -1.3 * L[s])])
		_rot(knocked, base, "thigh." + s, kt, [Vector3.ZERO, Vector3(0.7, 0, 0), Vector3(0.25 if s == "l" else 0.6, 0, -0.15 * L[s])])
		_rot(knocked, base, "shin." + s, kt, [Vector3.ZERO, Vector3(-0.6, 0, 0), Vector3(-0.2 if s == "l" else -0.8, 0, 0)])
		_rot(up, base, "upper_arm." + s, [0.0, 0.5, 0.9], [Vector3(0.4, 0, -1.3 * L[s]), Vector3(-0.3, 0, -0.5 * L[s]), Vector3.ZERO])
		_rot(up, base, "thigh." + s, [0.0, 0.5, 0.9], [Vector3(0.4, 0, 0), Vector3(1.3, 0, 0), Vector3.ZERO])
		_rot(up, base, "shin." + s, [0.0, 0.5, 0.9], [Vector3(-0.5, 0, 0), Vector3(-1.6, 0, 0), Vector3.ZERO])
	lib.add_animation("knocked", knocked)
	lib.add_animation("get_up", up)
	anim_player.add_animation_library("", lib)
	_build_tree()


func _gait(base: String, period: float, thigh: float, thigh_back: float, knee: float, arm: float, elbow: float, lean: float, bob: float) -> Animation:
	var a := _anim(period, true)
	var t := [0.0, period * 0.25, period * 0.5, period * 0.75, period]
	var sw := [1.0, 0.0, -1.0, 0.0, 1.0]
	for s in ["l", "r"]:
		var k := 1.0 if s == "l" else -1.0
		var th: Array = []
		var sh: Array = []
		var ar: Array = []
		for i in t.size():
			var v: float = sw[i] * k
			th.append(Vector3(v * (thigh if v > 0 else thigh_back), 0, 0))
			# knee bends most while the leg swings through (after pushing off behind)
			var phase := fposmod(float(i) / 4.0 + (0.0 if s == "l" else 0.5), 1.0)
			var bend := 0.12 + knee * maxf(0.0, sin((phase - 0.5) * TAU + PI / 2) * 0.5 + 0.5) * (1.0 if phase >= 0.5 else 0.35)
			sh.append(Vector3(-bend, 0, 0))
			ar.append(Vector3(-v * arm, 0, (-0.08 if s == "l" else 0.08)))
		_rot(a, base, "thigh." + s, t, th)
		_rot(a, base, "shin." + s, t, sh)
		_rot(a, base, "upper_arm." + s, t, ar)
		_rot(a, base, "forearm." + s, [0.0], [Vector3(elbow, 0, 0)])
	_rot(a, base, "spine", [0.0], [Vector3(lean, 0, 0)])
	_rot(a, base, "chest", t, [Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(0, -0.06, 0), Vector3.ZERO, Vector3(0, 0.06, 0)])
	_pos(a, base, "hips", t, [-bob, bob * 0.5, -bob, bob * 0.5, -bob])
	return a


func _anim(length: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a


func _rot(a: Animation, base: String, bone: String, times: Array, eulers: Array) -> void:
	var bi := skeleton.find_bone(bone)
	if bi < 0:
		return
	var rest := skeleton.get_bone_rest(bi).basis.get_rotation_quaternion()
	var tr := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(tr, NodePath(base + ":" + bone))
	for i in times.size():
		var e: Vector3 = eulers[i]
		a.rotation_track_insert_key(tr, times[i], rest * Quaternion.from_euler(e))


func _pos(a: Animation, base: String, bone: String, times: Array, dys: Array) -> void:
	var bi := skeleton.find_bone(bone)
	if bi < 0:
		return
	var rest := skeleton.get_bone_rest(bi).origin
	var tr := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(tr, NodePath(base + ":" + bone))
	for i in times.size():
		a.position_track_insert_key(tr, times[i], rest + Vector3(0, dys[i], 0))


func _build_tree() -> void:
	var sm := AnimationNodeStateMachine.new()
	# locomotion: idle -> walk -> run by speed, played faster as speed rises
	var move := AnimationNodeBlendTree.new()
	var blend := AnimationNodeBlendSpace1D.new()
	blend.min_space = 0.0
	blend.max_space = 8.0
	for p in [["idle", 0.0], ["walk", 2.0], ["run", 7.0]]:
		var n := AnimationNodeAnimation.new()
		n.animation = p[0]
		blend.add_blend_point(n, p[1], -1, p[0])
	move.add_node("blend", blend)
	move.add_node("scale", AnimationNodeTimeScale.new())
	move.connect_node("scale", 0, "blend")
	move.connect_node("output", 0, "scale")
	sm.add_node("move", move)
	for s in ["jump", "get_in", "knocked", "get_up"]:
		var n := AnimationNodeAnimation.new()
		n.animation = s
		sm.add_node(s, n)
	var states := ["move", "jump", "get_in", "knocked", "get_up"]
	for a in states:
		for b in states:
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = 0.12 if b != "knocked" else 0.06
			if a == "get_up" and b == "move":
				t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
				t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			sm.add_transition(a, b, t)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Start", "move", start)
	tree = AnimationTree.new()
	tree.tree_root = sm
	add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	playback = tree.get("parameters/playback")
	tree.set("parameters/move/scale/scale", 1.0)
