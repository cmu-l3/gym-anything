#!/bin/bash
set -e
echo "=== Setting up PAL Episodic Memory Analysis ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate dataset using Python
# This generates realistic test data deterministically for exactly 17 humans and 1 dummy
python3 << 'EOF'
import csv
import random

random.seed(12345)
rows = []
stages = [2, 4, 6, 8]

for i in range(1, 19):
    if i == 18:
        pid = "PAL-999"
        is_dummy = True
    else:
        pid = f"PAL-{i:03d}"
        is_dummy = False
        
    for stage in stages:
        passed = False
        max_attempts = 1 if is_dummy else random.randint(3, 10)
        
        for attempt in range(1, max_attempts + 1):
            if is_dummy:
                rt = random.uniform(50, 150)
                patterns_correct = stage
                errors = 0
                passed_this_attempt = 1
                passed = True
            else:
                rt = random.uniform(1500, 4500)
                prob = 0.5 + (attempt * 0.1) - (stage * 0.08)
                if random.random() < prob or attempt == max_attempts:
                    patterns_correct = stage
                    errors = random.randint(0, 2) if attempt == 1 else 0
                    passed_this_attempt = 1
                    passed = True
                else:
                    patterns_correct = random.randint(0, stage - 1)
                    errors = random.randint(1, 5)
                    passed_this_attempt = 0
                    
            rows.append({
                "participant_id": pid,
                "stage": stage,
                "attempt": attempt,
                "patterns_correct": patterns_correct,
                "errors": errors,
                "passed": passed_this_attempt,
                "mean_rt_ms": round(rt, 1)
            })
            if passed:
                break
        if not passed and not is_dummy:
            # Protocol: If failed all attempts at this stage, don't proceed
            break

with open("/home/ga/pebl/data/pal_raw_data.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "stage", "attempt", "patterns_correct", "errors", "passed", "mean_rt_ms"])
    writer.writeheader()
    writer.writerows(rows)
EOF

chown ga:ga /home/ga/pebl/data/pal_raw_data.csv

# Open a terminal and text editor for the user to make progression easier
export DISPLAY=:1
su - ga -c "DISPLAY=:1 setsid gnome-terminal --working-directory=/home/ga/pebl &"
su - ga -c "DISPLAY=:1 setsid gedit /home/ga/pebl/data/pal_raw_data.csv &"

# Wait for gedit window to appear
sleep 3
DISPLAY=:1 wmctrl -r "pal_raw_data.csv" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="