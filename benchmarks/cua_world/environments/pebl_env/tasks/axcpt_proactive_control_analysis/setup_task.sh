#!/bin/bash
# Setup for axcpt_proactive_control_analysis task
# Generates highly realistic trial-level data based on DMCC AX-CPT distributions
# 10 valid participants and 1 contaminated/disengaged participant (sub-999)

set -e
echo "=== Setting up axcpt_proactive_control_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate the realistic simulated dataset directly into the environment
python3 << 'PYEOF'
import csv
import random
import os

random.seed(42)

subjects = [f"sub-DMCC{str(i).zfill(2)}" for i in range(1, 11)]
subjects.append("sub-999")

trials_per_sub = 100
# Classic AX-CPT frequencies: ~70% AX, 10% AY, 10% BX, 10% BY
trial_types = ["AX"]*70 + ["AY"]*10 + ["BX"]*10 + ["BY"]*10

data = []

for sub in subjects:
    random.shuffle(trial_types)
    for i, tt in enumerate(trial_types, 1):
        cue = tt[0]
        probe = tt[1]
        
        if sub == "sub-999":
            # Invalid responder: Random responses, random RTs
            resp = random.choice(["target", "nontarget"])
            rt = random.randint(200, 800)
        else:
            # Valid responder: Base accuracies and RTs matching typical healthy adults
            if tt == "AX":
                is_correct = random.random() < 0.95
                expected = "target"
                rt = random.normalvariate(400, 50)
            elif tt == "AY":
                is_correct = random.random() < 0.85
                expected = "nontarget"
                rt = random.normalvariate(650, 80) # Slower due to proactive interference
            elif tt == "BX":
                is_correct = random.random() < 0.90
                expected = "nontarget"
                rt = random.normalvariate(550, 70)
            else: # BY
                is_correct = random.random() < 0.98
                expected = "nontarget"
                rt = random.normalvariate(350, 40)
            
            # Map correctness to actual button response
            if is_correct:
                resp = expected
            else:
                resp = "nontarget" if expected == "target" else "target"
                
            # Occasional non-response (omission)
            if random.random() < 0.01:
                resp = "none"
                rt = 0
                
        rt = max(0, int(rt))
        data.append({
            "participant_id": sub,
            "trial": i,
            "cue": cue,
            "probe": probe,
            "response": resp,
            "rt_ms": rt
        })

output_path = '/home/ga/pebl/data/axcpt_data.csv'
with open(output_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "cue", "probe", "response", "rt_ms"])
    writer.writeheader()
    writer.writerows(data)

print(f"Generated AX-CPT data with {len(data)} trials at {output_path}")
PYEOF

chown ga:ga /home/ga/pebl/data/axcpt_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address to launch terminal properly
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === AX-CPT Proactive Control Analysis ===; echo; echo Data file: ~/pebl/data/axcpt_data.csv; echo Output target: ~/pebl/analysis/axcpt_report.json; echo; bash' > /tmp/axcpt_terminal.log 2>&1 &"

# Maximize the terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== axcpt_proactive_control_analysis setup complete ==="