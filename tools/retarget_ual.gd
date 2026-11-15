extends SceneTree
## Retargets Quaternius's Universal Animation Library (CC0, proto3d/models/ual/UAL1_Standard.glb,
## Unreal-style humanoid rig) onto the Ultimate Animated Character Pack skeleton our people
## use, and saves the result as an AnimationLibrary: proto3d/models/people/ual_anims.res.
##
## The two rigs have different rest poses (A/T-pose vs. arms-down) and bone layouts, so each
## frame is matched in skeleton space rather than by copying rotations:
##  - spine, neck, head and pelvis: the source bone's rotation *change* from its T-pose is
##    applied to our bone's rest orientation (both spines are upright at rest)
##  - arms and legs: each of our bones is turned so it points the same way as the source
##    bone (shoulder->elbow, elbow->wrist, hip->knee, knee->ankle...)
##  - the pelvis moves up and down with the source (scaled to our proportions)
##  - our feet are IK bones under the root, so they're placed at the end of the shins
## Both rigs face +Z with the character's left on +X.
##
## Run: Godot --headless --path . --script res://tools/retarget_ual.gd

const SRC := "res://proto3d/models/ual/UAL1_Standard.glb"
const OUT := "res://proto3d/models/people/ual_anims.res"
const TARGET_MODEL := "Casual2_Male"
const FPS := 30.0

const ANIMS := ["Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Crouch_Idle_Loop", "Crouch_Fwd_Loop",
	"Pistol_Idle_Loop", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Pistol_Shoot", "Pistol_Reload",
	"Punch_Jab", "Punch_Cross", "Hit_Chest", "Hit_Head", "Roll", "Jump_Start", "Jump_Loop", "Jump_Land",
	"Sitting_Enter", "Sitting_Exit", "Swim_Fwd_Loop", "Swim_Idle_Loop", "Sword_Attack", "Death01", "Interact",
	"Idle_Talking_Loop", "Dance_Loop", "Walk_Formal_Loop", "Push_Loop"]

# our bone: [rule, source bone, source bone it points to (dir rule)]
const MAP := {
	"Body_2": ["delta", "pelvis", ""],
	"Abdomen": ["delta", "spine_01", ""],
	"Torso": ["delta", "spine_03", ""],
	"Neck": ["delta", "neck_01", ""],
	"Head": ["delta", "Head", ""],
	"Shoulder.L": ["dir", "clavicle_l", "upperarm_l"],
	"UpperArm.L": ["dir", "upperarm_l", "lowerarm_l"],
	"LowerArm.L": ["dir", "lowerarm_l", "hand_l"],
	"Fist.L": ["dir", "hand_l", "middle_01_l"],
	"Shoulder.R": ["dir", "clavicle_r", "upperarm_r"],
	"UpperArm.R": ["dir", "upperarm_r", "lowerarm_r"],
	"LowerArm.R": ["dir", "lowerarm_r", "hand_r"],
	"Fist.R": ["dir", "hand_r", "middle_01_r"],
	"UpperLeg.L": ["dir", "thigh_l", "calf_l"],
	"LowerLeg.L": ["dir", "calf_l", "foot_l"],
	"UpperLeg.R": ["dir", "thigh_r", "calf_r"],
	"LowerLeg.R": ["dir", "calf_r", "foot_r"],
}
# what each of our "dir" bones points at, at rest (a child bone, or the foot for the shins)
const AIM := {"Shoulder.L": "UpperArm.L", "UpperArm.L": "LowerArm.L", "LowerArm.L": "Fist.L",
	"Shoulder.R": "UpperArm.R", "UpperArm.R": "LowerArm.R", "LowerArm.R": "Fist.R",
	"UpperLeg.L": "LowerLeg.L", "LowerLeg.L": "Foot.L", "UpperLeg.R": "LowerLeg.R", "LowerLeg.R": "Foot.R"}

var src_sk: Skeleton3D
var src_ap: AnimationPlayer
var tgt_sk: Skeleton3D
var base_path := ""
var rest_g := {}          # our bone -> global rest Transform3D
var aim_local := {}       # our bone -> aim direction in the bone's rest frame
var src_ref := {}         # source bone -> global Transform3D in the T-pose
var hip_scale := 1.0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var u := (load(SRC) as PackedScene).instantiate()
	root.add_child(u)
	src_sk = u.find_children("*", "Skeleton3D", true, false)[0]
	src_ap = u.find_children("*", "AnimationPlayer", true, false)[0]
	var ch = load("res://proto3d/character.gd").new()
	ch.set_outfit({"model": TARGET_MODEL})
	root.add_child(ch)
	await process_frame
	tgt_sk = ch.skeleton
	base_path = ch._bone_track_base()
	ch.tree.active = false
	for i in tgt_sk.get_bone_count():
		rest_g[tgt_sk.get_bone_name(i)] = tgt_sk.get_bone_global_rest(i)
	for b in MAP:
		if MAP[b][0] == "dir":
			var aim_pt: Vector3
			if AIM.has(b):
				aim_pt = (rest_g[AIM[b]] as Transform3D).origin
			else:                                            # fists: along the bone
				aim_pt = (rest_g[b] as Transform3D) * Vector3(0, 0.2, 0)
			aim_local[b] = ((rest_g[b] as Transform3D).affine_inverse() * aim_pt).normalized()
	_sample_src("A_TPose", 0.0)
	for i in src_sk.get_bone_count():
		src_ref[src_sk.get_bone_name(i)] = src_sk.get_bone_global_pose(i)
	hip_scale = (rest_g["Body_2"] as Transform3D).origin.y / (src_ref["pelvis"] as Transform3D).origin.y
	var lib := AnimationLibrary.new()
	for a in ANIMS:
		# Godot's importer drops the "_Loop" suffix (and makes the animation loop)
		var src_name: String = a if src_ap.has_animation(a) else a.trim_suffix("_Loop")
		if not src_ap.has_animation(src_name):
			print("missing ", a)
			continue
		lib.add_animation(a.trim_suffix("_Loop"), _retarget(src_name, a.ends_with("_Loop")))
	var err := ResourceSaver.save(lib, OUT)
	print("saved %d animations to %s (%s)" % [lib.get_animation_list().size(), OUT, error_string(err)])
	quit()


func _sample_src(anim: String, t: float) -> void:
	src_ap.play(anim)
	src_ap.seek(t, true)
	src_ap.pause()


func _src_g(b: String) -> Transform3D:
	return src_sk.get_bone_global_pose(src_sk.find_bone(b))


func _retarget(anim_name: String, looping: bool) -> Animation:
	var sa := src_ap.get_animation(anim_name)
	var out := Animation.new()
	out.length = sa.length
	out.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var tracks := {}
	for b in MAP.keys() + ["Foot.L", "Foot.R"]:
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(base_path + ":" + b))
		tracks[b] = tr
	var pos_tracks := {}
	for b in ["Body_2", "Foot.L", "Foot.R"]:
		var tp := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(tp, NodePath(base_path + ":" + b))
		pos_tracks[b] = tp
	var steps := maxi(1, int(ceil(sa.length * FPS)))
	for s in steps + 1:
		var t := minf(sa.length, s / FPS)
		_sample_src(anim_name, t)
		var g := _frame()
		for b in tracks:
			var bi := tgt_sk.find_bone(b)
			var parent := tgt_sk.get_bone_parent(bi)
			var pg: Transform3D = g[tgt_sk.get_bone_name(parent)] if parent >= 0 else Transform3D.IDENTITY
			var local: Transform3D = pg.affine_inverse() * (g[b] as Transform3D)
			out.rotation_track_insert_key(tracks[b], t, local.basis.get_rotation_quaternion())
			if pos_tracks.has(b):
				out.position_track_insert_key(pos_tracks[b], t, local.origin)
	return out


## Our skeleton's global transforms for the current source frame.
func _frame() -> Dictionary:
	var g := {}
	for i in tgt_sk.get_bone_count():
		var b := tgt_sk.get_bone_name(i)
		var parent := tgt_sk.get_bone_parent(i)
		var pg: Transform3D = g[tgt_sk.get_bone_name(parent)] if parent >= 0 else Transform3D.IDENTITY
		var cand: Transform3D = pg * tgt_sk.get_bone_rest(i)
		if b.begins_with("Foot."):
			var shin := "LowerLeg." + b.get_slice(".", 1)
			if g.has(shin):
				cand = (g[shin] as Transform3D) * ((rest_g[shin] as Transform3D).affine_inverse() * (rest_g[b] as Transform3D))
			g[b] = cand
			continue
		if MAP.has(b):
			var rule: Array = MAP[b]
			var sb: String = rule[1]
			if rule[0] == "delta":
				var delta: Basis = _src_g(sb).basis.orthonormalized() * (src_ref[sb] as Transform3D).basis.orthonormalized().inverse()
				var basis: Basis = delta * (rest_g[b] as Transform3D).basis.orthonormalized()
				var origin := cand.origin
				if b == "Body_2":
					origin = (rest_g[b] as Transform3D).origin + (_src_g(sb).origin - (src_ref[sb] as Transform3D).origin) * hip_scale
				cand = Transform3D(basis, origin)
			else:
				var d: Vector3 = (_src_g(rule[2]).origin - _src_g(sb).origin).normalized()
				var v: Vector3 = (cand.basis * (aim_local[b] as Vector3)).normalized()
				if d.length() > 0.5 and v.length() > 0.5 and v.dot(d) < 0.99999:
					var axis := v.cross(d)
					if axis.length() < 1e-5:
						axis = cand.basis.x
					var q := Quaternion(axis.normalized(), v.angle_to(d))
					cand = Transform3D(Basis(q) * cand.basis, cand.origin)
		g[b] = cand
	return g
