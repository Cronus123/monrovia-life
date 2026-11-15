extends SkeletonModifier3D
## Keeps the Quaternius rig's feet (IK bones parented to the root) attached to the end
## of the shins while the ragdoll is active.

var _pairs: Array = []          # [foot index, shin index, foot pose relative to shin at rest]


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for side in ["L", "R"]:
		var f := sk.find_bone("Foot." + side)
		var s := sk.find_bone("LowerLeg." + side)
		if f >= 0 and s >= 0:
			var rel := sk.get_bone_global_rest(s).affine_inverse() * sk.get_bone_global_rest(f)
			_pairs.append([f, s, rel])


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for p in _pairs:
		var shin := sk.get_bone_global_pose(p[1])
		var want: Transform3D = shin * (p[2] as Transform3D)
		# global pose -> pose relative to the foot's parent (the root bone)
		var parent := sk.get_bone_parent(p[0])
		var parent_g := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
		sk.set_bone_pose(p[0], parent_g.affine_inverse() * want)
