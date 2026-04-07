#!/bin/bash
# Setup for pasat_processing_chunking_analysis
set -e
echo "=== Setting up PASAT Chunking Analysis Task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create required directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate highly realistic clinical PASAT data
# Using a python script to generate complex distributions (Ex-Gaussian RTs, Markov chain accuracy)
python3 << 'PYEOF'
import csv
import random
import math

random.seed(42)

conditions = ["3.0", "2.4", "2.0", "1.6"]
participants = [f"sub-{i:02d}" for i in range(1, 19)]
contaminated = "sub-999"

rows = []

def generate_participant_data(pid, is_contaminated=False):
    # Individual baseline ability
    base_acc_prob = random.uniform(0.85, 0.98)
    base_rt = random.uniform(800, 1100)
    
    for isi in conditions:
        isi_float = float(isi)
        # Difficulty modifiers based on ISI
        difficulty_penalty = (3.0 - isi_float) * 0.25 
        current_acc_prob = max(0.2, base_acc_prob - difficulty_penalty)
        
        # Omission vs Commission ratio (faster pace = more omissions)
        omission_ratio = 0.2 + (3.0 - isi_float) * 0.4
        
        consecutive_correct = 0
        
        for trial in range(1, 51):
            target = random.randint(2, 18)
            presented = random.randint(1, 9)
            
            if is_contaminated and isi == "1.6":
                # Impossible data signature
                acc = 1
                rt = random.uniform(20, 75)  # < 80ms RT
                resp = target
            else:
                # Fatigue / cognitive overload modeling (markov-ish)
                if consecutive_correct > 10 and isi_float < 2.5:
                    current_acc_prob -= 0.05 # Overload probability
                    
                if random.random() < current_acc_prob:
                    acc = 1
                    resp = target
                    rt = random.gauss(base_rt - (3.0 - isi_float)*100, 150)
                    rt = max(250, min(rt, isi_float * 1000 - 100))
                    consecutive_correct += 1
                else:
                    consecutive_correct = 0
                    if random.random() < omission_ratio:
                        acc = -1
                        resp = -1
                        rt = isi_float * 1000 # Timeout
                    else:
                        acc = 0
                        resp = target + random.choice([-2, -1, 1, 2])
                        rt = random.gauss(base_rt + 200, 200)
                        rt = max(300, min(rt, isi_float * 1000 - 50))
            
            rows.append({
                "participant_id": pid,
                "isi_condition": isi,
                "trial_num": trial,
                "presented_digit": presented,
                "expected_target": target,
                "participant_response": resp,
                "accuracy": acc,
                "rt_ms": round(rt, 1)
            })

for p in participants:
    generate_participant_data(p, False)
generate_participant_data(contaminated, True)

with open("/home/ga/pebl/data/pasat_data.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "isi_condition", "trial_num", "presented_digit", "expected_target", "participant_response", "accuracy", "rt_ms"])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga /home/ga/pebl/data/pasat_data.csv

# Record start time for anti-gaming (file creation checks)
date +%s > /tmp/task_start_time.txt

# Open a terminal for the agent with instructions
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === PASAT Information Processing Analysis ===; echo; echo Data: ~/pebl/data/pasat_data.csv; echo Target: ~/pebl/analysis/pasat_report.json; echo; bash' > /tmp/pasat_terminal.log 2>&1 &"

# Maximize Terminal
for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== PASAT Chunking Setup Complete ==="