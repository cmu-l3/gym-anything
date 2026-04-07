#!/bin/bash
# Setup for freerecall_serial_position_analysis task
# Generates a realistic, randomized dataset for the agent to analyze.

set -e
echo "=== Setting up freerecall_serial_position_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate unique randomized dataset
python3 << 'PYEOF'
import csv
import random
import time

# Use current time to make dataset unique per run (anti-gaming)
random.seed(int(time.time()))

# Base recall probabilities mimicking the serial position curve (U-shape)
base_probs = [0.85, 0.78, 0.65, 0.50, 0.40, 0.35, 0.32, 0.30, 0.30, 0.32, 0.40, 0.55, 0.75, 0.88, 0.95]

out_path = '/home/ga/pebl/data/freerecall_data.csv'

with open(out_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['participant_id', 'list_index', 'study_position', 'word', 'recalled', 'recall_rt_ms'])
    
    # 30 valid participants
    for p in range(1, 31):
        pid = f"sub-{p:02d}"
        
        # Participant-level skill offset (-0.15 to +0.15)
        p_offset = random.uniform(-0.15, 0.15)
        
        for l_idx in range(1, 11):
            for pos in range(1, 16):
                # Calculate probability with participant offset and slight trial noise
                prob = base_probs[pos-1] + p_offset + random.uniform(-0.05, 0.05)
                prob = max(0.0, min(1.0, prob))
                
                recalled = 1 if random.random() < prob else 0
                rt = int(random.uniform(800, 2500)) if recalled else 0
                word = f"WORD_{l_idx}_{pos}"
                
                writer.writerow([pid, l_idx, pos, word, recalled, rt])

    # 1 contaminated participant (sub-999) who skipped the experiment
    # 0% recall, impossibly fast response times (held down Enter key)
    pid = "sub-999"
    for l_idx in range(1, 11):
        for pos in range(1, 16):
            recalled = 0
            rt = int(random.uniform(10, 35)) # Mean RT will be ~22ms (< 50ms)
            word = f"WORD_{l_idx}_{pos}"
            writer.writerow([pid, l_idx, pos, word, recalled, rt])

print(f"Generated realistic dataset at {out_path}")
PYEOF

chown ga:ga /home/ga/pebl/data/freerecall_data.csv
chmod 644 /home/ga/pebl/data/freerecall_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Free Recall Serial Position Analysis ===; echo; echo Data file: ~/pebl/data/freerecall_data.csv; echo Output target: ~/pebl/analysis/serial_position_report.json; echo; bash' > /tmp/terminal_launch.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== freerecall_serial_position_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/freerecall_data.csv"
echo "Expected output: /home/ga/pebl/analysis/serial_position_report.json"