#!/bin/bash
set -e
echo "=== Setting up navon_global_precedence_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate dynamic task dataset
python3 << 'PYEOF'
import csv
import random

random.seed(42)
participants = [f"sub-{i:02d}" for i in range(1, 25)] + ["sub-99"]

rows = []
for p in participants:
    is_anomaly = (p == "sub-99")
    
    # 4 blocks of 40 trials = 160 trials per participant. 
    # Blocks 1 & 3: global focus. Blocks 2 & 4: local focus.
    for block in range(1, 5):
        focus = 'global' if block in (1, 3) else 'local'
        for t in range(40):
            congruency = 'congruent' if random.random() < 0.5 else 'incongruent'
            
            # Base RTs with interference logic
            if focus == 'global':
                base_rt = random.gauss(500, 50)
                if congruency == 'incongruent':
                    base_rt += random.gauss(15, 5) # Local interference
            else:
                base_rt = random.gauss(550, 50)
                if congruency == 'incongruent':
                    base_rt += random.gauss(60, 10) # Global interference
            
            # Accuracy logic for normal vs anomaly
            if is_anomaly:
                if focus == 'global':
                    correct = 1 if random.random() < 0.95 else 0
                else:
                    # Anomaly fails to switch to local focus
                    if congruency == 'congruent':
                        correct = 1 if random.random() < 0.95 else 0
                    else:
                        correct = 1 if random.random() < 0.05 else 0
            else:
                correct = 1 if random.random() < 0.95 else 0
            
            rt = int(base_rt)
            if not correct and not is_anomaly:
                rt += random.randint(100, 300)
                
            # Stimuli generation
            if congruency == 'congruent':
                letter = random.choice(['H', 'S'])
                stim_g = letter
                stim_l = letter
            else:
                stim_g = 'H' if random.random() < 0.5 else 'S'
                stim_l = 'S' if stim_g == 'H' else 'H'

            rows.append({
                'participant_id': p,
                'block_num': block,
                'attention_focus': focus,
                'stim_global': stim_g,
                'stim_local': stim_l,
                'congruency': congruency,
                'correct': correct,
                'rt_ms': rt
            })

with open('/home/ga/pebl/data/navon_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'block_num', 'attention_focus', 'stim_global', 'stim_local', 'congruency', 'correct', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga /home/ga/pebl/data/navon_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address for proper UI launch
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Navon Global Precedence Analysis ===; echo; echo Data file: ~/pebl/data/navon_data.csv; echo; echo Expected Outputs:; echo 1. ~/pebl/analysis/navon_report.json; echo 2. ~/pebl/analysis/navon_interaction_plot.png; echo; bash' > /tmp/navon_terminal.log 2>&1 &"

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

# Take initial state screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== navon_global_precedence_analysis setup complete ==="