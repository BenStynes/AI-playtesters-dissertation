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
        self.combat_win_count  = 0    
        self.exploration_turns = 0
        self.combat_turns = 0    
        self.final_hp = 0
        self.final_hp_percent = 0.0
        self.gold_collected = 0
        self.outcome = "unknown"
        self.combat_decision_times    = []
        self.exploration_decision_times = []
        #combat metrics
        self.combat_entry_hp  = 0
        self.post_combat_hp_ratios = [] #REMAING % OF HP

        #phase tracking
        self.current_phase = "exploration"



    def log_decision(self, state: dict, action: str, decision_time_ms: float):
        self.turns_taken += 1
        phase = state.get("phase")
        self.decision_times.append(decision_time_ms)

        if phase == "exploration":
            self.exploration_turns += 1
            self.exploration_decision_times.append(decision_time_ms)
            
        elif phase == "combat":
            self.combat_turns += 1
            self.combat_decision_times.append(decision_time_ms)

        
        self.actions_taken.append({
            "turn": self.turns_taken,
            "phase": state.get("phase"),
            "action": action,
            "player_hp": state.get("player", {}).get("hp",0),
            "player_hp_percent": state.get("player", {}).get("hp",0) /
            max(state.get("player", {}).get("max_hp",1),1),
            "decision_time_ms":decision_time_ms

        })
    

    def log_combat_start(self, state: dict):
        self.combat_encounters +=1
        self.combat_entry_hp  = state.get("player", {}).get("hp", 0)

    def log_combat_end(self, outcome:str,state: dict):
        if outcome == "won":
            self.combat_win_count  +=1

            max_hp = state.get("player", {}).get("max_hp", 1)
            final_hp =  state.get("player", {}).get("hp", 0)
            self.post_combat_hp_ratios.append(final_hp / max(max_hp, 1))
    
    
    
    def log_run_end(self, outcome: str, state: dict):
        self.outcome = outcome
        player = state.get("player", {})
        self.final_hp = player.get("hp",0)
        self.final_hp_percent = self.final_hp / max(player.get("max_hp",1),1)
        self.gold_collected = player.get("gold",0)
        self._save()
    
    def _calculate_metrics(self) -> dict:

        #game action diversity
        action_counts = {}
        combat_actions = []
        exploration_actions = []
        for entry in self.actions_taken:
            a = entry["action"]
            action_counts[a] = action_counts.get(a,0) + 1
            if entry["phase"] == "combat":
                combat_actions.append(a)
            elif entry["phase"] == "exploration":
                exploration_actions.append(a)
        total = max(len(self.actions_taken),1)
        #k = key , v = value
        action_distribution = {k: v/total for k, v in action_counts.items()}

        #using shannon entropy for action diversity

        import math
        entropy = 0.0
        for p in action_distribution.values():
            if p > 0:
                entropy-= p *math.log2(p)

        
        #strategy switching frequency
        switches = 0
        for i in range(1, len(self.actions_taken)):
            if self.actions_taken[i]["action"] != self.actions_taken[i-1]["action"]:
                switches +=1
        switching_frequency = switches / max(len(self.actions_taken)-1,1)


        #risk taking index whether aggressuve vs defensive in combat
        aggressive = sum(1 for a in combat_actions if a in ["attack","magic"])
        total_combat = max(len(combat_actions),1)
        risk_taking_index = aggressive / total_combat

        combat_action_counts = {}
        for a in combat_actions:
            combat_action_counts[a] = combat_action_counts.get(a, 0) + 1
        total_combat = max(len(combat_actions), 1)
        combat_distribution = {k: v / total_combat for k, v in combat_action_counts.items()}

        exploration_action_counts  = {}
        for a in exploration_actions:
            exploration_action_counts[a] = exploration_action_counts.get(a, 0) + 1
        total_exploration  = max(len(exploration_actions), 1)
        exploration_distribution  = {k: v / total_exploration  for k, v in exploration_action_counts.items()}
        #decsion latency stats
        avg_decision_time = sum(self.decision_times) / max(len(self.decision_times),1)
        avg_combat_decision_time = sum(self.combat_decision_times) / max(len(self.combat_decision_times), 1)
        avg_exploration_decision_time = sum(self.exploration_decision_times) / max(len(self.exploration_decision_times), 1)
        #health efficency
        avg_health_efficiency  = (sum(self.post_combat_hp_ratios)/ max(len(self.post_combat_hp_ratios),1))
        combat_win_rate = self.combat_win_count / max(self.combat_encounters, 1)

        return {
            "action_distribution": action_distribution,
            "combat_action_distribution": combat_distribution,
            "exploration_action_distribution" : exploration_distribution,
            "action_diversity_entropy": round(entropy,4),
            "strategy_switching_frequency": round(switching_frequency,4),
            "risk_taking_index": round(risk_taking_index,4),
            "combat_win_rate": round(combat_win_rate, 4),
            "avg_decision_time_ms": round(avg_decision_time,2),
            "avg_combat_decision_time_ms": round(avg_combat_decision_time, 2),
            "avg_exploration_decision_time_ms": round(avg_exploration_decision_time, 2),
            "avg_health_efficiency": round(avg_health_efficiency,4),

        }
    
    def _save(self):
        metrics = self._calculate_metrics()

        log_entry = {
            "agent_type": self.agent_type,
            "seed": self.seed,
            "personality": self.personality,#
            "timestamp": datetime.now().isoformat(),
            "duration_seconds": round(time.time()-self.start_time,2),
            "outcome": self.outcome,
            "turns_taken": self.turns_taken,
            "combat_win_rate": round(self.combat_win_count / max(self.combat_encounters, 1), 4),
            "exploration_turns": self.exploration_turns,
            "combat_turns": self.combat_turns,
            "combat_encounters": self.combat_encounters,
            "combat_win_count ": self.combat_win_count ,
            "final_hp": self.final_hp,
            "final_hp_percent": round(self.final_hp_percent,4),
            "gold_collected": self.gold_collected,
            "metrics": metrics,
            "actions_taken": self.actions_taken,
            "decision_time": self.decision_times,


        }

        timestamp = datetime.now().strftime("%H%M%S")
        filename = f"{self.agent_type}_run{self.seed}_{self.outcome}_{timestamp}.json"
        filepath = os.path.join(LOG_DIR, filename)
        with open(filepath, "w") as f:
            json.dump(log_entry, f, indent=2)
        print(f"Run log saved: {filename}")
        