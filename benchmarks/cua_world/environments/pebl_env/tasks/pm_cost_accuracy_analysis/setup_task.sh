#!/bin/bash
# Setup for pm_cost_accuracy_analysis task
# Generates a highly realistic Prospective Memory (PM) dataset with known ground truth.
# Injects one automated macro participant (sub-99).

set -e
echo "=== Setting up pm_cost_accuracy_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Record task start time
date +%s > /tmp/task_start_timestamp

# Generate realistic dataset
python3 << 'PYEOF'
import csv
import random

random.seed(42) # Fixed seed ensures deterministic ground truth

rows = []

# Generate 20 valid participants
for i in range(1, 21):
    pid = f"sub-{i:02d}"
    
    # Participant-specific baseline and PM cost parameters
    base_rt = random.uniform(450, 650)
    pm_cost = random.uniform(80, 220) # PM Cost: slowing due to holding an intention
    
    # 1. Baseline block (50 ongoing trials)
    for t in range(1, 51):
        rt = max(150, random.gauss(base_rt, 80))
        correct = 1 if random.random() < random.uniform(0.90, 0.98) else 0
        rows.append({
            'participant_id': pid, 
            'block_type': 'baseline', 
            'trial_type': 'ongoing', 
            'rt_ms': round(rt, 1), 
            'correct': correct
        })
        
    # 2. PM Block (40 ongoing trials, 10 PM cue trials)
    pm_trials = ['ongoing'] * 40 + ['pm_cue'] * 10
    random.shuffle(pm_trials)
    
    for t_type in pm_trials:
        if t_type == 'ongoing':
            rt = max(150, random.gauss(base_rt + pm_cost, 90))
            correct = 1 if random.random() < random.uniform(0.85, 0.96) else 0
        else:
            # PM Cues are typically slower and have varying accuracy (Hit Rate)
            rt = max(200, random.gauss(base_rt + pm_cost + 150, 120))
            correct = 1 if random.random() < random.uniform(0.55, 0.95) else 0
            
        rows.append({
            'participant_id': pid, 
            'block_type': 'pm_block', 
            'trial_type': t_type, 
            'rt_ms': round(rt, 1), 
            'correct': correct
        })

# Generate 1 contaminated participant (automated responder)
for b_type, t_counts in [('baseline', ['ongoing']*50), ('pm_block', ['ongoing']*40 + ['pm_cue']*10)]:
    for t_type in t_counts:
        rt = random.uniform(20.0, 30.0) # Impossibly fast, uniform
        correct = random.choice([0, 1]) # Random guessing
        rows.append({
            'participant_id': 'sub-99', 
            'block_type': b_type, 
            'trial_type': t_type, 
            'rt_ms': round(rt, 1), 
            'correct': correct
        })

with open('/home/ga/pebl/data/prospective_memory_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'block_type', 'trial_type', 'rt_ms', 'correct'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Dataset generated with {len(rows)} trials.")
PYEOF

chown ga:ga /home/ga/pebl/data/prospective_memory_data.csv
chmod 644 /home/ga/pebl/data/prospective_memory_data.csv

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent to start working
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Prospective Memory Cost Analysis ===; echo; echo Data file: ~/pebl/data/prospective_memory_data.csv; echo Output target: ~/pebl/analysis/pm_report.json; echo; bash' > /tmp/pm_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== pm_cost_accuracy_analysis setup complete ==="