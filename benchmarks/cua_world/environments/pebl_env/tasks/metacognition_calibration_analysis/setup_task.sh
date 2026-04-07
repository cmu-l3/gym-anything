#!/bin/bash
set -e
echo "=== Setting up metacognition_calibration_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

echo "Generating empirical metacognitive dataset..."
# Generate a highly realistic dataset based on empirical SDT parameters
python3 << 'PYEOF'
import csv
import random

random.seed(42)
domains = ['memory'] * 50 + ['perceptual'] * 50

rows = []
for i in range(1, 26):
    pid = f"sub-{i:02d}"
    for t in range(1, 101):
        domain = domains[t-1]
        
        # Simulate timeouts (missing data)
        if random.random() < 0.04:
            rows.append({
                'participant_id': pid,
                'trial_num': t,
                'task_domain': domain,
                'correct': -1,
                'confidence': 0
            })
            continue
            
        # Realistic accuracy (around 75%)
        correct = 1 if random.random() < 0.75 else 0
        
        # Confidence resolution based on correctness (Type 2 performance)
        if correct == 1:
            conf = int(random.triangular(50, 100, 85))
        else:
            conf = int(random.triangular(50, 100, 65))
            
        rows.append({
            'participant_id': pid,
            'trial_num': t,
            'task_domain': domain,
            'correct': correct,
            'confidence': conf
        })

# Inject corrupted participant (sub-99) with impossible confidence ratings
pid = "sub-99"
for t in range(1, 101):
    domain = domains[t-1]
    
    correct = 1 if random.random() < 0.75 else 0
    conf = int(random.triangular(50, 100, 80))
    
    # Hardware artifact injections
    if t == 15: conf = 20
    if t == 42: conf = 0
    if t == 88: conf = 35
    
    rows.append({
        'participant_id': pid,
        'trial_num': t,
        'task_domain': domain,
        'correct': correct,
        'confidence': conf
    })

with open('/home/ga/pebl/data/metacognition_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'trial_num', 'task_domain', 'correct', 'confidence'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Written {len(rows)} rows to /home/ga/pebl/data/metacognition_data.csv")
PYEOF

chown ga:ga /home/ga/pebl/data/metacognition_data.csv
chmod 644 /home/ga/pebl/data/metacognition_data.csv

# Get ga user's DBUS session address for GUI launching
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open terminal and text editor for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=100x30 -- bash -c 'echo === Metacognition Calibration Analysis ===; echo; echo Data file: ~/pebl/data/metacognition_data.csv; echo Output target: ~/pebl/analysis/metacognition_report.json; echo; bash' > /tmp/task_terminal.log 2>&1 &"
sleep 2
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/data/metacognition_data.csv > /tmp/gedit.log 2>&1 &"

# Ensure windows are visible
for i in {1..15}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "gedit" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="