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
var exp_to_next: int = 40
var stun_chance: float = 0.0
const CLASS_STATS: Dictionary = {
	"warrior": {
		"max_hp": 100, "max_mp": 30,
		"attack": 14, "magic_power": 5,
		"defense": 10, "crit_chance": 0.05,
		"stun_chance": 0.25
	},
	"mage": {
		"max_hp": 70, "max_mp": 150,
		"attack": 5, "magic_power": 35,
		"defense": 4, "crit_chance": 0.05,
		"stun_chance": 0.05,
	},
	"thief": {
		"max_hp": 70, "max_mp": 50,
		"attack": 10, "magic_power": 6,
		"defense": 7, "crit_chance": 0.35,
		"stun_chance": 0.10
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
	stun_chance = s["stun_chance"]

func take_damage(amount: int, ignore_defense: bool = false) -> int:
	if ignore_defense:
		var actual: int = max(1, amount)
		hp = max(0, hp -actual)
		return actual
	
	var reduction_factor: float = 100.0 /(100.0 + float(defense))
	var actual: int = max(1, int(amount * reduction_factor))
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
	exp_to_next = int(exp_to_next * 1.5)
	match player_class:
		"warrior":
			max_hp += 20; attack += 5; defense += 3
		"mage":
			max_hp += 10; max_mp += 25; magic_power += 7
		"thief":
			max_hp += 14; attack += 4; magic_power += 2
			crit_chance = min(0.55, crit_chance + 0.04)
	hp = max_hp   # full restore on level up
	mp = max_mp

func get_class_weapon() -> String:
	match player_class:
		"warrior": return "Sword"
		"mage":    return "Staff"
		"thief":   return "Dagger"
	return "Fists"
