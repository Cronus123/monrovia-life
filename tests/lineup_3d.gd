extends SceneTree
## Renders a lineup of pedestrian outfits to build/screens/lineup.png (windowed run).
const CharacterScript := preload("res://proto3d/character.gd")
var f := 0
var cam: Camera3D

func _initialize() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#a9cbe0")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.4, 0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 10)
	ground.mesh = pm
	root.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 8:
		var c = CharacterScript.new()
		c.set_outfit(CharacterScript.random_outfit(rng, i % 2 == 0))
		root.add_child(c)
		c.position = Vector3(-6.3 + i * 1.8, 0, 0)
		c.rotation.y = PI          # face the camera (+Z)
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.4, 7.5)
	cam.fov = 70
	root.add_child(cam)
	cam.make_current()

func _process(_d: float) -> bool:
	f += 1
	if f == 40:
		root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/screens/lineup.png"))
		print("LINEUP DONE")
		return true
	return false
