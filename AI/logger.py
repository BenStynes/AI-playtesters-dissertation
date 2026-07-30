import json
import os
import math
import time
from datetime import datetime

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
os.makedirs(LOG_DIR, exist_ok=True)


class RunLogger:
    """Records per-run metrics for a single agent playthrough and saves them to JSON."""

    def __init__(self, agent_type: str, seed: int, personality: str = None):
        self.agent_type = agent_type
        self.seed = seed
        self.personality = personality
        self.start_time = time.time()

        #  Overall counters 
        self.turns_taken = 0 # every decision, both phases
        self.exploration_turns = 0 # decisions made while exploring
        self.combat_turns = 0 # decisions made in combat
        self.actions_taken = [] # full per-turn record
        self.outcome = "unknown"

        #  Decision timing (milliseconds) 
        self.decision_times = []
        self.combat_decision_times = []
        self.exploration_decision_times = []

        #  Combat results 
        self.combat_encounters = 0
        self.combat_win_count = 0
        self.combat_entry_hp = 0 # HP when the current fight began
        self.post_combat_hp_ratios = [] # HP ratio remaining after each won fight

        #new metrics
        self.visited_count = 0
        self.total_walkable = 1
        self.chests_seen = set()
        self.turns_to_boss = None

        # End of run snapshot 
        self.final_hp = 0
        self.final_hp_percent = 0.0
        self.gold_collected = 0
        self.boss_reached = False
        self.run_completed = False # True only if the boss was defeated
        
  
    # Per turn logging
  
    def log_decision(self, state: dict, action: str, decision_time_ms: float):
        self.turns_taken += 1
        phase = state.get("phase")

        self.decision_times.append(decision_time_ms)
        if phase == "combat":
            self.combat_turns += 1
            self.combat_decision_times.append(decision_time_ms)
        elif phase == "exploration":
            self.exploration_turns += 1
            self.exploration_decision_times.append(decision_time_ms)

        player = state.get("player", {})
        hp = player.get("hp", 0)
        max_hp = max(player.get("max_hp", 1), 1)
        self.visited_count = state.get("visited_count", self.visited_count)
        self.total_walkable = max(state.get("total_walkable_tiles", self.total_walkable), 1)
        pos = state.get("position", {})
        for t in state.get("visible_special_tiles", []):
            if t.get("tile") in (4,7):
                key = f"{pos.get('x',0)+t.get('dx',0)},{pos.get('y',0)+t.get('dy',0)}"
                self.chests_seen.add(key)
        self.actions_taken.append({
            "turn": self.turns_taken,
            "phase": phase,
            "action": action,
            "position": state.get("position"),
            "player_hp": hp,
            "player_hp_percent": hp / max_hp,
            "player_level": player.get("level", 1),
            "current_tile": state.get("current_tile"),
            "decision_time_ms": decision_time_ms,
        })

   
    # Combat lifecycle
  
    def log_combat_start(self, state: dict):
        self.combat_encounters += 1
        self.combat_entry_hp = state.get("player", {}).get("hp", 0)
        if state.get("is_boss") and self.turns_to_boss is None:
            self.turns_to_boss = self.turns_taken

    def log_combat_end(self, outcome: str, state: dict):
        if outcome == "won":
            self.combat_win_count += 1
            player = state.get("player", {})
            max_hp = max(player.get("max_hp", 1), 1)
            self.post_combat_hp_ratios.append(player.get("hp", 0) / max_hp)

  
    # End of run
  
    def log_run_end(self, outcome: str, state: dict):
        self.outcome = outcome
        player = state.get("player", {})
        self.final_hp = player.get("hp", 0)
        self.final_hp_percent = self.final_hp / max(player.get("max_hp", 1), 1)
        self.gold_collected = player.get("gold", 0)
        self.final_level = player.get("level", 1)
        self.boss_reached = outcome in ("won", "died_at_boss")

        self.run_completed = outcome == "won"
        self._save()

  
    # Metric calculation
  
    def _calculate_metrics(self) -> dict:
        # Tally actions by phase
        all_action_counts = {}
        combat_actions = []
        exploration_actions = []
        heals_used = 0
        chests_opened = 0
        secrets_found = 0
        for entry in self.actions_taken:
            if entry["action"] == "interact":
                tile = entry.get("current_tile")
                if tile == 5:        # heal
                    heals_used += 1
                elif tile == 4:      # chest
                    chests_opened += 1
                elif tile == 7:      # secret door
                    secrets_found += 1
        for entry in self.actions_taken:
            action = entry["action"]
            all_action_counts[action] = all_action_counts.get(action, 0) + 1
            if entry["phase"] == "combat":
                combat_actions.append(action)
            elif entry["phase"] == "exploration":
                exploration_actions.append(action)

        total_actions = max(len(self.actions_taken), 1)
        action_distribution = {a: c / total_actions for a, c in all_action_counts.items()}

        # Action diversity — Shannon entropy over the full distribution
        action_diversity_entropy = 0.0
        for p in action_distribution.values():
            if p > 0:
                action_diversity_entropy -= p * math.log2(p)

        # Strategy switching — how often consecutive actions differ
        switches = sum(
            1 for i in range(1, len(self.actions_taken))
            if self.actions_taken[i]["action"] != self.actions_taken[i - 1]["action"]
        )
        strategy_switching_frequency = switches / max(len(self.actions_taken) - 1, 1)

        # Risk taking — aggressive share of COMBAT actions only
        aggressive_actions = sum(1 for a in combat_actions if a in ("attack", "magic"))
        risk_taking_index = aggressive_actions / max(len(combat_actions), 1)

        # Per-phase action distributions
        combat_action_distribution = self._distribution(combat_actions)
        exploration_action_distribution = self._distribution(exploration_actions)

        # Win rate, timing, health efficiency
        combat_win_rate = self.combat_win_count / max(self.combat_encounters, 1)
        avg_health_efficiency = (
            sum(self.post_combat_hp_ratios) / max(len(self.post_combat_hp_ratios), 1)
        )
        avg_decision_time = sum(self.decision_times) / max(len(self.decision_times), 1)
        avg_combat_decision_time = (
            sum(self.combat_decision_times) / max(len(self.combat_decision_times), 1)
        )
        avg_exploration_decision_time = (
            sum(self.exploration_decision_times) / max(len(self.exploration_decision_times), 1)
        )
        exploration_coverage = min(self.visited_count / max(self.total_walkable, 1), 1.0)
        tiles_stood = set()
        revisits = 0
        arrivals =0
        explore_steps = 0
        prev_key = None
        for e in self.actions_taken:
            if e["phase"] != "exploration":
                continue
            p = e.get("position") or {}
            if not p:
                continue
            key =f"{p.get('x')},{p.get('y')}"
            explore_steps += 1
            if key != prev_key:
                arrivals += 1
                if key  in tiles_stood:
                    revisits +=1
                tiles_stood.add(key)
            prev_key = key

        backtrack_rate = revisits / max(arrivals, 1)
        tiles_walked_coverage = len(tiles_stood) / max(self.total_walkable, 1)
        curiosity_rate = (chests_opened + secrets_found) / max(len(self.chests_seen), 1)

        LOW_HP = 0.3
        low_hp_combat = [e for e in self.actions_taken if e["phase"] == "combat" and e["player_hp_percent"] < LOW_HP]
        
        low_hp_aggression = sum(1 for e in low_hp_combat if e["action"] in ("attack", "magic"))/max(len(low_hp_combat), 1)


        return {
            "action_distribution": action_distribution,
            "combat_action_distribution": combat_action_distribution,
            "exploration_action_distribution": exploration_action_distribution,
            "action_diversity_entropy": round(action_diversity_entropy, 4),
            "strategy_switching_frequency": round(strategy_switching_frequency, 4),
            "risk_taking_index": round(risk_taking_index, 4),
            "combat_win_rate": round(combat_win_rate, 4),
            "avg_health_efficiency": round(avg_health_efficiency, 4),
            "avg_decision_time_ms": round(avg_decision_time, 2),
            "avg_combat_decision_time_ms": round(avg_combat_decision_time, 2),
            "avg_exploration_decision_time_ms": round(avg_exploration_decision_time, 2),
            "heals_used": heals_used,
            "chests_opened": chests_opened,
            "secrets_found": secrets_found,
            "exploration_coverage": round(exploration_coverage, 4),
            "tiles_walked_coverage": round(tiles_walked_coverage, 4),
            "backtrack_rate": round(backtrack_rate, 4),
            "curiosity_rate": round(curiosity_rate, 4),
            "low_hp_aggression": round(low_hp_aggression, 4),
            "turns_to_boss": self.turns_to_boss,
        }

    @staticmethod
    def _distribution(actions: list) -> dict:
        """Return a normalised frequency distribution for a list of actions."""
        counts = {}
        for a in actions:
            counts[a] = counts.get(a, 0) + 1
        total = max(len(actions), 1)
        return {a: c / total for a, c in counts.items()}

  
    # Persistence
  
    def _save(self):
        metrics = self._calculate_metrics()

        log_entry = {
            "agent_type": self.agent_type,
            "seed": self.seed,
            "personality": self.personality,
            "timestamp": datetime.now().isoformat(),
            "duration_seconds": round(time.time() - self.start_time, 2),
            "outcome": self.outcome,
            "turns_taken": self.turns_taken,
            "exploration_turns": self.exploration_turns,
            "combat_turns": self.combat_turns,
            "combat_encounters": self.combat_encounters,
            "combat_win_count": self.combat_win_count,
            "boss_reached": self.boss_reached,
            "run_completed": self.run_completed,
            "final_level": self.final_level,
            "final_hp": self.final_hp,
            "final_hp_percent": round(self.final_hp_percent, 4),
            "gold_collected": self.gold_collected,
            "metrics": metrics,
            "actions_taken": self.actions_taken,
            "decision_times": self.decision_times,
            "prompt_samples": getattr(self, "prompt_samples", None),
        }

        timestamp = datetime.now().strftime("%H%M%S")
        tag = f"_{self.personality}" if self.personality else ""
        filename = f"{self.agent_type}{tag}_{self.seed}_{self.outcome}_{timestamp}.json"
        filepath = os.path.join(LOG_DIR, filename)
        with open(filepath, "w") as f:
            json.dump(log_entry, f, indent=2)
        print(f"Run log saved: {filename}")