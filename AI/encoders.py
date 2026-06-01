"""encoders.py
-------
turns the JSON game state from the bridge into fixed length vectors for the neural network

will be imported by the training and evaluation scripts so the features is quaranteed to be the same for both.
"""

import math
SENTINEL_DIST = 1.0   # distance value of not visible 
NUM_DIRECTIONS = 4     # N, E, S, W
#tile maps to match dungeon tileset

WALL = 0
FLOOR = 1
ENTRANCE = 2
BOSS = 3
CHEST = 4
HEAL = 5
TRAP = 6
SECRET_DOOR = 7
NUM_TILE_TYPES = 8

def _one_hot(index: int, size: int) -> list:
    """returrns a list of length size with a 1 at index and 0s everywhere else"""
    vec = [0.0] * size
    if 0 <= index < size:
        vec[index] = 1.0
    return vec

def _norm_dist(dist: float, max_dist: float = 12.0) -> float:
    """normalizes a distance to be between 0 and 1, where 0 is on top of it  and 1 is far/absent"""
    return min(dist / max_dist, 1.0)

def _dir_from_offset(dx: int, dy: int) -> int:
    """maps a direction vector to the dominat compass direction code"""
    if abs(dx) > abs(dy):
        return 1 if dx > 0 else 3  # east or west
    else:
        return 0 if dy > 0 else 2  # north or south

def _nearest_speacial(state: dict, tile_type: int):
    """finds the nearest tile of a speacil type amd returns the normalized distance and direction code to it
    unless there is none in which case it returns  the  sentinel distance and a direction code of -1
    """
    best = None
    best_dist = None
    for info in state.get("visible_special_tiles", []):
        if info.get("tile") != tile_type:
            continue
        d = info.get("distance", 99.0)
        if best is None or d < best_dist:
            best = info
            best_dist = d
    if best is None:
        return SENTINEL_DIST, -1  # sentinel
    return _norm_dist(best_dist), _dir_from_offset(best.get("dx",0), best.get("dy",0))

def _nearest_frontier(state: dict):
    """distance and direction to the nearest unseen neighbour, using the
    four adjacent tiles and the seen_map returns norm_dist, dir code or sentincel dist, frontier
    is adaceny-based cheap and local"""
    pos = state.get("position", {})
    px, py = pos.get("x",0), pos.get("y",0)
    seen_map = state.get("seen_map", {})
    #adacency orffse in n e s w order
    offsets = [(0,-1), (1,0), (0,1), (-1,0)]
    for d_code, (dx,dy) in enumerate(offsets):
        key = f"{px+dx},{py+dy}"
        if key not in seen_map:
            return _norm_dist(1.0),d_code 
    return SENTINEL_DIST, -1  

COMBAT_VECTOR_LENGTH = 12

def encode_combat_state(state: dict) -> list:
    """Encodes the combat state"""
    player = state.get("player", {})
    hp = player.get("hp",0)
    max_hp = max(player.get("max_hp",1), 1)  # Ensure max_hp is at least 1 to avoid division by zero
    mp = player.get("mp",0)
    max_mp = max(player.get("max_mp",1), 1)  # Ensure max_mp is at least 1 to avoid division by zero

    attack_scaled = min(player.get("attack", 0) / 30.0, 1.0)
    magic_power_scaled = min(player.get("magic_power", 0) / 40.0, 1.0)
    defense_scaled = min(player.get("defense", 0) / 30.0, 1.0)
    crit_chance = player.get("crit_chance", 0.0)     
    stun_chance = player.get("stun_chance", 0.0)     

    hp_ratio = hp / max_hp
    mp_ratio = mp / max_mp
    magic_affordable =1.0 if mp >= 10 else 0.0

    enemies = state.get("enemies", [])
    living = [e for e in enemies if e.get("hp",0) > 0]
    target = living[0] if living else None

    if target:
        enemy_hp_ratio = target.get("hp",0) / max(target.get("max_hp",1), 1) 
        enemy_attack_scaled = min(target.get("attack",0) / 20.0, 1.0)
        enemy_is_boss = 1.0 if target.get("is_boss", False) else 0.0 
    else:
        enemy_hp_ratio = 0.0
        enemy_attack_scaled = 0.0
        enemy_is_boss = 0.0
    
    num_enemies_scaled = min(len(living) / 3.0, 1.0)

    return [
        hp_ratio, 
        mp_ratio, 
        magic_affordable,
        attack_scaled, 
        magic_power_scaled,
        defense_scaled,
        crit_chance,
        stun_chance,
        enemy_hp_ratio, 
        enemy_attack_scaled, 
        enemy_is_boss, 
        num_enemies_scaled,
        ]

EXPLORATION_VECTOR_LENGTH = 68

def _speacial_slot(state: dict, tile_type: int) -> list:
    """norm_dirst follwed by a 4 way direction one hot for the nearest tile of the given type"""
    dist,d_code = _nearest_speacial(state, tile_type)
    return [dist] + _one_hot(d_code, NUM_DIRECTIONS)

def encode_exploration_state(state: dict) -> list:
    """encodes the exploration state"""
    player = state.get("player", {})
    hp_ratio = player.get("hp",0) / max(player.get("max_hp",1), 1)
    
    vec = [hp_ratio]

    #facing one hot n e s w
    vec += _one_hot(state.get("facing", 0), NUM_DIRECTIONS)

    neighbours = [
        state.get("tile_north", FLOOR),
        state.get("tile_east", FLOOR),
        state.get("tile_south", FLOOR),
        state.get("tile_west", FLOOR),
    ]

    for tile in neighbours:
        vec += _one_hot(int(tile), NUM_TILE_TYPES)


    vec += _speacial_slot(state, BOSS)
    vec += _speacial_slot(state, CHEST)
    vec += _speacial_slot(state, HEAL)
    vec += _speacial_slot(state, TRAP)
    vec += _speacial_slot(state, SECRET_DOOR)


    f_dist, f_dir = _nearest_frontier(state)
    vec += [f_dist] + _one_hot(f_dir, NUM_DIRECTIONS)

    visited_count = state.get("visited_count", len(state.get("visited_tiles", {})))
    total_walkable =max(state.get("total_walkable_tiles", 1), 1)  # Avoid division by zero
    fraction_explored = min(visited_count / total_walkable, 1.0)
    vec.append(fraction_explored)

    return vec

def vector_length(phase: str) -> int:
    """report the fixed vector length for a given phase, for a sanity chack"""
    if phase == "combat":
        return COMBAT_VECTOR_LENGTH
    elif phase == "exploration":
        return EXPLORATION_VECTOR_LENGTH
    

if __name__ == "__main__":
    #self test the encoders with a dummy state

    fake_combat = {
        "phase": "combat",
        "player": {"hp": 30, "max_hp": 100, "mp": 5, "max_mp": 20},
        "enemies": [
            {"hp": 50, "max_hp": 100, "attack": 10, "is_boss": False},
            {"hp": 0, "max_hp": 50, "attack": 5, "is_boss": False},
        ]
    }
    fake_exploration = { 
        "phase": "exploration",
        "player": {"hp": 80, "max_hp": 100, "mp": 20, "max_mp": 30},
        "facing": 1,
        "tile_north": 1,
        "tile_east": 0,
        "tile_south": 2,
        "tile_west": 1,
        "visible_special_tiles": [
            {"tile": 3, "distance": 5, "dx": 1, "dy": 0},
            {"tile": 4, "distance": 3, "dx": 0, "dy": -1},
        ],
        "seen_map": {"42,44":1, "42,45":1},
        "position": {"x": 42, "y": 45},
        "visited_count": 10,
        "total_walkable_tiles": 50,
    }

    c = encode_combat_state(fake_combat)
    e = encode_exploration_state(fake_exploration)
    print("Combat vector len:", len(c), "expected:", COMBAT_VECTOR_LENGTH)
    print("Exploration vector len:", len(e), "expected:", EXPLORATION_VECTOR_LENGTH)
    assert len(c) == COMBAT_VECTOR_LENGTH, "Combat vector length mismatch"
    assert len(e) == EXPLORATION_VECTOR_LENGTH, "Exploration vector length mismatch"
    print("okay both worked")