#!/bin/bash
# Setup script for snarc_numerical_cognition_analysis task
# Dynamically generates a realistic dataset using ex-Gaussian distributions
# with a built-in mathematical SNARC effect, making it unique every run.

set -e
echo "=== Setting up snarc_numerical_cognition_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic SNARC data stochastically
python3 << 'PYEOF'
import csv
import random
import time

# Use current time to ensure data is uniquely generated each run (prevents hardcoding gaming)
random.seed(time.time())

def ex_gaussian(mu, sigma, tau):
    tau = max(tau, 1.0) # Prevent zero division
    return random.gauss(mu, sigma) + random.expovariate(1.0/tau)

participants = [f'sub-{i:02d}' for i in range(1, 21)]
blocks = [1, 2, 3] # 1=Practice, 2=Left/Odd, 3=Left/Even
trials_per_block = 64
numbers = [1, 2, 3, 4, 6, 7, 8, 9] # Standard 5-excluded parity set

rows = []
for p in participants:
    base_rt = random.uniform(450, 550)
    # Generate a realistic SNARC slope (-8 to -18 ms/digit)
    snarc_slope = random.uniform(-18, -8)
    
    for b in blocks:
        for t in range(trials_per_block):
            num = random.choice(numbers)
            parity = 'odd' if num % 2 != 0 else 'even'
            
            if b == 1:
                left_parity = 'odd' if random.random() > 0.5 else 'even'
            elif b == 2:
                left_parity = 'odd'
            else:
                left_parity = 'even'
                
            resp_hand = 'left' if parity == left_parity else 'right'
            
            # Embed SNARC effect: 
            # dRT (Right - Left) should linearly decrease with number.
            # Base it around the midpoint (5)
            dRT = snarc_slope * (num - 5.0)
            hand_modifier = 0.5 if resp_hand == 'right' else -0.5
            expected_rt = base_rt + hand_modifier * dRT
            
            rt = ex_gaussian(expected_rt, 40, 60)
            
            # Add error responses
            correct = 1 if random.random() > 0.08 else 0
            if not correct:
                resp_hand = 'right' if resp_hand == 'left' else 'left'
                rt += random.uniform(50, 150)
                
            # Truncate bounds
            rt = max(180, min(1800, rt))
            
            rows.append({
                'participant_id': p,
                'block': b,
                'trial': t+1,
                'number': num,
                'parity': parity,
                'response_hand': resp_hand,
                'correct': correct,
                'rt_ms': round(rt, 1)
            })

# Inject contaminated auto-responder participant
for b in blocks:
    for t in range(trials_per_block):
        num = random.choice(numbers)
        parity = 'odd' if num % 2 != 0 else 'even'
        rows.append({
            'participant_id': 'sub-99',
            'block': b,
            'trial': t+1,
            'number': num,
            'parity': parity,
            'response_hand': 'left' if random.random() > 0.5 else 'right',
            'correct': 1 if random.random() > 0.5 else 0,
            'rt_ms': 600.0 # Zero variance artifact
        })

with open('/home/ga/pebl/data/snarc_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'block', 'trial', 'number', 'parity', 'response_hand', 'correct', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga /home/ga/pebl/data/snarc_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address to launch terminal properly
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === SNARC Numerical Cognition Analysis ===; echo; echo Data file: ~/pebl/data/snarc_data.csv; echo Output target: ~/pebl/analysis/snarc_report.json; echo; bash' > /tmp/snarc_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== snarc_numerical_cognition_analysis setup complete ==="