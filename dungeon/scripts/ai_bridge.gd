extends Node

#paths for the two json files
var STATE_FILE: String
var ACTION_FILE: String
# AI mode active or nor
var ai_enabled: bool = true

func _ready() -> void:
	var base: String = ProjectSettings.globalize_path("res://").path_join("../bridge")
	STATE_FILE = base +"/game_state.json"
	ACTION_FILE = base + "/agent_action.json"
	
	DirAccess.make_dir_recursive_absolute(base)
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
		
		#check for wall  behind
		var backward: Vector2i = pos - dirs[facing]
		if _is_walkable(map, backward):
			actions.append("move_backward")
		
		#check for interactable
		var current_tile: int = map[pos.y][pos.x]
		if current_tile in [
			DungeonGenerator.Tile.CHEST,
			DungeonGenerator.Tile.HEAL,
			DungeonGenerator.Tile.ENTRANCE,
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
func write_exploration_state(map: Array,pos: Vector2i, facing: int) -> void:
		if not ai_enabled: return
		
		var p: PlayerData = GameManager.player
		 
		#show whats in tiles around the player
		#dirs = directions, fd = forward direction
		var dirs: Array =[Vector2i(0,-1), Vector2i(1,0),Vector2i(0,1), Vector2i(-1,0)]
		var fd: Vector2i = dirs[facing]
		var ahead: Vector2i = pos +fd
		
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
				"current_tile": map[pos.y][pos.x],
				"tile_ahead":  _get_tile_(map,ahead),
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
					"type": e.enemy_type,
					"is_boss": e.is_boss
			})
		var actions: Array = ["attack","defend"]
		#only let the ai chose magic if has mp to avoid errors
		if p.mp>=10:
			actions.append("magic")
			
		var state: Dictionary ={
			"phase": "exploration",
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
