#!/bin/bash
# Setup for prob_reversal_wsls_analysis task
# Generates highly realistic human Probabilistic Reversal Learning data
# using a domain-specific Rescorla-Wagner reinforcement learning model,
# plus one injected artifactual participant (PRL-999) with perfect alternation.

set -e
echo "=== Setting up prob_reversal_wsls_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Domain-specific dataset generator (Rescorla-Wagner RL model)
# Generates realistic computational psychiatry behavioral data
python3 << 'PYEOF'
import csv
import random
import math

# Use fixed seed for deterministic but realistic data distribution
random.seed(101)

def sigmoid(x):
    try:
        return 1 / (1 + math.exp(-x))
    except OverflowError:
        return 0.0 if x < 0 else 1.0

rows = []

# Generate 18 Real participants using Rescorla-Wagner RL
for p in range(1, 19):
    pid = f"PRL-{p:03d}"
    # Varying learning rates and inverse temperatures
    alpha = random.uniform(0.15, 0.45)
    beta = random.uniform(2.5, 6.0)
    q = {'A': 0.5, 'B': 0.5}
    
    # Reversal occurs between trials 55 and 65
    reversal_trial = random.choice([55, 60, 65])
    
    for trial in range(1, 121):
        phase = 'acquisition' if trial < reversal_trial else 'reversal'
        correct_stimulus = 'A' if phase == 'acquisition' else 'B'
        
        # 80/20 probabilistic contingencies
        prob_A = 0.8 if correct_stimulus == 'A' else 0.2
        prob_B = 0.8 if correct_stimulus == 'B' else 0.2
        
        # Softmax choice rule
        p_A = sigmoid(beta * (q['A'] - q['B']))
        choice = 'A' if random.random() < p_A else 'B'
        
        # Probabilistic feedback
        win_prob = prob_A if choice == 'A' else prob_B
        feedback = 'win' if random.random() < win_prob else 'lose'
        
        # Value update
        r = 1 if feedback == 'win' else 0
        q[choice] += alpha * (r - q[choice])
        
        rows.append({
            'participant_id': pid,
            'trial': trial,
            'phase': phase,
            'choice': choice,
            'feedback': feedback,
            'correct_stimulus': correct_stimulus,
            'reversal_trial': reversal_trial
        })

# Inject 1 Contaminated participant (PRL-999) - Mechanical Alternation
for trial in range(1, 121):
    phase = 'acquisition' if trial < 60 else 'reversal'
    correct_stimulus = 'A' if phase == 'acquisition' else 'B'
    
    # Strictly alternates A-B-A-B regardless of feedback (mechanical artifact)
    choice = 'A' if trial % 2 != 0 else 'B'
    
    win_prob = 0.8 if choice == correct_stimulus else 0.2
    feedback = 'win' if random.random() < win_prob else 'lose'
    
    rows.append({
        'participant_id': 'PRL-999',
        'trial': trial,
        'phase': phase,
        'choice': choice,
        'feedback': feedback,
        'correct_stimulus': correct_stimulus,
        'reversal_trial': 60
    })

with open('/tmp/reversal_learning_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id','trial','phase','choice','feedback','correct_stimulus','reversal_trial'])
    writer.writeheader()
    writer.writerows(rows)
    
print(f"Generated {len(rows)} trials of PRL data.")
PYEOF

# Move file into place and set permissions
mv /tmp/reversal_learning_data.csv /home/ga/pebl/data/reversal_learning_data.csv
chown ga:ga /home/ga/pebl/data/reversal_learning_data.csv
chmod 644 /home/ga/pebl/data/reversal_learning_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address for terminal launch
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Probabilistic Reversal Learning Analysis ===; echo; echo Data file: ~/pebl/data/reversal_learning_data.csv; echo Output target: ~/pebl/analysis/reversal_report.json; echo; bash' > /tmp/reversal_terminal.log 2>&1 &"

# Wait for terminal to appear and maximize it
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== prob_reversal_wsls_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/reversal_learning_data.csv"
echo "Expected output: /home/ga/pebl/analysis/reversal_report.json"