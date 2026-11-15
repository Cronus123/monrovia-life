extends RefCounted
## Ragdoll for the Quaternius characters: PhysicalBone3D bodies (Jolt) on the hips,
## spine, head, arms and legs, built the first time a person is knocked down.
## start(impulse) hands the skeleton to physics; blend_out(t) fades back to the
## animation (the get-up) over t seconds; is_active() / hips_position() for walker.gd.
## The pack's feet are IK bones parented to the root, so a small modifier keeps them
## on the end of the shins while the ragdoll is active.

const FootFollow := preload("res://proto3d/ragdoll_feet.gd")
const LAYER := 16                                 # ragdoll bodies: hit the world, cars, props

# bone: [child bone (sets the capsule length/direction), radius (skeleton units), mass kg, joint]
const PARTS := {
	"Hips": ["Abdomen", 0.2, 12.0, "none"],
	"Abdomen": ["Torso", 0.19, 8.0, "cone"],
	"Torso": ["Neck", 0.23, 12.0, "cone"],
	"Head": ["", 0.17, 5.0, "cone"],
	"UpperArm.L": ["LowerArm.L", 0.08, 2.5, "cone"],
	"LowerArm.L": ["Fist.L", 0.07, 1.6, "hinge"],
	"UpperArm.R": ["LowerArm.R", 0.08, 2.5, "cone"],
	"LowerArm.R": ["Fist.R", 0.07, 1.6, "hinge"],
	"UpperLeg.L": ["LowerLeg.L", 0.11, 7.0, "cone"],
	"LowerLeg.L": ["Foot.L", 0.09, 4.0, "hinge"],
	"UpperLeg.R": ["LowerLeg.R", 0.11, 7.0, "cone"],
	"LowerLeg.R": ["Foot.R", 0.09, 4.0, "hinge"],
}

var skeleton: Skeleton3D
var sim: PhysicalBoneSimulator3D
var feet: SkeletonModifier3D
var bones := {}                # name -> PhysicalBone3D
var _tween: Tween


func _init(sk: Skeleton3D) -> void:
	skeleton = sk


func is_active() -> bool:
	return sim != null and sim.is_simulating_physics()


func _build() -> void:
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	skeleton.add_child(sim)
	var scale := skeleton.global_basis.get_scale().x
	for bname in PARTS:
		var bi := skeleton.find_bone(bname)
		if bi < 0:
			continue
		var spec: Array = PARTS[bname]
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bname
		pb.bone_name = bname
		pb.mass = spec[2]
		pb.collision_layer = LAYER
		pb.collision_mask = 1 | 4 | 8
		pb.friction = 0.8
		pb.linear_damp = 0.15
		pb.angular_damp = 1.5
		var rest := skeleton.get_bone_global_rest(bi)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var child_name: String = spec[0]
		var ci := skeleton.find_bone(child_name) if child_name != "" else -1
		var tip_local := Vector3(0, 0.35, 0)                     # head: a short capsule up
		if ci >= 0:
			tip_local = rest.affine_inverse() * skeleton.get_bone_global_rest(ci).origin
		var length := maxf(tip_local.length(), 0.05)
		# physics shapes can't be scaled: size them in world units (the rig is scaled down)
		cap.radius = float(spec[1]) * scale
		cap.height = maxf(length * scale, cap.radius * 2.0 + 0.01)
		cs.shape = cap
		# capsule (local Y) from the bone origin toward its child, in bone space
		var y := tip_local.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		pb.body_offset = Transform3D(Basis(x, y, z), tip_local * 0.5)
		cs.transform = Transform3D.IDENTITY
		pb.add_child(cs)
		match String(spec[3]):
			"none":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
			"cone":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				pb.set("joint_constraints/swing_span", 55.0 if bname.begins_with("Upper") else 30.0)
				pb.set("joint_constraints/twist_span", 25.0)
			"hinge":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
				pb.set("joint_constraints/angular_limit_enabled", true)
				pb.set("joint_constraints/angular_limit_upper", 120.0)
				pb.set("joint_constraints/angular_limit_lower", 0.0)
		pb.joint_offset = pb.body_offset.affine_inverse()      # the joint sits at the bone origin
		sim.add_child(pb)
		bones[bname] = pb
	feet = FootFollow.new()
	skeleton.add_child(feet)
	sim.active = false
	feet.active = false


## Hand the body to physics, thrown with `impulse` (m/s).
func start(impulse: Vector3) -> void:
	if sim == null:
		_build()
	if _tween != null:
		_tween.kill()
	sim.influence = 1.0
	sim.active = true
	feet.active = true
	sim.physical_bones_start_simulation()
	for bname in bones:
		var pb: PhysicalBone3D = bones[bname]
		pb.linear_velocity = impulse
		pb.angular_velocity = Vector3.ZERO
	if bones.has("Torso"):
		(bones["Torso"] as PhysicalBone3D).apply_central_impulse(impulse.normalized() * 6.0 + Vector3.UP * 4.0)


## Where the ragdoll's hips are now (world space).
func hips_position() -> Vector3:
	if bones.has("Hips"):
		return (bones["Hips"] as PhysicalBone3D).global_position
	return skeleton.global_position


## Is it lying face up? (the get-up animation starts on the back)
func face_up() -> bool:
	if not bones.has("Torso"):
		return true
	return (bones["Torso"] as PhysicalBone3D).global_basis.z.y > 0.0


## Fade from the ragdoll back to the animation over `t` seconds, then stop physics.
func blend_out(t: float) -> void:
	if not is_active():
		return
	if _tween != null:
		_tween.kill()
	_tween = skeleton.create_tween()
	_tween.tween_property(sim, "influence", 0.0, t)
	_tween.tween_callback(stop)


func stop() -> void:
	if sim == null:
		return
	sim.physical_bones_stop_simulation()
	sim.active = false
	sim.influence = 1.0
	feet.active = false
