#!/bin/bash
# Setup for fitts_throughput_analysis task
# Generates a realistic simulated Fitts' law dataset based on empirical ISO 9241-411 parameters
# and injects one contaminated participant (auto-clicker).

set -e
echo "=== Setting up fitts_throughput_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic Fitts' Law data
cat << 'PYEOF' > /tmp/generate_fitts.py
import csv
import random
import math

# Amplitudes (A) and Widths (W) in pixels
As = [128, 256, 384, 512]
Ws = [16, 32, 64, 128]

random.seed(42)

with open('/home/ga/pebl/data/fitts_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['participant', 'block', 'amplitude', 'width', 'trial', 'mt_ms', 'dx'])
    
    # 1. Generate 15 valid human participants
    for p in range(1, 16):
        pid = f"P{p:02d}"
        
        # Sample realistic human motor parameters based on ISO 9241-411 studies
        intercept = random.uniform(30, 80)
        slope = random.uniform(120, 170)
        
        for b in range(1, 4):
            for a in As:
                for w in Ws:
                    # Realistic endpoint variability: ~4% error rate maps to SDx ~ W/4.133
                    condition_sdx = (w / 4.133) * random.uniform(0.85, 1.15)
                    We = 4.133 * condition_sdx
                    
                    # Effective ID
                    IDe = math.log2(2 * a / We) if We > 0 else math.log2(2 * a / w)
                    mean_mt = intercept + slope * IDe
                    
                    for t in range(1, 16):
                        # Add variance to movement time
                        mt = max(50, random.gauss(mean_mt, mean_mt * 0.12))
                        # Sample spatial deviation
                        dx = random.gauss(0, condition_sdx)
                        writer.writerow([pid, b, a, w, t, round(mt, 1), round(dx, 2)])

    # 2. Generate P99 (Contaminated: Auto-clicker macro)
    for b in range(1, 4):
        for a in As:
            for w in Ws:
                for t in range(1, 16):
                    # Constant super-fast MT regardless of difficulty
                    mt = random.uniform(40, 70)
                    # Perfect precision (SDx approx 0.5)
                    dx = random.gauss(0, 0.5)
                    writer.writerow(["P99", b, a, w, t, round(mt, 1), round(dx, 2)])

print("Successfully generated ISO 9241-411 Fitts dataset.")
PYEOF

python3 /tmp/generate_fitts.py
chown ga:ga /home/ga/pebl/data/fitts_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === ISO 9241-411 Fitts Throughput Analysis ===; echo; echo Data file: ~/pebl/data/fitts_data.csv; echo Output target: ~/pebl/analysis/fitts_report.json; echo; bash' > /tmp/fitts_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== fitts_throughput_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/fitts_data.csv"
echo "Expected output: /home/ga/pebl/analysis/fitts_report.json"