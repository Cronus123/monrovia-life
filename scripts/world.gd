extends RefCounted
## Procedural, stylized map of Monrovia, Liberia (not survey-accurate).
## 1 tile = 32 px. Coordinates in tiles: x grows east, y grows south.

const TS := 32.0
const W := 260
const H := 104

const OCEAN := 0
const RIVER := 1
const SAND := 2
const GRASS := 3
const ROAD := 4
const BLD := 5
const MANG := 6
const GROUND := 7
const BRIDGE := 8
const MARKET := 9
const LMK := 10
const TREE := 11
const TARMAC := 12

const TCOL_HEX := ["#1d6e9e", "#3c7f7a", "#e5d1a0", "#5d9842", "#3f434a", "#a7a39b", "#2d5e37", "#b9774f", "#8d9096", "#d06a3a", "#e8e8e2", "#2e6f2c", "#5a5d63"]
const BCOL_HEX := ["#9aa3ad", "#a0522d", "#b8672e", "#8e9aa6", "#e3d3ad", "#d9a5a5", "#9cc3d5", "#c6dcae", "#6f8fbf", "#d8c06a", "#b0b8bf", "#c27c5a"]
const STALL_HEX := ["#c8173a", "#1aa39e", "#f5c518", "#2b5fb3", "#ef7d22", "#7c3aed"]

const LABELS := [
	["Mamba Point", 20, 67], ["Downtown", 36, 65], ["Waterside", 49, 50], ["Providence Island", 60, 44],
	["Capitol Hill", 68, 60], ["Bushrod Island", 62, 18], ["Vai Town", 56, 36], ["Clara Town", 36, 27],
	["Logan Town", 82, 34], ["Sinkor", 105, 72], ["Congo Town", 158, 75], ["Gardnersville", 130, 17],
	["Barnersville", 158, 16], ["Paynesville", 215, 30], ["ELWA Junction", 205, 74],
	["Mesurado Wetlands", 125, 44], ["Mesurado River", 30, 46], ["Atlantic Ocean", 90, 92], ["Saint Paul River", 150, 8],
]

var tiles := PackedByteArray()
var variant := PackedByteArray()
var road_dist := PackedByteArray()
var road_id := PackedInt32Array()
var roads: Array = []
var landmarks: Array = []
var pois: Array = []
var dests: Array = []
var curbs := PackedInt32Array()
var lamps: Array = []
var used_curb := {}
var tcol: Array = []
var bcol: Array = []
var stall: Array = []

func _init() -> void:
	for h in TCOL_HEX: tcol.append(Color(h))
	for h in BCOL_HEX: bcol.append(Color(h))
	for h in STALL_HEX: stall.append(Color(h))
	var n := W * H
	tiles.resize(n)
	variant.resize(n)
	road_dist.resize(n)
	road_dist.fill(255)
	road_id.resize(n)
	road_id.fill(-1)
	_define()
	_build()
	_place_pois()
	_place_lamps()

# ---------------------------------------------------------------- helpers
func idx(x: int, y: int) -> int:
	return y * W + x

func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H

func tile_at(p: Vector2) -> int:
	var x := int(floor(p.x))
	var y := int(floor(p.y))
	if not inb(x, y):
		return OCEAN
	return tiles[y * W + x]

func tile_xy(x: int, y: int) -> int:
	if not inb(x, y):
		return OCEAN
	return tiles[y * W + x]

func hash2(x: int, y: int, s: int = 0) -> float:
	var h: int = (x * 374761393 + y * 668265263 + s * 982451653) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 4294967296.0

func vnoise(x: float, y: float, sc: float, s: int = 7) -> float:
	var fx := x / sc
	var fy := y / sc
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - ix
	var ty := fy - iy
	var a := hash2(ix, iy, s)
	var b := hash2(ix + 1, iy, s)
	var c := hash2(ix, iy + 1, s)
	var d := hash2(ix + 1, iy + 1, s)
	var sx := tx * tx * (3.0 - 2.0 * tx)
	var sy := ty * ty * (3.0 - 2.0 * ty)
	return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy

func coast_y(x: float) -> float:
	return 70.0 + (x - 20.0) * 0.11 + sin(x * 0.13) * 1.2 + sin(x * 0.041 + 1.0) * 1.8

func terrain(x: float, y: float) -> int:
	var cy := coast_y(x)
	var wob := sin(x * 0.31 + y * 0.17) * 0.7 + sin(x * 0.07 + 1.0) * 1.1
	if y >= cy: return OCEAN
	if x < 13.0 + sin(y * 0.5) * 0.8: return OCEAN
	var north := 12.0 + sin(x * 0.09) * 1.5
	if y < north:
		return OCEAN if x < 110 else RIVER
	if pow((x - 60.0) / 4.5, 2) + pow((y - 46.0) / 2.6, 2) < 1.0: return GRASS  # Providence Island
	if x < 95 and y < 40.0 + wob * 0.5:
		return OCEAN if x < 17 else GRASS  # Bushrod Island
	if x >= 95 and x < 99 and y < 32: return RIVER  # Stockton Creek
	if x >= 99 and x < 175 and y < 27.0 + wob: return GRASS  # Gardnersville
	if x < 72 and y < 52.0 + wob * 0.4: return RIVER  # Mesurado River
	if x < 72: return GRASS  # Cape Mesurado peninsula
	if x < 172 and y < 57.0 + wob:  # Mesurado wetlands
		var edge: float = min(y - (27.0 + wob), (57.0 + wob) - y)
		if edge < 2.2 or vnoise(x, y, 5.0) > 0.68:
			return MANG
		return RIVER
	return GRASS

func _ord(n: int) -> String:
	var suf := "th"
	if not (n % 100 > 10 and n % 100 < 14):
		match n % 10:
			1: suf = "st"
			2: suf = "nd"
			3: suf = "rd"
	return str(n) + suf

func _road(n: String, w: float, pts: Array) -> void:
	var p: Array = []
	for q in pts:
		p.append(Vector2(q[0], q[1]))
	roads.append({"n": n, "w": w, "p": p})

func poly_y(p: Array, x: float) -> float:
	for i in range(p.size() - 1):
		var a: Vector2 = p[i]
		var b: Vector2 = p[i + 1]
		if x >= min(a.x, b.x) and x <= max(a.x, b.x):
			var dx := b.x - a.x
			if abs(dx) < 0.0001: return a.y
			return a.y + (b.y - a.y) * ((x - a.x) / dx)
	return p[p.size() - 1].y

func point_on(r: Dictionary, s: float) -> Dictionary:
	var lens: Array = r.len
	var p: Array = r.p
	s = clamp(s, 0.0, r.total)
	var i := 1
	while i < lens.size() - 1 and lens[i] < s:
		i += 1
	var a: Vector2 = p[i - 1]
	var b: Vector2 = p[i]
	var L: float = max(0.0001, lens[i] - lens[i - 1])
	var t: float = (s - lens[i - 1]) / L
	var d := (b - a) / L
	return {"pos": a.lerp(b, t), "dir": d, "nrm": Vector2(-d.y, d.x)}

# ---------------------------------------------------------------- data
func _define() -> void:
	_road("Broad Street", 2.4, [[14.5, 61], [24, 60.5], [36, 59.5], [48, 59], [58, 59.5], [66, 61.5]])
	_road("UN Drive", 2.0, [[14.5, 61], [15, 56], [24, 54.6], [36, 54.4], [48, 54.6], [62, 55]])
	_road("Tubman Boulevard", 3.0, [[66, 61.5], [76, 63.5], [95, 66], [120, 69], [145, 71], [170, 72], [205, 71]])
	_road("Sinkor Beach Road", 2.0, [[74, 70], [100, 73], [125, 75.5], [150, 78], [165, 79.5]])
	_road("Gabriel Tucker Bridge", 2.0, [[42, 54.6], [42, 46], [42, 33]])
	_road("Old Bridge", 2.0, [[54, 54.6], [57, 47], [60, 40], [61, 33]])
	_road("Bushrod Highway", 2.4, [[20, 33], [42, 33], [61, 33], [80, 31], [93, 27], [101, 24]])
	_road("Freeport Road", 2.0, [[28, 33], [27, 23]])
	_road("Somalia Drive", 3.0, [[101, 24], [120, 21.5], [145, 20.5], [172, 23], [195, 36], [214, 47], [228, 54]])
	_road("Paynesville Road", 2.0, [[205, 71], [216, 62], [228, 54]])
	_road("Kakata Highway", 2.0, [[228, 54], [244, 48], [259.5, 44]])
	_road("Robertsfield Highway", 2.4, [[205, 71], [230, 75], [259.5, 80]])
	_road("Duport Road", 2.0, [[195, 36], [193, 52], [190, 71.5]])
	_road("SKD Boulevard", 2.0, [[190, 71.5], [190, 82]])
	_road("Randall Street", 1.6, [[22, 54.6], [22, 66]])
	_road("Mechlin Street", 1.6, [[30, 54.5], [30, 66.5]])
	_road("Center Street", 1.6, [[38, 54.4], [38, 67]])
	_road("Lynch Street", 1.6, [[46, 54.6], [46, 67]])
	_road("Capitol Hill Road", 1.6, [[62, 55], [71, 55.5], [74, 59], [76, 63.5]])
	_road("Clara Town Road", 1.6, [[36, 33], [36, 24], [60, 22], [78, 25], [80, 31]])
	_road("Barnersville Road", 1.6, [[150, 20.8], [152, 15]])
	var tub: Array = roads[2].p
	var beach: Array = roads[3].p
	var k := 1
	var x := 82
	while x <= 158:
		_road(_ord(k) + " Street", 1.6, [[x, poly_y(tub, x)], [x, poly_y(beach, x)]])
		k += 2
		x += 8
	for ox in [100, 140, 160]:
		_road("Old Road", 1.6, [[ox, poly_y(tub, ox)], [ox, 60.5]])
	for r in roads:
		var lens := [0.0]
		var p: Array = r.p
		for i in range(1, p.size()):
			lens.append(lens[i - 1] + (p[i] as Vector2).distance_to(p[i - 1]))
		r["len"] = lens
		r["total"] = lens[lens.size() - 1]

	landmarks = [
		{"n": "Ducor Hotel", "x": 17, "y": 57, "w": 4, "h": 2, "k": "bld", "fill": Color("#d8cdb4"), "deco": "windows"},
		{"n": "Centennial Pavilion", "x": 32, "y": 62, "w": 3, "h": 2, "k": "bld", "fill": Color("#f1efe8"), "deco": "columns"},
		{"n": "Waterside Market", "x": 43, "y": 51, "w": 11, "h": 2, "k": "market"},
		{"n": "Capitol Building", "x": 64, "y": 57, "w": 5, "h": 2, "k": "bld", "fill": Color("#eeeeea"), "deco": "dome"},
		{"n": "Executive Mansion", "x": 65, "y": 64, "w": 5, "h": 3, "k": "bld", "fill": Color("#f4f4f0"), "deco": "mansion"},
		{"n": "University of Liberia", "x": 50, "y": 62, "w": 5, "h": 3, "k": "bld", "fill": Color("#b5654a"), "deco": "windows"},
		{"n": "Police HQ", "x": 59, "y": 63, "w": 4, "h": 2, "k": "bld", "fill": Color("#2b4a7a"), "deco": "police"},
		{"n": "Freeport of Monrovia", "x": 17, "y": 16, "w": 14, "h": 5, "k": "bld", "fill": Color("#6d7882"), "deco": "containers"},
		{"n": "JFK Medical Center", "x": 88, "y": 60, "w": 5, "h": 3, "k": "bld", "fill": Color("#f2f2f2"), "deco": "cross"},
		{"n": "Spriggs Payne Airfield", "x": 103, "y": 60, "w": 24, "h": 3, "k": "tarmac"},
		{"n": "Ministerial Complex", "x": 150, "y": 66, "w": 5, "h": 3, "k": "bld", "fill": Color("#a9b4bd"), "deco": "windows"},
		{"n": "SKD Sports Complex", "x": 192, "y": 75, "w": 8, "h": 6, "k": "bld", "fill": Color("#c9ced3"), "deco": "stadium"},
		{"n": "Red Light Market", "x": 230, "y": 56, "w": 9, "h": 5, "k": "market"},
	]

func density(x: int, y: int) -> float:
	if x < 95 and y < 41: return 0.72
	if x >= 99 and x < 172 and y < 30: return 0.5
	if x < 62: return 0.9
	if x < 76: return 0.35
	if x < 135: return 0.72
	if x < 172: return 0.55
	return 0.62

func _build() -> void:
	for y in H:
		for x in W:
			tiles[idx(x, y)] = terrain(x + 0.5, y + 0.5)
	# beaches
	var t0 := tiles.duplicate()
	for y in H:
		for x in W:
			var i := idx(x, y)
			if t0[i] != GRASS: continue
			var near_ocean := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if inb(x + dx, y + dy) and t0[idx(x + dx, y + dy)] == OCEAN:
						near_ocean = true
						break
				if near_ocean: break
			if near_ocean: tiles[i] = SAND
	# roads
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var half: float = r.w / 2.0 + 0.15
		var p: Array = r.p
		for s in range(p.size() - 1):
			var a: Vector2 = p[s]
			var b: Vector2 = p[s + 1]
			for y in range(int(floor(min(a.y, b.y) - half - 1)), int(ceil(max(a.y, b.y) + half + 1)) + 1):
				for x in range(int(floor(min(a.x, b.x) - half - 1)), int(ceil(max(a.x, b.x) + half + 1)) + 1):
					if not inb(x, y): continue
					var c := Vector2(x + 0.5, y + 0.5)
					var ab := b - a
					var t: float = clamp((c - a).dot(ab) / max(0.0001, ab.length_squared()), 0.0, 1.0)
					if c.distance_to(a + ab * t) <= half:
						var i := idx(x, y)
						var tt := tiles[i]
						if tt == OCEAN or tt == RIVER: tiles[i] = BRIDGE
						elif tt != BRIDGE: tiles[i] = ROAD
						if road_id[i] < 0 or r.w > roads[road_id[i]].w: road_id[i] = ri
	# landmarks
	for L in landmarks:
		for y in range(L.y, L.y + L.h):
			for x in range(L.x, L.x + L.w):
				var i := idx(x, y)
				if tiles[i] == ROAD or tiles[i] == BRIDGE: continue
				tiles[i] = MARKET if L.k == "market" else (TARMAC if L.k == "tarmac" else LMK)
		for y in range(L.y - 1, L.y + L.h + 1):
			for x in range(L.x - 1, L.x + L.w + 1):
				if not inb(x, y): continue
				var i := idx(x, y)
				var tt := tiles[i]
				if tt == GRASS or tt == SAND or tt == RIVER or tt == MANG:
					tiles[i] = GRASS if L.k == "tarmac" else GROUND
	# distance to road (BFS)
	var q := PackedInt32Array()
	for i in W * H:
		if tiles[i] == ROAD or tiles[i] == BRIDGE:
			road_dist[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var d := road_dist[i]
		if d >= 12: continue
		var x := i % W
		var y := i / W
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + off.x
			var ny: int = y + off.y
			if not inb(nx, ny): continue
			var j := idx(nx, ny)
			if road_dist[j] > d + 1:
				road_dist[j] = d + 1
				q.append(j)
	# buildings
	for y in H:
		for x in W:
			var i := idx(x, y)
			if tiles[i] != GRASS: continue
			var d := road_dist[i]
			var dens := density(x, y)
			if d == 1:
				tiles[i] = GROUND if dens > 0.2 else GRASS
				continue
			var dd := dens * (1.0 if d <= 5 else (0.5 if d <= 8 else 0.18))
			var lx := x & 3
			var ly := y & 3
			if lx == 0 or ly == 0:
				if dd > 0.4: tiles[i] = GROUND
				elif hash2(x, y, 4) < 0.1: tiles[i] = TREE
				continue
			if hash2(x >> 2, y >> 2, 3) < dd:
				tiles[i] = BLD
				variant[i] = int(hash2(x >> 2, y >> 2, 5) * BCOL_HEX.size())
			elif hash2(x, y, 9) < 0.1 + (1.0 - dd) * 0.12:
				tiles[i] = TREE

func district_at(p: Vector2) -> String:
	var x := p.x
	var y := p.y
	var t := tile_at(p)
	if pow((x - 60.0) / 5.0, 2) + pow((y - 46.0) / 3.0, 2) < 1.0: return "Providence Island"
	if t == OCEAN: return "Saint Paul River mouth" if y < 20 else "Atlantic Ocean"
	if t == RIVER or t == MANG:
		if y < 14: return "Saint Paul River"
		if x < 72: return "Mesurado River"
		if x >= 95 and x < 99: return "Stockton Creek"
		return "Mesurado Wetlands"
	if x < 95 and y < 41:
		if x < 45: return "Bushrod Island (Clara Town)"
		if x < 70: return "Bushrod Island (Vai Town)"
		return "Bushrod Island (Logan Town)"
	if x >= 99 and x < 175 and y < 30: return "Barnersville" if x > 145 else "Gardnersville"
	if x < 26: return "Mamba Point"
	if x >= 42 and x < 58 and y < 57: return "Waterside"
	if x < 60: return "Downtown Monrovia"
	if x < 76: return "Capitol Hill"
	if x < 135: return "Sinkor"
	if x < 172: return "Congo Town"
	if x > 196 and x < 215 and y > 64: return "ELWA Junction"
	if x >= 222 and y > 48 and y < 66: return "Red Light, Paynesville"
	return "Paynesville"

func street_at(p: Vector2) -> String:
	var x := int(clamp(floor(p.x), 0, W - 1))
	var y := int(clamp(floor(p.y), 0, H - 1))
	var ri := road_id[idx(x, y)]
	return roads[ri].n if ri >= 0 else ""

# ---------------------------------------------------------------- places
func nearest_curb(x: float, y: float, max_r: int = 25, avoid: bool = false) -> Vector2:
	var best := Vector2(x, y)
	var bd := 1e9
	var found := false
	for r in range(max_r + 1):
		for yy in range(int(floor(y)) - r, int(floor(y)) + r + 1):
			for xx in range(int(floor(x)) - r, int(floor(x)) + r + 1):
				if not inb(xx, yy): continue
				var i := idx(xx, yy)
				if road_dist[i] != 1: continue
				if avoid and used_curb.has(i): continue
				var t := tiles[i]
				if t != GROUND and t != GRASS and t != SAND and t != MARKET: continue
				var d := Vector2(xx + 0.5, yy + 0.5).distance_to(Vector2(x, y))
				if d < bd:
					bd = d
					best = Vector2(xx + 0.5, yy + 0.5)
					found = true
		if found and r > bd + 1: break
	return best

func _place_pois() -> void:
	for i in W * H:
		var t := tiles[i]
		if road_dist[i] == 1 and (t == GROUND or t == GRASS or t == MARKET or t == SAND):
			curbs.append(i)
	var defs := [
		["home", "Safehouse", 84, 68],
		["mission", "Auntie Musu", 52, 57],
		["garage", "Crew garage, Vai Town", 56, 37],
		["guns", "Weapon shop", 30, 63], ["guns", "Weapon shop", 210, 60],
		["spray", "Respray shop", 64, 34], ["spray", "Respray shop", 138, 70], ["spray", "Respray shop", 200, 45],
		["park", "Keke park", 79, 67], ["park", "Vehicle park", 226, 64],
		["food", "Ma Kebeh Cookshop", 26, 62], ["food", "Sinkor Cookshop", 94, 70], ["food", "Old Road Cookshop", 118, 72],
		["food", "Congo Town Cookshop", 160, 74], ["food", "ELWA Cookshop", 200, 68], ["food", "Red Light Cookshop", 225, 62],
		["food", "Vai Town Cookshop", 75, 35], ["food", "Gardnersville Cookshop", 150, 24], ["food", "Waterside Cookshop", 40, 57],
	]
	for d in defs:
		var c := nearest_curb(d[2], d[3], 25, true)
		var i := idx(int(floor(c.x)), int(floor(c.y)))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				used_curb[i + dy * W + dx] = true
		if tiles[i] == GRASS or tiles[i] == SAND: tiles[i] = GROUND
		pois.append({"t": d[0], "n": d[1], "pos": c})
	for L in landmarks:
		dests.append({"n": L.n, "pos": nearest_curb(L.x + L.w / 2.0, L.y + L.h / 2.0)})
	var extra := [["Vai Town", 56, 36], ["Clara Town", 36, 28], ["Logan Town", 82, 30], ["Barnersville", 152, 16],
		["Fiamah, Sinkor", 100, 71], ["Congo Town", 160, 74], ["ELWA Junction", 205, 72], ["Duport Road", 193, 50],
		["Mamba Point", 18, 60], ["Gardnersville", 130, 23], ["Broad Street", 40, 59], ["Providence Island", 58, 46]]
	for e in extra:
		dests.append({"n": e[0], "pos": nearest_curb(e[1], e[2])})

func poi(t: String) -> Dictionary:
	for p in pois:
		if p.t == t: return p
	return {}

func dest(n: String) -> Vector2:
	for d in dests:
		if d.n == n: return d.pos
	return Vector2(50, 58)

func _place_lamps() -> void:
	for r in roads:
		if r.w < 2.0: continue
		var s := 3.0
		while s < r.total:
			var p := point_on(r, s)
			lamps.append(p.pos + p.nrm * (r.w / 2.0 + 0.4))
			s += 7.0

func random_curb() -> Vector2:
	var i: int = curbs[randi() % curbs.size()]
	return Vector2(i % W + 0.5, i / W + 0.5)

# ---------------------------------------------------------------- drawing
func _shade(c: Color, f: float) -> Color:
	return c.lightened(f) if f > 0.0 else c.darkened(-f)

static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, rot: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for k in 14:
		var a := k * TAU / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	ci.draw_colored_polygon(pts, col)

func draw_chunk(ci: CanvasItem, cx: int, cy: int, cs: int) -> void:
	for y in range(cy * cs, min(H, (cy + 1) * cs)):
		for x in range(cx * cs, min(W, (cx + 1) * cs)):
			_draw_tile(ci, x, y)

func _draw_tile(ci: CanvasItem, x: int, y: int) -> void:
	var t := tiles[idx(x, y)]
	var px := x * TS
	var py := y * TS
	var h := hash2(x, y, 1)
	var r := Rect2(px, py, TS, TS)
	match t:
		OCEAN:
			ci.draw_rect(r, _shade(tcol[OCEAN], (vnoise(x, y, 6.0) - 0.5) * 0.15))
			if h < 0.12:
				ci.draw_arc(Vector2(px + 16, py + 22), 10, PI * 1.2, PI * 1.8, 8, Color(1, 1, 1, 0.25), 2.0)
			var up := tile_xy(x, y - 1)
			if up == SAND or up == GRASS:
				ci.draw_rect(Rect2(px, py, TS, 4), Color(1, 1, 1, 0.35))
		RIVER:
			ci.draw_rect(r, _shade(tcol[RIVER], (vnoise(x, y, 5.0) - 0.5) * 0.2))
		BRIDGE:
			ci.draw_rect(r, tcol[BRIDGE])
			var rail := Color("#5d6066")
			if not _is_road(tile_xy(x, y - 1)): ci.draw_rect(Rect2(px, py, TS, 4), rail)
			if not _is_road(tile_xy(x, y + 1)): ci.draw_rect(Rect2(px, py + TS - 4, TS, 4), rail)
			if not _is_road(tile_xy(x - 1, y)): ci.draw_rect(Rect2(px, py, 4, TS), rail)
			if not _is_road(tile_xy(x + 1, y)): ci.draw_rect(Rect2(px + TS - 4, py, 4, TS), rail)
		MANG:
			ci.draw_rect(r, tcol[RIVER])
			for k in 3:
				ci.draw_circle(Vector2(px + 6 + hash2(x, y, 10 + k) * 20, py + 6 + hash2(x, y, 20 + k) * 20), 8 + hash2(x, y, 30 + k) * 5, Color("#2d5e37"))
			ci.draw_circle(Vector2(px + 16, py + 14), 6, Color("#3d7a46"))
		SAND:
			ci.draw_rect(r, _shade(tcol[SAND], (h - 0.5) * 0.08))
		GRASS, TREE:
			ci.draw_rect(r, _shade(tcol[GRASS], (vnoise(x, y, 4.0) - 0.5) * 0.25 + (h - 0.5) * 0.06))
			if t == TREE:
				ellipse(ci, Vector2(px + 19, py + 22), 11, 6, Color(0, 0, 0, 0.25))
				if h > 0.5:
					ci.draw_line(Vector2(px + 16, py + 26), Vector2(px + 16, py + 15), Color("#6b4a2b"), 3.0)
					for k in 5:
						var a := k * 1.256 + h * 3.0
						ellipse(ci, Vector2(px + 16 + cos(a) * 7, py + 13 + sin(a) * 5), 8, 3.5, Color("#2f7a2f"), a)
				else:
					ci.draw_circle(Vector2(px + 16, py + 15), 11, Color("#2e6f2c"))
					ci.draw_circle(Vector2(px + 13, py + 12), 6, Color("#3e8a38"))
		ROAD:
			ci.draw_rect(r, tcol[ROAD])
		GROUND:
			var downtown := x < 62 and y > 50 and y < 72
			if downtown: ci.draw_rect(r, _shade(Color("#aaa59a"), (h - 0.5) * 0.08))
			else: ci.draw_rect(r, _shade(tcol[GROUND], (vnoise(x, y, 3.0) - 0.5) * 0.18))
			if tile_xy(x, y - 1) == BLD: ci.draw_rect(Rect2(px, py, TS, 7), Color(0, 0, 0, 0.22))
		MARKET:
			ci.draw_rect(r, tcol[GROUND])
			ci.draw_rect(Rect2(px + 3, py + 3, TS - 6, TS - 12), stall[int(h * stall.size()) % stall.size()])
			ci.draw_rect(Rect2(px + 3, py + TS - 9, TS - 6, 4), Color(0, 0, 0, 0.25))
			ci.draw_rect(Rect2(px + 3, py + 3, TS - 6, 3), Color(1, 1, 1, 0.25))
		TARMAC:
			ci.draw_rect(r, tcol[TARMAC])
			if y == 61: ci.draw_rect(Rect2(px + 4, py + 14, TS - 8, 3), Color("#eeeeee"))
		BLD:
			var v := variant[idx(x, y)]
			ci.draw_rect(r, bcol[v])
			if v % 4 < 2:
				var k := 4
				while k < TS:
					ci.draw_line(Vector2(px + k, py), Vector2(px + k, py + TS), Color(0, 0, 0, 0.12), 1.0)
					k += 6
			if not _same_bld(x, y, x, y - 1): ci.draw_rect(Rect2(px, py, TS, 3), Color(1, 1, 1, 0.28))
			if not _same_bld(x, y, x - 1, y): ci.draw_rect(Rect2(px, py, 3, TS), Color(1, 1, 1, 0.15))
			if not _same_bld(x, y, x + 1, y): ci.draw_rect(Rect2(px + TS - 4, py, 4, TS), Color(0, 0, 0, 0.25))
			if not _same_bld(x, y, x, y + 1): ci.draw_rect(Rect2(px, py + TS - 5, TS, 5), Color(0, 0, 0, 0.35))
		LMK:
			ci.draw_rect(r, Color("#8a8f96"))

func _is_road(t: int) -> bool:
	return t == ROAD or t == BRIDGE

func _same_bld(x: int, y: int, xx: int, yy: int) -> bool:
	return tile_xy(xx, yy) == BLD and (xx >> 2) == (x >> 2) and (yy >> 2) == (y >> 2)

func draw_roads(ci: CanvasItem) -> void:
	for pass_i in 2:
		for r in roads:
			var pts := PackedVector2Array()
			for p in r.p: pts.append(p * TS)
			var w: float = r.w * TS + (3.0 if pass_i == 0 else 0.0)
			var col: Color = Color("#2c2f35") if pass_i == 0 else tcol[ROAD]
			ci.draw_polyline(pts, col, w)
			for p in pts: ci.draw_circle(p, w / 2.0, col)
	for r in roads:
		if r.w < 2.0: continue
		var col := Color(0.96, 0.77, 0.09, 0.85) if r.w >= 3.0 else Color(0.94, 0.94, 0.94, 0.7)
		var p: Array = r.p
		for i in range(p.size() - 1):
			var a: Vector2 = p[i] * TS
			var b: Vector2 = p[i + 1] * TS
			var L := a.distance_to(b)
			var dir: Vector2 = (b - a) / maxf(0.001, L)
			var s := 0.0
			while s < L:
				ci.draw_line(a + dir * s, a + dir * min(L, s + 14.0), col, 2.0)
				s += 28.0

func draw_landmarks(ci: CanvasItem, font: Font) -> void:
	for L in landmarks:
		if L.k != "bld": continue
		var px: float = L.x * TS
		var py: float = L.y * TS
		var w: float = L.w * TS
		var h: float = L.h * TS
		ci.draw_rect(Rect2(px + 5, py + 6, w, h), Color(0, 0, 0, 0.3))
		ci.draw_rect(Rect2(px, py, w, h), L.fill)
		ci.draw_rect(Rect2(px + 1, py + 1, w - 2, h - 2), Color(0, 0, 0, 0.35), false, 2.0)
		match L.deco:
			"windows":
				var yy := py + 8
				while yy < py + h - 6:
					var xx := px + 6
					while xx < px + w - 6:
						ci.draw_rect(Rect2(xx, yy, 6, 5), Color(0.12, 0.2, 0.31, 0.6))
						xx += 10
					yy += 10
			"columns":
				var xx := px + 6
				while xx < px + w - 4:
					ci.draw_rect(Rect2(xx, py + 6, 5, h - 12), Color("#c9c4b5"))
					xx += 12
			"dome":
				ci.draw_rect(Rect2(px + 8, py + 8, w - 16, h - 16), Color("#d9d9d2"))
				ci.draw_circle(Vector2(px + w / 2, py + h / 2), h * 0.42, Color("#c7cdd2"))
				ci.draw_circle(Vector2(px + w / 2 - 4, py + h / 2 - 4), h * 0.15, Color.WHITE)
			"mansion":
				ci.draw_rect(Rect2(px + 10, py + 10, w - 20, h - 20), Color("#e7e7e2"))
				ci.draw_rect(Rect2(px + w / 2 - 10, py + h - 14, 20, 14), Color("#2b5fb3"))
				ci.draw_rect(Rect2(px - 10, py - 10, w + 20, h + 20), Color("#1aa39e"), false, 4.0)
			"cross":
				ci.draw_rect(Rect2(px + w / 2 - 4, py + h / 2 - 14, 8, 28), Color("#c8173a"))
				ci.draw_rect(Rect2(px + w / 2 - 14, py + h / 2 - 4, 28, 8), Color("#c8173a"))
			"police":
				ci.draw_rect(Rect2(px + 8, py + 8, w - 16, h - 16), Color("#1e3a66"))
				ci.draw_circle(Vector2(px + w / 2, py + h / 2), 9, Color("#f5c518"))
			"containers":
				for yy in 4:
					for xx in 12:
						ci.draw_rect(Rect2(px + 10 + xx * 34, py + 12 + yy * 34, 30, 14), stall[int(hash2(xx, yy, 77) * stall.size()) % stall.size()])
				ci.draw_polyline(PackedVector2Array([Vector2(px + w - 30, py + h), Vector2(px + w - 30, py - 30), Vector2(px + w - 110, py - 30)]), Color("#f5c518"), 5.0)
			"stadium":
				ellipse(ci, Vector2(px + w / 2, py + h / 2), w / 2 - 4, h / 2 - 4, Color("#b4bac0"))
				ellipse(ci, Vector2(px + w / 2, py + h / 2), w / 2 - 28, h / 2 - 28, Color("#3f8f3a"))
				ci.draw_line(Vector2(px + w / 2, py + 34), Vector2(px + w / 2, py + h - 34), Color(1, 1, 1, 0.7), 2.0)
				ci.draw_arc(Vector2(px + w / 2, py + h / 2), 14, 0, TAU, 20, Color(1, 1, 1, 0.7), 2.0)
	for L in landmarks:
		var c := Vector2((L.x + L.w / 2.0) * TS, (L.y - 0.4) * TS)
		var txt: String = L.n
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		ci.draw_string_outline(font, c - Vector2(tw / 2, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0.04, 0.06, 0.12, 0.8))
		ci.draw_string(font, c - Vector2(tw / 2, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func build_minimap_image() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			img.set_pixel(x, y, tcol[tiles[idx(x, y)]])
	for r in roads:
		var p: Array = r.p
		var col := Color("#f0e3b0") if r.w >= 2.4 else Color("#d8d8d8")
		for i in range(p.size() - 1):
			var a: Vector2 = p[i]
			var b: Vector2 = p[i + 1]
			var n := int(a.distance_to(b) * 2.0) + 1
			for k in n + 1:
				var q := a.lerp(b, float(k) / n)
				var qx := int(q.x)
				var qy := int(q.y)
				if inb(qx, qy): img.set_pixel(qx, qy, col)
	return img
