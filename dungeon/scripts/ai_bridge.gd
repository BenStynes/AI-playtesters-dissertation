extends Node

#paths for the two json files
var STATE_FILE: String
var ACTION_FILE: String
# AI mode active or nor
var ai_enabled: bool = true
var ai_training: bool = true
var start_seed:  int  = 123
func _ready() -> void:
	
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	var base: String = exe_dir.path_join("bridge") 
	STATE_FILE = base +"/game_state.json"
	ACTION_FILE = base + "/agent_action.json"
	
	DirAccess.make_dir_recursive_absolute(base)
	
	if FileAccess.file_exists(ACTION_FILE):
			DirAccess.remove_absolute(ACTION_FILE)
	if FileAccess.file_exists(STATE_FILE):
			DirAccess.remove_absolute(STATE_FILE)
func _is_walkable(map: Array, pos: Vector2i) -> bool:
		if pos.x < 0 or pos.x >= DungeonGenerator.GRID_W: return false
		if pos.y <0 or pos.y >= DungeonGenerator.GRID_H: return false
		return map[pos.y][pos.x] != DungeonGenerator.Tile.WALL
		
func _get_tile_(map: Array, pos: Vector2i) ->int:
	if pos.x < 0 or pos.x >= DungeonGenerator.GRID_W: return DungeonGenerator.Tile.WALL
	if pos.y < 0 or pos.y >= DungeonGenerator.GRID_H: return DungeonGenerator.Tile.WALL
	return map[pos.y][pos.x]



func _get_exploration_Actions(map: Array,pos: Vector2i, facing: int) -> Array:
		var dirs: Array =[Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]
		var actions: Array = ["turn_left","turn_right"]
		
		#check for wall in front
		var forward: Vector2i = pos + dirs[facing]
		if _is_walkable(map,forward):
			actions.append("move_forward")
		
		
		
		#check for interactable
		var current_tile: int = map[pos.y][pos.x]
		if current_tile in [
			DungeonGenerator.Tile.CHEST,
			DungeonGenerator.Tile.HEAL,
			DungeonGenerator.Tile.SECRET_DOOR
		]:
			actions.append("interact")
		return actions
		
func _write_json(state: Dictionary) -> void:
		state["waiting_for_action"] = true
		var file := FileAccess.open(STATE_FILE,FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(state, "\t"))
			file.close()
#write the exploration state/phase to json
func write_exploration_state(map: Array,pos: Vector2i, facing: int,visited: Dictionary = {}) -> void:
		if not ai_enabled: return
		
		var p: PlayerData = GameManager.player
		 
		#show whats in tiles around the player
		#dirs = directions, fd = forward direction
		var dirs: Array =[Vector2i(0,-1), Vector2i(1,0),Vector2i(0,1), Vector2i(-1,0)]
		var fd: Vector2i = dirs[facing]
		var ahead: Vector2i = pos +fd
		var visible_special_tiles: Array = []
		var radius: int = 6
		var walkable_count: int = 0
		for y in range(DungeonGenerator.GRID_H):
			for x in range(DungeonGenerator.GRID_W):
				if map[y][x] != DungeonGenerator.Tile.WALL:
					walkable_count +=1
		for dy in range(-radius, radius +1):
			for dx in range(-radius, radius +1):
				if dx * dx + dy *dy >radius* radius +1: continue
				var check_pos: Vector2i = pos + Vector2i(dx,dy)
				if check_pos.x <0 or check_pos.x >= DungeonGenerator.GRID_W: continue
				if check_pos.y < 0 or check_pos.y >= DungeonGenerator.GRID_H: continue
				var tile: int = map[check_pos.y][check_pos.x]
				if tile in [DungeonGenerator.Tile.BOSS, DungeonGenerator.Tile.CHEST,
						DungeonGenerator.Tile.HEAL, DungeonGenerator.Tile.TRAP,
						DungeonGenerator.Tile.SECRET_DOOR]:
							
					var dist: float = sqrt(float(dx*dx + dy*dy))
					visible_special_tiles.append({
						"tile": tile,
						"dx":dx,
						"dy":dy,
						"distance": dist
					})
		var full_map: Array = []
		for y in range(DungeonGenerator.GRID_H):
				var row: Array = []
				for x in range(DungeonGenerator.GRID_W):
					row.append(map[y][x])
					full_map.append(row)
		var seen_map  = {}
		for posi in visited:
			var key = str(posi.x)+","+str(posi.y)
			seen_map[key] = map[posi.y][posi.x]
		var state: Dictionary ={
			"phase": "exploration",
			"waiting_for_action": true,
			"seed": GameManager.current_seed,
			"floor": GameManager.current_floor,
			"player": {
				"hp": p.hp,
				"max_hp": p.max_hp,
				"mp": p.mp,
				"max_mp": p.max_mp,
				"attack": p.attack,
				"magic_power": p.magic_power,
				"gold": p.gold,
				"level": p.level,
				"class": p.player_class,
				},
				"position": {"x": pos.x,"y": pos.y},
				"facing": facing,
				"vision_radius": radius,
				"seen_map": seen_map,
				"visited_count": visited.size(),
				"current_tile": map[pos.y][pos.x],
				"tile_ahead":  _get_tile_(map,ahead),
				"tile_north": _get_tile_(map, pos + Vector2i(0, -1)),
				"tile_east":  _get_tile_(map, pos + Vector2i(1,  0)),
				"tile_south": _get_tile_(map, pos + Vector2i(0,  1)),
				"tile_west":  _get_tile_(map, pos + Vector2i(-1, 0)),
				"visible_special_tiles": visible_special_tiles,
				"total_walkable_tiles": walkable_count,
				"available_actions": _get_exploration_Actions(map,pos,facing), 
		}
		#think thats all ill need for data for exploration phase
		_write_json(state)

#combat state time
func write_combat_state(enemies: Array, player_turn: bool, defending: bool) -> void:
		if not ai_enabled: return
		
		var p: PlayerData = GameManager.player
		
		var enemy_list: Array = []
		for e: EnemyData in enemies:
			if not e.is_dead():
				enemy_list.append({
					"name":e.enemy_name,
					"hp": e.hp,
					"max_hp": e.max_hp,
					"attack": e.attack,
					"magic_attack": e.magic_attack,  
					"phys_defense": e.phys_defense,
					"magic_defense": e.magic_defense, 
					"type": e.enemy_type,
					"is_boss": e.is_boss
			})
		var actions: Array = ["attack","defend"]
		#only let the ai chose magic if has mp to avoid errors
		if p.mp>=10:
			actions.append("magic")
			
		var state: Dictionary ={
			"phase": "combat",
			"seed": GameManager.current_seed,
			"floor": GameManager.current_floor,
			"waiting_for_action": true,
			"player": {
				"hp": p.hp,
				"max_hp": p.max_hp,
				"mp": p.mp,
				"max_mp": p.max_mp,
				"attack": p.attack,
				"magic_power": p.magic_power,
				"defense": p.defense,
				"crit_chance": p.crit_chance,
				"stun_chance": p.stun_chance,
				"defending": defending
				},
				"enemies": enemy_list,
				"is_boss":  GameManager.is_boss_fight,
				"player_turn": player_turn,
				"available_actions": actions, 
		}
		#think thats all ill need for data for combat  phase
		_write_json(state)

func read_action() -> String:
	
		
	
	var timeout: float = 15.0
	var elapsed: float =0.0
	var wait: float =0.1
	
	while elapsed< timeout:
		if FileAccess.file_exists(ACTION_FILE):
			OS.delay_msec(100)
			var file := FileAccess.open(ACTION_FILE, FileAccess.READ)
			if file:
				var text: String = file.get_as_text()
				file.close()
				var parsed = JSON.parse_string(text)
				
				if parsed and parsed.get("ready") == true:
					var action: String =parsed.get("action","defend")
					
					DirAccess.remove_absolute(ACTION_FILE)
					_clear_waiting_flag()
					return action
				
		OS.delay_msec(100)
		elapsed += wait
		
	push_warning("AI BRIDGE: Timedout defaulting action")
	return "defend"
func write_game_over(outcome: String,state: Dictionary) -> void:
		state["game_over"] = true
		state["outcome"] = outcome
		_write_json(state)
func write_game_over_state(outcome: String) -> void:
		if not ai_enabled: return
		
		var p: PlayerData = GameManager.player
		var state: Dictionary = {
			"phase": "game_over",
			"outcome": outcome,
			"game_over": true,
			"waiting_for_action": true,
			"seed": GameManager.current_seed,
			"player": {
				"hp": p.hp,
				"max_hp": p.max_hp,
				"gold": p.gold,
				"level": p.level
			},
			"score": GameManager.calculate_final_score(),
			"kills": GameManager.kills,
			"available_actions": ["replay","quit"]
		}
		_write_json(state)
func clear_state_file() -> void:
	if FileAccess.file_exists(STATE_FILE):
		DirAccess.remove_absolute(STATE_FILE)
func _clear_waiting_flag() -> void:
	if FileAccess.file_exists(STATE_FILE):
		var file:= FileAccess.open(STATE_FILE,FileAccess.READ)
		if file:
			var text: String =file.get_as_text()
			file.close()
			var parsed = JSON.parse_string(text)
			if parsed:
				parsed["waiting_for_action"] = false
				var out := FileAccess.open(STATE_FILE,FileAccess.WRITE)
				if out:
					out.store_string(JSON.stringify(parsed,"\t"))
					out.close()
