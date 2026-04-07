#!/bin/bash
echo "=== Setting up BFI Psychometric Scoring Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/lab
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Dynamically generate the dataset, scoring key, and hidden ground truth
python3 << 'PYEOF'
import json
import csv
import random
import statistics
import os

random.seed()

# 1. Generate Scoring Key
bfi_key = {
    "Extraversion": { "positive": [1, 11, 16, 26, 36], "reverse": [6, 21, 31] },
    "Agreeableness": { "positive": [7, 17, 22, 32, 42], "reverse": [2, 12, 27, 37] },
    "Conscientiousness": { "positive": [3, 13, 28, 33, 38], "reverse": [8, 18, 23, 43] },
    "Neuroticism": { "positive": [4, 14, 19, 29, 39], "reverse": [9, 24, 34] },
    "Openness": { "positive": [5, 10, 15, 20, 25, 30, 40, 44], "reverse": [35, 41] }
}

with open('/home/ga/pebl/lab/bfi_key.json', 'w') as f:
    json.dump(bfi_key, f, indent=2)

# 2. Generate Dataset
rows = []
participants_gt = {}
group_trait_sums = {"Extraversion": 0, "Agreeableness": 0, "Conscientiousness": 0, "Neuroticism": 0, "Openness": 0}
valid_count = 0

def add_participant(pid, is_speeder=False, is_straightliner=False):
    global valid_count
    item_responses = {}
    rts = []
    
    # Determine base response pattern for straightliners
    sl_response = random.choice([2, 3, 4]) if is_straightliner else None
    
    for item_id in range(1, 45):
        if is_straightliner:
            resp = sl_response
        else:
            resp = random.randint(1, 5)
            
        if is_speeder:
            rt = random.randint(100, 350)
        else:
            rt = random.randint(1200, 4500)
            
        item_responses[item_id] = resp
        rts.append(rt)
        rows.append({
            "participant_id": pid,
            "item_id": item_id,
            "response": resp,
            "rt_ms": rt
        })
        
    # Quality Control Check (for ground truth generation)
    median_rt = statistics.median(rts)
    sd_resp = statistics.stdev(list(item_responses.values())) if len(item_responses) > 1 else 0
    
    is_valid = median_rt >= 500 and sd_resp >= 0.25
    
    if not is_valid:
        reason = []
        if median_rt < 500: reason.append("speeding")
        if sd_resp < 0.25: reason.append("straight-lining")
        participants_gt[pid] = {"excluded": True, "reason": " & ".join(reason)}
    else:
        # Calculate traits
        traits = {}
        for trait, keys in bfi_key.items():
            scores = []
            for i in keys["positive"]:
                scores.append(item_responses[i])
            for i in keys["reverse"]:
                scores.append(6 - item_responses[i]) # Reverse score
            trait_mean = sum(scores) / len(scores)
            traits[trait] = round(trait_mean, 4)
            group_trait_sums[trait] += trait_mean
            
        participants_gt[pid] = {"traits": traits}
        valid_count += 1

# Add real participants
for i in range(1, 16):
    add_participant(f"app-{i:02d}")

# Add synthetic careless responders
add_participant("bot-888", is_speeder=True)
add_participant("bot-999", is_straightliner=True)
# Add one that is both
add_participant("bot-777", is_speeder=True, is_straightliner=True)

# Write CSV
with open('/home/ga/pebl/data/bfi_raw_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "item_id", "response", "rt_ms"])
    writer.writeheader()
    writer.writerows(rows)

# Calculate Group Means
group_means_gt = {}
if valid_count > 0:
    for trait in group_trait_sums:
        group_means_gt[trait] = round(group_trait_sums[trait] / valid_count, 4)

# 3. Save Hidden Ground Truth
ground_truth = {
    "participants": participants_gt,
    "group_means": group_means_gt
}
with open('/tmp/hidden_bfi_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

PYEOF

# Fix permissions
chown ga:ga /home/ga/pebl/lab/bfi_key.json
chown ga:ga /home/ga/pebl/data/bfi_raw_data.csv
chmod 600 /tmp/hidden_bfi_ground_truth.json # Hide from ga user

# Get DBUS session for launching terminal
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Launch terminal with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=110x30 -- bash -c 'echo \"=== BFI Psychometric Scoring Task ===\"; echo; echo \"Input Data: ~/pebl/data/bfi_raw_data.csv\"; echo \"Scoring Key: ~/pebl/lab/bfi_key.json\"; echo \"Target Output: ~/pebl/analysis/bfi_report.json\"; echo; bash' > /dev/null 2>&1 &"

# Focus the terminal
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="