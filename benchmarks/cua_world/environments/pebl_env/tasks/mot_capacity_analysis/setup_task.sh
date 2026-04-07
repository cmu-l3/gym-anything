#!/bin/bash
echo "=== Setting up MOT Capacity Analysis Task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate dataset and hidden ground truth
python3 << 'EOF'
import csv
import random
import json

random.seed(42)

subjects = [f"MOT_{i:02d}" for i in range(1, 15)] + ["MOT_99"]
target_counts = [2, 3, 4, 5, 6]
distractors = 4

data = []
gt = {"participants": {}, "group_means": {}}

for subj in subjects:
    gt["participants"][subj] = {
        "k_capacity": {str(tc): 0.0 for tc in target_counts},
        "mean_rt_ms": 0.0
    }
    total_rt = 0.0
    
    for tc in target_counts:
        sum_k = 0.0
        total_items = tc + distractors
        chance = tc / total_items
        
        for trial in range(10): # 10 trials per condition
            if subj == "MOT_99":
                # The cheater: 100% accuracy, suspiciously fast RT
                obs_acc = 1.0
                rt = random.uniform(2.0, 3.0)
            else:
                # Normal participant behavior
                target_k = {2: 1.95, 3: 2.75, 4: 3.2, 5: 3.3, 6: 3.1}[tc]
                target_adj = target_k / tc
                target_obs = target_adj * (1 - chance) + chance
                obs_acc = min(1.0, max(0.0, random.gauss(target_obs, 0.15)))
                rt = random.uniform(3.0, 6.0)
                
            targets_clicked = int(round(obs_acc * tc))
            
            # Recalculate true capacities mathematically based on integers
            actual_obs_acc = targets_clicked / tc
            adj_acc = max(0.0, (actual_obs_acc - chance) / (1 - chance))
            k_cap = tc * adj_acc
            
            sum_k += k_cap
            total_rt += rt
            
            data.append({
                "subject_id": subj,
                "trial": trial + 1,
                "target_count": tc,
                "distractor_count": distractors,
                "speed_deg_sec": random.choice(["slow", "medium", "fast"]),
                "targets_clicked": targets_clicked,
                "rt_sec": round(rt, 3)
            })
            
        gt["participants"][subj]["k_capacity"][str(tc)] = sum_k / 10.0
    
    gt["participants"][subj]["mean_rt_ms"] = (total_rt / (len(target_counts) * 10)) * 1000.0

# Calculate group means (STRICTLY excluding MOT_99)
for tc in target_counts:
    sum_group = 0.0
    count_group = 0
    for subj in subjects:
        if subj != "MOT_99":
            sum_group += gt["participants"][subj]["k_capacity"][str(tc)]
            count_group += 1
    gt["group_means"][str(tc)] = sum_group / count_group

# Save dataset
with open("/home/ga/pebl/data/mot_tracking_data.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["subject_id", "trial", "target_count", "distractor_count", "speed_deg_sec", "targets_clicked", "rt_sec"])
    writer.writeheader()
    writer.writerows(data)

# Save hidden ground truth
with open("/tmp/mot_ground_truth.json", "w") as f:
    json.dump(gt, f)
EOF

chown ga:ga /home/ga/pebl/data/mot_tracking_data.csv
chmod 644 /tmp/mot_ground_truth.json

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch a terminal for the agent with instructions
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === MOT Capacity Analysis ===; echo; echo Data file: ~/pebl/data/mot_tracking_data.csv; echo Output JSON: ~/pebl/analysis/mot_capacity_report.json; echo Output Plot: ~/pebl/analysis/capacity_plot.png; echo; bash' > /tmp/mot_terminal.log 2>&1 &"

# Focus and maximize terminal window
sleep 3
WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l | grep "Terminal" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Capture initial evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="