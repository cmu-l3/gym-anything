#!/bin/bash
set -e
echo "=== Setting up subitizing_enumeration_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create directories and clear previous state
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
rm -f /home/ga/pebl/analysis/subitizing_report.json 2>/dev/null || true
chown -R ga:ga /home/ga/pebl

echo "Generating highly realistic psychometric enumeration dataset..."
# Generate domain-specific dataset
python3 << 'PYEOF'
import csv
import random

# Use a fixed seed so the verifier can also perfectly reproduce/verify the dataset
random.seed(8675309)
rows = []

# Generate 18 real participants
for i in range(1, 19):
    pid = f"sub-{i:02d}"
    
    # Individual differences (baselines and cognitive processing speeds)
    base_rt = random.gauss(320, 30)
    sub_slope = random.gauss(60, 10)     # Subitizing limit parallel processing (~60ms/item)
    count_slope = random.gauss(290, 35)  # Serial counting speed (~290ms/item)
    
    # 10 blocks of 1-9 dots
    for block in range(1, 11):
        for dots in range(1, 10):
            # Calculate underlying RT via piecewise linear model
            if dots <= 3:
                expected_rt = base_rt + sub_slope * dots
            elif dots == 4:
                # Transition boundary
                expected_rt = base_rt + sub_slope * 3 + count_slope * 0.8
            else:
                expected_rt = base_rt + sub_slope * 3 + count_slope * (dots - 3)
            
            # Add log-normal-like noise
            rt = expected_rt + abs(random.gauss(0, 45))
            
            # Accuracy drops slightly for higher numbers
            if dots <= 4:
                correct = 1 if random.random() < 0.98 else 0
            else:
                correct = 1 if random.random() < (0.96 - (dots-5)*0.04) else 0
            
            # Responses
            if correct:
                resp = dots
            else:
                offset = random.choice([-1, 1, -2, 2])
                resp = max(1, min(9, dots + offset))
            
            rows.append({
                'participant_id': pid,
                'trial': (block-1)*9 + dots,
                'dot_count': dots,
                'response': resp,
                'correct': correct,
                'rt_ms': round(rt, 1)
            })

# Inject contaminated participant (sub-99) - "Response Masher"
for block in range(1, 11):
    for dots in range(1, 10):
        correct = 1 if dots == 1 else 0
        rows.append({
            'participant_id': 'sub-99',
            'trial': (block-1)*9 + dots,
            'dot_count': dots,
            'response': 1,
            'correct': correct,
            'rt_ms': round(random.gauss(115, 12), 1)
        })

# Sort by participant, then trial
rows.sort(key=lambda x: (x['participant_id'], x['trial']))

with open('/home/ga/pebl/data/enumeration_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'trial', 'dot_count', 'response', 'correct', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga /home/ga/pebl/data/enumeration_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=110x30 -- bash -c 'echo === Subitizing vs Counting Analysis ===; echo; echo Data file: ~/pebl/data/enumeration_data.csv; echo Output target: ~/pebl/analysis/subitizing_report.json; echo; bash' > /tmp/terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== setup complete ==="