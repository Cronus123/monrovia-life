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
const MAX_STARS := 5

var money := 300
var health := 100.0
var armor := 0.0
var has_pistol := false
var ammo := 0
var weapon := FISTS
var stars := 0
var mission_idx := 0
var time_min := 9.0 * 60.0              # game minutes since day 1, 00:00
var rain_from := -1.0
var rain_until := -1.0


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
func give_pistol(rounds: int) -> void:
	has_pistol = true
	ammo += rounds
	weapon = PISTOL
	weapon_changed.emit(weapon, ammo)


func add_ammo(rounds: int) -> void:
	ammo += rounds
	weapon_changed.emit(weapon, ammo)


func select_weapon(w: int) -> bool:
	if w == PISTOL and not has_pistol:
		return false
	weapon = w
	weapon_changed.emit(weapon, ammo)
	return true


func use_ammo() -> bool:
	if ammo <= 0:
		return false
	ammo -= 1
	weapon_changed.emit(weapon, ammo)
	return true


func lose_weapons() -> void:
	has_pistol = false
	ammo = 0
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
	return {"money": money, "health": health, "armor": armor, "has_pistol": has_pistol, "ammo": ammo,
		"weapon": weapon, "mission_idx": mission_idx, "time_min": time_min}


func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", 300))
	health = float(d.get("health", 100.0))
	armor = float(d.get("armor", 0.0))
	has_pistol = bool(d.get("has_pistol", false))
	ammo = int(d.get("ammo", 0))
	weapon = int(d.get("weapon", FISTS)) if has_pistol else FISTS
	mission_idx = int(d.get("mission_idx", 0))
	time_min = float(d.get("time_min", 540.0))
	stars = 0
	money_changed.emit(money)
	health_changed.emit(health, armor)
	weapon_changed.emit(weapon, ammo)
	wanted_changed.emit(stars)
