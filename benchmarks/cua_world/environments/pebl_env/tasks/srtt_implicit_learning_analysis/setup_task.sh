#!/bin/bash
# Setup for srtt_implicit_learning_analysis task
# Generates realistic Serial Reaction Time Task (SRTT) data for 15 real participants
# Plus one corrupted participant (p99) with zero RT variance.

set -e
echo "=== Setting up srtt_implicit_learning_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate the SRTT data using a Python script
python3 << 'PYEOF'
import csv
import random

random.seed(42)

blocks = [
    (1, 'RANDOM', 410),
    (2, 'SEQUENCED', 380),
    (3, 'SEQUENCED', 350),
    (4, 'SEQUENCED', 335),
    (5, 'SEQUENCED', 325),
    (6, 'RANDOM', 395),
    (7, 'SEQUENCED', 340),
    (8, 'SEQUENCED', 335)
]

sequence = [4, 2, 3, 1, 3, 4, 2, 1, 4, 3, 1, 2]
trials_per_block = 96

rows = []

# Generate 15 valid participants
for pid_num in range(1, 16):
    pid = f"p{pid_num:02d}"
    intercept = random.uniform(-40, 40)
    learning_rate = random.uniform(0.7, 1.3)
    
    for block_num, block_type, base_rt in blocks:
        # Apply individual differences to block RTs
        if block_type == 'SEQUENCED':
            expected_rt = base_rt * learning_rate + intercept
        else:
            expected_rt = base_rt + intercept
            
        for trial_num in range(1, trials_per_block + 1):
            # Position
            if block_type == 'SEQUENCED':
                pos = sequence[(trial_num - 1) % len(sequence)]
            else:
                pos = random.choice([1, 2, 3, 4])
                
            # Error simulation (~4.5% error rate, typically faster RTs on errors)
            correct = 0 if random.random() < 0.045 else 1
            
            # RT generation
            rt = expected_rt + random.gauss(0, 50)
            if correct == 0:
                rt -= random.uniform(20, 80) # Errors are often fast guesses
                
            rt = max(150, min(rt, 1000)) # Bound RTs realistically
            
            rows.append({
                'participant': pid,
                'block': block_num,
                'block_type': block_type,
                'trial': trial_num,
                'position': pos,
                'rt_ms': round(rt, 1),
                'correct': correct
            })

# Inject corrupted participant (p99)
for block_num, block_type, base_rt in blocks:
    for trial_num in range(1, trials_per_block + 1):
        if block_type == 'SEQUENCED':
            pos = sequence[(trial_num - 1) % len(sequence)]
        else:
            pos = random.choice([1, 2, 3, 4])
            
        rows.append({
            'participant': 'p99',
            'block': block_num,
            'block_type': block_type,
            'trial': trial_num,
            'position': pos,
            'rt_ms': 250.0, # Zero variance
            'correct': 1    # Perfect accuracy
        })

with open('/home/ga/pebl/data/srtt_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant', 'block', 'block_type', 'trial', 'position', 'rt_ms', 'correct'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {len(rows)} trials for srtt_data.csv")
PYEOF

chown ga:ga /home/ga/pebl/data/srtt_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === SRTT Implicit Learning Analysis ===; echo; echo Data file: ~/pebl/data/srtt_data.csv; echo Output target: ~/pebl/analysis/srtt_report.json; echo; bash' > /tmp/srtt_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== srtt_implicit_learning_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/srtt_data.csv"
echo "Expected output: /home/ga/pebl/analysis/srtt_report.json"