#!/bin/bash
# Setup for vlt_clinical_scoring_analysis task
# Generates physiologically plausible Verbal Learning Test data for 50 participants
# Injects two exclusion cases (missing demographics and impossible malingering pattern)
# Generates a hidden ground truth file for verification

set -e
echo "=== Setting up vlt_clinical_scoring_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic data and hidden ground truth using Python
python3 << 'PYEOF'
import csv
import json
import random
import math

random.seed(42)

# Approximate RAVLT Norms
norms = {
    "18-29": {"mean": 55.0, "sd": 8.0},
    "30-44": {"mean": 52.0, "sd": 8.5},
    "45-59": {"mean": 48.0, "sd": 9.0},
    "60-69": {"mean": 44.0, "sd": 9.0},
    "70-79": {"mean": 40.0, "sd": 9.5},
    "80+":   {"mean": 35.0, "sd": 9.5}
}

def get_age_group(age):
    if age < 30: return "18-29"
    if age < 45: return "30-44"
    if age < 60: return "45-59"
    if age < 70: return "60-69"
    if age < 80: return "70-79"
    return "80+"

with open('/home/ga/pebl/data/norms.json', 'w') as f:
    json.dump(norms, f, indent=2)

demographics = []
vlt_data = []

trials = ["A1", "A2", "A3", "A4", "A5", "B1", "A6", "A7"]
messy_trials = {
    "A1": ["A1", " a1", "A1 "],
    "A2": ["A2", " a2 ", " A2"],
    "A3": ["A3", "a3", " A3 "],
    "A4": ["A4", " A4", "a4 "],
    "A5": ["A5", "a5", " A5"],
    "B1": ["B1", " b1", "B1 "],
    "A6": ["A6", " a6", " A6 "],
    "A7": ["A7", "a7", "A7 "]
}

scores_dict = {}
ages_dict = {}

def generate_subject(sub_id, age):
    demographics.append({"participant_id": sub_id, "age": age, "education": random.randint(12, 18)})
    ages_dict[sub_id] = age
    
    # Base performance dependent on age
    if age < 30: base = 7
    elif age < 45: base = 6
    elif age < 60: base = 5
    elif age < 70: base = 4
    elif age < 80: base = 4
    else: base = 3
    
    a1 = min(15, max(0, int(random.gauss(base, 1.5))))
    a2 = min(15, max(a1, int(random.gauss(a1 + 2, 1))))
    a3 = min(15, max(a2, int(random.gauss(a2 + 1.5, 1))))
    a4 = min(15, max(a3, int(random.gauss(a3 + 1, 1))))
    a5 = min(15, max(a4, int(random.gauss(a4 + 0.5, 1))))
    
    b1 = min(15, max(0, int(random.gauss(base - 1, 1.5))))
    a6 = min(15, max(0, int(random.gauss(a5 - 1.5, 1.5))))
    a7 = min(15, max(0, int(random.gauss(a6 - 0.5, 1))))
    
    scores = {"A1": a1, "A2": a2, "A3": a3, "A4": a4, "A5": a5, "B1": b1, "A6": a6, "A7": a7}
    scores_dict[sub_id] = scores
    
    for t in trials:
        t_messy = random.choice(messy_trials[t])
        vlt_data.append({"participant_id": sub_id, "trial": t_messy, "correct": scores[t]})

# Valid participants
for i in range(101, 149):
    age = random.randint(18, 85)
    generate_subject(f"sub-{i}", age)

# Injected Participant 1: sub-888 (Missing Demographics)
demographics.append({"participant_id": "sub-888", "age": "NA", "education": 14})
for t in trials:
    vlt_data.append({"participant_id": "sub-888", "trial": random.choice(messy_trials[t]), "correct": random.randint(5,10)})

# Injected Participant 2: sub-999 (Invalid/Malingering -> A2 - A1 = 12 >= 10)
demographics.append({"participant_id": "sub-999", "age": 25, "education": 16})
scores_999 = {"A1": 2, "A2": 14, "A3": 14, "A4": 15, "A5": 15, "B1": 5, "A6": 12, "A7": 12}
for t in trials:
    vlt_data.append({"participant_id": "sub-999", "trial": random.choice(messy_trials[t]), "correct": scores_999[t]})

with open('/home/ga/pebl/data/demographics.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "age", "education"])
    writer.writeheader()
    writer.writerows(demographics)

with open('/home/ga/pebl/data/vlt_raw_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "correct"])
    writer.writeheader()
    writer.writerows(vlt_data)

# Compute hidden ground truth for verification
ground_truth = {
    "participants": [],
    "group_means": {}
}

sum_metrics = {
    "total_acquisition": 0,
    "learning_slope": 0,
    "retroactive_interference": 0,
    "delayed_retention": 0,
    "total_acquisition_zscore": 0
}
valid_count = 0

for i in range(101, 149):
    sub_id = f"sub-{i}"
    acq = sum([scores_dict[sub_id][t] for t in ["A1","A2","A3","A4","A5"]])
    slope = scores_dict[sub_id]["A5"] - scores_dict[sub_id]["A1"]
    retro = scores_dict[sub_id]["A5"] - scores_dict[sub_id]["A6"]
    dr = scores_dict[sub_id]["A7"] / scores_dict[sub_id]["A6"] if scores_dict[sub_id]["A6"] > 0 else 0.0
    
    age_group = get_age_group(ages_dict[sub_id])
    n_mean = norms[age_group]["mean"]
    n_sd = norms[age_group]["sd"]
    zscore = (acq - n_mean) / n_sd
    
    ground_truth["participants"].append({
        "id": sub_id,
        "total_acquisition": acq,
        "learning_slope": slope,
        "retroactive_interference": retro,
        "delayed_retention": round(dr, 2),
        "total_acquisition_zscore": round(zscore, 2)
    })
    
    sum_metrics["total_acquisition"] += acq
    sum_metrics["learning_slope"] += slope
    sum_metrics["retroactive_interference"] += retro
    sum_metrics["delayed_retention"] += dr
    sum_metrics["total_acquisition_zscore"] += zscore
    valid_count += 1

ground_truth["participants"].append({"id": "sub-888", "excluded": True})
ground_truth["participants"].append({"id": "sub-999", "excluded": True})

for k in sum_metrics:
    ground_truth["group_means"][k] = round(sum_metrics[k] / valid_count, 2)

with open('/root/vlt_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)
PYEOF

chown ga:ga /home/ga/pebl/data/norms.json
chown ga:ga /home/ga/pebl/data/demographics.csv
chown ga:ga /home/ga/pebl/data/vlt_raw_data.csv

# Secure ground truth from agent
chmod 700 /root/vlt_ground_truth.json
chown root:root /root/vlt_ground_truth.json

# Record start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Verbal Learning Test Clinical Scoring ===; echo; echo Data: ~/pebl/data/vlt_raw_data.csv, demographics.csv, norms.json; echo Target: ~/pebl/analysis/vlt_report.json; echo; bash' > /tmp/vlt_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== vlt_clinical_scoring_analysis setup complete ==="