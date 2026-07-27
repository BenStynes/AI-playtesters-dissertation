import torch
import torch.optim as optim
import json
import os
import time

import encoders
from policy_network import PolicyNetwork
from action_selection import select_action


#configs
GAMMA = 0.99 # discount factor 
LEARNING_RATE = 0.001 # how big each step the optimizer takes each update
#action sets
COMBAT_ACTIONS = ["attack", "defend", "magic"]
EXPLORATION_ACTIONS = ["move_forward", "turn_left", "turn_right", "interact"]
#two networks for combat and exploration
combat_net = PolicyNetwork(input_size=encoders.vector_length("combat"), num_actions=len(COMBAT_ACTIONS))
exploration_net = PolicyNetwork(input_size=encoders.vector_length("exploration"), num_actions=len(EXPLORATION_ACTIONS))

#one optimizer for each network
combat_optimizer = optim.Adam(combat_net.parameters(), lr=LEARNING_RATE)
exploration_optimizer = optim.Adam(exploration_net.parameters(), lr=LEARNING_RATE)

def new_episode_memory():
    return {
            "combat_log_probs": [],
            "combat_rewards": [],
            "exploration_log_probs": [],
            "exploration_rewards": []

    }

def compute_reward(prev_state,new_state,phase):
    """reward for the tranistion from prev_state to new_state in the given phase (combat or exploration)
       keeping it simple so the network can discover good play"""
    reward = 0.0
    if new_state.get("game_over"):
        outcome = new_state.get("outcome", "")
        if outcome == "won":
            return 100.0
        elif outcome == "died_at_boss":
            return 40.0 #partial credit for making it to the boss
        elif outcome == "died":
            return -50.0
        elif outcome == "timeout":
            return -70.0
        return 0.0
    prev_hp = prev_state.get("player",{}).get("hp", 0)
    new_hp = new_state.get("player",{}).get("hp", 0)
    

    reward += (new_hp - prev_hp) * 0.5 # reward for taking less damage or healing
    reward -= 0.05

    if phase == "exploration":
        prev_seen = prev_state.get("visited_count", 0)
        new_seen = new_state.get("visited_count", 0)
        if new_seen > prev_seen:
            reward += 0.5 # reward for discovering new areas

    return reward

def learn_from_episode(memory):#
    """reinforce update, run once at the end of each episode"""
    _update_one(combat_net,combat_optimizer,memory["combat_log_probs"],memory["combat_rewards"])
    _update_one(exploration_net,exploration_optimizer,memory["exploration_log_probs"],memory["exploration_rewards"])

def _update_one(network,optimizer,log_probs,rewards):
    if len(log_probs) == 0:
        return
    #compute the return G(t) for every step, walking backwards
    returns = []
    G = 0.0
    for r in reversed(rewards):
        G = r + GAMMA * G
        returns.insert(0,G)
    #convert to a tensor and standardise
    returns = torch.tensor(returns, dtype=torch.float32)
    if len(returns) > 1:
        returns = (returns - returns.mean()) / (returns.std() + 1e-8)
    #build the loss, -log prob * G(t), summed over all steps
    loss = 0.0
    for log_prob,G in zip(log_probs,returns):

        loss = loss +(-log_prob * G)
    #apply the update
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BRIDGE_DIR = os.path.join(BASE_DIR, "..", "bridge")
STATE_FILE = os.path.join(BRIDGE_DIR, "game_state.json")
ACTION_FILE = os.path.join(BRIDGE_DIR, "agent_action.json")

#  Training config 
TRAINING_MODE = True
TOTAL_EPISODES = 5000         # how many games to train across

def write_action(action: str, seed: int = 0):
    with open(ACTION_FILE, "w") as f:
        json.dump({"action": action, "ready": True, "seed": seed}, f)


def train():
    if os.path.exists(ACTION_FILE):
        os.remove(ACTION_FILE)
    if os.path.exists(STATE_FILE):
        os.remove(STATE_FILE)

    print(f"DRL training started — {TOTAL_EPISODES} episodes")

    episodes_done = 0
    last_modified = 0

    memory = new_episode_memory()
    prev_state = None
    prev_phase = None
    reward_history = []
    outcome_history = []
    LOG_EVERY = 50   # will set to 50 for the real run; 1 for this small smoke test
    
    decision_log = []
    log_this_episode = (episodes_done % LOG_EVERY == 0)
    while episodes_done < TOTAL_EPISODES:
        try:
            if not os.path.exists(STATE_FILE):
                time.sleep(0.005)
                continue
            modified = os.path.getmtime(STATE_FILE)
            if modified == last_modified:
                time.sleep(0.005)
                continue
            last_modified = modified

            with open(STATE_FILE, "r") as f:
                state = json.load(f)
            
            if not state.get("waiting_for_action", False):
                continue
            if os.path.exists(ACTION_FILE):
                continue

            if state.get("game_over"):
                outcome = state.get("outcome","unknown")
                if prev_state is not None and prev_phase is not None:
                    r = compute_reward(prev_state,state,prev_phase)
                    if prev_phase == "combat":
                        memory["combat_rewards"].append(r)
                    else:
                        memory["exploration_rewards"].append(r)
                learn_from_episode(memory)
                episode_reward = sum(memory["combat_rewards"]) + sum(memory["exploration_rewards"])
                reward_history.append(episode_reward)
                outcome_history.append(outcome)

                # write the rich detail for this episode if it was a logged one
                if log_this_episode:
                    path = os.path.join(BASE_DIR, "logs", f"train_ep{episodes_done}_{outcome}.json")
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    with open(path, "w") as f:
                        json.dump({
                            "episode": episodes_done,
                            "outcome": outcome,
                            "total_reward": episode_reward,
                            "decisions": decision_log,
                        }, f, indent=2)

                # progress print every 10 episodes
                if episodes_done % 10 == 0:
                    recent = reward_history[-50:]
                    avg = sum(recent) / len(recent)
                    wins = outcome_history[-50:].count("won")
                    print(f"  [progress] ep {episodes_done} | avg reward: {avg:.1f} | wins: {wins}/{len(recent)}")
                episodes_done += 1
                if episodes_done % 50 == 0:
                    save_models(f"_ep{episodes_done}")
                print(f"Episode {episodes_done}/{TOTAL_EPISODES} — {outcome}")

                #reset
                memory = new_episode_memory()
                prev_state = None
                prev_phase = None
                last_modified = 0
                decision_log = []
                log_this_episode = (episodes_done % LOG_EVERY == 0)


                if episodes_done < TOTAL_EPISODES:
                    request_seed = 0 if TRAINING_MODE else 123
                    time.sleep(0.1)
                    write_action("replay", request_seed)
                else:
                    write_action("quit", 0)
                    break
                continue

            prev_state, prev_phase = handle_turn(state, memory, prev_state, prev_phase, log_this_episode, decision_log)
          

            
        except (json.JSONDecodeError,PermissionError,FileNotFoundError):
            pass
        except Exception as e:
            print(f"Error: {e}")

        time.sleep(0.005)
    with open(os.path.join(BASE_DIR, "training_history.json"), "w") as f:
        json.dump({"reward": reward_history, "outcome": outcome_history}, f)
    print("Saved training history.")
    save_models("_final")
    print("Training complete.")



def handle_turn(state,memory, prev_state,prev_phase,log_detail,decision_log):
    """one decsion step, pick an action record its log prob, and record the rewoerd for the prev step"""
    phase = state.get("phase", "exploration")
    # encode the state  and pick the right network and action set
    if phase == "combat":
        state_vector = encoders.encode_combat_state(state)
        net = combat_net
        all_actions = COMBAT_ACTIONS
    else: 
        state_vector = encoders.encode_exploration_state(state)
        net = exploration_net
        all_actions = EXPLORATION_ACTIONS
    # record the previous steps rewards
    if prev_state is not None and prev_phase is not None:
        r = compute_reward(prev_state,state,prev_phase)
        if prev_phase == "combat":
            memory["combat_rewards"].append(r)
        else:
            memory["exploration_rewards"].append(r)
    #select an action
    avalible = state.get("available_actions", [])
    action,log_prob, probs = select_action(net,state_vector,avalible,all_actions,temperature=1.0)

    if log_detail:
        chosen_prob = probs[all_actions.index(action)].item()
        decision_log.append({
            "phase": phase,
            "action": action,
            "chosen_prob": round(chosen_prob, 4),
            "confidence": round(probs.max().item(), 4),
            "all_probs": {a: round(p, 4) for a, p in zip(all_actions, probs.tolist())},
            "player_hp": state.get("player", {}).get("hp"),
        })

    #record this steps log prob(reward arrives next turn)
    if phase == "combat":
        memory["combat_log_probs"].append(log_prob)
    else:
        memory["exploration_log_probs"].append(log_prob)
    #send action and hand back this state as the previous
    write_action(action)
    return state, phase
def save_models(tag=""):
    os.makedirs(os.path.join(BASE_DIR, "models"), exist_ok=True)
    torch.save(combat_net.state_dict(), os.path.join(BASE_DIR, "models", f"combat_net{tag}.pt"))
    torch.save(exploration_net.state_dict(), os.path.join(BASE_DIR, "models", f"exploration_net{tag}.pt"))
    print(f"  saved models{tag}")

if __name__ == "__main__":
    train()

