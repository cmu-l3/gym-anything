#!/bin/bash
set -e
echo "=== Setting up vwm_color_reproduction_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic VWM continuous reproduction data with one contaminated participant
python3 << 'EOF'
import csv
import random
import numpy as np

random.seed(42)
np.random.seed(42)

set_sizes = [1, 2, 4, 8]
participants = [f"s{i:02d}" for i in range(1, 16)] + ["s99"]

rows = []

for p in participants:
    for ss in set_sizes:
        if p == "s99":
            guess_rate = 1.0 
            sd = 100 
        else:
            if ss == 1:
                guess_rate, sd = 0.02, 12
            elif ss == 2:
                guess_rate, sd = 0.05, 16
            elif ss == 4:
                guess_rate, sd = 0.15, 25
            else:
                guess_rate, sd = 0.35, 35
                
            guess_rate = max(0, min(1, guess_rate + random.uniform(-0.01, 0.02)))
            sd = sd + random.uniform(-2, 3)
            
        for t in range(1, 51):
            target = random.randint(0, 359)
            
            if random.random() < guess_rate:
                response = random.randint(0, 359)
            else:
                error = round(np.random.normal(0, sd))
                response = int((target + error) % 360)
                
            rt = int(np.random.normal(800 + ss * 100, 150))
            if p == "s99":
                rt = int(np.random.normal(300, 50))
                
            rows.append({
                'participant_id': p,
                'trial': t,
                'set_size': ss,
                'target_color': target,
                'response_color': response,
                'rt_ms': max(150, rt)
            })

with open('/home/ga/pebl/data/color_wheel_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'trial', 'set_size', 'target_color', 'response_color', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)
EOF

chown ga:ga /home/ga/pebl/data/color_wheel_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address for opening UI
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Visual Working Memory Analysis ===; echo; echo Data file: ~/pebl/data/color_wheel_data.csv; echo Output target: ~/pebl/analysis/vwm_report.json; echo; bash' > /tmp/vwm_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== vwm_color_reproduction_analysis setup complete ==="