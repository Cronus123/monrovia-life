extends SceneTree
## Side-by-side before/after images of the same views:
## build/screens/before-visuals/game_<view>.png + build/screens/game_<view>.png
## -> build/screens/compare_<view>.png (before left, after right, each at half size).
## Run: Godot.exe --headless --path . --script res://tests/compare_screens.gd

const VIEWS := ["hud_on_foot", "traffic_lights", "police_chase", "driveby", "night"]


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://build/screens/")
	for v in VIEWS:
		var a := Image.load_from_file(dir + "before-visuals/game_%s.png" % v)
		var b := Image.load_from_file(dir + "game_%s.png" % v)
		if a == null or b == null:
			print("missing ", v)
			continue
		for img in [a, b]:
			img.convert(Image.FORMAT_RGB8)
			img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		var out := Image.create(1288, 360, false, Image.FORMAT_RGB8)
		out.fill(Color(0.1, 0.1, 0.1))
		out.blit_rect(a, Rect2i(0, 0, 640, 360), Vector2i(0, 0))
		out.blit_rect(b, Rect2i(0, 0, 640, 360), Vector2i(648, 0))
		out.save_png(dir + "compare_%s.png" % v)
		print("saved compare_", v)
	quit()
