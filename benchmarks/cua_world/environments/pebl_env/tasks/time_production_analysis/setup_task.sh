#!/bin/bash
# Setup for time_production_analysis task
# Dynamically generates a CSV dataset with 15 realistic participants and 1 cheater (sub-99).
# By using dynamic runtime generation, the exact ground truth is un-guessable.

set -e
echo "=== Setting up time_production_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate dynamic CSV dataset
python3 << 'PYEOF'
import csv
import random
import time

random.seed(time.time())
participants = [f"sub-{i:02d}" for i in range(1, 16)]
targets = [500, 1000, 2000, 3000]
trials_per_target = 10

rows = []

# Generate real participants with Weber's Law scaling and Vierordt's Law bias
for p in participants:
    for t in targets:
        # Bias: typically overestimate short durations, underestimate long durations
        bias = (1000 - t) * random.uniform(0.05, 0.15)
        # CV for humans usually between 0.08 and 0.15
        cv = random.uniform(0.1, 0.15)
        sd = t * cv
        for tr in range(1, trials_per_target + 1):
            prod = int(random.gauss(t + bias, sd))
            prod = max(100, prod)  # Floor at 100ms
            rows.append({
                "participant_id": p, 
                "trial": tr, 
                "target_duration_ms": t, 
                "produced_duration_ms": prod
            })
            
# Generate cheater sub-99 (Used a stopwatch)
# Hyper-precise, tiny standard deviation (~2ms) regardless of target duration
for t in targets:
    for tr in range(1, trials_per_target + 1):
        prod = int(random.gauss(t, 2.0))
        rows.append({
            "participant_id": "sub-99", 
            "trial": tr, 
            "target_duration_ms": t, 
            "produced_duration_ms": prod
        })
        
# Shuffle rows to look like a realistic unstructured log
random.shuffle(rows)

csv_path = "/home/ga/pebl/data/time_production_data.csv"
with open(csv_path, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "target_duration_ms", "produced_duration_ms"])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga /home/ga/pebl/data/time_production_data.csv

# Record start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address to launch terminal properly
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with context
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Time Production Psychophysics Analysis ===; echo; echo Data file: ~/pebl/data/time_production_data.csv; echo Output target: ~/pebl/analysis/timing_report.json; echo; bash' > /tmp/timing_terminal.log 2>&1 &"

# Wait for terminal to appear and maximize it
for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== time_production_analysis setup complete ==="