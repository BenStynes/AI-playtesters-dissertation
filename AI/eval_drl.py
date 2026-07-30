import torch
import torch.optim as optim
import json
import os
import time
import random
from logger import RunLogger
import encoders
from policy_network import PolicyNetwork
from action_selection import select_action

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BRIDGE_DIR = os.path.join(BASE_DIR, "..", "bridge")
STATE_FILE = os.path.join(BRIDGE_DIR, "game_state.json")
ACTION_FILE = os.path.join(BRIDGE_DIR, "agent_action.json")

COMBAT_ACTIONS = ["attack", "defend", "magic"]
EXPLORATION_ACTIONS = ["move_forward", "turn_left", "turn_right", "interact"]
#two networks for combat and exploration
combat_net = PolicyNetwork(input_size=encoders.vector_length("combat"), num_actions=len(COMBAT_ACTIONS))
exploration_net = PolicyNetwork(input_size=encoders.vector_length("exploration"), num_actions=len(EXPLORATION_ACTIONS))

TEMPERATURE  = 1.0

combat_net.load_state_dict(torch.load(os.path.join(BASE_DIR, "models", "combat_net_ep300.pt")))
exploration_net.load_state_dict(torch.load(os.path.join(BASE_DIR, "models", "exploration_net_ep300.pt")))
combat_net.eval()
exploration_net.eval()

def choose_action(state):
    phase = state.get("phase", "exploration")
    if phase == "combat":
        state_vector = encoders.encode_combat_state(state)
        net = combat_net
        all_actions = COMBAT_ACTIONS
    else:
        state_vector = encoders.encode_exploration_state(state)
        net = exploration_net
        all_actions = EXPLORATION_ACTIONS

    availabe = state.get("available_actions", [])
    with torch.no_grad():
        action,_log_prob,_probs = select_action(net,state_vector, availabe,all_actions, temperature=TEMPERATURE)
    return action

TRAINING_MODE = False
FIXED_SEED = 42
SEEDS = list(range(1,31)) 
total_runs = len(SEEDS)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BRIDGE_DIR = os.path.join(BASE_DIR, "..", "bridge")
STATE_FILE = os.path.join(BRIDGE_DIR, "game_state.json")
ACTION_FILE = os.path.join(BRIDGE_DIR, "agent_action.json")

TOTAL_RUNS = len(SEEDS)

def write_action(action: str, seed: int = 0):
    with open(ACTION_FILE, "w") as f:
        json.dump({"action": action, "ready": True, "seed": seed}, f)
        
        print(f"==== wrote action: {action}")

def run():
    #reset code
    if os.path.exists(ACTION_FILE):
        os.remove(ACTION_FILE)
    if os.path.exists(STATE_FILE):
        os.remove(STATE_FILE)
    runs_completed =0 
    last_modified = 0
    print("random agent started waiting for game")
    print(f"watching:{STATE_FILE}")
    logger = RunLogger(agent_type="drl", seed=SEEDS[runs_completed])




    last_phase = None

    while runs_completed < TOTAL_RUNS:
        try:
            if os.path.exists(STATE_FILE):

                modified  = os.path.getmtime(STATE_FILE)

                if modified  != last_modified:
                    last_modified = modified 

                    with open(STATE_FILE, "r") as f:
                        state = json.load(f)
                    print(f"State read — waiting: {state.get('waiting_for_action')} | phase: {state.get('phase')}")
                    phase = state.get("phase","unknown")
                    actions = state.get("available_actions",[])
                    if not state.get("waiting_for_action",False):
                        continue
                    if os.path.exists(ACTION_FILE):
                        continue

                    if state.get("game_over"):
                        outcome = state.get("outcome","unknown")    

                        logger.log_run_end(outcome,state)
                        runs_completed += 1
                        print(f"run{runs_completed}/{TOTAL_RUNS} completed | outcome: {outcome}")

                        if runs_completed < TOTAL_RUNS:
                            next_seed = SEEDS[runs_completed]
                            logger = RunLogger(agent_type="drl", seed=next_seed)
                            last_phase = None
                            last_modified = 0
                            time.sleep(0.5)
                            write_action("replay", next_seed)
                        else:
                            print("all runs complete stopping")
                            write_action("quit")
                            break
                        continue

                    if not actions:
                        continue
                    
                    if phase =="combat" and last_phase != "combat":
                        logger.log_combat_start(state)

                    if last_phase == "combat" and phase == "exploration":
                        logger.log_combat_end("won",state)
                    


                    time.sleep(0.1)
                    decision_start = time.time()
                    action = choose_action(state)
                   

                    

                   
                  
                    print(f"Phase:{phase} |  Actions:{actions}| Chose: {action}")
                    decision_time  =(time.time() -decision_start) *1000

                    logger.log_decision(state,action,decision_time)

                    last_phase =phase

                    write_action(action)

        except json.JSONDecodeError:
            #file was mid write when read wait for next update
            pass
        except Exception as e:
            print(f"error: {e}")

        time.sleep(0.05)
if __name__ == "__main__":
    run()


