import json
import os
import time
import random
import math
import copy
from logger import RunLogger

#  File paths 
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BRIDGE_DIR = os.path.join(BASE_DIR, "..", "bridge")
STATE_FILE = os.path.join(BRIDGE_DIR, "game_state.json")
ACTION_FILE = os.path.join(BRIDGE_DIR, "agent_action.json")

#  Config 
TRAINING_MODE = True
FIXED_SEED = 123
TOTAL_RUNS = 2
NUM_SIMULATIONS = 10# how many futures MCTS simulates before picking an action



# MCTS tree node

class MCTSNode:
    def __init__(self, game_state: dict, parent=None, action_taken: str = None):
        self.game_state = game_state
        self.parent = parent
        self.action_taken = action_taken
        self.visit_count = 0 # times this node was visited during search
        self.total_reward = 0.0 # accumulated reward
        self.children = []
        self.unexplored_actions = list(game_state.get("available_actions", []))

    def is_fully_expanded(self) -> bool:
        return len(self.unexplored_actions) == 0

    def is_terminal(self) -> bool:
        return self.game_state.get("game_over", False)

    def ucb1_score(self, exploration_constant: float = 1.414) -> float:
        # UCB1 balances exploitation (paths that scored well) against
        # exploration (paths tried less often). Constant defaults to sqrt(2).
        if self.visit_count == 0:
            return float("inf")
        if self.parent is None or self.parent.visit_count == 0:
            return float("inf")

        exploitation = self.total_reward / self.visit_count
        exploration = exploration_constant * math.sqrt(
            math.log(self.parent.visit_count) / self.visit_count
        )
        return exploitation + exploration



# Game simulation logic

def apply_action(game_state: dict, action: str) -> dict:
    # Deep copy so simulations never modify the real state.
    new_state = copy.deepcopy(game_state)
    phase = new_state.get("phase", "exploration")

    if phase == "combat":
        return _apply_combat_action(new_state, action)
    else:
        return _apply_exploration_action(new_state, action)


def _apply_combat_action(state: dict, action: str) -> dict:
    player = state["player"]
    enemies = state.get("enemies", [])

    target = next((e for e in enemies if e.get("hp", 0) > 0), None)
    if target is None:
        state["game_over"] = True
        state["battle_won"] = True
        return state

    #  Player action 
    if action == "attack":
        dmg = player.get("attack", 10)
        defense = target.get("phys_defense", 0)
        crit_chance = player.get("crit_chance", 0.05)
        if random.random() < crit_chance:
            dmg = int(dmg * 2.5)
            actual_dmg = max(1, dmg)# crits ignore defense
        else:
            reduction_factor = 100.0 / (100.0 + float(defense * 0.5))
            actual_dmg = max(1, int(dmg * reduction_factor))
        target["hp"] = max(0, target["hp"] - actual_dmg)

    elif action == "magic":
        player["mp"] = max(0, player.get("mp", 0) - 10)
        dmg = int(player.get("magic_power", 5) * 1.5)
        actual_dmg = max(1, dmg)
        target["hp"] = max(0, target["hp"] - actual_dmg)

    elif action == "defend":
        pass

    #  Check for victory 
    if target["hp"] <= 0:
        all_dead = all(e.get("hp", 0) <= 0 for e in enemies)
        if all_dead:
            state["game_over"] = True
            state["battle_won"] = True
            return state

    #  Defend may stun the enemy 
    if action == "defend":
        stun_chance = player.get("stun_chance", 0.1)
        if random.random() < stun_chance:
            state["enemy_stunned"] = True

    #  Enemy retaliates 
    enemy_attack = target.get("attack", 8)
    if action == "defend":
        enemy_attack = int(enemy_attack * 0.5)
    if state.get("enemy_stunned"):
        enemy_attack = 0
        state["enemy_stunned"] = False

    player_defense = player.get("defense", 0)
    reduction = 100.0 / (100.0 + float(player_defense))
    actual_enemy_dmg = max(1, int(enemy_attack * reduction))
    player["hp"] = max(0, player["hp"] - actual_enemy_dmg)

    if player["hp"] <= 0:
        state["game_over"] = True
        state["player_died"] = True

    #  Refresh available actions (magic only if MP allows) 
    actions = ["attack", "defend"]
    if player.get("mp", 0) >= 10:
        actions.append("magic")
    state["available_actions"] = actions

    return state


def _apply_exploration_action(state: dict, action: str) -> dict:
    pos = state.get("position", {"x": 0, "y": 0})
    facing = state.get("facing", 0)
    player = state["player"]
    visited = state.setdefault("visited_tiles", {})
    recent_actions = state.setdefault("recent_actions", [])

    # north, east, south, west
    dirs = [
        {"x": 0, "y": -1},
        {"x": 1, "y": 0},
        {"x": 0, "y": 1},
        {"x": -1, "y": 0},
    ]

    if action == "move_forward":
        fd = dirs[facing]
        pos["x"] += fd["x"]
        pos["y"] += fd["y"]
        state["position"] = pos

        key = f"{pos['x']},{pos['y']}"
        visited[key] = visited.get(key, 0) + 1

        recent = state.setdefault("recent_positions", [])
        recent.append(key)
        if len(recent) > 6:
            recent.pop(0)

        # Update current tile to the one we just stepped onto.
        facing_to_tile = {
            0: state.get("tile_north", 1),
            1: state.get("tile_east", 1),
            2: state.get("tile_south", 1),
            3: state.get("tile_west", 1),
        }
        state["current_tile"] = facing_to_tile.get(facing, 1)
        state = _check_tile_effects(state)

    elif action == "turn_right":
        state["facing"] = (facing + 1) % 4

    elif action == "turn_left":
        state["facing"] = (facing - 1 + 4) % 4

    elif action == "interact":
        current_tile = state.get("current_tile", 1)

        if current_tile == 4 or current_tile == 7: # chest / secret door
            player["gold"] = player.get("gold", 0) + 20
            state["current_tile"] = 1
            state["chest_collected"] = True

        elif current_tile == 3: # boss
            pos = state.get("position", {})
            print(f"BOSS ENCOUNTERED at ({pos.get('x')}, {pos.get('y')})")
            state["in_combat"] = True
            state["is_boss"] = True
            state["boss_encountered"] = True

        elif current_tile == 5: # heal
            max_hp = player.get("max_hp", 100)
            max_mp = player.get("max_mp", 50)
            player["hp"] = min(max_hp, player["hp"] + int(max_hp * 0.5))
            player["mp"] = min(max_mp, player.get("mp", 0) + int(max_mp * 0.4))

    recent_actions.append(action)
    if len(recent_actions) > 6:
        recent_actions.pop(0)

    return state


def _check_tile_effects(state: dict) -> dict:
    current_tile = state.get("current_tile", 1)
    player = state["player"]

    if current_tile == 6: # trap
        dmg = 10
        player_defense = player.get("defense", 0)
        reduction = 100.0 / (100.0 + float(player_defense))
        actual = max(1, int(dmg * reduction))
        player["hp"] = max(0, player["hp"] - actual)

        if player["hp"] <= 0:
            state["game_over"] = True
            state["player_died"] = True

    elif current_tile == 3: # boss
        pos = state.get("position", {})
        print(f"BOSS ENCOUNTERED at ({pos.get('x')}, {pos.get('y')})")
        state["in_combat"] = True
        state["is_boss"] = True
        state["boss_encountered"] = True

    return state



# Reward function

def evaluate_terminal_state(state: dict) -> float:
    visited = state.get("visited_tiles", {})
    recent_positions = state.get("recent_positions", [])
    recent_actions = state.get("recent_actions", [])

    #  One-off bonuses 
    interaction_bonus = 0.0
    boss_discovery_bonus = 0.0
    if state.get("boss_encountered"):
        boss_discovery_bonus = 100000.0
    if state.get("chest_collected"):
        interaction_bonus += 15

    #  Spin penalty: too many turns in a row 
    spin_penalty = 0.0
    if len(recent_actions) >= 4:
        turn_count = sum(1 for a in recent_actions if a in ["turn_left", "turn_right"])
        if turn_count >= 3:
            spin_penalty = -40.0

    #  Loop penalty: stuck cycling a few tiles 
    loop_penalty = 0.0
    if len(recent_positions) >= 4:
        unique_recent = len(set(recent_positions))
        if unique_recent <= 2:
            loop_penalty = -40.0
        elif unique_recent <= 3:
            loop_penalty = -25.0

    # Player snapshot 
    player = state.get("player", {})
    hp_ratio = player.get("hp", 0) / max(player.get("max_hp", 1), 1)
    gold = player.get("gold", 0)
    level = player.get("level", 1)

    # Terminal outcomes 
    if state.get("battle_won"):
        boss_bonus = 5000.0 if state.get("is_boss") else 3.0
        return boss_bonus + (hp_ratio * 1.5)
    elif state.get("player_died"):
        return -10000.0
    elif state.get("game_over"):
        return -0.5

    #  Non-terminal scoring 
    health_score = hp_ratio * 1.5

    enemies = state.get("enemies", [])
    living_enemies = [e for e in enemies if e.get("hp", 0) > 0]
    enemy_hp_total = sum(e.get("hp", 0) for e in enemies)
    enemy_max_total = sum(e.get("max_hp", 1) for e in enemies)
    enemy_damage_score = 0.0
    if enemy_max_total > 0:
        enemy_damage_score = (1.0 - (enemy_hp_total / enemy_max_total)) * 1.5

    danger_penalty = 0.0
    if living_enemies and hp_ratio < 0.4:
        danger_penalty = -0.5 * (0.4 - hp_ratio)

    gold_score = min(gold / 300, 0.3)
    level_score = (level - 1) * 0.1

    #  Visible special tiles 
    boss_score = 0.0
    heal_score = 0.0
    chest_score = 0.0
    trap_penalty = 0.0
    boss_proximity_bonus = 0.0

    for tile_info in state.get("visible_special_tiles", []):
        tile = tile_info.get("tile")
        dist = tile_info.get("distance", 3.0)
        proximity = 1.0 / max(dist, 0.5)

        if tile == 3:                                  # boss
           
            boss_proximity_bonus = 2000.0 / (dist + 0.1)
            continue
        elif tile == 5:                                # heal
            if hp_ratio < 0.75:
                heal_score = max(heal_score, 0.6 * proximity)
        elif tile == 6:                                # trap
            trap_penalty += -100.5 * proximity

    # #  Boss direction memory (currently unused in returns) 
    # boss_direction_bonus = 0.0
    # last_boss_dir = state.get("last_known_boss_direction")
    # if last_boss_dir:
    #     facing = state.get("facing", 0)
    #     dx, dy = last_boss_dir.get("dx", 0), last_boss_dir.get("dy", 0)
    #     if abs(dx) > abs(dy):
    #         target_dir = 1 if dx > 0 else 3
    #     else:
    #         target_dir = 0 if dy < 0 else 2

    #     diff = (target_dir - facing) % 4
    #     if diff == 0:
    #         boss_direction_bonus = 20.0
    #     elif diff == 1 or diff == 3:
    #         boss_direction_bonus = 10.0
    #     else:
    #         boss_direction_bonus = 5.0

    #  Exploration shaping 
    revisit_penalty = sum(
        (count - 1) * 50.0 for count in visited.values() if count > 1
    )
    unique_tiles = len(visited)
    exploration_bonus = unique_tiles * 100.0

    current_pos = state.get("position", {"x": 0, "y": 0})
    current_tile_key = f"{current_pos['x']},{current_pos['y']}"

    visit_density = visited.get(current_tile_key, 0)
    density_penalty = -2.0 * max(0, visit_density - 1)

    new_tile_bonus = 0.0
    if visited.get(current_tile_key, 0) == 1:# first visit this rollout
        new_tile_bonus = 200.0
    known_trap_penalty = 0.0
    if current_tile_key in state.get("known_traps", set()):
        known_trap_penalty = -40.0
    seen_map = state.get("seen_map", {})
    frontier_bonus = 500.0 if current_tile_key not in seen_map else 0.0

    #  Final score by phase 
    phase = state.get("phase", "exploration")

    if phase == "combat":
        return (
            health_score
            + gold_score
            + danger_penalty
            + level_score
            + boss_score
            + heal_score
            + chest_score
            + trap_penalty
            + enemy_damage_score
            - revisit_penalty
            + loop_penalty
            + exploration_bonus
            + spin_penalty
            + boss_discovery_bonus
            + density_penalty
        )

    else:  # exploration
        return (
            frontier_bonus
            + heal_score
            + chest_score
            + trap_penalty
            + boss_discovery_bonus
            + known_trap_penalty          
            - revisit_penalty
            + loop_penalty
            + exploration_bonus
            + spin_penalty
            + health_score
            + density_penalty
            + interaction_bonus
            + boss_proximity_bonus
            + new_tile_bonus
        )



# MCTS agent

class MCTSAgent:
    def __init__(self, num_simulations: int = 200, exploration_constant: float = 1.414):
        self.num_simulations = num_simulations
        self.exploration_constant = exploration_constant

    def choose_action(self, game_state: dict) -> str:
        root = MCTSNode(game_state)

        for _ in range(self.num_simulations):
            node = self._select(root)                       # 1. selection
            if not node.is_terminal() and not node.is_fully_expanded():
                node = self._expand(node)                   # 2. expansion
            reward = self._simulate(node.game_state)        # 3. simulation
            self._backpropagate(node, reward)               # 4. backprop

        if not root.children:
            actions = game_state.get("available_actions", ["defend"])
            return random.choice(actions)

        # Adjust visit counts to discourage flip-flopping and reward momentum.
        recent_actions = game_state.get("recent_actions", [])
        action_scores = []
        for child in root.children:
            score = child.visit_count
            if recent_actions:
                last = recent_actions[-1]
                if last == "turn_left" and child.action_taken == "turn_right":
                    score *= 0.35
                elif last == "turn_right" and child.action_taken == "turn_left":
                    score *= 0.35
                elif last == "move_forward" and child.action_taken == "move_forward":
                    score *= 1.75
            action_scores.append((score, child))

        best_child = max(action_scores, key=lambda x: x[0])[1]
        return best_child.action_taken

    def _select(self, node: MCTSNode) -> MCTSNode:
        while not node.is_terminal() and node.is_fully_expanded():
            node = max(
                node.children,
                key=lambda child: child.ucb1_score(self.exploration_constant),
            )
        return node

    def _expand(self, node: MCTSNode) -> MCTSNode:
        action = random.choice(node.unexplored_actions)
        node.unexplored_actions.remove(action)

        new_state = apply_action(node.game_state, action)
        child = MCTSNode(new_state, parent=node, action_taken=action)
        node.children.append(child)
        return child

    def _simulate(self, game_state: dict) -> float:
        simulated_state = copy.deepcopy(game_state)
        simulated_state.pop("seen_map", None)

        # Safety ceiling only — the frontier-break below is the real limiter.
     
       
        known_tiles = len(self.seen_map) if hasattr(self, "seen_map") else 0
        max_steps = known_tiles + 30
        steps = 0

        while not simulated_state.get("game_over", False) and steps < max_steps:
            available = simulated_state.get("available_actions", [])
            if not available:
                break

            if simulated_state.get("phase") == "combat":
                random_action = self._rollout_combat_action(simulated_state, available)
            else:
                random_action = self._rollout_exploration_action(simulated_state)

            simulated_state = apply_action(simulated_state, random_action)

            # Frontier-break: roam freely across anything already in seen_map,
            # but stop the moment a step lands on a tile we've never observed.
         
            if simulated_state.get("phase") == "exploration" and hasattr(self, "seen_map"):
                new_pos = simulated_state.get("position", {})
                new_key = f"{new_pos.get('x', 0)},{new_pos.get('y', 0)}"
                if new_key not in self.seen_map:
                    break

            # Refresh neighbour tiles from the known map for the next step.
            if hasattr(self, "seen_map"):
                self._apply_seen_map(simulated_state)

            steps += 1

        return evaluate_terminal_state(simulated_state)

    #  rollout policies 
    def _rollout_combat_action(self, state: dict, available: list) -> str:
        player = state["player"]
        enemies = state.get("enemies", [])
        target = next((e for e in enemies if e.get("hp", 0) > 0), None)
        hp_ratio = player.get("hp", 1) / max(player.get("max_hp", 1), 1)

        can_kill_with_attack = False
        can_kill_with_magic = False
        if target:
            enemy_hp = target.get("hp", 0)
            atk_dmg = player.get("attack", 10)
            mag_dmg = int(player.get("magic_power", 5) * 1.5)
            defense = target.get("phys_defense", 0)
            reduction = 100.0 / (100.0 + float(defense * 0.5))
            actual_atk = max(1, int(atk_dmg * reduction))

            can_kill_with_attack = actual_atk >= enemy_hp
            can_kill_with_magic = mag_dmg >= enemy_hp and player.get("mp", 0) >= 10

        if can_kill_with_attack:
            return "attack"
        elif can_kill_with_magic:
            return "magic"
        elif hp_ratio < 0.5 and "defend" in available:
            return "defend"
        elif player.get("mp", 0) >= 10 and "magic" in available:
            return "magic"
        else:
            return "attack"

    def _rollout_exploration_action(self, state: dict) -> str:
        # Refresh neighbour tiles and rebuild available actions from the map.
        self._apply_seen_map(state)
        available = state.get("available_actions", [])

        last_actions = state.get("recent_actions", [])

        # Count how many forward moves we've made in a row (for momentum).
        consecutive_forward = 0
        for a in reversed(last_actions):
            if a == "move_forward":
                consecutive_forward += 1
            else:
                break

        forward_bias = []
        if "move_forward" in available:
            momentum = min(consecutive_forward + 1, 4)
            forward_bias += ["move_forward"] * (20 * momentum)

        # Only allow a turn if we didn't just turn (avoids spinning).
        turn_streak = 0
        for a in reversed(last_actions):
            if a in ["turn_left", "turn_right"]:
                turn_streak += 1
            else:
                break
        if turn_streak < 1:
            if "turn_left" in available:
                forward_bias += ["turn_left"]
            if "turn_right" in available:
                forward_bias += ["turn_right"]

        if "interact" in available:
            forward_bias += ["interact"] * 3

        if not forward_bias:
            forward_bias = available

        return random.choice(forward_bias)

    def _apply_seen_map(self, state: dict) -> None:
        # Fill the four neighbour tiles from the known map (unknown -> walkable),
        # then rebuild available actions based on what's ahead.
        pos = state.get("position")
        if pos is None:
            return
        px, py = pos.get("x", 0), pos.get("y", 0)

        dirs = [(0, -1), (1, 0), (0, 1), (-1, 0)]
        dir_names = ["tile_north", "tile_east", "tile_south", "tile_west"]
        for i, (dx, dy) in enumerate(dirs):
            nkey = f"{px + dx},{py + dy}"
            if hasattr(self, "seen_map") and nkey in self.seen_map:
                state[dir_names[i]] = self.seen_map[nkey]
            else:
                state[dir_names[i]] = 1   # unknown assumed walkable

        facing = state.get("facing", 0)
        tile_ahead = state.get(dir_names[facing], 1)

        avail = ["turn_left", "turn_right"]
        if tile_ahead != 0:
            avail.append("move_forward")
        if state.get("current_tile", 1) in (4, 5, 7):
            avail.append("interact")
        state["available_actions"] = avail

    def _backpropagate(self, node: MCTSNode, reward: float) -> None:
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

    agent = MCTSAgent(num_simulations=NUM_SIMULATIONS)

    logger = RunLogger(agent_type="mcts", seed=FIXED_SEED)
    runs_completed = 0
    last_modified = 0
    last_phase = None
    real_visited = {}
    real_recent_positions = []
    real_recent_actions = []
    last_known_boss_pos = None
    known_traps = set()
    while runs_completed < TOTAL_RUNS:
        try:
            if not os.path.exists(STATE_FILE):
                time.sleep(0.05)
                continue

            modified = os.path.getmtime(STATE_FILE)
            if modified == last_modified:
                time.sleep(0.05)
                continue
            last_modified = modified

            with open(STATE_FILE, "r") as f:
                state = json.load(f)

            if "seen_map" in state:
                agent.seen_map = state["seen_map"]
            if "seed" in state and not state.get("game_over"):
                logger.seed = state["seed"]

            phase = state.get("phase", "unknown")
            actions = state.get("available_actions", [])

            # Remember the boss direction if it's currently visible.
            pos = state.get("position", {})
            px, py = pos.get("x", 0), pos.get("y", 0)
            for tile_info in state.get("visible_special_tiles", []):
                if tile_info.get("tile") == 3:
                    last_known_boss_pos = {
                        "dx": tile_info.get("dx", 0),
                        "dy": tile_info.get("dy", 0),
                    }
                elif tile_info.get("tile") == 6:           # trap — remember it forever
                    tx = px + tile_info.get("dx", 0)
                    ty = py + tile_info.get("dy", 0)
                    known_traps.add(f"{tx},{ty}")
            if last_known_boss_pos:
                state["last_known_boss_direction"] = last_known_boss_pos

            # Only respond when Godot is waiting and the last action is consumed.
            if not state.get("waiting_for_action", False):
                continue
            if os.path.exists(ACTION_FILE):
                continue

            #  Game over: log and either replay or quit 
            if state.get("game_over"):
                outcome = state.get("outcome", "unknown")
                
                logger.seed = state.get("seed", logger.seed)
                logger.log_run_end(outcome, state)
                runs_completed += 1
                print(f"Run {runs_completed}/{TOTAL_RUNS} complete — outcome: {outcome}")

                if runs_completed < TOTAL_RUNS:
                    request_seed = 0 if TRAINING_MODE else FIXED_SEED
                    logger = RunLogger(agent_type="mcts", seed=request_seed)
                    last_phase = None
                    last_modified = 0
                    real_visited = {}
                    real_recent_positions = []
                    real_recent_actions = []
                    last_known_boss_pos = None
                    known_traps = set()
                    agent.seen_map = {}
                    time.sleep(2.0)
                    write_action("replay", request_seed)
                else:
                    print("All runs complete — stopping.")
                    write_action("quit", 0)
                    break
                continue

            if not actions:
                continue

            #  Phase transition logging 
            if phase == "combat" and last_phase != "combat":
                logger.log_combat_start(state)
            if last_phase == "combat" and phase == "exploration":
                logger.log_combat_end("won", state)

            time.sleep(0.1)
            decision_start = time.time()

            # Inject the agent's real memory before it decides.
            if phase == "exploration":
                pos = state.get("position", {})
                key = f"{pos.get('x', 0)},{pos.get('y', 0)}"
                real_visited[key] = real_visited.get(key, 0) + 1
                real_recent_positions.append(key)
                if len(real_recent_positions) > 10:
                    real_recent_positions.pop(0)
                state["visited_tiles"] = real_visited
                state["recent_positions"] = real_recent_positions
                state["recent_actions"] = real_recent_actions
                state["known_traps"] = known_traps
            action = agent.choose_action(state)

            if phase == "exploration":
                real_recent_actions.append(action)
                if len(real_recent_actions) > 5:
                    real_recent_actions.pop(0)

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