#!/bin/bash
set -euo pipefail

echo "=== Setting up Gratton Conflict Adaptation Analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Generate a statistically accurate Simon Task dataset mimicking real human performance
# We use ex-Gaussian components to embed a mathematically precise Gratton effect
# along with post-error slowing phenomena.
python3 << 'PYEOF'
import csv
import random

random.seed(101) # Fixed seed for deterministic generation

def exgauss(mu, sigma, tau):
    # Approximation of an ex-Gaussian distribution for realistic RTs
    return mu + random.gauss(0, sigma) + random.expovariate(1.0/tau)

rows = []
# Generate 25 real human participants
for p in range(1, 26):
    pid = f"sub-{p:02d}"
    for b in range(1, 5): # 4 blocks
        prev_cong = None
        prev_acc = 1
        for t in range(1, 73): # 72 trials per block
            cong = 'C' if random.random() < 0.5 else 'I'
            
            # Base RTs mapping to the Gratton effect:
            # Conflict adaptation means CE is smaller after I than after C.
            # Example CE after C = 60ms; CE after I = 10ms.
            if prev_cong == 'C' and cong == 'C':
                acc = 1 if random.random() < 0.95 else 0
                rt = exgauss(360, 25, 40)
            elif prev_cong == 'C' and cong == 'I':
                acc = 1 if random.random() < 0.82 else 0
                rt = exgauss(420, 30, 50)
            elif prev_cong == 'I' and cong == 'C':
                acc = 1 if random.random() < 0.90 else 0
                rt = exgauss(390, 25, 45)
            elif prev_cong == 'I' and cong == 'I':
                acc = 1 if random.random() < 0.87 else 0
                rt = exgauss(400, 25, 45)
            else: # First trial of block
                acc = 1 if random.random() < 0.90 else 0
                rt = exgauss(385, 25, 45)

            # Introduce post-error slowing (agent must drop post-error trials to get the clean Gratton effect!)
            if prev_acc == 0:
                rt += random.uniform(50, 100)
                
            rt_ms = round(rt, 1)
            
            rows.append({
                'participant_id': pid,
                'block': b,
                'trial': t,
                'congruency': cong,
                'acc': acc,
                'rt_ms': rt_ms
            })
            
            prev_cong = cong
            prev_acc = acc

# Inject 1 contaminated bot participant (sub-999)
for b in range(1, 5):
    for t in range(1, 73):
        cong = 'C' if random.random() < 0.5 else 'I'
        acc = 1 if random.random() < 0.5 else 0
        rt_ms = round(random.uniform(20, 60), 1) # Impossibly fast choice RT
        rows.append({
            'participant_id': 'sub-999',
            'block': b,
            'trial': t,
            'congruency': cong,
            'acc': acc,
            'rt_ms': rt_ms
        })

with open('/home/ga/pebl/data/simon_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'block', 'trial', 'congruency', 'acc', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)
    
print(f"Generated {len(rows)} trials for 26 participants in simon_data.csv")
PYEOF

chown ga:ga /home/ga/pebl/data/simon_data.csv

# Get ga user's DBUS session address to launch terminal properly
GA_PID=$(pgrep -u ga -f gnome-session | head -1 || echo "")
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Simon Task Conflict Adaptation Analysis ===; echo; echo Data file: ~/pebl/data/simon_data.csv; echo Output target: ~/pebl/analysis/gratton_report.json; echo; bash' > /tmp/simon_terminal.log 2>&1 &"

# Maximize the terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1 || echo "")
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== Setup complete ==="