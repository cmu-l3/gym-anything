#!/bin/bash
set -e
echo "=== Setting up DSST Processing Speed Analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate deterministic DSST data containing valid participants, slow participants, and one random responder
python3 << 'EOF'
import csv
import random

random.seed(12345)

rows = []
participants = [f"sub-{100+i}" for i in range(1, 30)]
participants.append("sub-err-44")
random.shuffle(participants)

for p in participants:
    elapsed = 0
    trial = 1
    
    if p == "sub-err-44":
        # Artifact: chance-level responding (approx 15% accuracy)
        while elapsed < 120000:
            rt = int(random.uniform(300, 1000))
            elapsed += rt
            correct = 1 if random.random() < 0.15 else 0
            rows.append({"participant_id": p, "trial": trial, "elapsed_time_ms": elapsed, "rt_ms": rt, "correct": correct})
            trial += 1
    elif p in ["sub-108", "sub-115", "sub-122"]:
        # Slow responder: will complete fewer than 30 trials in 90 seconds
        while elapsed < 120000:
            rt = int(random.uniform(3000, 4500))
            elapsed += rt
            correct = 1 if random.random() < 0.90 else 0
            rows.append({"participant_id": p, "trial": trial, "elapsed_time_ms": elapsed, "rt_ms": rt, "correct": correct})
            trial += 1
    else:
        # Standard responder: > 35 trials in 90s, with a noticeable learning effect (decreasing RT)
        base_rt = random.uniform(1800, 2400)
        while elapsed < 120000:
            rt_mean = max(1000, base_rt - (trial * 15))
            rt = int(random.gauss(rt_mean, 200))
            if rt < 500: rt = 500
            elapsed += rt
            correct = 1 if random.random() < 0.95 else 0
            rows.append({"participant_id": p, "trial": trial, "elapsed_time_ms": elapsed, "rt_ms": rt, "correct": correct})
            trial += 1

with open('/home/ga/pebl/data/dsst_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "elapsed_time_ms", "rt_ms", "correct"])
    writer.writeheader()
    writer.writerows(rows)
EOF

chown ga:ga /home/ga/pebl/data/dsst_data.csv

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === DSST Processing Speed Analysis ===; echo; echo Data file: ~/pebl/data/dsst_data.csv; echo Output target: ~/pebl/analysis/dsst_report.json; echo; bash' > /tmp/dsst_terminal.log 2>&1 &"

sleep 3

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== setup complete ==="