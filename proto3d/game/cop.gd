extends "res://proto3d/walker.gd"
## Police officer on foot: runs at the player, grabs them (arrest) when close, and shoots
## when the wanted level is high enough. Steered by police.gd.

var police                       # police.gd
var target: Node3D
var car: RigidBody3D             # the patrol car they came from
var shoot_cd := 1.0


func _ready() -> void:
	_setup_walker({"model": "Casual2_Male", "skin": "#4a2e1e", "shirt": "#2b4a7a", "pants": "#14213d", "hair": "#151210"})
	collision_mask = 1 | 4 | 8
	hp = 90.0


func _physics_process(delta: float) -> void:
	var wish := Vector3.ZERO
	if target != null and is_instance_valid(target) and not is_down():
		var to := target.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > 1.1:
			wish = to / d * 4.8
		if d > 0.2:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0.0, 1.0))
		shoot_cd -= delta
		if police != null and shoot_cd <= 0.0 and police.cops_may_shoot() and d < 22.0:
			shoot_cd = randf_range(1.1, 1.7)
			body.play("shoot")
			police.cop_fire(self, d)
	walk(wish, 10.0, delta)
	body.set_speed(Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0)
