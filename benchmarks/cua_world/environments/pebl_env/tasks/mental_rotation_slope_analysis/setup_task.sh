#!/bin/bash
set -e

echo "=== Setting up mental_rotation_slope_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Create ground truth directory (hidden from agent)
mkdir -p /var/lib/pebl_ground_truth
chown root:root /var/lib/pebl_ground_truth
chmod 755 /var/lib/pebl_ground_truth

echo "Generating empirical dataset and exact ground truth..."
python3 << 'PYEOF'
import csv
import json
import random
import math
import os

random.seed(1024)

participants = [f"s{i}" for i in range(1, 21)]
angles = [0, 45, 90, 135, 180]
stim_types = ['same', 'mirror']
trials_per_cond = 8

data = []
ground_truth = {}
valid_slopes = []
valid_accs = []

for p in participants:
    base_rt = random.uniform(450.0, 650.0)
    slope = random.uniform(2.0, 6.0) # ms/deg
    
    same_correct_rts = {a: [] for a in angles}
    total_trials = 0
    correct_trials = 0
    
    trial_num = 1
    for a in angles:
        for st in stim_types:
            for _ in range(trials_per_cond):
                # Accuracy models typical mental rotation difficulty curve
                prob_correct = 0.98 - (a / 180.0) * 0.15
                if st == 'mirror': 
                    prob_correct -= 0.05
                
                correct = 1 if random.random() < prob_correct else 0
                
                # Ex-Gaussian RT generation
                if st == 'same':
                    expected_rt = base_rt + slope * a
                else:
                    expected_rt = base_rt + 150 + (slope * 0.5) * a 
                
                rt = expected_rt + random.expovariate(1/100.0) + random.gauss(0, 40)
                if rt < 250: 
                    rt = 250 + random.random()*50
                
                data.append({
                    'participant': p,
                    'trial': trial_num,
                    'angle_deg': a,
                    'stimulus_type': st,
                    'correct': correct,
                    'rt_ms': round(rt, 1)
                })
                
                total_trials += 1
                if correct == 1:
                    correct_trials += 1
                    if st == 'same':
                        same_correct_rts[a].append(rt)
                        
                trial_num += 1

    # Compute exact ground truth slope for generated data
    x = []
    y = []
    for a in angles:
        if len(same_correct_rts[a]) > 0:
            x.append(a)
            y.append(sum(same_correct_rts[a]) / len(same_correct_rts[a]))
    
    n = len(x)
    if n > 1:
        sum_x = sum(x)
        sum_y = sum(y)
        sum_xy = sum(x[i]*y[i] for i in range(n))
        sum_xx = sum(x[i]*x[i] for i in range(n))
        gt_slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
    else:
        gt_slope = 0.0
        
    gt_acc = correct_trials / total_trials
    
    ground_truth[p] = {
        'slope_ms_per_deg': round(gt_slope, 3),
        'mean_accuracy': round(gt_acc, 3)
    }
    
    valid_slopes.append(gt_slope)
    valid_accs.append(gt_acc)

# Inject s99 (Contaminated participant: flat RT, chance accuracy)
p = 's99'
trial_num = 1
for a in angles:
    for st in stim_types:
        for _ in range(trials_per_cond):
            correct = random.choice([0, 1])
            rt = random.gauss(400, 20)
            data.append({
                'participant': p,
                'trial': trial_num,
                'angle_deg': a,
                'stimulus_type': st,
                'correct': correct,
                'rt_ms': round(rt, 1)
            })
            trial_num += 1

# Calculate group means
group_mean_slope = sum(valid_slopes) / len(valid_slopes)
group_mean_acc = sum(valid_accs) / len(valid_accs)

# Calculate SD for slope
variance = sum((s - group_mean_slope) ** 2 for s in valid_slopes) / (len(valid_slopes) - 1)
group_sd_slope = math.sqrt(variance)

ground_truth['GROUP_STATS'] = {
    'group_mean_slope_ms_per_deg': round(group_mean_slope, 3),
    'group_sd_slope_ms_per_deg': round(group_sd_slope, 3),
    'group_mean_accuracy': round(group_mean_acc, 3)
}

# Write CSV
csv_path = '/home/ga/pebl/data/mental_rotation_data.csv'
with open(csv_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant','trial','angle_deg','stimulus_type','correct','rt_ms'])
    writer.writeheader()
    writer.writerows(data)

# Write Ground Truth
gt_path = '/var/lib/pebl_ground_truth/mental_rotation_gt.json'
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

os.chmod(csv_path, 0o644)
os.chown(csv_path, 1000, 1000) # ga user
PYEOF

chmod 644 /var/lib/pebl_ground_truth/mental_rotation_gt.json

# Record task start time (for anti-gaming checks)
date +%s > /tmp/task_start_time.txt

# Start a terminal and gedit for the agent
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

echo "Launching terminal and editor..."
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Mental Rotation Slope Analysis ===; echo; echo Data file: ~/pebl/data/mental_rotation_data.csv; echo Output target: ~/pebl/analysis/mental_rotation_report.json; echo; bash' > /tmp/terminal.log 2>&1 &"

sleep 2

su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/data/mental_rotation_data.csv > /tmp/gedit.log 2>&1 &"

# Maximize gedit
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "mental_rotation_data" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="