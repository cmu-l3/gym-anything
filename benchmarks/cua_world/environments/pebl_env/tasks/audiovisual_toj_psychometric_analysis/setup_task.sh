#!/bin/bash
# Setup for audiovisual_toj_psychometric_analysis task
# Generates realistic exact binomial counts for TOJ psychometric data
# and outputs the ground truth parameters for the verifier to use.

set -e
echo "=== Setting up audiovisual_toj_psychometric_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Record task start time
date +%s > /tmp/task_start_timestamp

# Python script to generate exact deterministic data and the ground truth json
python3 << 'PYEOF'
import csv, json, math, random

# Exact generating parameters for 15 realistic subjects
participants = [
    ("sub-01", 15.0, 40.0),  ("sub-02", -5.0, 35.0),
    ("sub-03", 22.5, 50.0),  ("sub-04", 10.0, 45.0),
    ("sub-05", 0.0, 30.0),   ("sub-06", 30.0, 60.0),
    ("sub-07", -15.0, 38.0), ("sub-08", 5.0, 42.0),
    ("sub-09", 18.0, 48.0),  ("sub-10", -8.0, 32.0),
    ("sub-11", 12.0, 44.0),  ("sub-12", 25.0, 55.0),
    ("sub-13", 3.0, 36.0),   ("sub-14", -10.0, 39.0),
    ("sub-15", 20.0, 52.0)
]

soas = [-240, -120, -60, -30, 0, 30, 60, 120, 240]
trials_per_soa = 20

gt = {}
rows = []
random.seed(42)

for pid, pss, jnd in participants:
    k = 1.09861228867 / jnd
    gt[pid] = {"pss": pss, "jnd": jnd}
    for soa in soas:
        prob = 1.0 / (1.0 + math.exp(-k * (soa - pss)))
        n_ones = int(round(prob * trials_per_soa))
        n_zeros = trials_per_soa - n_ones
        
        resps = [1]*n_ones + [0]*n_zeros
        random.shuffle(resps)
        for r in resps:
            rows.append({"participant_id": pid, "soa_ms": soa, "response_visual_first": r, "rt_ms": random.randint(300, 800)})

# Inject degenerate sub-99 (50% uniform responses)
for soa in soas:
    resps = [1]*10 + [0]*10
    random.shuffle(resps)
    for r in resps:
        rows.append({"participant_id": "sub-99", "soa_ms": soa, "response_visual_first": r, "rt_ms": random.randint(200, 600)})

# Assign sequential trial numbers per participant
p_trial = {}
for r in rows:
    pid = r["participant_id"]
    p_trial[pid] = p_trial.get(pid, 0) + 1
    r["trial"] = p_trial[pid]

# Group Means
mean_pss = sum(p[1] for p in participants) / len(participants)
mean_jnd = sum(p[2] for p in participants) / len(participants)
gt["group_means"] = {"pss_ms": mean_pss, "jnd_ms": mean_jnd}

with open("/home/ga/pebl/data/toj_data.csv", "w", newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "soa_ms", "response_visual_first", "rt_ms"])
    writer.writeheader()
    writer.writerows(rows)

with open("/tmp/toj_ground_truth.json", "w") as f:
    json.dump(gt, f)

PYEOF

chown ga:ga /home/ga/pebl/data/toj_data.csv
chmod 644 /tmp/toj_ground_truth.json

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent to start working
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=130x40 -- bash -c 'echo === Audiovisual TOJ Psychometric Analysis ===; echo; echo Data file: ~/pebl/data/toj_data.csv; echo Output target: ~/pebl/analysis/toj_report.json; echo; bash' > /tmp/toj_terminal.log 2>&1 &"

for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== audiovisual_toj_psychometric_analysis setup complete ==="