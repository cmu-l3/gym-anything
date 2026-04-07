#!/bin/bash
set -e
echo "=== Setting up gng_inhibitory_control_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic human Go/No-Go data matching typical OpenNeuro distributions
python3 << 'PYEOF'
import csv, random, math

# Setup empirical distributions
np_random = random.Random(888)
rows = []

# 1) Generate 25 valid human participants
for i in range(1, 26):
    pid = f"sub-{i:02d}"
    
    # Inter-individual variability
    base_rt = np_random.gauss(340, 25)
    rt_sigma = np_random.gauss(40, 5)
    p_hit = np_random.uniform(0.92, 1.0) # High go accuracy
    p_fa = np_random.uniform(0.05, 0.35) # Hard to inhibit NOGO
    
    for t in range(1, 101):
        # 80% GO, 20% NOGO
        condition = 'GO' if np_random.random() < 0.8 else 'NOGO'
        
        if condition == 'GO':
            response = 1 if np_random.random() < p_hit else 0
            rt = int(np_random.lognormvariate(math.log(base_rt), rt_sigma/base_rt)) if response == 1 else 0
        else:
            response = 1 if np_random.random() < p_fa else 0
            # Commission errors tend to be faster than valid hits
            rt = int(np_random.lognormvariate(math.log(base_rt - 30), rt_sigma/base_rt)) if response == 1 else 0
            
        if response == 1:
            rt = max(150, min(800, rt))
            
        rows.append({
            'participant_id': pid,
            'trial': t,
            'condition': condition,
            'response': response,
            'rt_ms': rt
        })

# 2) Inject sub-99 (Contamination artifact: stuck spacebar / book on keyboard)
for t in range(1, 101):
    condition = 'GO' if np_random.random() < 0.8 else 'NOGO'
    response = 1 # 100% respond
    rt = round(np_random.uniform(10, 25)) # Impossibly fast, no cognitive processing
    
    rows.append({
        'participant_id': 'sub-99',
        'trial': t,
        'condition': condition,
        'response': response,
        'rt_ms': rt
    })

# Write to file
file_path = '/home/ga/pebl/data/gng_data.csv'
with open(file_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'trial', 'condition', 'response', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated GNG dataset with {len(rows)} trials.")
PYEOF

chown ga:ga /home/ga/pebl/data/gng_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Go/No-Go Inhibitory Control Analysis ===; echo; echo Data file: ~/pebl/data/gng_data.csv; echo Output target: ~/pebl/analysis/gng_report.json; echo; bash' > /tmp/gng_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== gng_inhibitory_control_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/gng_data.csv"