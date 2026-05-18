import json
import os
import time
from datetime import datetime

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
os.makedirs(LOG_DIR, exist_ok=True)

class RunLogger:

    def __init__(self,agent_type: str, seed: int, personality: str = None):
        self.agent_type = agent_type
        self.seed = seed
        self.personality = personality
        self.start_time = time.time()

        #metrics tracked

        self.turns_taken = 0 # amount of turns overall in both play states so each move and each attack 
        self.actions_taken = [] # full list of actions taken
        self.decision_times = [] # how many millieseconds per decision
        self.combat_encounters = 0 # how many fighrs happened
        self.combat_won = 0        
        self.final_hp = 0
        self.final_hp_percent = 0.0
        self.gold_collected = 0
        self.outcome = "unknown"

        #combat metrics
        self.current_combat_start_hp = 0
        self.health_efficiency_scores - [] #REMAING % OF HP

        #phase tracking
        self.current_phase = "exploration"



    def log_decision(self, state: dict, action: str, decision_time_ms: float):
        self.turns_taken += 1
        self.actions_taken.append({
            "turn": self.turns_taken,
            "phase": state.get("phase"),
            "action": action,
            "player_hp": state.get("player", {}).get("hp",0),
            "player_hp_percent": state.get("player", {}).get("hp",0) /
            max(state.get("player", {}).get("max_hp",1),1),
            "decision_time_ms":decision_time_ms

        })
        self.decision_times.append(decision_time_ms)
    

    def log_combat_start(self, state: dict):
        self.combat_encounters +=1
        self.current_combat_start_hp = state.get("player", {}).get("hp", 0)

    def log_combat_end(self, outcome:str,state: dict):
        if outcome == "won":
            self.combat_won +=1

            max_hp = state.get("player", {}).get("max_hp", 1)
            final_hp =  state.get("player", {}).get("hp", 0)
            self.health_efficiency_scores.append(final_hp / max(max_hp, 1))
        
        