class_name EnemyData
extends RefCounted

enum EnemyType { SLIME, SKELETON, ORC, DEMON }

var enemy_type: EnemyType
var enemy_name: String
var max_hp: int
var hp: int
var attack: int
var magic_attack: int
var phys_defense: int
var magic_defense: int
var gold_drop: int
var exp_drop: int
var is_boss: bool = false

# Boss attack pattern: basic, basic, strong, magic, magic, strong → repeat
# Weakness rule: whatever the boss uses, the OPPOSITE type is effective
const BOSS_PATTERN: Array = ["basic", "basic", "strong", "magic", "magic", "strong"]
var pattern_index: int = 0

const ENEMY_DATA: Dictionary = {
	EnemyType.SLIME: {
		"name": "Slime",
		"max_hp": 25, "attack": 4, "magic_attack": 2,
		"phys_defense": 0, "magic_defense": 0,
		"gold": 6, "exp": 15, "is_boss": false
	},
	EnemyType.SKELETON: {
		"name": "Skeleton",
		# Armored against physical, shattered by magic
		"max_hp": 35, "attack": 9, "magic_attack": 7,
		"phys_defense": 8, "magic_defense": 0,
		"gold": 12, "exp": 25, "is_boss": false
	},
	EnemyType.ORC: {
		"name": "Orc",
		# Hits hard but slow; magic is decent against it
		"max_hp": 55, "attack": 10, "magic_attack": 3,
		"phys_defense": 4, "magic_defense": 3,
		"gold": 18, "exp": 35, "is_boss": false
	},
	EnemyType.DEMON: {
		"name": "Demon Lord",
		# Balanced for a fresh floor-1 player: killable if defend is used on strong/magic turns
		"max_hp": 100, "attack": 11, "magic_attack": 11,
		"phys_defense": 6, "magic_defense": 6,
		"gold": 150, "exp": 300, "is_boss": true
	}
}

func _init(type: EnemyType) -> void:
	enemy_type = type
	var d: Dictionary = ENEMY_DATA[type]
	enemy_name    = d["name"]
	is_boss       = d["is_boss"]

	# Apply floor scaling — bosses scale slightly less aggressively
	var scale: float = GameManager.get_floor_scale()
	var boss_scale: float = 1.0 + (scale - 1.0) * 0.6 if is_boss else scale

	max_hp        = int(d["max_hp"]       * boss_scale);  hp = max_hp
	attack        = int(d["attack"]       * scale)
	magic_attack  = int(d["magic_attack"] * scale)
	phys_defense  = int(d["phys_defense"] * scale)
	magic_defense = int(d["magic_defense"]* scale)
	gold_drop     = int(d["gold"]         * scale)
	exp_drop      = int(d["exp"]          * scale)

func take_damage(amount: int, is_magic: bool) -> int:
	var def: int = magic_defense if is_magic else phys_defense
	var actual: int = max(1, amount - int(def * 0.5))
	hp = max(0, hp - actual)
	return actual

func is_dead() -> bool:
	return hp <= 0

# Returns a dict with "type" (basic/strong/magic) and "damage"
func get_attack_action() -> Dictionary:
	if is_boss:
		var action: String = BOSS_PATTERN[pattern_index % BOSS_PATTERN.size()]
		pattern_index += 1
		var dmg: int = attack
		match action:
			"strong": dmg = int(attack * 1.8)
			"magic":  dmg = magic_attack
		return {"type": action, "damage": dmg, "is_magic": action == "magic"}
	# Normal enemies just do a physical attack
	return {"type": "basic", "damage": attack, "is_magic": false}

# Hint for the player about what is effective against boss after its attack
func get_weakness_hint(action_type: String) -> String:
	match action_type:
		"basic", "strong": return "[Context] The Demon uses physical force — Magic is effective!"
		"magic":           return "[Context] The Demon uses magic — Physical attacks are effective!"
	return ""
