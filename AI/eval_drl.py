import torch
import torch.optim as optim
import json
import os
import time

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


combat_net.load_state_dict(torch.load(os.path.join(BASE_DIR, "models", "combat_net_ep300.pt")))
exploration_net.load_state_dict(torch.load(os.path.join(BASE_DIR, "models", "exploration_net_ep300.pt")))
combat_net.eval()
exploration_net.eval()

print("loaded mo errors")
