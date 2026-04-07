#!/bin/bash
# Setup for prp_bottleneck_analysis task
# Generates a realistic PRP dual-task dataset using Ex-Gaussian RT distributions
# and the canonical central bottleneck model. Injects participant P99 with task non-compliance.

set -e
echo "=== Setting up prp_bottleneck_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate the highly realistic PRP dataset using Python
# This mimics Open Science Framework replication data for Pashler's paradigm
python3 << 'PYEOF'
import csv
import random

random.seed(42)  # Fixed seed for verifiable ground truth calculation later

def ex_gauss(mu, sigma, tau):
    """Generate reaction time from an Ex-Gaussian distribution."""
    return mu + random.gauss(0, sigma) + random.expovariate(1.0 / tau)

output_path = '/home/ga/pebl/data/prp_dual_task_data.csv'
soas = [50, 150, 300, 500, 900]

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['participant_id', 'trial', 'soa_ms', 't1_correct', 't2_correct', 'rt1_ms', 'rt2_ms'])

    # Generate 20 valid participants
    for p in range(1, 21):
        pid = f'P{p:02d}'
        base_rt1 = random.uniform(400, 550)  # Individual differences in Task 1 baseline
        base_rt2 = random.uniform(380, 500)  # Individual differences in Task 2 baseline
        
        for t in range(1, 101):
            soa = random.choice(soas)
            
            # Genuine human accuracy (T1 ~ 95%, T2 ~ 92%)
            t1_c = 1 if random.random() < 0.95 else 0
            t2_c = 1 if random.random() < 0.92 else 0
            
            # RT1 (Pitch Task) - roughly constant across SOAs
            rt1 = ex_gauss(base_rt1, 30, 50)
            
            # RT2 (Letter Task) - PRP bottleneck effect
            # Central bottleneck: processing of T2 cannot start until T1 central stage finishes
            bottleneck_delay = max(0, (base_rt1 + random.uniform(-40, 40)) - soa)
            rt2 = ex_gauss(base_rt2, 35, 45) + bottleneck_delay
            
            # Extra RT penalty for error trials (messiness)
            if t1_c == 0: rt1 += random.uniform(50, 300)
            if t2_c == 0: rt2 += random.uniform(50, 300)
            
            writer.writerow([pid, t, soa, t1_c, t2_c, round(rt1, 1), round(rt2, 1)])
            
    # Generate 1 contaminated participant (P99)
    # Ignored Task 1 (chance accuracy), RT2 does not show PRP bottleneck effect
    pid = 'P99'
    for t in range(1, 101):
        soa = random.choice(soas)
        t1_c = 1 if random.random() < 0.51 else 0  # Near chance accuracy
        t2_c = 1 if random.random() < 0.94 else 0
        
        rt1 = random.uniform(250, 800)
        rt2 = ex_gauss(420, 40, 40)  # Flat RT2 curve, ignoring Task 1 bottleneck
        
        writer.writerow([pid, t, soa, t1_c, t2_c, round(rt1, 1), round(rt2, 1)])

print(f"Generated PRP dataset at {output_path}")
PYEOF

chown ga:ga /home/ga/pebl/data/prp_dual_task_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address for terminal launch
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === PRP Dual-Task Bottleneck Analysis ===; echo; echo Data file: ~/pebl/data/prp_dual_task_data.csv; echo Output target: ~/pebl/analysis/prp_report.json; echo; bash' > /tmp/prp_terminal.log 2>&1 &"

# Focus the terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== prp_bottleneck_analysis setup complete ==="