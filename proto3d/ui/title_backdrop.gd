class_name TitleBackdrop
extends Control
## The title screen's background while the city is still streaming in: an evening sky over
## a made-up Monrovia skyline (blocks, zinc-roofed houses, palms, a radio mast), with
## windows lighting up, a slow sun, drifting clouds and a lighthouse beam. Drawn with plain
## 2D shapes (nothing to download or compile), then faded out once the 3D city is ready.

const NAVY := Color(0.063, 0.102, 0.196)
var _t := 0.0
var _blocks: Array = []      # [x, w, h, layer, roof kind]
var _palms: Array = []       # [x, h, lean]
var _windows: Array = []     # [block index, u, v, phase]
var _clouds: Array = []      # [x, y, w, speed]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1847
	for layer in 2:
		var x := -0.02
		while x < 1.04:
			var w := rng.randf_range(0.025, 0.07) * (1.0 if layer == 0 else 0.8)
			var h := rng.randf_range(0.05, 0.16) * (1.0 if layer == 0 else 1.25)
			if layer == 1 and rng.randf() < 0.12:
				h *= 1.9                                # a few taller office blocks
			_blocks.append([x, w, h, layer, rng.randi() % 3])
			x += w + rng.randf_range(0.0, 0.012)
	for i in _blocks.size():
		var b: Array = _blocks[i]
		if b[3] == 1:
			for k in int(b[2] * 60.0):
				_windows.append([i, rng.randf_range(0.15, 0.85), rng.randf_range(0.12, 0.9), rng.randf() * 40.0])
	for i in 9:
		_palms.append([rng.randf(), rng.randf_range(0.11, 0.17), rng.randf_range(-0.3, 0.3)])
	for i in 6:
		_clouds.append([rng.randf(), rng.randf_range(0.08, 0.32), rng.randf_range(0.12, 0.26), rng.randf_range(0.004, 0.01)])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var horizon := s.y * 0.74
	# sky: night blue at the top, warm orange at the horizon
	var top := NAVY
	var mid := Color(0.24, 0.2, 0.36)
	var low := Color(0.93, 0.52, 0.27)
	var bands := 24
	for i in bands:
		var a := float(i) / bands
		var c := top.lerp(mid, a * 1.6) if a < 0.62 else mid.lerp(low, (a - 0.62) / 0.38)
		draw_rect(Rect2(0, horizon * a, s.x, horizon / bands + 1.0), c)
	# sun sinking slowly into the sea
	var sun_y := horizon - s.y * 0.07 + sin(_t * 0.05) * s.y * 0.015
	draw_circle(Vector2(s.x * 0.7, sun_y), s.y * 0.07, Color(1.0, 0.72, 0.35, 0.35))
	draw_circle(Vector2(s.x * 0.7, sun_y), s.y * 0.05, Color(1.0, 0.82, 0.45))
	# clouds
	for c in _clouds:
		var cx := fposmod(float(c[0]) + _t * float(c[3]), 1.3) - 0.15
		var r := Rect2(cx * s.x, float(c[1]) * horizon, float(c[2]) * s.x, s.y * 0.018)
		draw_rect(r, Color(1, 0.85, 0.8, 0.12))
		draw_rect(r.grow_individual(-r.size.x * 0.2, s.y * 0.01, -r.size.x * 0.25, 0), Color(1, 0.85, 0.8, 0.08))
	# sea
	draw_rect(Rect2(0, horizon, s.x, s.y - horizon), Color(0.09, 0.13, 0.24))
	for i in 7:
		var y := horizon + (i + 1) * (s.y - horizon) / 8.0
		var off := sin(_t * 0.6 + i) * s.x * 0.01
		draw_line(Vector2(s.x * 0.55 + off, y), Vector2(s.x * 0.85 + off, y), Color(1.0, 0.7, 0.4, 0.18 - i * 0.02), 2.0)
	# lighthouse beam sweeping over the sea (Mamba Point)
	var beam := sin(_t * 0.8)
	var lh := Vector2(s.x * 0.93, horizon - s.y * 0.2)
	draw_colored_polygon(PackedVector2Array([lh, lh + Vector2(-s.x * 0.5, -s.y * 0.05 + beam * s.y * 0.06),
		lh + Vector2(-s.x * 0.5, s.y * 0.03 + beam * s.y * 0.06)]), Color(1, 0.95, 0.75, 0.06 + 0.05 * absf(beam)))
	draw_rect(Rect2(lh.x - 5, lh.y, 10, horizon - lh.y), Color(0.05, 0.07, 0.13))
	draw_circle(lh, 6.0, Color(1, 0.95, 0.7, 0.9))
	# skyline: far layer first, then the near layer with lit windows
	for layer in [1, 0]:
		var col := Color(0.1, 0.12, 0.22) if layer == 1 else Color(0.04, 0.05, 0.1)
		var base := horizon + (0.0 if layer == 1 else s.y * 0.04)
		for i in _blocks.size():
			var b: Array = _blocks[i]
			if b[3] != layer:
				continue
			var r := Rect2(float(b[0]) * s.x, base - float(b[2]) * s.y, float(b[1]) * s.x, float(b[2]) * s.y + s.y)
			draw_rect(r, col)
			if int(b[4]) == 1:                           # zinc roof
				draw_colored_polygon(PackedVector2Array([r.position + Vector2(-3, 0), r.position + Vector2(r.size.x * 0.5, -r.size.x * 0.25),
					r.position + Vector2(r.size.x + 3, 0)]), col)
			elif int(b[4]) == 2 and layer == 1:          # water tank on the roof
				draw_rect(Rect2(r.position + Vector2(r.size.x * 0.6, -8), Vector2(7, 8)), col)
	# lit windows (they come on one by one)
	for w in _windows:
		var b: Array = _blocks[int(w[0])]
		if fmod(_t + float(w[3]), 40.0) < 14.0:
			continue
		var r := Rect2(float(b[0]) * s.x, horizon - float(b[2]) * s.y, float(b[1]) * s.x, float(b[2]) * s.y)
		draw_rect(Rect2(r.position + Vector2(r.size.x * float(w[1]), r.size.y * float(w[2])), Vector2(3, 4)), Color(1.0, 0.85, 0.5, 0.8))
	# radio mast with a blinking light
	var mx := s.x * 0.35
	draw_line(Vector2(mx, horizon - s.y * 0.34), Vector2(mx, horizon), Color(0.1, 0.12, 0.22), 3.0)
	if fmod(_t, 1.6) < 0.8:
		draw_circle(Vector2(mx, horizon - s.y * 0.34), 4.0, Color(1, 0.25, 0.2))
	# palms in front, swaying
	for p in _palms:
		var x := float(p[0]) * s.x
		var h := float(p[1]) * s.y
		var sway := sin(_t * 0.9 + x) * 0.04 + float(p[2]) * 0.2
		var foot := Vector2(x, s.y)
		var head := foot + Vector2(sway * h * 2.0, -h - s.y * 0.04)
		draw_line(foot, head, Color(0.02, 0.03, 0.06), 5.0)
		for k in 6:
			var a := -PI / 2.0 + (k - 2.5) * 0.55 + sway
			var tip := head + Vector2(cos(a), sin(a) * 0.5 + 0.35) * h * 0.45
			draw_line(head, tip, Color(0.02, 0.03, 0.06), 4.0)
