extends Node
## Skills that grow with use and perks unlocked by reputation and milestones, from
## data/perks.json. Progress lives in GameState (skill_xp, rep, fares, perks, cooldowns)
## and is saved with the game. Other systems ask: level(skill), bonus(skill),
## has(perk), effect(perk, key). Also the sprint stamina meter and the B ability key
## (Roadside Mechanic / Big Talk Connect).

signal perk_unlocked(id: String)
signal level_up(skill: String, level: int)

const DATA := "res://proto3d/game/data/perks.json"
const BASE_STAMINA := 100.0
const DRAIN := 14.0                # per second sprinting
const REGEN := 20.0

var state: GameState
var main
var data: Dictionary
var stamina := BASE_STAMINA
var winded := false           # ran out: no sprinting until a quarter has come back
var _check_t := 0.0


func setup(game_state: GameState, main_node) -> void:
	state = game_state
	main = main_node
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	stamina = max_stamina()


# ------------------------------------------------------------------ queries
func level(skill: String) -> int:
	var xp: float = state.skill_xp.get(skill, 0.0)
	var lv := 0
	var levels: Array = data["levels"]
	for i in levels.size():
		if xp >= float(levels[i]):
			lv = i
	return lv


## The skill's total bonus (e.g. 0.06 = +6%).
func bonus(skill: String) -> float:
	return level(skill) * float(data["skills"][skill]["per_level"])


func has(perk: String) -> bool:
	return state.perks.has(perk)


func effect(perk: String, key: String, default: float = 0.0) -> float:
	if not has(perk):
		return default
	for p in data["perks"]:
		if p["id"] == perk:
			return float(p["effect"].get(key, default))
	return default


func max_stamina() -> float:
	return BASE_STAMINA * (1.0 + bonus("stamina") + effect("bush_runner", "stamina"))


func xp_to_next(skill: String) -> Array:
	var lv := level(skill)
	var levels: Array = data["levels"]
	if lv >= levels.size() - 1:
		return [1.0, 1.0]
	var a := float(levels[lv])
	var b := float(levels[lv + 1])
	return [float(state.skill_xp.get(skill, 0.0)) - a, b - a]


# ------------------------------------------------------------------ earning
func add_xp(skill: String, amount: float) -> void:
	var before := level(skill)
	state.skill_xp[skill] = float(state.skill_xp.get(skill, 0.0)) + amount
	var after := level(skill)
	if after > before:
		state.say("%s skill up: level %d" % [String(data["skills"][skill]["name"]), after], Color("#8ff0ea"), 3.5)
		level_up.emit(skill, after)
		check_unlocks()


func add_rep(what: String, times: float = 1.0) -> void:
	state.rep += int(float(data["reputation"].get(what, 0)) * times)
	check_unlocks()


func add_fare() -> void:
	state.fares += 1
	add_rep("taxi_fare")


func check_unlocks() -> void:
	for p in data["perks"]:
		var id: String = p["id"]
		if has(id) or not _meets(p["needs"]):
			continue
		state.perks.append(id)
		state.big_text.emit("PERK: " + String(p["name"]).to_upper(), Color("#8ff0ea"))
		state.say(String(p["text"]), Color("#8ff0ea"), 6.0)
		perk_unlocked.emit(id)


func _meets(n: Dictionary) -> bool:
	if n.has("rep") and state.rep < int(n["rep"]):
		return false
	if n.has("fares") and state.fares < int(n["fares"]):
		return false
	if n.has("skill") and level(String(n["skill"])) < int(n["level"]):
		return false
	if n.has("bigtalk_stage"):
		if state.bt_stage < int(n["bigtalk_stage"]) and state.bt_ending != "senator":
			return false
		if bool(n.get("not_crossed", false)) and (state.bt_crossed or state.bt_ending == "expose"):
			return false
	return true


## What a locked perk still needs, in words.
func needs_text(p: Dictionary) -> String:
	var n: Dictionary = p["needs"]
	if n.has("rep"):
		return "Reputation %d (you have %d)" % [int(n["rep"]), state.rep]
	if n.has("fares"):
		return "Taxi fares %d (you have %d)" % [int(n["fares"]), state.fares]
	if n.has("skill"):
		return "%s level %d" % [String(data["skills"][n["skill"]]["name"]), int(n["level"])]
	if n.has("bigtalk_stage"):
		return "Get close to Big Talk Dweh (his Big Man stage) without crossing him"
	return ""


# ------------------------------------------------------------------ per frame: use-based xp, stamina
func _process(delta: float) -> void:
	if main == null or not main.ready_done or get_tree().paused:
		return
	var p = main.player
	var xp: Dictionary = data["xp"]
	if main.car == null and p != null and p.active:
		var spd := Vector2(p.velocity.x, p.velocity.z).length()
		var sprinting: bool = Input.is_action_pressed("p3_sprint") and spd > 5.0
		if sprinting:
			stamina = maxf(0.0, stamina - DRAIN * delta)
			if stamina <= 0.0:
				winded = true
			add_xp("stamina", float(xp["sprint_per_s"]) * delta)
		else:
			stamina = minf(max_stamina(), stamina + REGEN * delta)
		if p.swimming:
			add_xp("swimming", float(xp["swim_per_s"]) * delta)
	else:
		stamina = minf(max_stamina(), stamina + REGEN * delta)
		if main.car != null and absf(main.car.speed) > 12.0:
			add_xp("driving", float(xp["drive_fast_per_s"]) * delta)
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 2.0
		check_unlocks()


func can_sprint() -> bool:
	if winded and stamina >= max_stamina() * 0.25:
		winded = false
	return not winded and stamina > 0.0


# ------------------------------------------------------------------ the B ability
## Roadside Mechanic in a damaged car; Big Talk Connect with a wanted level.
func use_ability() -> void:
	var now := state.time_min
	if main.car != null and has("roadside_mechanic") and main.car.damage > 5.0:
		var ready_at: float = state.cooldowns.get("roadside_mechanic", -1.0e9)
		if now < ready_at:
			state.say("Your tools need a rest: %d more minutes." % int(ceil(ready_at - now)), Color("#ff9a9a"), 2.5)
			return
		main.car.damage = maxf(0.0, main.car.damage - effect("roadside_mechanic", "repair"))
		main.car.burning = -1.0
		state.cooldowns["roadside_mechanic"] = now + effect("roadside_mechanic", "cooldown")      # game minutes
		state.say("Roadside Mechanic: patched up. Condition %d%%." % main.car.condition(), Color("#8ff0ea"), 3.0)
		return
	if state.stars > 0 and has("big_talk_connect"):
		var day := state.day()
		if int(state.cooldowns.get("big_talk_connect", 0)) >= day:
			state.say("Big Talk: \"I already made one call today. You want me to finish my credit?\"", Color("#e0c0ff"), 3.0)
			return
		state.cooldowns["big_talk_connect"] = day
		state.set_stars(maxi(0, state.stars - int(effect("big_talk_connect", "stars"))))
		if state.stars == 0:
			main.police.clear()
		state.say("Big Talk: \"Officer, that one is my nephew. Leave him.\"", Color("#e0c0ff"), 4.0)
		return
	state.say("Nothing to use right now.", Color("#9fb0c0"), 1.5)
