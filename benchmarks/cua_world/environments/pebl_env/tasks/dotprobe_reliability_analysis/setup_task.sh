#!/bin/bash
echo "=== Setting up dotprobe_reliability_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic psychometric data using a domain-specific generator
# Simulates Ex-Gaussian RT distributions and realistic attentional bias reliability paradox
cat > /tmp/generate_dotprobe.py << 'EOF'
import csv
import random

random.seed(101)  # Fixed seed for deterministic ground truth
rows = []

# Generate 40 valid participants
for i in range(1, 41):
    pid = f"sub-{i:02d}"
    base_rt = random.uniform(350, 500)
    true_ab = random.gauss(15, 20)  # Individual differences in attentional bias
    
    # 80 filler, 40 congruent, 40 incongruent
    conditions = ['filler'] * 80 + ['congruent'] * 40 + ['incongruent'] * 40
    random.shuffle(conditions)
    
    for trial_num, cond in enumerate(conditions, 1):
        stim = 'neutral_neutral' if cond == 'filler' else 'threat_neutral'
        
        # Realistic accuracy ~95%
        correct = 1 if random.random() < 0.95 else 0
        
        # Ex-Gaussian RT simulation
        rt = base_rt + random.expovariate(1/80.0)
        if cond == 'incongruent':
            rt += true_ab
            
        # Motor noise
        rt += random.gauss(0, 15)
        
        # Occasional outliers (too fast or too slow)
        if random.random() < 0.02:
            rt = random.choice([random.uniform(100, 190), random.uniform(1100, 1500)])
            
        rows.append({
            'participant_id': pid,
            'trial_num': trial_num,
            'stimulus_type': stim,
            'probe_location': random.choice(['left', 'right']),
            'threat_location': random.choice(['left', 'right', 'none']),
            'congruency': cond,
            'correct': correct,
            'rt_ms': round(rt, 1)
        })

# Generate contaminated participant (sub-99)
conditions = ['filler'] * 80 + ['congruent'] * 40 + ['incongruent'] * 40
random.shuffle(conditions)
for trial_num, cond in enumerate(conditions, 1):
    stim = 'neutral_neutral' if cond == 'filler' else 'threat_neutral'
    # 50% chance accuracy (random clicking script)
    correct = 1 if random.random() < 0.50 else 0
    rt = random.uniform(150, 900)
    rows.append({
        'participant_id': 'sub-99',
        'trial_num': trial_num,
        'stimulus_type': stim,
        'probe_location': random.choice(['left', 'right']),
        'threat_location': random.choice(['left', 'right', 'none']),
        'congruency': cond,
        'correct': correct,
        'rt_ms': round(rt, 1)
    })

with open('/home/ga/pebl/data/dotprobe_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=[
        'participant_id', 'trial_num', 'stimulus_type', 
        'probe_location', 'threat_location', 'congruency', 
        'correct', 'rt_ms'
    ])
    writer.writeheader()
    writer.writerows(rows)
EOF

# Run generator and clean up
python3 /tmp/generate_dotprobe.py
rm /tmp/generate_dotprobe.py
chown ga:ga /home/ga/pebl/data/dotprobe_data.csv

# Launch a terminal and gedit for the agent
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Dot-Probe Reliability Analysis ===; echo; echo Data file: ~/pebl/data/dotprobe_data.csv; echo Output target: ~/pebl/analysis/dotprobe_reliability.json; echo; bash' > /dev/null 2>&1 &"

# Open the data file so the agent can inspect it immediately
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/data/dotprobe_data.csv > /dev/null 2>&1 &"

# Wait and arrange windows
sleep 3
WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l | grep -i "gedit" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="