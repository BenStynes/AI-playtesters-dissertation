import json, os, time
import ollama
from logger import RunLogger
from personas import PERSONAS
from llm_prompt import build_prompt

MODEL = "llama3.2:3b"
PERSONA = "cautious"     
SEEDS = list(range(1, 3))      
TOTAL_RUNS = len(SEEDS)

persona_prompt = PERSONAS[PERSONA]["prompt"]


BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BRIDGE_DIR = os.path.join(BASE_DIR, "..", "bridge")
STATE_FILE = os.path.join(BRIDGE_DIR, "game_state.json")
ACTION_FILE = os.path.join(BRIDGE_DIR, "agent_action.json")
turn_number = 0
parse_failures = 0
walked = set()
recent_actions = []
prompt_samples = []
def write_action(action: str, seed: int = 0):
    with open(ACTION_FILE, "w") as f:
        json.dump({"action": action, "ready": True, "seed": seed}, f)


def choose_action(state):
    
    global parse_failures, turn_number
    prompt = build_prompt(state, persona_prompt, walked, recent_actions, turn_number)
    
    if not recent_actions:          # first decision of the run
        print("\n--- PROMPT ---\n" + prompt + "\n--------------\n")
    if len(prompt_samples) < 6:
        prompt_samples.append({"phase": state.get("phase"), "prompt": prompt})
    
    try:
        response = ollama.chat(
            model=MODEL,
            messages=[{"role": "user", "content": prompt}],
            options={"num_predict": 10},
        )
        reply = response["message"]["content"].strip().lower()
    except Exception as e:
        print(f"  model error: {e}")
        reply = ""

    available = state.get("available_actions", [])
    for action in available:
        if action in reply:
            return action

    parse_failures += 1
    return available[0] if available else "defend"


def run():
    global  parse_failures, walked, recent_actions, turn_number
    if os.path.exists(ACTION_FILE):
        os.remove(ACTION_FILE)
    if os.path.exists(STATE_FILE):
        os.remove(STATE_FILE)

    print(f"LLM agent ({PERSONA}) started:  {TOTAL_RUNS} runs")

    runs_completed = 0
    last_modified = 0
    last_phase = None
    logger = RunLogger(agent_type="llm", seed=SEEDS[runs_completed],
                       personality=PERSONA)

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

            if not state.get("waiting_for_action", False):
                continue
            if os.path.exists(ACTION_FILE):
                continue

            if state.get("game_over"):
                outcome = state.get("outcome", "unknown")
                
                logger.prompt_samples = list(prompt_samples)
                logger.log_run_end(outcome, state)
                runs_completed += 1
                print(f"run {runs_completed}/{TOTAL_RUNS} — {outcome} "
                      f"| parse failures: {parse_failures}")

                if runs_completed < TOTAL_RUNS:
                    next_seed = SEEDS[runs_completed]
                    logger = RunLogger(agent_type="llm", seed=next_seed,
                                       personality=PERSONA)
                    parse_failures = 0
                    turn_number = 0
                    walked.clear()
                    recent_actions.clear()
                    prompt_samples.clear()
                    last_phase = None
                    last_modified = 0
                    time.sleep(0.5)
                    write_action("replay", next_seed)
                else:
                    write_action("quit")
                    break
                continue

            phase = state.get("phase", "unknown")
            if phase == "combat" and last_phase != "combat":
                logger.log_combat_start(state)
            if last_phase == "combat" and phase == "exploration":
                logger.log_combat_end("won", state)

            if not state.get("available_actions"):
                continue
            pos = state.get("position") or {}
            if pos:
                walked.add(f"{pos.get('x')},{pos.get('y')}")
            decision_start = time.time()
            action = choose_action(state)
            decision_time = (time.time() - decision_start) * 1000

            logger.log_decision(state, action, decision_time)
            recent_actions.append(action) 
            turn_number += 1
            last_phase = phase
            write_action(action)

        except (json.JSONDecodeError, PermissionError, FileNotFoundError):
            pass
        except Exception as e:
            print(f"Error: {e}")

        time.sleep(0.05)


if __name__ == "__main__":
    run()