#!/bin/bash
# Setup for change_detection_k_analysis task
# Generates realistic change detection VWM data based on Cowan (2001) / Rouder (2011) parameters.
# Injects one participant (p25) with physiologically impossible perfect accuracy.

set -e
echo "=== Setting up change_detection_k_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate dataset programmatically
cat > /tmp/generate_data.py << 'EOF'
import csv
import random

random.seed(42)

set_sizes = [2, 4, 6, 8]
trials_per_condition = 20 # 20 change present, 20 change absent

rows = []

# Generate 20 real participants with physiologically plausible capacity constraints
for i in range(1, 21):
    pid = f"p{i:02d}"
    # True capacity roughly between 1.5 and 5.5 items
    capacity = random.uniform(1.5, 5.5)
    
    for ss in set_sizes:
        # Effective K is bounded by display set size
        expected_k = min(capacity, ss) + random.uniform(-0.4, 0.4)
        expected_k = max(0.1, expected_k)
        
        # In single-probe change detection, K = S * (H - F) => (H - F) = K / S
        diff = expected_k / ss
        diff = max(0.0, min(1.0, diff))
        
        # Pick realistic False Alarm rate
        F = random.uniform(0.02, 0.20)
        H = diff + F
        
        # Cap at 0.98 for realistic human error
        if H > 0.98:
            H = random.uniform(0.90, 0.98)
            F = H - diff
            if F < 0: F = 0.0
            
        # Generate individual trials
        for t in range(1, trials_per_condition * 2 + 1):
            change_present = 1 if t <= trials_per_condition else 0
            if change_present == 1:
                response = 1 if random.random() < H else 0
            else:
                response = 1 if random.random() < F else 0
                
            rt = int(random.gauss(600 + ss * 40, 150))
            rt = max(250, rt)
            
            rows.append({
                'participant_id': pid,
                'set_size': ss,
                'trial': t,
                'change_present': change_present,
                'response': response,
                'rt_ms': rt
            })

# Inject corrupted participant (p25) - 100% accuracy simulating auto-clicker
for ss in set_sizes:
    for t in range(1, trials_per_condition * 2 + 1):
        change_present = 1 if t <= trials_per_condition else 0
        response = change_present  # Perfect performance (H=1.0, F=0.0) -> K=set_size
        rt = int(random.uniform(200, 350))
        rows.append({
            'participant_id': 'p25',
            'set_size': ss,
            'trial': t,
            'change_present': change_present,
            'response': response,
            'rt_ms': rt
        })

with open('/home/ga/pebl/data/change_detection_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'set_size', 'trial', 'change_present', 'response', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)
EOF

python3 /tmp/generate_data.py
chown ga:ga /home/ga/pebl/data/change_detection_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Visual Working Memory Capacity Analysis ===; echo; echo Data file: ~/pebl/data/change_detection_data.csv; echo Output target: ~/pebl/analysis/k_capacity_report.json; echo; bash' > /tmp/vwm_terminal.log 2>&1 &"

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

echo "=== change_detection_k_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/change_detection_data.csv"
echo "Expected output: /home/ga/pebl/analysis/k_capacity_report.json"