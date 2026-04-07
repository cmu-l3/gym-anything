#!/bin/bash
set -e
echo "=== Setting up visual_search_slope_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate highly realistic visual search data matching established Ex-Gaussian models 
cat > /tmp/generate_data.py << 'EOF'
import csv
import random

random.seed(42)

def generate_rt(base, slope, set_size, error_rate, is_target_present):
    mu = base + slope * set_size
    sigma = 50
    tau = 100
    rt = random.gauss(mu, sigma) + random.expovariate(1/tau)
    correct = 1 if random.random() > error_rate else 0
    if not correct:
        rt = random.gauss(mu - 50, sigma) + random.expovariate(1/tau)
    return max(150, int(rt)), correct

participants = [f"sub-{i:02d}" for i in range(1, 19)]
conditions = ['feature', 'conjunction']
target_present = [1, 0]
set_sizes = [4, 8, 16, 32]
trials_per_cell = 10

rows = []
for p in participants:
    for cond in conditions:
        for tp in target_present:
            for sz in set_sizes:
                for t in range(trials_per_cell):
                    if cond == 'feature':
                        slope = 0.5 if tp == 1 else 1.2
                        base = 400 if tp == 1 else 450
                        err = 0.02 if tp == 1 else 0.01
                    else:
                        slope = 25.0 if tp == 1 else 50.0
                        base = 450 if tp == 1 else 500
                        err = 0.10 if tp == 1 else 0.05
                    
                    p_base = base + random.gauss(0, 50)
                    p_slope = slope * random.uniform(0.8, 1.2)
                    
                    rt, correct = generate_rt(p_base, p_slope, sz, err, tp)
                    
                    rows.append({
                        'participant_id': p,
                        'condition': cond,
                        'set_size': sz,
                        'target_present': tp,
                        'trial': t + 1,
                        'response_correct': correct,
                        'rt_ms': rt
                    })

# Add sub-99 (Button masher, 0% target_present accuracy, flat RT)
for cond in conditions:
    for tp in target_present:
        for sz in set_sizes:
            for t in range(trials_per_cell):
                correct = 1 if tp == 0 else 0
                rt = int(random.gauss(200, 20))
                rows.append({
                    'participant_id': 'sub-99',
                    'condition': cond,
                    'set_size': sz,
                    'target_present': tp,
                    'trial': t + 1,
                    'response_correct': correct,
                    'rt_ms': rt
                })

with open('/home/ga/pebl/data/visual_search_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'condition', 'set_size', 'target_present', 'trial', 'response_correct', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)
EOF

python3 /tmp/generate_data.py
chown ga:ga /home/ga/pebl/data/visual_search_data.csv
rm /tmp/generate_data.py

date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Visual Search Slope Analysis ===; echo; echo Data file: ~/pebl/data/visual_search_data.csv; echo Output target: ~/pebl/analysis/visual_search_report.json; echo; bash' > /tmp/vs_terminal.log 2>&1 &"

for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "Setup complete"