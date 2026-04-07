#!/bin/bash
# Setup script for mullerlyer_pse_analysis
# Generates a realistic psychophysical dataset for the Müller-Lyer illusion
# based on empirical distributions (Predebon, 2004) to avoid trivial synthetic data.

set -e
echo "=== Setting up mullerlyer_pse_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
mkdir -p /var/lib/pebl/ground_truth

# Generate the realistic dataset and ground truth
python3 << 'PYEOF'
import csv
import random
import math
import json
import os

random.seed(42)  # Fixed seed for deterministic grading
participants = [f"P{i:02d}" for i in range(1, 16)]
conditions = ["fins_in", "fins_out"]
standard = 100
comparisons = list(range(70, 135, 5))
trials_per_comp = 20

gt_params = {}
rows = []

# Generate valid participants
for p in participants:
    # Randomize PSEs around empirical means (Illusion ~20% of shaft)
    pse_in = random.uniform(108.0, 116.0)
    pse_out = random.uniform(84.0, 92.0)
    # Psychometric slopes
    slope_in = random.uniform(0.12, 0.20)
    slope_out = random.uniform(0.12, 0.20)

    gt_params[p] = {
        "pse_fins_in": round(pse_in, 2),
        "pse_fins_out": round(pse_out, 2),
        "illusion_magnitude": round(pse_in - pse_out, 2)
    }

    for cond in conditions:
        pse = pse_in if cond == "fins_in" else pse_out
        slope = slope_in if cond == "fins_in" else slope_out

        for comp in comparisons:
            # Logistic psychometric function: P(comparison longer)
            prob = 1.0 / (1.0 + math.exp(-slope * (comp - pse)))
            for _ in range(trials_per_comp):
                resp = 1 if random.random() < prob else 0
                rows.append({
                    "participant_id": p,
                    "condition": cond,
                    "standard_length": standard,
                    "comparison_length": comp,
                    "response": resp
                })

# Inject corrupted participant P99
for cond in conditions:
    for comp in comparisons:
        for _ in range(trials_per_comp):
            rows.append({
                "participant_id": "P99",
                "condition": cond,
                "standard_length": standard,
                "comparison_length": comp,
                "response": 1  # Impossible 100% "longer" response
            })

# Save the dataset for the agent
data_path = '/home/ga/pebl/data/mullerlyer_data.csv'
with open(data_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "condition", "standard_length", "comparison_length", "response"])
    writer.writeheader()
    writer.writerows(rows)

# Save ground truth hidden from the agent
gt_path = '/var/lib/pebl/ground_truth/mullerlyer_gt.json'
with open(gt_path, 'w') as f:
    json.dump(gt_params, f, indent=2)

print(f"Generated {len(rows)} trials of psychophysical data.")
PYEOF

# Secure the ground truth
chmod 700 /var/lib/pebl/ground_truth
chmod 600 /var/lib/pebl/ground_truth/mullerlyer_gt.json
chown root:root /var/lib/pebl/ground_truth/mullerlyer_gt.json

# Setup agent workspace
chown -R ga:ga /home/ga/pebl

# Get ga user's DBUS session address for UI launching
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open terminal and gedit showing the data
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=100x30 -- bash -c 'echo === Müller-Lyer PSE Analysis ===; echo; echo Data file: ~/pebl/data/mullerlyer_data.csv; echo Expected Output: ~/pebl/analysis/mullerlyer_report.json; echo; bash' > /dev/null 2>&1 &"
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/data/mullerlyer_data.csv > /dev/null 2>&1 &"

# Wait for windows and arrange
sleep 3
for i in $(seq 1 10); do
    GEDIT_WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "mullerlyer_data.csv" 2>/dev/null | head -1)
    if [ -n "$GEDIT_WID" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$GEDIT_WID" -e 0,0,0,800,600 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== mullerlyer_pse_analysis setup complete ==="