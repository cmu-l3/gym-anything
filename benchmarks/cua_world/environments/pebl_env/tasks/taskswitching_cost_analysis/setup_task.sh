#!/bin/bash
set -e
echo "=== Setting up taskswitching_cost_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic task-switching data
python3 << 'PYEOF'
import csv, random

random.seed(42)
participants = {
    "sub-10159": {"rep_rt": 668, "sw_rt": 782, "rep_acc": 0.94, "sw_acc": 0.88},
    "sub-10171": {"rep_rt": 550, "sw_rt": 620, "rep_acc": 0.96, "sw_acc": 0.90},
    "sub-10189": {"rep_rt": 710, "sw_rt": 850, "rep_acc": 0.92, "sw_acc": 0.85},
    "sub-10206": {"rep_rt": 605, "sw_rt": 715, "rep_acc": 0.95, "sw_acc": 0.89},
    "sub-10217": {"rep_rt": 630, "sw_rt": 780, "rep_acc": 0.93, "sw_acc": 0.88},
    "sub-10225": {"rep_rt": 580, "sw_rt": 660, "rep_acc": 0.97, "sw_acc": 0.94},
    "sub-10235": {"rep_rt": 690, "sw_rt": 810, "rep_acc": 0.91, "sw_acc": 0.84},
    "sub-10249": {"rep_rt": 820, "sw_rt": 980, "rep_acc": 0.89, "sw_acc": 0.80},
    "sub-10280": {"rep_rt": 590, "sw_rt": 675, "rep_acc": 0.95, "sw_acc": 0.91},
    "sub-10292": {"rep_rt": 750, "sw_rt": 890, "rep_acc": 0.90, "sw_acc": 0.85},
    "sub-10304": {"rep_rt": 640, "sw_rt": 765, "rep_acc": 0.94, "sw_acc": 0.89},
}

rows = []
for pid, params in participants.items():
    for block in range(1, 5):
        for trial in range(1, 25):
            trial_num = (block - 1) * 24 + trial
            if trial == 1:
                ttype = "FIRST"
                rt = int(random.gauss(params["rep_rt"] + 100, 100))
                correct = 1 if random.random() < params["rep_acc"] else 0
            else:
                ttype = "SWITCH" if random.random() < 0.33 else "REPEAT"
                rt_mean = params["sw_rt"] if ttype == "SWITCH" else params["rep_rt"]
                acc_prob = params["sw_acc"] if ttype == "SWITCH" else params["rep_acc"]
                rt = int(random.gauss(rt_mean, rt_mean * 0.15))
                correct = 1 if random.random() < acc_prob else 0
                
                # occasional timeout
                if random.random() < 0.01:
                    rt = 0
                    correct = 0
            
            cues = ["LETTER", "NUMBER"]
            cue = random.choice(cues)
            stimulus = random.choice("AEIOUBCDFG") + random.choice("123456789")
            
            rows.append({
                "participant_id": pid,
                "trial_num": trial_num,
                "task_cue": cue,
                "trial_type": ttype,
                "stimulus": stimulus,
                "correct": correct,
                "rt_ms": max(0, rt)
            })

# Contaminated participant
for block in range(1, 5):
    for trial in range(1, 25):
        trial_num = (block - 1) * 24 + trial
        ttype = "FIRST" if trial == 1 else ("SWITCH" if random.random() < 0.33 else "REPEAT")
        cue = random.choice(["LETTER", "NUMBER"])
        stimulus = random.choice("AEIOUBCDFG") + random.choice("123456789")
        rt = int(random.uniform(40, 70))
        rows.append({
            "participant_id": "sub-99999",
            "trial_num": trial_num,
            "task_cue": cue,
            "trial_type": ttype,
            "stimulus": stimulus,
            "correct": 1,
            "rt_ms": rt
        })

with open('/tmp/ground_truth_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial_num", "task_cue", "trial_type", "stimulus", "correct", "rt_ms"])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

# Provide data to the agent
cp /tmp/ground_truth_data.csv /home/ga/pebl/data/taskswitching_data.csv
chown ga:ga /home/ga/pebl/data/taskswitching_data.csv
chmod 644 /home/ga/pebl/data/taskswitching_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1 || echo "")
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1 || echo "")
fi

# Open gedit with the data file to prompt the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/data/taskswitching_data.csv > /tmp/gedit_terminal.log 2>&1 &"

# Wait for gedit window to stabilize and maximize it
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "taskswitching_data.csv" 2>/dev/null | head -1 || echo "")
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== taskswitching_cost_analysis setup complete ==="