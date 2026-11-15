extends RefCounted
## Materials and parts of the vehicle models built by tools/make_vehicles.py:
## see-through Glass, recolourable Paint, and the light objects (light_head, light_tail,
## light_ind_l, light_ind_r) whose glow the cars switch. Shared by car.gd (player /
## physics cars, own light materials) and traffic_car.gd (shared materials).

const PALETTES := {
	"car": ["#c8173a", "#2b5fb3", "#e8e8e4", "#1b1b1b", "#7a8088", "#1d6e3a", "#8a2b1a", "#d8cfbd"],
	"suv": ["#1b1b1b", "#e8e8e4", "#7a8088", "#2b3a55", "#5a3a20"],
	"sport": ["#c8173a", "#f5c518", "#2b5fb3", "#1b1b1b", "#ef7d22"],
	"pickup": ["#e8e8e4", "#7a8088", "#1d6e3a", "#8a2b1a", "#2b5fb3"],
	"minibus": ["#e8e8e4", "#2b5fb3", "#f5c518", "#1d6e3a"],
	"truck": ["#1d6e3a", "#e8e8e4", "#c8173a", "#2b5fb3"],
}

static var _glass: StandardMaterial3D
static var _shared := {}            # light materials shared by traffic cars
static var night := 0.0             # set by the world clock (0 day .. 1 night)


static func glass() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.16, 0.22, 0.28, 0.42)
		_glass.roughness = 0.04
		_glass.metallic_specular = 0.9
	return _glass


static func paint_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.28
	m.metallic = 0.25
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.15
	return m


static func light_material(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c: Color = {"head": Color("#fff6d8"), "tail": Color("#ff2020"), "ind": Color("#ffa020")}[kind]
	m.albedo_color = c.darkened(0.4)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	return m


static func shared_light(kind: String) -> StandardMaterial3D:
	if not _shared.has(kind):
		_shared[kind] = light_material(kind)
	return _shared[kind]


## Traffic: headlights and tail lights glow at night (one material for all traffic).
static func update_shared() -> void:
	if _shared.has("head"):
		(_shared["head"] as StandardMaterial3D).emission_energy_multiplier = night * 3.0
	if _shared.has("tail"):
		(_shared["tail"] as StandardMaterial3D).emission_energy_multiplier = night * 1.2


static func random_paint(kind: String, rng: RandomNumberGenerator) -> Variant:
	if not PALETTES.has(kind):
		return null                                  # taxi, police, keke, armoured van: livery colours
	var p: Array = PALETTES[kind]
	return Color(String(p[rng.randi() % p.size()]))


## Styles a vehicle model. Returns {"lights": {name: MeshInstance3D}, "wheels": [...],
## "paint": [[MeshInstance3D, surface]...]}. Own light materials when own_lights.
static func style(root: Node3D, paint: Variant, own_lights: bool) -> Dictionary:
	var out := {"lights": {}, "wheels": [], "paint": []}
	var lights := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if nm.begins_with("light_"):
			var k := "head" if nm == "light_head" else ("tail" if nm == "light_tail" else "ind")
			if own_lights:
				if not lights.has(nm):
					lights[nm] = light_material(k)
				_set_all(mi, lights[nm])
			else:
				_set_all(mi, shared_light(k))          # traffic indicators stay off (energy 0)
			out["lights"][nm] = mi
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		if nm.begins_with("wheel") or nm.begins_with("Cylinder"):
			out["wheels"].append(mi)
		if nm.begins_with("interior"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 40.0
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var mn: String = m.resource_name if m != null else ""
			if mn == "Glass":
				if DisplayServer.get_name() != "headless":
					mi.set_surface_override_material(i, glass())
			elif mn == "Paint":
				out["paint"].append([mi, i])
				if paint != null and DisplayServer.get_name() != "headless":
					mi.set_surface_override_material(i, paint_material(paint))
	return out


static func _set_all(mi: MeshInstance3D, m: Material) -> void:
	# (skipped on the headless test renderer, which reports emissive overrides as errors)
	if mi.mesh == null or DisplayServer.get_name() == "headless":
		return
	for i in mi.mesh.get_surface_count():
		mi.set_surface_override_material(i, m)


## Drop the shared materials (called when the game closes, before the renderer goes).
static func release() -> void:
	_glass = null
	_shared.clear()


static func repaint(parts: Dictionary, col: Color) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var m := paint_material(col)
	for p in parts.get("paint", []):
		if is_instance_valid(p[0]):
			(p[0] as MeshInstance3D).set_surface_override_material(int(p[1]), m)
