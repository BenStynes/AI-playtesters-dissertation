import torch


def select_action(network,state_vector, available_actions,all_actions,temperature: float = 1.0):
    """pick an action from the networks policy
       network: the network to use for action selection
         state_vector: the encoded state
         avalible_actions: the actions that are legal in the current state
            all_actions: the list of all possible actions in the fixed output order
            

            returns (chosen_action,log_probability_tensor) 
    """

    #1 state to tensor, shaped 

    x = torch.tensor(state_vector, dtype=torch.float32).unsqueeze(0) 
    #2 raw scores from the network before softmax
    logits = network.logits(x).squeeze(0) #shape (num_actions,)

    #3 mask out illegal actions by setting their logits to -inf
    mask = torch.full_like(logits, float('-inf'))
    for i,a in enumerate(all_actions):
        if a in available_actions:
            mask[i] =0.0
    logits = logits + mask
    #4 apply temperature and softmax to get probabilities
    probs = torch.softmax(logits / temperature, dim=-1)
    #5 sample an action index from the categorical distribution
    dist = torch.distributions.Categorical(probs)
    action_index = dist.sample()
    #6 get the chosen action and its log probability for trainging
    chosen  = all_actions[action_index.item()]
    log_prob = dist.log_prob(action_index)

    return chosen , log_prob