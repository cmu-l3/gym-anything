#!/bin/bash
set -e
echo "=== Setting up recognition_memory_sdt_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

DATA_FILE="/home/ga/pebl/data/recognition_memory_data.csv"

# Attempt to copy real data from assets, fallback to realistic generation if missing
if [ -f "/workspace/assets/recognition_memory_data_real.csv" ]; then
    echo "Using real dataset from assets..."
    cp "/workspace/assets/recognition_memory_data_real.csv" "/tmp/rm_base.csv"
else
    echo "Asset not found. Generating realistic fallback dataset modeled on OpenNeuro ds000030..."
    # Python script to generate realistic log-normal RTs and beta-binomial accuracy
    python3 << 'PYEOF'
import csv
import random
import math

random.seed(12345)
participants = [f"sub-{10159 + i}" for i in range(14)]
rows = []

# Real-world inspired SDT parameters for 14 participants
configs = [
    (24, 4), (27, 9), (18, 3), (29, 15), (21, 6), (30, 2), (25, 0),
    (22, 10), (26, 8), (15, 15), (28, 5), (20, 2), (23, 12), (27, 1)
]

for pid, (hits, fas) in zip(participants, configs):
    trials = []
    # 30 OLD items
    for i in range(30):
        resp = "old" if i < hits else "new"
        corr = 1 if resp == "old" else 0
        # Realistic Lognormal RT (median ~800ms)
        rt = int(math.exp(random.gauss(6.68, 0.25)))
        trials.append((pid, "OLD", resp, corr, rt))
    # 30 NEW items
    for i in range(30):
        resp = "old" if i < fas else "new"
        corr = 1 if resp == "new" else 0
        rt = int(math.exp(random.gauss(6.75, 0.25)))
        trials.append((pid, "NEW", resp, corr, rt))
    
    random.shuffle(trials)
    for i, t in enumerate(trials):
        rows.append({
            "participant_id": t[0], "trial_num": i+1, "stimulus_type": t[1],
            "response": t[2], "correct": t[3], "rt_ms": t[4]
        })

with open('/tmp/rm_base.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
PYEOF
fi

# Inject the contaminated participant (sub-99999)
echo "Injecting contaminated participant (sub-99999)..."
python3 << 'PYEOF'
import csv
import random

random.seed(999)
rows = []
with open('/tmp/rm_base.csv', 'r') as f:
    reader = csv.DictReader(f)
    rows = list(reader)

# sub-99999: 100% Hits, 0% FAs, 25-45ms RTs
trials = []
for i in range(30):
    trials.append(("sub-99999", "OLD", "old", 1, random.randint(25, 45)))
    trials.append(("sub-99999", "NEW", "new", 1, random.randint(25, 45)))
random.shuffle(trials)

for i, t in enumerate(trials):
    rows.append({
        "participant_id": t[0], "trial_num": i+1, "stimulus_type": t[1],
        "response": t[2], "correct": t[3], "rt_ms": t[4]
    })

with open('/home/ga/pebl/data/recognition_memory_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga "$DATA_FILE"
chmod 644 "$DATA_FILE"

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open the data file in gedit for the agent
echo "Starting gedit..."
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit '$DATA_FILE' > /tmp/gedit.log 2>&1 &"

# Wait and maximize
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "gedit" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="