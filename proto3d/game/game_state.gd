class_name GameState
extends Node
## The player's progress and status, shared by every game system:
## money, health and armour, weapons, wanted level, mission progress and the clock.
## Systems change it through these methods and listen to its signals (the HUD does).

signal money_changed(amount: int)
signal health_changed(health: float, armor: float)
signal wanted_changed(stars: int)
signal weapon_changed(weapon: int, ammo: int)
signal message(text: String, color: Color, seconds: float)
signal big_text(text: String, color: Color)
signal player_down                       # health reached zero

const FISTS := 0
const PISTOL := 1
const BAT := 2
const MACHETE := 3
const SMG := 4
const SHOTGUN := 5
const WEAPON_COUNT := 6
const GUNS := [PISTOL, SMG, SHOTGUN]
const MAGS := [0, 12, 0, 0, 30, 6]          # magazine sizes (also in data/weapons.json)
const MAX_STARS := 5

var money := 300
var health := 100.0
var armor := 0.0
var owned: Array = [true, false, false, false, false, false]
var clip: Array = [0, 0, 0, 0, 0, 0]        # rounds in the magazine, per weapon
var reserve: Array = [0, 0, 0, 0, 0, 0]     # spare rounds, per weapon
var weapon := FISTS
## (older code and saves talk about "the pistol" and "ammo": kept as views on the above)
var has_pistol: bool:
	get:
		return owned[PISTOL]
	set(v):
		owned[PISTOL] = v
## Rounds for the weapon in hand (magazine + spare).
var ammo: int:
	get:
		return clip[weapon] + reserve[weapon] if is_gun(weapon) else 0
var stars := 0
var mission_idx := 0
var time_min := 9.0 * 60.0              # game minutes since day 1, 00:00
var rain_from := -1.0
var rain_until := -1.0
# Big Talk Dweh's story (big_talk.gd)
var bt_stage := 0                       # 0..4: nobody, radio, campaign, big man, scandal
var bt_done: Array = []                 # finished job ids
var bt_posters: Array = []              # indices of posters the player pasted
var bt_crossed := false                 # the player crossed him (he holds a grudge)
var bt_ending := ""                     # "", "expose" or "senator"


func day() -> int:
	return int(time_min / 1440.0) + 1


func minute_of_day() -> float:
	return fmod(time_min, 1440.0)


func clock_text() -> String:
	var m := int(minute_of_day())
	var h := m / 60
	return "%d:%02d %s" % [((h + 11) % 12) + 1, m % 60, "AM" if h < 12 else "PM"]


static func money_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + "L$ " + s + out


func say(text: String, color: Color = Color.WHITE, seconds: float = 3.5) -> void:
	message.emit(text, color, seconds)


# ------------------------------------------------------------------ money
func add_money(n: int) -> void:
	money += n
	money_changed.emit(money)


func can_afford(n: int) -> bool:
	return money >= n


func spend(n: int) -> bool:
	if money < n:
		return false
	money -= n
	money_changed.emit(money)
	return true


## Lose up to `fee` (hospital bills, fines) without going negative.
func charge(fee: int) -> int:
	var paid: int = mini(money, fee)
	money -= paid
	money_changed.emit(money)
	return paid


# ------------------------------------------------------------------ health
func hurt(damage: float) -> void:
	if health <= 0.0:
		return
	if armor > 0.0:
		var absorbed: float = minf(armor, damage * 0.7)
		armor -= absorbed
		damage -= absorbed
	health = maxf(0.0, health - damage)
	health_changed.emit(health, armor)
	if health <= 0.0:
		player_down.emit()


func heal(amount: float) -> void:
	health = minf(100.0, health + amount)
	health_changed.emit(health, armor)


func set_armor(a: float) -> void:
	armor = clampf(a, 0.0, 100.0)
	health_changed.emit(health, armor)


# ------------------------------------------------------------------ weapons
static func is_gun(w: int) -> bool:
	return w in GUNS


## Gives a weapon (and rounds for a gun) and puts it in your hands.
func give_weapon(w: int, rounds: int = 0) -> void:
	owned[w] = true
	if is_gun(w):
		reserve[w] += rounds
		_top_up(w)
	weapon = w
	weapon_changed.emit(weapon, ammo)


func give_pistol(rounds: int) -> void:
	give_weapon(PISTOL, rounds)


## Spare rounds for a gun (the one in hand by default).
func add_ammo(rounds: int, w: int = -1) -> void:
	if w < 0:
		w = weapon if is_gun(weapon) else PISTOL
	reserve[w] += rounds
	if clip[w] == 0:
		_top_up(w)
	weapon_changed.emit(weapon, ammo)


func _top_up(w: int) -> void:
	var take: int = mini(int(MAGS[w]) - int(clip[w]), int(reserve[w]))
	clip[w] += take
	reserve[w] -= take


func select_weapon(w: int) -> bool:
	if w < 0 or w >= WEAPON_COUNT or not owned[w]:
		return false
	weapon = w
	weapon_changed.emit(weapon, ammo)
	return true


## One round out of the magazine. False when the magazine is empty (reload, or out).
func use_ammo() -> bool:
	if not is_gun(weapon) or clip[weapon] <= 0:
		return false
	clip[weapon] -= 1
	weapon_changed.emit(weapon, ammo)
	return true


func can_reload() -> bool:
	return is_gun(weapon) and clip[weapon] < int(MAGS[weapon]) and reserve[weapon] > 0


func reload() -> void:
	_top_up(weapon)
	weapon_changed.emit(weapon, ammo)


func lose_weapons() -> void:
	owned = [true, false, false, false, false, false]
	clip = [0, 0, 0, 0, 0, 0]
	reserve = [0, 0, 0, 0, 0, 0]
	weapon = FISTS
	weapon_changed.emit(weapon, ammo)


# ------------------------------------------------------------------ wanted level
func set_stars(n: int) -> void:
	var before := stars
	stars = clampi(n, 0, MAX_STARS)
	if stars != before:
		wanted_changed.emit(stars)


# ------------------------------------------------------------------ save data
func to_dict() -> Dictionary:
	return {"money": money, "health": health, "armor": armor, "owned": owned, "clip": clip, "reserve": reserve,
		"weapon": weapon, "mission_idx": mission_idx, "time_min": time_min,
		"bt_stage": bt_stage, "bt_done": bt_done, "bt_posters": bt_posters, "bt_crossed": bt_crossed, "bt_ending": bt_ending}


func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", 300))
	health = float(d.get("health", 100.0))
	armor = float(d.get("armor", 0.0))
	lose_weapons()
	if d.has("owned"):
		for i in mini(WEAPON_COUNT, (d["owned"] as Array).size()):
			owned[i] = bool(d["owned"][i])
			clip[i] = int(d["clip"][i])
			reserve[i] = int(d["reserve"][i])
	elif bool(d.get("has_pistol", false)):        # saves from before the weapon update
		owned[PISTOL] = true
		reserve[PISTOL] = int(d.get("ammo", 0))
		_top_up(PISTOL)
	owned[FISTS] = true
	weapon = int(d.get("weapon", FISTS))
	if weapon < 0 or weapon >= WEAPON_COUNT or not owned[weapon]:
		weapon = FISTS
	mission_idx = int(d.get("mission_idx", 0))
	time_min = float(d.get("time_min", 540.0))
	bt_stage = int(d.get("bt_stage", 0))
	bt_done = Array(d.get("bt_done", []))
	bt_posters = []
	for i in d.get("bt_posters", []):
		bt_posters.append(int(i))
	bt_crossed = bool(d.get("bt_crossed", false))
	bt_ending = String(d.get("bt_ending", ""))
	stars = 0
	money_changed.emit(money)
	health_changed.emit(health, armor)
	weapon_changed.emit(weapon, ammo)
	wanted_changed.emit(stars)
