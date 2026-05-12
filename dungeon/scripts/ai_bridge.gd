extends Node

#paths for the two json files
const STATE_FILE: String = "user://game_state.json"
const ACTION_FILE: String= "user://agent_action.json"
# AI mode active or nor
var ai_enabled: bool = true
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
				"tile_ahead":  "temp", #will write later
				"avalible actions": "temp", #will write later
		}
		#think thats all ill need for data for exploration phase
