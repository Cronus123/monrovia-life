extends SceneTree
## Windowed capture for the 1:1 city: screenshots (overview, Broad Street, Tubman Boulevard,
## Mamba Point) to build/screens/city_*.png and per-frame FPS on foot and while driving
## across tiles at top speed.
## Run: Godot.exe --path . --script res://tests/capture_city.gd

const OUT := "res://build/screens"
var m
var f := 0
var t0 := -1
var dt := 0.016
var samples := {}
var step := 0
var wait_until := 0
var drive_start := Vector3.ZERO

func _place(n: String) -> Vector3:
	var p: Array = m.streamer.manifest["places"][n]
	return Vector3(p[0], p[1] + 1.0, p[2])


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	m = load("res://proto3d/main_city.tscn").instantiate()
	root.add_child(m)


func _save(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/city_" + n + ".png"))
	print("saved ", n)


func _sample(n: String) -> void:
	if not samples.has(n):
		samples[n] = []
	samples[n].append(1.0 / maxf(dt, 0.001))


func _teleport(p: Vector3) -> void:
	m.player.global_position = p
	m.player.velocity = Vector3.ZERO
	m.streamer.focus = p


func _process(d: float) -> bool:
	dt = d
	f += 1
	if not m.ready_done:
		return f > 3000
	if t0 < 0:
		t0 = f
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var k := f - t0
	match k:
		90:
			_save("broad_street")
		100:
			m.rig.process_mode = Node.PROCESS_MODE_DISABLED
			var target: Vector3 = m.player.global_position
			m.rig.cam.global_transform = Transform3D(Basis.IDENTITY, target + Vector3(-380, 420, 520)).looking_at(target + Vector3(250, 0, -150))
		160:
			_save("overview")
			m.rig.process_mode = Node.PROCESS_MODE_INHERIT
			_teleport(_place("Tubman Boulevard"))
		400:
			m.rig.yaw = -PI / 2 + 0.5
		430:
			_save("tubman_boulevard")
			_teleport(_place("United Nations Drive"))
		700:
			m.rig.yaw = PI * 0.75
		730:
			_save("mamba_point")
			_teleport(m.streamer.spawn_point())
		1000:
			var c = m.cars[0]
			m.enter_car(c)
			drive_start = c.global_position
	if k > 20 and k < 90:
		_sample("on_foot")
	if k > 1000 and k < 1900 and m.car != null:
		# top speed (~27 m/s) east across the tiles; streaming must keep up without stutter
		m.car.global_position += Vector3(0.45, 0, 0)
		m.car.linear_velocity = Vector3.ZERO
		if k > 1010:
			_sample("driving_across_tiles")
	if k == 1900:
		for n in samples:
			var a: Array = samples[n]
			a.sort()
			var s := 0.0
			for v in a:
				s += v
			print("FPS %s: avg %.0f, 1%% low %.0f, worst %.0f" % [n, s / a.size(), a[int(a.size() * 0.01)], a[0]])
		print("tiles loaded: ", m.streamer.tiles.size(), "  drove %.0f m" % m.car.global_position.distance_to(drive_start))
		print("CAPTURE DONE")
		return true
	return false
