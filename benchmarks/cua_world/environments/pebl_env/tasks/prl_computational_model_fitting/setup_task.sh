#!/bin/bash
set -e
echo "=== Setting up PRL Computational Model Fitting task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/pebl/analysis/prl_model_report.json

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Generate realistic PRL data using a dual-rate Rescorla-Wagner simulation
echo "Generating PRL model fitting dataset..."
python3 - << 'EOF'
import csv, random, math

random.seed(2024)

# 14 valid participants with known generative parameters (dual-rate RW model)
# Format: (id, alpha_pos, alpha_neg, beta)
# Varied to produce a mix of single-rate and dual-rate AIC preferences
participants = [
    ("PRL-001", 0.35, 0.20, 5.0),   # moderate learner, asymmetric
    ("PRL-002", 0.60, 0.35, 8.0),   # fast learner, asymmetric
    ("PRL-003", 0.15, 0.08, 3.0),   # slow learner, asymmetric
    ("PRL-004", 0.40, 0.38, 6.5),   # moderate, nearly symmetric
    ("PRL-005", 0.30, 0.28, 4.0),   # moderate, nearly symmetric
    ("PRL-006", 0.55, 0.30, 10.0),  # fast, very asymmetric
    ("PRL-007", 0.42, 0.22, 7.0),   # moderate, asymmetric
    ("PRL-008", 0.25, 0.12, 2.5),   # slow, asymmetric
    ("PRL-009", 0.50, 0.48, 9.0),   # fast, nearly symmetric
    ("PRL-010", 0.18, 0.10, 3.5),   # slow, asymmetric
    ("PRL-011", 0.65, 0.40, 12.0),  # very fast, asymmetric
    ("PRL-012", 0.10, 0.08, 2.0),   # very slow, nearly symmetric
    ("PRL-013", 0.38, 0.28, 5.5),   # moderate, asymmetric
    ("PRL-014", 0.48, 0.46, 7.5),   # fast, nearly symmetric
]

NUM_TRIALS = 200
REWARD_PROB = 0.80

rows = []

for pid, alpha_pos, alpha_neg, beta in participants:
    Q = {'A': 0.5, 'B': 0.5}
    rewarded = 'A'
    recent_correct = []

    for t in range(1, NUM_TRIALS + 1):
        # Softmax choice probability
        exp_A = math.exp(beta * Q['A'])
        exp_B = math.exp(beta * Q['B'])
        p_A = exp_A / (exp_A + exp_B)
        choice = 'A' if random.random() < p_A else 'B'

        # Probabilistic reward
        if choice == rewarded:
            outcome = 1 if random.random() < REWARD_PROB else 0
        else:
            outcome = 1 if random.random() < (1.0 - REWARD_PROB) else 0

        # Record trial BEFORE updating state
        rows.append([pid, t, choice, outcome, rewarded])

        # Dual-rate Q-value update
        PE = outcome - Q[choice]
        if PE >= 0:
            Q[choice] += alpha_pos * PE
        else:
            Q[choice] += alpha_neg * PE

        # Track correctness for reversal criterion
        correct = 1 if choice == rewarded else 0
        recent_correct.append(correct)
        if len(recent_correct) >= 10 and sum(recent_correct[-10:]) >= 8:
            # Reversal: switch rewarded stimulus
            rewarded = 'B' if rewarded == 'A' else 'A'
            recent_correct = []

# PRL-999: random bot (50/50 choices regardless of feedback)
rewarded_bot = 'A'
recent_bot = []
for t in range(1, NUM_TRIALS + 1):
    choice = 'A' if random.random() < 0.5 else 'B'

    if choice == rewarded_bot:
        outcome = 1 if random.random() < REWARD_PROB else 0
    else:
        outcome = 1 if random.random() < (1.0 - REWARD_PROB) else 0

    rows.append(["PRL-999", t, choice, outcome, rewarded_bot])

    correct = 1 if choice == rewarded_bot else 0
    recent_bot.append(correct)
    if len(recent_bot) >= 10 and sum(recent_bot[-10:]) >= 8:
        rewarded_bot = 'B' if rewarded_bot == 'A' else 'A'
        recent_bot = []

# Write CSV
with open('/home/ga/pebl/data/prl_model_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['participant_id', 'trial', 'choice', 'outcome', 'rewarded_stimulus'])
    writer.writerows(rows)

print(f"Generated {len(rows)} trials for {len(participants) + 1} participants")
EOF

chown ga:ga /home/ga/pebl/data/prl_model_data.csv
chmod 644 /home/ga/pebl/data/prl_model_data.csv

# Get ga user's DBUS session address for gnome-terminal
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === PRL Computational Model Fitting ===; echo; echo Data file: ~/pebl/data/prl_model_data.csv; echo Output target: ~/pebl/analysis/prl_model_report.json; echo; echo Columns: participant_id, trial, choice, outcome, rewarded_stimulus; echo Participants: PRL-001 through PRL-014 plus PRL-999; echo; bash' > /tmp/prl_terminal.log 2>&1 &"

# Maximize the terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial state screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== PRL setup complete ==="
