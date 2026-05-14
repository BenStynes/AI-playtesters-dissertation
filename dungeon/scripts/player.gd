class_name PlayerData
extends RefCounted

var player_class: String
var level: int = 1
var max_hp: int
var hp: int
var max_mp: int
var mp: int
var attack: int
var magic_power: int
var defense: int
var crit_chance: float
var gold: int = 0
var experience: int = 0
var exp_to_next: int = 60

const CLASS_STATS: Dictionary = {
	"warrior": {
		"max_hp": 150, "max_mp": 30,
		"attack": 20, "magic_power": 5,
		"defense": 12, "crit_chance": 0.05
	},
	"mage": {
		"max_hp": 70, "max_mp": 200,
		"attack": 6, "magic_power": 50,
		"defense": 5, "crit_chance": 0.05
	},
	"thief": {
		"max_hp": 90, "max_mp": 50,
		"attack": 12, "magic_power": 8,
		"defense": 8, "crit_chance": 0.25
	}
}

func _init(p_class: String) -> void:
	player_class = p_class
	var s: Dictionary = CLASS_STATS[p_class]
	max_hp = s["max_hp"];  hp = max_hp
	max_mp = s["max_mp"];  mp = max_mp
	attack = s["attack"]
	magic_power = s["magic_power"]
	defense = s["defense"]
	crit_chance = s["crit_chance"]

func take_damage(amount: int, ignore_defense: bool = false) -> int:
	var reduction: int = 0 if ignore_defense else int(defense * 0.5)
	var actual: int = max(1, amount - reduction)
	hp = max(0, hp - actual)
	return actual

func heal(amount: int) -> void:
	hp = min(max_hp, hp + amount)

func restore_mp(amount: int) -> void:
	mp = min(max_mp, mp + amount)

func is_dead() -> bool:
	return hp <= 0

# Returns true if levelled up
func gain_exp(amount: int) -> bool:
	experience += amount
	if experience >= exp_to_next:
		_level_up()
		return true
	return false

func _level_up() -> void:
	level += 1
	experience -= exp_to_next
	exp_to_next = int(exp_to_next * 1.6)
	match player_class:
		"warrior":
			max_hp += 18; attack += 4; defense += 3
		"mage":
			max_hp += 10; max_mp += 20; magic_power += 5
		"thief":
			max_hp += 12; attack += 3; magic_power += 1
			crit_chance = min(0.55, crit_chance + 0.03)
	hp = max_hp   # full restore on level up
	mp = max_mp

func get_class_weapon() -> String:
	match player_class:
		"warrior": return "Sword"
		"mage":    return "Staff"
		"thief":   return "Dagger"
	return "Fists"
