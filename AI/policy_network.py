import torch
import torch.nn as nn
import torch.nn.functional as F 

class PolicyNetwork(nn.Module):
    """A simple policly network takes in the endoed game state and ouputs a probility fpr each action
    used for combat and exploration action selection
    only the input and output will be diffetent"""

    def __init__(self, input_size: int, num_actions: int, hidden_size: int = 128):
        super(PolicyNetwork, self).__init__()
        self.fc1 = nn.Linear(input_size, hidden_size)
        self.fc2 = nn.Linear(hidden_size, hidden_size)
        self.fc3 = nn.Linear(hidden_size, num_actions)

    def logits(self, x):
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        return self.fc3(x)              # raw scores, no softmax

    def forward(self, x):
        return F.softmax(self.logits(x), dim=-1)
    

if __name__ == "__main__":
    import encoders

    net = PolicyNetwork(input_size=encoders.vector_length("combat"), num_actions=3)


    fake_state = torch.randn(1, encoders.vector_length("combat"))
    probs = net(fake_state)

    print("output probabilities:", probs)
    print("sum of probabilities:", probs.sum().item())
    assert abs(probs.sum().item() - 1.0) < 1e-5, "Probabilities do not sum to 1"
    print("Test passed: Output is a valid probability distribution.")