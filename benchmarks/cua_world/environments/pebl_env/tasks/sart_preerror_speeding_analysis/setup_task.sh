#!/bin/bash
set -e
echo "=== Setting up sart_preerror_speeding_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic SART data with pre-error speeding effect
# This avoids numpy dependency to ensure it works reliably in the standard python3 environment
python3 << 'EOF'
import csv
import random
import json

random.seed(101)

participants = [f"cand_{i:02d}" for i in range(1, 26)] + ["cand_99"]

base_stimuli = [3]*25 + [1,2,4,5,6,7,8,9]*25
data = []
gt_data = {}

for p in participants:
    # cand_99 is a mechanical artifact
    if p == "cand_99":
        for t in range(1, 226):
            stim = random.choice([1,2,3,4,5,6,7,8,9])
            data.append({"participant_id": p, "trial": t, "stimulus": stim, "response": 1, "rt_ms": random.randint(180, 220)})
        continue

    stimuli = base_stimuli[:]
    random.shuffle(stimuli)
    # Ensure the first three trials are not No-Go trials so windowing works smoothly
    while 3 in stimuli[:3]:
        random.shuffle(stimuli)
    
    ce_prob = random.uniform(0.3, 0.6)
    p_data = []
    
    for t, stim in enumerate(stimuli, 1):
        if stim == 3:
            is_ce = random.random() < ce_prob
            if is_ce:
                rt = int(random.gauss(280, 30))
                p_data.append({"participant_id": p, "trial": t, "stimulus": stim, "response": 1, "rt_ms": rt})
            else:
                p_data.append({"participant_id": p, "trial": t, "stimulus": stim, "response": 0, "rt_ms": 0})
        else:
            is_oe = random.random() < random.uniform(0.01, 0.05)
            if is_oe:
                p_data.append({"participant_id": p, "trial": t, "stimulus": stim, "response": 0, "rt_ms": 0})
            else:
                rt = int(random.gauss(350, 50))
                p_data.append({"participant_id": p, "trial": t, "stimulus": stim, "response": 1, "rt_ms": rt})
                
    # Second pass: Embed the pre-error speeding effect explicitly
    for i in range(len(p_data)):
        if p_data[i]["stimulus"] == 3:
            is_ce = (p_data[i]["response"] == 1)
            preceding = []
            for j in range(i-1, max(-1, i-4), -1):
                if p_data[j]["stimulus"] != 3 and p_data[j]["response"] == 1:
                    preceding.append(j)
            
            target_mean = 300 if is_ce else 370
            for j in preceding:
                p_data[j]["rt_ms"] = int(random.gauss(target_mean, 20))
                
    data.extend(p_data)

# Save the dataset
with open('/home/ga/pebl/data/sart_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "stimulus", "response", "rt_ms"])
    writer.writeheader()
    writer.writerows(data)

# Calculate ground truth specifically applying the windowing criteria
for p in participants:
    if p == "cand_99": continue
    
    p_rows = [r for r in data if r["participant_id"] == p]
    nogo_trials = [r for r in p_rows if r["stimulus"] == 3]
    go_trials = [r for r in p_rows if r["stimulus"] != 3]
    
    ce_count = sum(1 for r in nogo_trials if r["response"] == 1)
    oe_count = sum(1 for r in go_trials if r["response"] == 0)
    
    ce_rate = ce_count / len(nogo_trials) if nogo_trials else 0
    oe_rate = oe_count / len(go_trials) if go_trials else 0
    
    pre_ce_means = []
    pre_cw_means = []
    
    for i, row in enumerate(p_rows):
        if row["stimulus"] == 3:
            is_ce = (row["response"] == 1)
            valid_preceding = []
            for j in range(i-1, max(-1, i-4), -1):
                if p_rows[j]["stimulus"] != 3 and p_rows[j]["response"] == 1 and p_rows[j]["rt_ms"] > 0:
                    valid_preceding.append(p_rows[j]["rt_ms"])
            
            if valid_preceding:
                mean_rt = sum(valid_preceding) / len(valid_preceding)
                if is_ce:
                    pre_ce_means.append(mean_rt)
                else:
                    pre_cw_means.append(mean_rt)
                    
    pre_ce_rt = sum(pre_ce_means) / len(pre_ce_means) if pre_ce_means else None
    pre_cw_rt = sum(pre_cw_means) / len(pre_cw_means) if pre_cw_means else None
    speeding = pre_cw_rt - pre_ce_rt if (pre_ce_rt is not None and pre_cw_rt is not None) else None
    
    gt_data[p] = {
        "commission_error_rate": round(ce_rate, 4),
        "omission_error_rate": round(oe_rate, 4),
        "pre_ce_rt_ms": round(pre_ce_rt, 2) if pre_ce_rt else None,
        "pre_cw_rt_ms": round(pre_cw_rt, 2) if pre_cw_rt else None,
        "speeding_effect_ms": round(speeding, 2) if speeding else None
    }

group_speeding = [v["speeding_effect_ms"] for v in gt_data.values() if v["speeding_effect_ms"] is not None]
gt_data["group_mean_speeding_effect_ms"] = round(sum(group_speeding) / len(group_speeding), 2) if group_speeding else 0

with open('/tmp/sart_ground_truth.json', 'w') as f:
    json.dump(gt_data, f)
EOF

chown ga:ga /home/ga/pebl/data/sart_data.csv
date +%s > /tmp/task_start_timestamp

# Open terminal for the agent with instructions
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === SART Pre-Error Speeding Analysis ===; echo; echo Data file: ~/pebl/data/sart_data.csv; echo Output target: ~/pebl/analysis/sart_report.json; echo; bash' > /tmp/sart_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/sart_initial_screenshot.png 2>/dev/null || true

echo "=== sart_preerror_speeding_analysis setup complete ==="