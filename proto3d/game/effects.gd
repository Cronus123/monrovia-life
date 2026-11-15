class_name Effects
extends Node3D
## Short-lived visual effects and pickups: explosions, muzzle flashes, bullet tracers,
## and cash dropped by people that the player can pick up.

signal cash_picked(amount: int)

var player: Node3D
var _cash: Array = []          # [node, amount, time left]
var _cash_mat: StandardMaterial3D
var _cash_mesh: BoxMesh


func _ready() -> void:
	_cash_mat = StandardMaterial3D.new()
	_cash_mat.albedo_color = Color("#3ccf7a")
	_cash_mat.emission_enabled = true
	_cash_mat.emission = Color("#1f8a4c")
	_cash_mesh = BoxMesh.new()
	_cash_mesh.size = Vector3(0.35, 0.08, 0.2)


func explosion(at: Vector3) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.6, 0.15, 0.9)
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = at + Vector3(0, 1.0, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 25.0
	light.light_energy = 6.0
	add_child(light)
	light.global_position = at + Vector3(0, 2.0, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * 6.0, 0.6)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.8)
	tw.tween_property(light, "light_energy", 0.0, 0.9)
	tw.chain().tween_callback(func(): ball.queue_free(); light.queue_free())


func muzzle(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.5)
	l.omni_range = 5.0
	l.light_energy = 3.0
	add_child(l)
	l.global_position = at
	get_tree().create_timer(0.06).timeout.connect(l.queue_free)


func tracer(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	get_tree().create_timer(0.07).timeout.connect(mi.queue_free)


func drop_cash(at: Vector3, amount: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _cash_mesh
	mi.material_override = _cash_mat
	add_child(mi)
	mi.global_position = at + Vector3(randf_range(-0.4, 0.4), 0.25, randf_range(-0.4, 0.4))
	_cash.append([mi, amount, 30.0])


func _process(delta: float) -> void:
	for c in _cash.duplicate():
		var mi: MeshInstance3D = c[0]
		c[2] -= delta
		mi.rotate_y(delta * 3.0)
		if player != null and player.visible and mi.global_position.distance_to(player.global_position + Vector3(0, 0.3, 0)) < 1.3:
			cash_picked.emit(c[1])
			c[2] = 0.0
		if c[2] <= 0.0:
			mi.queue_free()
			_cash.erase(c)
