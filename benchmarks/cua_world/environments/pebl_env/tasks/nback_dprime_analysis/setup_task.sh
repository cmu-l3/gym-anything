#!/bin/bash
# Setup for nback_dprime_analysis task
# Generates highly realistic N-back dataset with deterministic signal detection properties,
# edge-case perfect performance (for log-linear correction checks),
# and one injected participant with a 100% response rate (button masher).

set -e
echo "=== Setting up nback_dprime_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create required directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic N-back data using Python
python3 << 'PYEOF'
import csv
import random

random.seed(42)
rows = []

# Generate 24 "real" participants
for i in range(1, 25):
    pid = f"s{i:02d}"
    
    for level in [1, 2, 3]:
        # Realistic performance degrades as N-back level increases
        if level == 1:
            hr_prob, far_prob = 0.92, 0.08
        elif level == 2:
            hr_prob, far_prob = 0.80, 0.18
        else:
            hr_prob, far_prob = 0.65, 0.35
            
        # Add random noise for individual differences
        hr_prob = min(0.99, max(0.01, hr_prob + random.uniform(-0.1, 0.1)))
        far_prob = min(0.99, max(0.01, far_prob + random.uniform(-0.1, 0.1)))
        
        # EXACT EDGE CASES for verification (forces the use of extreme value corrections)
        if pid == "s01" and level == 1:
            hr_prob, far_prob = 1.0, 0.0  # Perfect performance (HR=1, FAR=0)
        if pid == "s02" and level == 3:
            hr_prob, far_prob = 0.0, 1.0  # Inverse performance (HR=0, FAR=1)

        targets = [1]*20 + [0]*40
        random.shuffle(targets)
        
        for t, is_target in enumerate(targets, 1):
            rt = int(random.gauss(500 + level * 120, 100))
            rt = max(200, min(1500, rt))
            
            if is_target == 1:
                resp = 1 if random.random() < hr_prob else 0
            else:
                resp = 1 if random.random() < far_prob else 0
                
            # Override for the forced edge cases
            if pid == "s01" and level == 1:
                resp = is_target
            if pid == "s02" and level == 3:
                resp = 1 - is_target
                
            rows.append({
                'subject_id': pid,
                'nback_level': level,
                'trial_num': t,
                'is_target': is_target,
                'response': resp,
                'rt_ms': rt
            })

# Inject Participant s99 (Button Masher)
# Always presses "Match" (response=1), yielding 100% HR and 100% FAR -> Overall FAR = 1.0 > 0.80 exclusion criteria
for level in [1, 2, 3]:
    targets = [1]*20 + [0]*40
    random.shuffle(targets)
    for t, is_target in enumerate(targets, 1):
        rt = int(random.gauss(280, 40))  # Unnaturally fast and consistent RT
        rt = max(100, min(500, rt))
        rows.append({
            'subject_id': 's99',
            'nback_level': level,
            'trial_num': t,
            'is_target': is_target,
            'response': 1,
            'rt_ms': rt
        })

with open('/home/ga/pebl/data/nback_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['subject_id', 'nback_level', 'trial_num', 'is_target', 'response', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Dataset generated successfully at ~/pebl/data/nback_data.csv with {len(rows)} trials.")
PYEOF

chown ga:ga /home/ga/pebl/data/nback_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === N-Back Working Memory Sensitivity Analysis ===; echo; echo Data file: ~/pebl/data/nback_data.csv; echo Output target: ~/pebl/analysis/nback_report.json; echo; bash' > /tmp/nback_terminal.log 2>&1 &"

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

echo "=== nback_dprime_analysis setup complete ==="