"""turns a bridge file into a natural language prompt for the llm agent"""

TILE_NAMES = {
    0: "a wall", 1: "open floor", 2: "the dungeon entrance" , 3: "the BOSS", 4: "a chest", 5: "a healing fountain", 6: "a trap", 7: "a secret door", }
COMPASS = ["north", "east", "south", "west"]


MAP_SYMBOLS = {0: "#", 1: ".", 2: "E", 3: "B", 4: "C", 5: "H", 6: "T", 7: "S"}
MAP_RADIUS = 12          


def _local_map(state, walked):
    """ASCII view of the remembered map around the player, north at the top."""
    seen = state.get("seen_map", {})
    pos = state.get("position", {})
    px, py = pos.get("x", 0), pos.get("y", 0)

    rows = []
    for y in range(py - MAP_RADIUS, py + MAP_RADIUS + 1):
        row = []
        for x in range(px - MAP_RADIUS, px + MAP_RADIUS + 1):
            if x == px and y == py:
                row.append("@")
                continue
            key = f"{x},{y}"
            if key not in seen:
                adjacent_to_floor = any(
                    seen.get(f"{x+ax},{y+ay}", 0) != 0
                    for ax, ay in ((0, -1), (1, 0), (0, 1), (-1, 0))
                )
                row.append("?" if adjacent_to_floor else " ")
                continue
            else:
                sym = MAP_SYMBOLS.get(seen[key], ".")
                if sym == "." and key not in walked:
                    sym = ","        # seen floor you have not walked on
                row.append(sym)
        rows.append("".join(row))
    return "\n".join(rows)


def _relative_tiles(state):
    """the four neighboring tiles of the player, in order of ahead, right, behind, left rotated to the player's current facing direction(0=N, 1=E, 2=S, 3=W)"""
    facing = state.get("facing", 0)
    absolute = [
        state.get("tile_north", 0),
        state.get("tile_east", 0),
        state.get("tile_south", 0),
        state.get("tile_west", 0),
    ]
    return{
        "ahead": absolute[facing % 4],
        "right": absolute[(facing + 1) % 4],
        "behind": absolute[(facing + 2) % 4],
        "left": absolute[(facing + 3) % 4],
    }
def _nearest_frontier(state):
    """Nearest known-walkable tile that borders somewhere never seen.
    Returns (distance, bearing) or None."""
    seen = state.get("seen_map", {})
    pos = state.get("position", {})
    px, py = pos.get("x", 0), pos.get("y", 0)
    best = None

    for key, tile in seen.items():
        if tile == 0:                      
            continue
        try:
            tx, ty = (int(v) for v in key.split(","))
        except ValueError:
            continue
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            if f"{tx+dx},{ty+dy}" not in seen:
                d = abs(tx - px) + abs(ty - py)
                if d > 0 and (best is None or d < best[0]):
                    best = (d, tx - px, ty - py)
                break

    if best is None:
        return None
    d, dx, dy = best
    vertical = "north" if dy < 0 else "south"
    horizontal = "east" if dx > 0 else "west"
    if dx == 0:
        bearing = vertical
    elif dy == 0:
        bearing = horizontal
    else:
        bearing = f"{vertical}-{horizontal}"
    idx = (0 if dy < 0 else 2) if abs(dy) >= abs(dx) else (1 if dx > 0 else 3)
    return d, bearing, idx
    

def describe_exploration(state, walked=None):
    walked = walked or set()
    player = state.get("player", {})
    hp, max_hp = player.get("hp", 0), max(player.get("max_hp", 1), 1)

    facing = state.get("facing", 0) % 4
    pos = state.get("position", {})
    px, py = pos.get("x", 0), pos.get("y", 0)
   

    absolute = {
        "north": (state.get("tile_north", 0), (0, -1)),
        "east":  (state.get("tile_east", 0),  (1, 0)),
        "south": (state.get("tile_south", 0), (0, 1)),
        "west":  (state.get("tile_west", 0),  (-1, 0)),
    }
    order = [
        ("Directly ahead of you", COMPASS[facing]),
        ("To your right", COMPASS[(facing + 1) % 4]),
        ("To your left", COMPASS[(facing + 3) % 4]),
    ]

    lines = [
        f"You are exploring a dungeon. Health: {hp}/{max_hp}. "
        f"You are facing {COMPASS[facing]}."
    ]
    lines.append(
        "Map of what you remember (north is up, each symbol is one tile):\n"
        + _local_map(state, walked) + "\n"
        "Legend: @ you, # wall, . floor you have walked on, , floor you have seen "
        "but not walked on, ? unknown/unexplored, B boss, C chest, H healing "
        "fountain, T trap, S secret door, E entrance."
    )
    parts = []
    for label, compass in order:
        tile, (dx, dy) = absolute[compass]
        name = TILE_NAMES.get(tile, "unknown ground")
        if tile == 0:
            tag = "impassable"
        elif f"{px+dx},{py+dy}" in walked:
            tag = "already visited"
        else:
            tag = "NEW GROUND"
        parts.append(f"{label} is {name} ({tag})")
    lines.append(". ".join(parts) + ".")

    sightings = []
    for t in state.get("visible_special_tiles", []):
        name = TILE_NAMES.get(t.get("tile"), "something")
        dist = round(t.get("distance", 0))
        dx, dy = t.get("dx", 0), t.get("dy", 0)
        bearing = COMPASS[1] if dx > 0 else COMPASS[3]
        if abs(dy) > abs(dx):
            bearing = COMPASS[2] if dy > 0 else COMPASS[0]
        sightings.append(f"{name} about {dist} tiles {bearing}")
    if sightings:
        lines.append("You can see: " + "; ".join(sightings[:5]) + ".")
    else:
        lines.append("You cannot see anything special from here.")
    frontier = _nearest_frontier(state)
    if frontier:
        dist, bearing, idx = frontier
        rel = (idx - facing) % 4
        towards = ["straight ahead", "to your RIGHT", "BEHIND you", "to your LEFT"][rel]
        lines.append(f"The nearest unexplored area is about {dist} tiles "
                     f"{bearing}, which is {towards}.")
    visited = state.get("visited_count", 0)
    total = max(state.get("total_walkable_tiles", 1), 1)
    lines.append(f"You have explored about {round(100 * visited / total)}% of the dungeon.")
    lines.append("Prefer moving onto NEW GROUND. Do not turn repeatedly on the spot.")
    return "\n".join(lines)

def describe_combat(state):
    player = state.get("player", {})
    hp,max_hp = player.get("hp", 0), max(player.get("max_hp", 1), 1)
    mp = player.get("mp",0)

    lines = [f"you are in compat. your health:  {hp}/{max_hp}. Your magic points: {mp}."]

    living = [e for e in state.get("enemies", []) if e.get("hp", 0) > 0]
    if living:
        e = living[0]
        kind = "THE BOSS" if e.get("is_boss") else e.get("name", "an enemy")
        lines.append(
            f"you are fighing {kind} which has {e.get('hp',0)}/"
            f"{max(e.get('max_hp', 1), 1)} health.")
        if e.get("is_boss") and state.get("boss_next_action"):
            lines.append(f"its next moce will be: {state['boss_next_action']}.")
        if len(living) > 1:
            lines.append(f"There are {len(living)} enemies in total.")
    lines.append("Attacking deals damage. Defending reduces incoming damage. "
                 "Magic costs 10 MP and can be stronger against armoured enemies.")
    return "\n".join(lines)

def build_prompt(state, persona_prompt, walked=None, recent_actions=None,turn_number=0):
    phase = state.get("phase", "exploration")
    if phase == "combat":
        situation = describe_combat(state)
    else:
        situation = describe_exploration(state, walked)
    objective = (
        "You are playing a turn-based dungeon crawler on a 56x56 grid. Somewhere in "
        "the dungeon is a BOSS; to win, find it and defeat it in combat.\n"
        "You can only see tiles near you the rest of the dungeon is unknown until "
        "you walk there, so you must explore to find the boss.\n"
        "Turning changes which way you face but does NOT move you; only move_forward "
        "changes your position. Use interact to open chests, use healing fountains, "
        "or open secret doors when you are standing on them.\n"
        "Walls block movement completely. If move_forward is not in your available "
        "actions, the way ahead is blocked and you must turn.\n"
        f"You have taken {turn_number} turns. You have a limit of 3000 turns to "
        f"find and defeat the boss, so do not waste moves.\n"
    )
    history = ""
    if recent_actions:
        history = f"\nYour last moves were: {', '.join(recent_actions[-6:])}."

    actions = state.get("available_actions", [])
    return (
        f"{objective}\n"
        f"{persona_prompt}\n\n"
        f"{situation}{history}\n\n"
        f"Your available actions are: {', '.join(actions)}.\n"
        f"Choose one action that fits your character. "
        f"Reply with ONLY the action word, nothing else."
    )