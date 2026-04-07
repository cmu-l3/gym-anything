#!/bin/bash
# Setup for mfft_cognitive_style_analysis task
# Generates realistic MFFT normative data with a domain-specific python generator
# matching standard empirical variance for 30 children + 1 corrupted artifact participant.

set -e
echo "=== Setting up MFFT Cognitive Style Analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Domain-specific generator to simulate empirical MFFT normative distributions
python3 << 'PYEOF'
import csv
import random

def generate_mfft_data():
    random.seed(42) # Fixed seed ensures perfectly reproducible ground truth
    rows = []
    
    # 30 valid participants
    for i in range(1, 31):
        pid = f"child-{i:02d}"
        quad = i % 4
        
        # Base parameters reflecting the 4 cognitive styles
        if quad == 0:
            base_rt = 4000; base_err_prob = 0.1 # Reflective
        elif quad == 1:
            base_rt = 1500; base_err_prob = 0.6 # Impulsive
        elif quad == 2:
            base_rt = 1500; base_err_prob = 0.1 # Fast-Accurate
        else:
            base_rt = 4000; base_err_prob = 0.6 # Slow-Inaccurate

        for t in range(1, 13):
            # Normal distribution of RT with minimum floor
            rt = max(500, random.gauss(base_rt, 500))
            
            # Simulated error counts based on probability
            err = 0
            while random.random() < base_err_prob and err < 5:
                err += 1
                
            rows.append({
                "participant_id": pid, 
                "trial": t, 
                "first_response_rt_ms": round(rt, 1), 
                "errors": err
            })

    # 1 contaminated participant (Mechanical button mashing artifact)
    for t in range(1, 13):
        rt = random.uniform(50, 120)
        err = random.randint(3, 6)
        rows.append({
            "participant_id": "child-99", 
            "trial": t, 
            "first_response_rt_ms": round(rt, 1), 
            "errors": err
        })

    return rows

rows = generate_mfft_data()

with open('/home/ga/pebl/data/mfft_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "first_response_rt_ms", "errors"])
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {len(rows)} trials of MFFT data.")
PYEOF

chown ga:ga /home/ga/pebl/data/mfft_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address to launch terminal properly
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === MFFT Cognitive Style Analysis ===; echo; echo Data file: ~/pebl/data/mfft_data.csv; echo Output target: ~/pebl/analysis/mfft_cognitive_styles.json; echo; bash' > /tmp/mfft_terminal.log 2>&1 &"

# Wait and maximize terminal window
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== MFFT setup complete ==="