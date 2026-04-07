#!/bin/bash
# Setup for ospan_scoring_analysis task
# Generates a highly realistic Operation Span (OSPAN) dataset with specific 
# string permutations (spaces, lowercases, transpositions) to robustly test 
# the agent's string alignment and psychometric scoring logic.

set -e
echo "=== Setting up ospan_scoring_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic OSPAN data using Python
python3 << 'PYEOF'
import csv
import random

random.seed(42)  # Fixed seed for deterministic data generation

participants = [f"sub-{i:02d}" for i in range(1, 26)] + ["sub-99"]
set_sizes = [3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7]  # Standard OSPAN block structure
letters = "FHKLNPQRSVY"

rows = []
for p in participants:
    is_bad = (p == "sub-99")
    set_id = 1
    for sz in set_sizes:
        presented = "".join(random.sample(letters, sz))
        
        # Math accuracy logic
        if is_bad:
            # Sub-99 ignores the math task (low accuracy, triggers exclusion)
            math_correct = random.randint(0, sz)
        else:
            # Normal human participants (mostly correct, occasional slip)
            math_correct = sz if random.random() < 0.90 else sz - 1
            
        # Memory recall logic (injecting realistic human typing errors)
        recalled = presented
        err_type = random.random()
        
        if err_type < 0.15:
            # typed in lowercase
            recalled = recalled.lower()
        elif err_type < 0.30:
            # added spaces
            recalled = " ".join(list(recalled))
        elif err_type < 0.45:
            # transposed last two letters (partial span high, abs span 0)
            if sz >= 3:
                recalled = recalled[:-2] + recalled[-1] + recalled[-2]
        elif err_type < 0.60:
            # omitted a letter (partial span drops, abs span 0)
            recalled = recalled[:-1]
        elif err_type < 0.65:
            # intrusion (extra letter)
            recalled = recalled + random.choice(letters)
            
        rows.append({
            "participant_id": p,
            "set_id": set_id,
            "set_size": sz,
            "math_correct": math_correct,
            "math_attempted": sz,
            "letters_presented": presented,
            "letters_recalled": recalled
        })
        set_id += 1

with open("/home/ga/pebl/data/ospan_data.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {len(rows)} trials across {len(participants)} participants.")
PYEOF

chown ga:ga /home/ga/pebl/data/ospan_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Operation Span \(OSPAN\) Scoring Analysis ===; echo; echo Data file: ~/pebl/data/ospan_data.csv; echo Output target: ~/pebl/analysis/ospan_report.json; echo; bash' > /tmp/ospan_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== ospan_scoring_analysis setup complete ==="