import json
import os
import time
import random
from logger import RunLogger

TRAINING_MODE = False
FIXED_SEED = 42
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BRIDGE_DIR = os.path.join(BASE_DIR, "..", "bridge")
STATE_FILE = os.path.join(BRIDGE_DIR, "game_state.json")
ACTION_FILE = os.path.join(BRIDGE_DIR, "agent_action.json")

TOTAL_RUNS = 2

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
   
    print("random agent started waiting for game")
    print(f"watching:{STATE_FILE}")
    logger = RunLogger(agent_type="random",seed=0)

    runs_completed =0 
    last_modified = 0


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
                            new_seed = 0 if TRAINING_MODE else FIXED_SEED
                            logger = RunLogger(agent_type="random",seed=0)
                            last_phase = None

                            last_modified = 0
                            time.sleep(2.0)
                            write_action("replay")
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
                    action =random.choice(actions)
                    decision_start = time.time()

                    

                   
                  
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
