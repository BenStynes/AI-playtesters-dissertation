import json
import os
import time
import random

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BRIDGE_DIR = os.path.join(BASE_DIR, "..", "bridge")
STATE_FILE = os.path.join(BRIDGE_DIR, "game_state.json")
ACTION_FILE = os.path.join(BRIDGE_DIR, "agent_action.json")

def write_action(action: str):
    with open(ACTION_FILE, "w") as f:
        json.dump({"action": action, "ready": True}, f)
        
        print(f"==== wrote action: {action}")

def run():
    print("random agent started waiting for game")
    print(f"watching:{STATE_FILE}")

    last_modifed = 0

    while True:
        try:
            if os.path.exists(STATE_FILE):
                modifided = os.path.getmtime(STATE_FILE)

                if modifided != last_modifed:
                    last_modifed = modifided

                    with open(STATE_FILE, "r") as f:
                        state = json.load(f)

                    phase = state.get("phase","unknown")
                    actions = state.get("available_actions",[])

                    if not actions:
                        print("no actions avaliable - skipping")
                        continue

                    action =random.choice(actions)
                    print(f"Phase:{phase} |  Actions:{actions}| Chose: {action}")
                    write_action(action)

        except json.JSONDecodeError:
            #file was mid write when read wait for next update
            pass
        except Exception as e:
            print(f"error: {e}")

        time.sleep(0.05)
if __name__ == "__main__":
    run()
