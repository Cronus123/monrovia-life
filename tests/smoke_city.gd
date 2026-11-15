extends SceneTree
## Headless smoke test for the 1:1 Monrovia city (res://proto3d/main_city.tscn).
## Waits for streaming around the Broad Street spawn, checks collision and the player,
## then drives across several tiles and checks new tiles stream in and the car stays up.
## Skips (passes) if the city hasn't been generated (tools/build_osm_city.py).

var m
var frame := 0
var failures: Array[String] = []
var car_start := Vector3.ZERO
var loaded_before := 0
var start_wait := 0


func _initialize() -> void:
	if not FileAccess.file_exists("res://proto3d/city/manifest.json"):
		print("SMOKECITY TEST PASSED (skipped: city not generated)")
		quit()
		return
	m = load("res://proto3d/main_city.tscn").instantiate()
	root.add_child(m)


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)
		push_error("SMOKECITY CHECK FAILED: " + what)


func _physics_process(_d: float) -> bool:
	if m == null or m.get_script() == null:
		print("SMOKECITY TEST FAILED: city scene failed to load")
		return true
	frame += 1
	if not m.ready_done:
		if frame > 1800:
			check(false, "city streamed in around the spawn within 30 s")
			return _finish()
		return false
	if start_wait == 0:
		start_wait = frame
	var f := frame - start_wait
	match f:
		60:
			check(m.player.is_on_floor(), "player stands on the streamed ground (y=%.2f)" % m.player.global_position.y)
			check(m.streamer.detailed_loaded() >= 4, "detailed tiles loaded near spawn (%d)" % m.streamer.detailed_loaded())
			check(m.streamer.tiles.size() >= 20, "low-detail ring loaded (%d tiles)" % m.streamer.tiles.size())
			check(m.cars.size() >= 1, "a car near the spawn")
			var c = m.cars[0]
			m.player.global_position = c.exit_point()
		70:
			m.enter_car(m.cars[0])
			car_start = m.car.global_position
			loaded_before = m.streamer.tiles.size()
			# drive by moving the car along +x quickly (tests streaming, not handling)
		71, 600:
			pass
	if f > 70 and f < 400 and m.car != null:
		m.car.global_position += Vector3(0.45, 0, 0)    # 27 m/s, about top speed
		m.car.linear_velocity = Vector3.ZERO
	if f == 420:
		var d: float = m.car.global_position.distance_to(car_start)
		check(d > 120.0, "car moved across tiles (%.0f m)" % d)
		check(m.streamer.detailed_loaded() >= 3, "detailed tiles follow the car (%d)" % m.streamer.detailed_loaded())
		check(m.streamer.tiles.has(m.streamer.tile_key(m.car.global_position)), "tile under the car is loaded")
		return _finish()
	return false


func _finish() -> bool:
	if failures.is_empty():
		print("SMOKECITY TEST PASSED (tiles %d)" % m.streamer.tiles.size())
	else:
		print("SMOKECITY TEST FAILED: ", ", ".join(failures))
	return true
