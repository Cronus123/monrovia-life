extends Node3D
## Third-person / first-person camera rig with smooth blending between views.
##
## On foot: over-the-shoulder camera on a SpringArm3D (pulls in when a wall is behind
## the player) or a first-person camera at head height. In a vehicle: a chase camera
## that recentres behind the car, or a first-person driver's-seat camera.
## V switches view. The last view is remembered separately for on foot and in a car.

const BLEND_TIME := 0.35
const MOUSE_SENS := 0.0028
const RECENTER_DELAY := 1.2   # s without mouse input before the car camera recentres

enum View { THIRD, FIRST }

var target: Node3D            # the player or the car being driven
var in_vehicle := false
var view_on_foot: View = View.THIRD
var view_in_vehicle: View = View.THIRD

var yaw := 0.0                # on foot: world yaw. In a vehicle: offset from the car's heading.
var pitch := -0.18
var cam: Camera3D
var arm: SpringArm3D
var arm_end: Node3D
var _blend_from := Transform3D()
var _blend_t := 1.0
var _idle_look := 0.0
var sensitivity := 1.0         # from Settings (1 = default)
var invert_y := false
var base_fov := 70.0            # from Settings; widens a little at speed
var motion_blur := true         # off on the Low preset
var _shake := 0.0               # crash shake strength, decays
var _blur: ShaderMaterial
var _blur_rect: ColorRect
const STICK_SPEED := 2.6       # rad/s at full right-stick deflection


func _ready() -> void:
	_make_blur()
	top_level = true
	arm = SpringArm3D.new()
	arm.margin = 0.25
	arm.collision_mask = 1 | 4
	add_child(arm)
	arm_end = Node3D.new()
	arm.add_child(arm_end)
	cam = Camera3D.new()
	cam.top_level = true
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()


func current_view() -> View:
	return view_in_vehicle if in_vehicle else view_on_foot


func is_first_person() -> bool:
	return current_view() == View.FIRST


## Point the rig at a new target (player or car). Blends from the current shot.
func follow(new_target: Node3D, vehicle: bool) -> void:
	_start_blend()
	if target is CollisionObject3D:
		arm.remove_excluded_object((target as CollisionObject3D).get_rid())
	target = new_target
	if vehicle and not in_vehicle:
		yaw = 0.0                                   # look straight ahead when getting in
	elif not vehicle and in_vehicle and target != null:
		yaw = target.global_rotation.y              # keep facing the way the car faced
	in_vehicle = vehicle
	if target is CollisionObject3D:
		arm.add_excluded_object((target as CollisionObject3D).get_rid())


func toggle_view() -> void:
	_start_blend()
	if in_vehicle:
		view_in_vehicle = View.FIRST if view_in_vehicle == View.THIRD else View.THIRD
	else:
		view_on_foot = View.FIRST if view_on_foot == View.THIRD else View.THIRD


## World yaw the camera is looking along (used for camera-relative movement).
func look_yaw() -> float:
	if in_vehicle and target != null:
		return target.global_rotation.y + yaw
	return yaw


func _start_blend() -> void:
	if cam != null and is_inside_tree():
		_blend_from = cam.global_transform
		_blend_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		yaw -= rel.x * MOUSE_SENS * sensitivity
		pitch -= rel.y * MOUSE_SENS * sensitivity * (-1.0 if invert_y else 1.0)
		_idle_look = 0.0


func _process(delta: float) -> void:
	if target == null:
		return
	if InputMap.has_action("p3_look_left"):          # gamepad right stick
		var look := Input.get_vector("p3_look_left", "p3_look_right", "p3_look_up", "p3_look_down")
		if look.length() > 0.05:
			yaw -= look.x * STICK_SPEED * sensitivity * delta
			pitch -= look.y * STICK_SPEED * 0.7 * sensitivity * delta * (-1.0 if invert_y else 1.0)
			_idle_look = 0.0
	var first := is_first_person()
	pitch = clampf(pitch, -1.35, 1.2) if first else clampf(pitch, -1.2, 0.55)
	# In a car the view drifts back behind the car when the mouse is left alone.
	_idle_look += delta
	if in_vehicle and _idle_look > RECENTER_DELAY:
		yaw = lerp_angle(yaw, 0.0, clampf(delta * 2.5, 0.0, 1.0))
		pitch = lerpf(pitch, -0.12 if not first else -0.05, clampf(delta * 2.0, 0.0, 1.0))
	var world_yaw := look_yaw()
	var look_basis := Basis.from_euler(Vector3(pitch, world_yaw, 0.0))

	var goal: Transform3D
	if first:
		goal = Transform3D(look_basis, target.call("first_person_point"))
	else:
		var right := Basis(Vector3.UP, world_yaw) * Vector3.RIGHT
		if in_vehicle:
			arm.spring_length = 7.5
			global_position = target.global_position + Vector3(0, 2.0, 0)
		else:
			arm.spring_length = 3.0
			global_position = target.global_position + Vector3(0, 1.6, 0) + right * 0.55
		arm.global_basis = look_basis
		goal = arm_end.global_transform
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / BLEND_TIME)
		var t := ease(_blend_t, -2.2)   # ease in-out
		cam.global_transform = _blend_from.interpolate_with(goal, t)
	else:
		cam.global_transform = goal
	_speed_effects(delta)


## Crash/explosion shake: strength ~0.2 (bump) .. 1.0 (big crash).
func shake(strength: float) -> void:
	_shake = clampf(maxf(_shake, strength), 0.0, 1.2)


func _speed_effects(delta: float) -> void:
	var speed := 0.0
	if in_vehicle and target is RigidBody3D:
		speed = (target as RigidBody3D).linear_velocity.length()
	cam.fov = lerpf(cam.fov, base_fov + clampf((speed - 12.0) * 0.35, 0.0, 12.0), clampf(delta * 3.0, 0.0, 1.0))
	if _shake > 0.001:
		var t := Time.get_ticks_msec() * 0.001
		var a := _shake * _shake
		cam.global_transform.origin += cam.global_basis * Vector3(sin(t * 47.0) * 0.12, sin(t * 59.0 + 1.3) * 0.1, 0.0) * a
		cam.rotate_object_local(Vector3.FORWARD, sin(t * 31.0) * 0.03 * a)
		_shake = maxf(0.0, _shake - delta * 1.6)
	if _blur != null:
		var amount := clampf((speed - 14.0) / 30.0, 0.0, 1.0) * 0.012 if motion_blur else 0.0
		_blur.set_shader_parameter("amount", amount)
		_blur_rect.visible = amount > 0.0005


## Subtle radial motion blur at speed (a full-screen pass, only shown while it's needed).
func _make_blur() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = -1                     # under the HUD
	add_child(layer)
	_blur_rect = ColorRect.new()
	_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur = ShaderMaterial.new()
	_blur.shader = preload("res://proto3d/motion_blur.gdshader")
	_blur_rect.material = _blur
	_blur_rect.visible = false
	layer.add_child(_blur_rect)
