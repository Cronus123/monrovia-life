class_name GameAudio
extends Node
## All game sound (sounds and music are synthesised by tools/make_audio.py).
## Buses: Master > Music, SFX, Ambience, Voice.
##   one-shots:  play(name, position) on a pool of 3D players (limited voices), ui(name)
##   cars:       engine loops pitched by speed and throttle on the nearest cars, sirens,
##               tyre skids for the player's car, horns
##   footsteps:  hard (roads, pavements, floors) or soft (earth, grass), from the player
##   ambience:   city day / night, market chatter, waves, rain, crossfaded by time and place
##   music:      the menu theme; in a car, a radio with three stations (R to change), which
##               keep "broadcasting" while you're tuned away

const DIR := "res://proto3d/audio/%s.wav"
const BUSES := ["Music", "SFX", "Ambience", "Voice"]
const VOICES := 14
const ENGINE_CARS := 6
const STATIONS := [["radio_highlife", "Highlife 98.1"], ["radio_hipco", "Hipco Beat FM"], ["radio_palmwine", "Palm Wine Radio"]]
const ALL := ["engine_car", "engine_keke", "engine_truck", "horn_car", "horn_keke", "siren", "skid", "crash",
	"explosion", "gunshot", "punch", "step_hard_1", "step_hard_2", "step_soft_1", "step_soft_2", "door", "cash",
	"ui_click", "ui_confirm", "amb_city_day", "amb_city_night", "amb_market", "amb_waves", "amb_rain",
	"music_menu", "radio_highlife", "radio_hipco", "radio_palmwine", "radio_bigtalk", "bigtalk_shout",
	"smg_shot", "shotgun_shot", "reload", "swing", "melee_hit", "shell"]
const LOOPS := ["engine_car", "engine_keke", "engine_truck", "siren", "skid", "amb_city_day", "amb_city_night",
	"amb_market", "amb_waves", "amb_rain", "music_menu", "radio_highlife", "radio_hipco", "radio_palmwine", "radio_bigtalk"]

var main                          # main_city.gd
var streams := {}
var station := 0                  # 0 = radio off, 1.. = stations
var stations: Array = STATIONS.duplicate()   # Big Talk adds his talk show here (big_talk.gd)
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _ui: AudioStreamPlayer
var _amb := {}                    # name -> AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_name := ""
var _engines := {}                # car -> AudioStreamPlayer3D
var _sirens := {}
var _skid: AudioStreamPlayer3D
var _step_t := 0.0
var _water_img: Image
var _mm := {}
var _t := 0.0


static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func setup(main_node) -> void:
	main = main_node
	ensure_buses()
	for n in ALL:
		if not ResourceLoader.exists(DIR % n):
			continue
		var s = load(DIR % n)
		if s is AudioStreamWAV:
			if n in LOOPS:
				(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
				(s as AudioStreamWAV).loop_begin = 0
				(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
			streams[n] = s
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 8.0
		p.max_distance = 140.0
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	_ui.bus = "SFX"
	add_child(_ui)
	for a in ["amb_city_day", "amb_city_night", "amb_market", "amb_waves", "amb_rain"]:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = streams.get(a)
		p.volume_db = -60.0
		add_child(p)
		if p.stream != null:
			p.play()
		_amb[a] = p
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_skid = AudioStreamPlayer3D.new()
	_skid.bus = "SFX"
	_skid.stream = streams.get("skid")
	_skid.volume_db = -60.0
	add_child(_skid)
	if FileAccess.file_exists("res://proto3d/city/minimap.json"):
		_mm = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/city/minimap.json"))
		var tex = load("res://proto3d/city/minimap.png")
		if tex is Texture2D:
			_water_img = (tex as Texture2D).get_image()


# ------------------------------------------------------------------ one-shots
func play(name: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = streams[name]
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func ui(name: String) -> void:
	if streams.has(name):
		_ui.stream = streams[name]
		_ui.play()


func horn(car) -> void:
	play("horn_keke" if car.kind == "keke" else "horn_car", car.global_position, 2.0)


# ------------------------------------------------------------------ music and radio
func set_music(name: String, from_position: float = 0.0) -> void:
	if name == _music_name:
		return
	_music_name = name
	if name == "" or not streams.has(name):
		_music.stop()
		return
	_music.stream = streams[name]
	_music.play(from_position)


func next_station() -> String:
	station = (station + 1) % (stations.size() + 1)
	return "Radio off" if station == 0 else String(stations[station - 1][1])


## The station playing now ("" when the radio is off or you're on foot).
func station_stream() -> String:
	return String(stations[station - 1][0]) if main != null and main.car != null and station > 0 and station <= stations.size() else ""


func set_talk_station(on: bool, stream: String, title: String) -> void:
	var has := stations.any(func(st): return st[0] == stream)
	if on and not has:
		stations.append([stream, title])
	elif not on and has:
		stations = stations.filter(func(st): return st[0] != stream)
		station = mini(station, stations.size())


func _update_music() -> void:
	if main.get_tree().paused or not main.ready_done:
		set_music("music_menu")
		return
	if main.car != null and station > 0:
		var nm: String = stations[mini(station, stations.size()) - 1][0]
		# a real broadcast: tune in mid-song, wherever the station has got to
		var length := (streams[nm] as AudioStream).get_length() if streams.has(nm) else 60.0
		set_music(nm, fmod(Time.get_ticks_msec() / 1000.0, length))
	else:
		set_music("")


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if main == null or not main.ready_done:
		return
	_t += delta
	_update_music()
	if main.get_tree().paused:
		return
	_update_engines()
	_update_skid()
	_update_footsteps(delta)
	if _t > 0.25:
		_t = 0.0
		_update_ambience()


func _engine_stream(kind: String) -> AudioStream:
	if kind == "keke":
		return streams.get("engine_keke")
	if kind in ["truck", "van"]:
		return streams.get("engine_truck")
	return streams.get("engine_car")


func _update_engines() -> void:
	var focus: Vector3 = main.focus_pos()
	# the nearest moving cars (the player's first), plus every siren in earshot
	var cands: Array = []
	if main.car != null:
		cands.append([0.0, main.car, main.car.kind, main.car.speed, true])
	for c in main.cars:
		if c != main.car and is_instance_valid(c) and not c.wrecked and (c.controller != null):
			cands.append([c.global_position.distance_to(focus), c, c.kind, c.speed, false])
	for t in main.traffic.cars:
		var d: float = t.global_position.distance_to(focus)
		if d < 50.0:
			cands.append([d, t, t.kind, t.speed, false])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	for i in mini(cands.size(), ENGINE_CARS):
		var c = cands[i][1]
		keep[c] = true
		if not _engines.has(c):
			var p := AudioStreamPlayer3D.new()
			p.bus = "SFX"
			p.stream = _engine_stream(cands[i][2])
			p.unit_size = 6.0
			p.max_distance = 70.0
			c.add_child(p)
			p.play()
			_engines[c] = p
		var pl: AudioStreamPlayer3D = _engines[c]
		var spd := absf(float(cands[i][3]))
		var throttle := Input.get_axis("p3_back", "p3_forward") if cands[i][4] else 0.6
		pl.pitch_scale = clampf(0.65 + spd / 14.0 + absf(throttle) * 0.15, 0.6, 2.6)
		pl.volume_db = -8.0 + minf(spd, 20.0) * 0.4 + (4.0 if cands[i][4] else 0.0)
	for c in _engines.keys():
		if not keep.has(c) or not is_instance_valid(c):
			if is_instance_valid(_engines[c]):
				(_engines[c] as Node).queue_free()
			_engines.erase(c)
	# sirens
	for c in main.police.cars:
		if is_instance_valid(c) and c.siren and not _sirens.has(c) and c.global_position.distance_to(focus) < 250.0:
			var s := AudioStreamPlayer3D.new()
			s.bus = "SFX"
			s.stream = streams.get("siren")
			s.unit_size = 25.0
			s.max_distance = 260.0
			c.add_child(s)
			s.play()
			_sirens[c] = s
	for c in _sirens.keys():
		if not is_instance_valid(c) or not c.siren:
			if is_instance_valid(_sirens[c]):
				(_sirens[c] as Node).queue_free()
			_sirens.erase(c)


func _update_skid() -> void:
	var c = main.car
	if c == null or not is_instance_valid(c):
		_skid.volume_db = -60.0
		return
	var side := absf(c.linear_velocity.dot(c.global_basis.x))
	var slip: float = c.wheel_slip if "wheel_slip" in c else 0.0
	side = maxf(side, slip * 10.0)
	var hard := side > 3.0 or slip > 0.3 or (Input.is_action_pressed("p3_jump") and absf(c.speed) > 6.0)
	if hard and not _skid.playing:
		_skid.play()
	_skid.global_position = c.global_position
	_skid.volume_db = lerpf(_skid.volume_db, (-6.0 + minf(side, 10.0)) if hard else -60.0, 0.2)


func _update_footsteps(delta: float) -> void:
	var p = main.player
	if main.car != null or not p.active or not p.is_on_floor():
		return
	var spd := Vector2(p.velocity.x, p.velocity.z).length()
	if spd < 0.8:
		_step_t = 0.0
		return
	_step_t -= delta
	if _step_t > 0.0:
		return
	_step_t = clampf(1.6 / spd, 0.24, 0.55)
	var soft := false
	var col = p.get_last_slide_collision()
	if col != null and col.get_collider() != null:
		var n := String((col.get_collider() as Node).get_parent().name)
		soft = n.begins_with("Terrain")
	play(("step_soft_" if soft else "step_hard_") + str(randi() % 2 + 1), p.global_position, -6.0)


func _near_water(p: Vector3) -> float:
	if _water_img == null or _mm.is_empty():
		return 0.0
	var mpp := float(_mm["m_per_px"])
	var cx := int((p.x - float(_mm["x0"])) / mpp)
	var cy := int((p.z - float(_mm["z0"])) / mpp)
	var wet := 0
	var total := 0
	for dy in range(-15, 16, 5):
		for dx in range(-15, 16, 5):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= _water_img.get_width() or y >= _water_img.get_height():
				continue
			total += 1
			var c := _water_img.get_pixel(x, y)
			if c.b > 0.5 and c.r < 0.25:
				wet += 1
	return float(wet) / maxf(1.0, total)


func _update_ambience() -> void:
	var p: Vector3 = main.focus_pos()
	var dk: float = main.clock.darkness()
	var rain: float = main.clock.rain_amount()
	var market := 0.0
	for d in main.shops.dests:
		if "Market" in String(d["name"]):
			market = maxf(market, clampf(1.0 - (d["pos"] as Vector3).distance_to(p) / 120.0, 0.0, 1.0))
	market = maxf(market, clampf(1.0 - main.shops.place_pos("auntie").distance_to(p) / 90.0, 0.0, 1.0) * (1.0 - dk))
	var levels := {"amb_city_day": 1.0 - dk, "amb_city_night": dk, "amb_market": market,
		"amb_waves": clampf(_near_water(p) * 2.0, 0.0, 1.0), "amb_rain": rain}
	var inside := 0.55 if main.car != null else 1.0
	for k in levels:
		var pl: AudioStreamPlayer = _amb[k]
		var target := linear_to_db(maxf(0.0001, float(levels[k]) * inside))
		pl.volume_db = lerpf(pl.volume_db, target, 0.3)


## Stop every player before quitting: a stream still playing at exit keeps its
## playback (and the stream resource) alive in the audio server, which shows up as a leak.
## (Cars carry their own engine and siren players, so search the whole game.)
func _exit_tree() -> void:
	var top: Node = get_parent() if get_parent() != null else self
	var players: Array = []
	for n in top.find_children("*", "", true, false):
		if n is AudioStreamPlayer or n is AudioStreamPlayer3D:
			players.append(n)
	if players.is_empty():
		return
	# the audio thread registers new playbacks and drops stopped ones asynchronously:
	# give it a moment before and after stopping, so nothing is left behind at shutdown
	OS.delay_msec(60)
	for n in players:
		n.stop()
		n.stream = null
	OS.delay_msec(60)
