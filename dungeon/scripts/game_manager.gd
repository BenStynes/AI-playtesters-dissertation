extends Node

# Global singleton — persists all game state between scene changes

var player: PlayerData = null
var current_floor: int = 1
var floor_start_time: float = 0.0
var encounter_threshold: int = 82  # RNG(0-100) + steps_taken > this = combat

# Combat handoff data
var pending_enemies: Array = []   # Array of EnemyData.EnemyType
var is_boss_fight: bool = false

# Dungeon persistence (so dungeon state survives returning from combat)
var dungeon_map: Array = []
var player_grid_pos: Vector2i = Vector2i(0, 0)
var player_facing: int = 0  # 0=North 1=East 2=South 3=West
var visited_tiles: Dictionary = {}

# ── Score tracking ────────────────────────────────────────────────────────────
var score: int = 0
var kills: int = 0
var floors_cleared: int = 0
var game_start_time: float = 0.0

func start_new_game(p_class: String) -> void:
	player = PlayerData.new(p_class)
	current_floor = 1
	floor_start_time = Time.get_ticks_msec() / 1000.0
	game_start_time  = floor_start_time
	dungeon_map = []
	visited_tiles = {}
	score = 0
	kills = 0
	floors_cleared = 0

func next_floor() -> void:
	floors_cleared += 1
	# Floor-clear bonus: 500 pts × floor number
	score += 500 * current_floor
	current_floor += 1
	dungeon_map = []
	visited_tiles = {}
	floor_start_time = Time.get_ticks_msec() / 1000.0
	if player:
		player.heal(int(player.max_hp * 0.5))
		player.restore_mp(int(player.max_mp * 0.5))

func add_combat_score(enemies: Array) -> void:
	for e: EnemyData in enemies:
		kills += 1
		# Base exp_drop scaled by floor — deeper = more points
		score += e.exp_drop * current_floor

func calculate_final_score() -> int:
	# Bonus: gold carried, survival HP ratio, time bonus (under 10 min)
	var hp_bonus: int  = int(float(player.hp) / float(player.max_hp) * 300)
	var gold_bonus: int = player.gold * 2
	var elapsed: float = (Time.get_ticks_msec() / 1000.0) - game_start_time
	var time_bonus: int = max(0, int(600 - elapsed)) * 2
	return score + hp_bonus + gold_bonus + time_bonus

func check_encounter(steps_taken: int) -> bool:
	var roll: int = randi_range(0, 100)
	return (roll + steps_taken) > encounter_threshold

func get_floor_elapsed() -> float:
	return (Time.get_ticks_msec() / 1000.0) - floor_start_time

# ── Floor-scaled enemy stats ──────────────────────────────────────────────────
# Returns a multiplier for HP and attack based on the current floor.
func get_floor_scale() -> float:
	# Floor 1 = 1.0, each floor adds 15% difficulty
	return 1.0 + (current_floor - 1) * 0.15
