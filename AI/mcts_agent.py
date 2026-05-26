import json
import os
import time
import random
import math
import random 
import copy
from logger import RunLogger

#file paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BRIDGE_DIR = os.path.join(BASE_DIR, "..", "bridge")
STATE_FILE = os.path.join(BRIDGE_DIR, "game_state.json")
ACTION_FILE = os.path.join(BRIDGE_DIR, "agent_action.json")
#configs
TRAINING_MODE = False
FIXED_SEED = 42
TOTAL_RUNS = 5

#Sim amount how many times MCTS will simulate futures before picking an action
NUM_SIMULATIONS = 200

class MCTSNode:
    def __init__(self,game_state: dict, parent=None,action_taken: str = None):

        self.game_state = game_state
        self.parent = parent
        self.action_taken = action_taken
        self.visit_count = 0 #how many times the node has been visited during simulation
        self.total_reward =0.0 #acumulated reward
        self.children = []
        self.unexplored_actions = list(game_state.get("available_actions",[]))


    def is_fully_expanded(self) -> bool:
        return len(self.unexplored_actions) == 0
    
    def is_terminal(self) ->bool:

        return self.game_state.get("game_over", False)
    
    def ucb1_score(self,exploration_constant: float = 1.414) ->float:
        #ucb1 is the formula that balances competeing desires
        #exploitation is choosing paths that worked well already
        #exploration is trying new paths
        #the constant is the square root of 2 which is the optimal value
        

        if self.visit_count == 0:
            return float('inf')
        
        exploitation = self.total_reward / self.visit_count

        exploration = exploration_constant * math.sqrt(math.log(self.parent.visit_count)/self.visit_count)

        return exploitation + exploration
    
#Game simulation logic
def apply_action(game_state: dict, action: str)-> dict:
    #create a deep copy so to neever modify the real state  and ensure all nested dicts and lists are copied
    new_state = copy.deepcopy(game_state)
    phase = new_state.get("phase","exploration")

    if phase == "combat":
        return _apply_combat_action(new_state, action)
    else:
        
        return _apply_exploration_action(new_state, action)
def _apply_combat_action(state:dict,action: str)-> dict:

    player = state["player"]
    enemies =state.get("enemies",[])

    target = next((e for e in enemies if e.get("hp",0)>0),None)
    if target is None:
        state["game_over"] =True
        state["battle_won"]= True
        return state
    if action == "attack":
        dmg = player.get("attack",10)
        defense = target.get("phys_defense",0)
        actual_dmg = max(1,dmg - int(defense*0.5))
        target["hp"] = max(0, target["hp"]- actual_dmg)
    elif action == "magic":
        dmg = int(player.get("magic_power",5)*1.5)
        actual_dmg = max(1,dmg)
        target["hp"] = max(0, target["hp"]-actual_dmg)
    elif action =="defend":
        pass

    if target["hp"] <= 0:
        all_dead = all(e.get("hp",0)<= 0 for e in enemies)
        if all_dead:
            state["game_over"] = True
            state["battle_won"] = True
            return state
    
    enemy_attack = target.get("attack",8)
    if action == "defend":
        enemy_attack = int(enemy_attack*0.5)
    
    player_defense = player.get("defense",0)
    reduction = 100.0/ (100.0 + float(player_defense))
    actual_enemy_dmg = max(1,int(enemy_attack* reduction))
    player["hp"] = max(0,player["hp"]-actual_enemy_dmg)

    if player["hp"] <= 0:
        state["game_over"] = True
        state["player_died"] = True

    return state

def _apply_exploration_action(state:dict,action: str)-> dict:

    pos = state.get("position", {"x":0,"y":0})
    facing = state.get("facing",0)
    player = state["player"]
    visted = state.setdefault("visited_tiles",{})

    key = f"{pos['x']},pos[{['y']}"

    visted[key] = visted.get(key,0) + 1
    dirs = [
        {"x":0,"y":-1}, #north
        {"x":1,"y":0}, #east
        {"x":0,"y":1}, #south
        {"x":-1,"y":0}, # west
    ]

    if action == "move_forward":
        fd = dirs[facing]
        pos["x"] += fd["x"]
        pos["y"] += fd["y"]
        state["position"] = pos
        state = _check_tile_effects(state)
    elif action == "turn_right":
        state["facing"] = (facing + 1) % 4
    elif action == "turn_left":
        state["facing"] = (facing - 1 + 4) % 4

    elif action == "interact":
        current_tile = state.get("current_tile",1)

        if current_tile == 4: #chest
            player["gold"] = player.get("gold",0) +20
            state["current_tile"] = 1
        elif current_tile == 5: #heal
            max_hp = player.get("max_hp",100)
            max_mp = player.get("max_mp",50)
            player["hp"] = min(max_hp, player["hp"] + int(max_hp * 0.5))
            player["mp"] = min(max_mp, player.get("mp", 0) + int(max_mp * 0.4))
    return state
def _check_tile_effects(state:dict)-> dict:

    current_tile = state.get("current_tile",1)
    player = state["player"]

    if current_tile == 6: #trap
        dmg = 10
        player_defense = player.get("defense", 0)
        reduction = 100.0 / (100.0 + float(player_defense))
        actual = max(1, int(dmg * reduction))
        player["hp"] = max(0, player["hp"] - actual)

        if player["hp"] <= 0:
            state["game_over"] = True
            state["player_died"] = True
    elif current_tile == 3: #boss
        state["in_combat"] = True
        state["is_boss"] = True
    return state

def evaluate_terminal_state(state:dict)->float:
#reward function will have to redo
    visited = state.get("visited_tiles", {})
    
    player = state.get("player",{})
    hp_ratio = player.get("hp",0) / max(player.get("max_hp",1),1)
    gold = player.get("gold", 0)
    level = player.get("level", 1)

    if state.get("battle_won"):
        
        return 1.0+ hp_ratio
    
    elif state.get("player_died"):
        return -1.0
    elif state.get("game_over"):
        return -0.5
    
    else:
        revisit_penalty = 0.0

        for count in visited.values():
            if count > 1:
                revisit_penalty += (count -1) * 0.03

        health_score = hp_ratio *0.7

        gold_score = min(gold/300,0.3)
        if level < 5:
            level_score = (level - 1) * 0.1
        else: 
            level_score = 0.01
        visible = state.get("visible_special_tiles", []) 

        boss_score =0.0
        heal_score =0.0
        chest_score=0.0
        trap_penalty=0.0
       
        for tile_info in visible:
            tile = tile_info.get("tile")
            dist = tile_info.get("distance",3.0)

            proximity = 1.0 / max(dist,0.5)
            
            if tile == 3:
                boss_score = max(boss_score, 0.4 * proximity)
            elif tile == 5:
                if hp_ratio < 0.6:
                    heal_score =max(heal_score, 0.4 * proximity)
            elif tile == 4:
                chest_score = max(chest_score, 0.5 * proximity)
            elif tile ==6:
                trap_penalty += -0.5 *proximity


        return health_score + gold_score + level_score + boss_score + heal_score + chest_score + trap_penalty - revisit_penalty
    

class MCTSAgent:
    
    def __init__(self,num_simulations: int = 200, exploration_constant: float = 1.414):
        self.num_simulations = num_simulations
        self.exploration_constant = exploration_constant

    def choose_action(self, game_state: dict) -> str:

        root = MCTSNode(game_state)

        for _ in range(self.num_simulations):

            #selection 
            #walk through the tree using ucb1 to fdind a node to expand
            node = self._select(root)

            #expansion
            #if its unexplored create a new child node
            if not node.is_terminal() and not node.is_fully_expanded():
                node = self._expand(node)

            #simulation
            #play from this node and score it
            reward = self._simulate(node.game_state)

            #backpropagation
            #pass the reward up the tree updating each node visited
            self._backpropagate(node,reward)

            #after all sims pick the action visited the most
            #if no kids fall back to random
        if not root.children:
            actions = game_state.get("available_actions",["defend"])
            return random.choice(actions)
        best_child = max(root.children, key=lambda child: child.visit_count)
        return best_child.action_taken
        
    def _select(self, node: MCTSNode) -> MCTSNode:
        while not node.is_terminal() and node.is_fully_expanded():
            node = max(node.children,key= lambda child: child.ucb1_score(self.exploration_constant))
        return node
    def _expand(self, node: MCTSNode) -> MCTSNode:
        
        action = node.unexplored_actions.pop()

        new_state = apply_action(node.game_state,action)

        child = MCTSNode(new_state,parent=node,action_taken=action)
        node.children.append(child)

        return child
    
    def _simulate(self, game_state: dict) ->float:

        simulated_state =copy.deepcopy(game_state)

        max_steps = 50
        steps = 0


        while not simulated_state.get("game_over",False) and steps < max_steps:
            avaliable = simulated_state.get("available_actions", [])

            if not avaliable:
                break

            random_action = random.choice(avaliable)
            simulated_state = apply_action(simulated_state, random_action)
            steps +=1

        return evaluate_terminal_state(simulated_state)

    def _backpropagate(self, node: MCTSNode,reward: float)-> None:

        current = node
        while current is not None:
            current.visit_count += 1

            current.total_reward += reward

            current = current.parent 
def write_action(action: str, seed: int = 0):
    with open(ACTION_FILE, "w") as f:
        json.dump({"action": action, "ready": True, "seed": seed}, f)
    print(f"  == Wrote action: {action}")


def run():
    if os.path.exists(ACTION_FILE):
        os.remove(ACTION_FILE)
    if os.path.exists(STATE_FILE):
        os.remove(STATE_FILE)

    print(f"MCTS agent started — {NUM_SIMULATIONS} simulations per decision")
    print(f"Running {TOTAL_RUNS} games")
    print(f"Watching: {STATE_FILE}")

    # Create the MCTS agent — reused across all runs
    agent = MCTSAgent(num_simulations=NUM_SIMULATIONS)

    logger= RunLogger(agent_type="mcts", seed=FIXED_SEED)
    runs_completed = 0
    last_modified = 0
    last_phase  = None
   
    while runs_completed < TOTAL_RUNS:
        try:
            if os.path.exists(STATE_FILE):
                modified = os.path.getmtime(STATE_FILE)

                if modified != last_modified:
                    last_modified = modified

                    with open(STATE_FILE, "r") as f:
                        state = json.load(f)

                    phase = state.get("phase", "unknown")
                    actions = state.get("available_actions", [])
                    

                    # Only respond when Godot is waiting for an action
                    if not state.get("waiting_for_action", False):
                        continue

                    # Only respond if previous action has been consumed
                    if os.path.exists(ACTION_FILE):
                        continue

                    # Handle game over
                    if state.get("game_over"):
                        outcome = state.get("outcome", "unknown")
                        logger.log_run_end(outcome, state)
                        runs_completed += 1
                        print(f"Run {runs_completed}/{TOTAL_RUNS} complete — outcome: {outcome}")

                        if runs_completed < TOTAL_RUNS:
                            new_seed = 0 if TRAINING_MODE else FIXED_SEED
                            logger = RunLogger(agent_type="mcts", seed=new_seed)
                            last_phase    = None
                            last_modified = 0
                            time.sleep(2.0)
                            write_action("replay", new_seed)
                        else:
                            print("All runs complete — stopping.")
                            write_action("quit", 0)
                            break
                        continue

                    if not actions:
                        continue

                    # Phase transition logging
                    if phase == "combat" and last_phase != "combat":
                        logger.log_combat_start(state)

                    if last_phase == "combat" and phase == "exploration":
                        logger.log_combat_end("won", state)


                    time.sleep(0.1)
                    decision_start = time.time()
                    action = agent.choose_action(state)
                    decision_time = (time.time() - decision_start) * 1000
                    print(f"Phase: {phase} | MCTS chose: {action} in {decision_time:.1f}ms")
                    logger.log_decision(state, action, decision_time)
                    last_phase = phase
                    write_action(action)

        except json.JSONDecodeError:
            pass
        except Exception as e:
            print(f"Error: {e}")

        time.sleep(0.05)

    print("Experiment finished. Logs saved to AI/logs/")


if __name__ == "__main__":
    run()
