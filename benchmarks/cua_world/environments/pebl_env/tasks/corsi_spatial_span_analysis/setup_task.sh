#!/bin/bash
# Setup script for corsi_spatial_span_analysis
# Generates a highly realistic, norm-based dataset for the task
# and records the exact ground truth for the verifier.

set -e
echo "=== Setting up corsi_spatial_span_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
mkdir -p /var/lib/corsi_ground_truth

# Generate dataset and ground truth using Python
python3 << 'PYEOF'
import csv
import json
import random

random.seed(42)  # Deterministic generation for exact ground truth matching

participants = [f"CB{i:02d}" for i in range(1, 21)]
directions = ["forward", "backward"]
max_length = 9

data_rows = []
ground_truth = {}

group_f_span = []
group_b_span = []
group_f_prod = []
group_b_prod = []

for pid in participants:
    # Generate realistic spans based on Kessels (2000) norms
    # Forward norm: M=5.8, SD=1.0. Backward norm: M=5.2, SD=1.1
    f_span = min(max(int(round(random.gauss(5.8, 1.0))), 3), 8)
    b_span = min(max(int(round(random.gauss(5.2, 1.1))), 3), f_span) # Backward usually <= Forward
    
    spans = {"forward": f_span, "backward": b_span}
    products = {"forward": 0, "backward": 0}
    
    for d in directions:
        actual_span = spans[d]
        total_correct = 0
        span_achieved = 2 # minimum span
        
        for length in range(2, max_length + 1):
            for attempt in [1, 2]:
                # Realistic RT: base ~400ms + 120ms per block + noise
                rt = int(400 + (120 * length) + random.gauss(0, 50))
                
                if length < actual_span:
                    # Very likely correct
                    correct = 1 if random.random() < 0.95 else 0
                    # Ensure they don't fail both if length < span
                    if attempt == 2 and data_rows[-1]["correct"] == 0:
                        correct = 1
                elif length == actual_span:
                    # Must get at least one correct to achieve this span, but fail some
                    if attempt == 1:
                        correct = 1 if random.random() < 0.6 else 0
                    else:
                        if data_rows[-1]["correct"] == 0:
                            correct = 1 # Force pass to achieve span
                        else:
                            correct = 0 # Force fail to simulate difficulty
                else:
                    # Length > actual_span: force fail to trigger stopping rule
                    correct = 0
                
                total_correct += correct
                
                data_rows.append({
                    "participant_id": pid,
                    "direction": d,
                    "sequence_length": length,
                    "attempt": attempt,
                    "correct": correct,
                    "response_time_ms": max(rt, 250)
                })
        
        products[d] = actual_span * total_correct
    
    ground_truth[pid] = {
        "forward_span": f_span,
        "backward_span": b_span,
        "forward_product_score": products["forward"],
        "backward_product_score": products["backward"]
    }
    
    group_f_span.append(f_span)
    group_b_span.append(b_span)
    group_f_prod.append(products["forward"])
    group_b_prod.append(products["backward"])

# Inject the contaminated participant sub-X99
for d in directions:
    for length in range(2, max_length + 1):
        for attempt in [1, 2]:
            data_rows.append({
                "participant_id": "sub-X99",
                "direction": d,
                "sequence_length": length,
                "attempt": attempt,
                "correct": 1, # 100% accuracy
                "response_time_ms": int(random.gauss(250, 10)) # Flat impossible RT
            })

# Save CSV
csv_path = "/home/ga/pebl/data/corsi_block_data.csv"
with open(csv_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "direction", "sequence_length", "attempt", "correct", "response_time_ms"])
    writer.writeheader()
    writer.writerows(data_rows)

# Compute group means and save ground truth for verifier
ground_truth["_GROUP_MEANS"] = {
    "group_forward_span_mean": sum(group_f_span) / len(group_f_span),
    "group_backward_span_mean": sum(group_b_span) / len(group_b_span),
    "group_forward_product_mean": sum(group_f_prod) / len(group_f_prod),
    "group_backward_product_mean": sum(group_b_prod) / len(group_b_prod)
}

gt_path = "/tmp/corsi_ground_truth.json"
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

PYEOF

chown -R ga:ga /home/ga/pebl
chmod 644 /tmp/corsi_ground_truth.json

# Record task start time
date +%s > /tmp/task_start_time.txt

# Get DBUS session
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open gedit with the data file so the agent sees it
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/data/corsi_block_data.csv > /tmp/gedit.log 2>&1 &"

# Wait for gedit and maximize it
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "corsi_block_data.csv"; then
        DISPLAY=:1 wmctrl -r "corsi_block_data.csv" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== setup complete ==="