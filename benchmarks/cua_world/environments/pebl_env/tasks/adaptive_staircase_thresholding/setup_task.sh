#!/bin/bash
# Setup for adaptive_staircase_thresholding task
# Generates realistic 2-down/1-up staircase data based on psychometric functions

set -e
echo "=== Setting up adaptive_staircase_thresholding task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create required directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic psychophysics data deterministically
python3 << 'PYEOF'
import csv
import random
import math

# Use fixed seed so verifier and agent see the exact same data
random.seed(4242)

# Generate 20 normal participants, 2 corrupted
participants = [f"sub-{i:02d}" for i in range(1, 23)]
participants.remove("sub-04")
participants.remove("sub-22")
participants.append("sub-04") # Corrupted: fails to converge
participants.append("sub-99") # Corrupted: impossibly fast RT

rows = []
for p in participants:
    C = 80.0
    # True underlying threshold
    T = random.uniform(15.0, 35.0) 
    consecutive_correct = 0
    
    for t in range(1, 61):
        # Determine RT and Accuracy based on participant profile
        if p == "sub-04":
            # Random responding (fails to converge)
            correct = 1 if random.random() < 0.4 else 0
            rt = random.randint(300, 800)
        elif p == "sub-99":
            # Impossibly fast RT (auto-responder)
            prob = 0.5 + 0.5 / (1.0 + math.exp(-(C - T)/3.0))
            correct = 1 if random.random() < prob else 0
            rt = random.randint(40, 80)
        else:
            # Normal participant
            prob = 0.5 + 0.5 / (1.0 + math.exp(-(C - T)/3.0))
            correct = 1 if random.random() < prob else 0
            rt = int(random.gauss(500, 100))
            rt = max(160, rt) # Ensure normal RTs are > 150
            
        rows.append({
            "participant_id": p,
            "trial": t,
            "target_contrast": round(C, 1),
            "response_correct": correct,
            "rt_ms": rt
        })
        
        # 2-down/1-up Staircase logic
        if correct:
            consecutive_correct += 1
            if consecutive_correct == 2:
                C = max(1.0, C - 4.0)
                consecutive_correct = 0
        else:
            consecutive_correct = 0
            C = min(100.0, C + 4.0)

# Write out the dataset
file_path = '/home/ga/pebl/data/contrast_staircase_data.csv'
with open(file_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "target_contrast", "response_correct", "rt_ms"])
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated psychophysics data for {len(participants)} participants.")
PYEOF

chown ga:ga /home/ga/pebl/data/contrast_staircase_data.csv

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Get ga user's DBUS session address for opening terminal
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Adaptive Staircase Thresholding Analysis ===; echo; echo Data file: ~/pebl/data/contrast_staircase_data.csv; echo Output target: ~/pebl/analysis/staircase_report.json; echo; bash' > /tmp/staircase_terminal.log 2>&1 &"

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

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== adaptive_staircase_thresholding setup complete ==="