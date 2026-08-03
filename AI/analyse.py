import json,glob,os,statistics as st
from collections import Counter,defaultdict

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")

METRICS = ["risk_taking_index", "low_hp_aggression", "avg_health_efficiency",
           "action_diversity_entropy", "tiles_walked_coverage", "exploration_coverage",
           "backtrack_rate", "curiosity_rate", "turns_to_boss", "chests_opened",
           "secrets_found", "heals_used", "avg_decision_time_ms"]
TOP = ["turns_taken", "final_level", "final_hp_percent", "combat_encounters"]

def get(run, key):
    if key in run.get("metrics", {}):
        return run["metrics"][key]
    return run.get(key)

groups = defaultdict(list)
for path in glob.glob(os.path.join(LOG_DIR, "*.json")):
    run = json.load(open(path))
    label = run.get("personality") or run.get("agent_type")
    groups[label].append(run)

for label in sorted(groups):
    runs = groups[label]
    print(f"\n===== {label}  (n={len(runs)}) =====")
    print("outcomes:", dict(Counter(r["outcome"] for r in runs)))
    print("boss reached:", sum(1 for r in runs if r.get("boss_reached")), "/", len(runs))
    for key in METRICS + TOP:
        vals = [get(r, key) for r in runs]
        vals = [v for v in vals if v is not None]
        if not vals:
            print(f"  {key:28s} —")
            continue
        sd = st.stdev(vals) if len(vals) > 1 else 0.0
        print(f"  {key:28s} mean {st.mean(vals):9.3f}  sd {sd:7.3f}")
    c = Counter()
    for r in runs:
        for a, p in r["metrics"]["combat_action_distribution"].items():
            c[a] += p
    print("  combat dist:", {a: round(v / len(runs), 3) for a, v in c.items()})
    