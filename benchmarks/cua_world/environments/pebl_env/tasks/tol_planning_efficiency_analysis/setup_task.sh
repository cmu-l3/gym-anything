#!/bin/bash
set -e
echo "=== Setting up tol_planning_efficiency_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate dataset programmatically to ensure it's "real-like" and GT is known
python3 << 'PYEOF'
import csv
import random
import json

random.seed(42)

rows = []
difficulties = [2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]

ground_truth = {}

for i in range(1, 21):
    pid = f"sub-{i:02d}"
    slope = random.gauss(1200, 200)
    intercept = random.gauss(-500, 300)
    
    gt_diffs = {d: {'opt_count': 0, 'exc_moves': 0, 'plan_time': 0} for d in set(difficulties)}
    
    for prob_idx, opt_moves in enumerate(difficulties, 1):
        prob_optimal = max(0.1, 1.0 - (opt_moves - 2) * 0.15)
        solved_opt = 1 if random.random() < prob_optimal else 0
        
        if solved_opt == 1:
            excess = 0
        else:
            excess = int(random.expovariate(1.0 / (opt_moves - 1))) + 1
            
        actual_moves = opt_moves + excess
        
        expected_plan = intercept + slope * opt_moves
        plan_time = max(200, expected_plan + random.gauss(0, 500))
        
        total_time = plan_time + actual_moves * random.gauss(800, 100)
        
        rows.append({
            'participant_id': pid,
            'problem': prob_idx,
            'optimal_moves': opt_moves,
            'actual_moves': actual_moves,
            'first_move_latency_ms': round(plan_time),
            'total_time_ms': round(total_time),
            'solved_optimal': solved_opt
        })
        
        gt_diffs[opt_moves]['opt_count'] += solved_opt
        gt_diffs[opt_moves]['exc_moves'] += excess
        gt_diffs[opt_moves]['plan_time'] += round(plan_time)
        
    ground_truth[pid] = {}
    for d in set(difficulties):
        ground_truth[pid][str(d)] = {
            'proportion_optimal': gt_diffs[d]['opt_count'] / 2.0,
            'mean_excess_moves': gt_diffs[d]['exc_moves'] / 2.0,
            'mean_planning_time_ms': gt_diffs[d]['plan_time'] / 2.0
        }

# Contaminated participant sub-99
for prob_idx, opt_moves in enumerate(difficulties, 1):
    rows.append({
        'participant_id': 'sub-99',
        'problem': prob_idx,
        'optimal_moves': opt_moves,
        'actual_moves': opt_moves + random.randint(5, 15),
        'first_move_latency_ms': random.randint(2, 8),
        'total_time_ms': random.randint(1000, 5000),
        'solved_optimal': 0
    })

# Write CSV
with open('/home/ga/pebl/data/tower_of_london_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'problem', 'optimal_moves', 'actual_moves', 'first_move_latency_ms', 'total_time_ms', 'solved_optimal'])
    writer.writeheader()
    writer.writerows(rows)

# Calculate slopes
slopes_gt = {}
for pid, diffs in ground_truth.items():
    x = [2, 3, 4, 5, 6, 7]
    y = [diffs[str(d)]['mean_planning_time_ms'] for d in x]
    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_xy = sum(x[i]*y[i] for i in range(n))
    sum_xx = sum(x[i]**2 for i in range(n))
    slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x**2)
    slopes_gt[pid] = slope

# Group means
group_means = {}
for d in x:
    group_means[str(d)] = {
        'proportion_optimal': sum(ground_truth[pid][str(d)]['proportion_optimal'] for pid in ground_truth) / 20.0,
        'mean_excess_moves': sum(ground_truth[pid][str(d)]['mean_excess_moves'] for pid in ground_truth) / 20.0,
        'mean_planning_time_ms': sum(ground_truth[pid][str(d)]['mean_planning_time_ms'] for pid in ground_truth) / 20.0
    }
group_mean_slope = sum(slopes_gt.values()) / 20.0

gt_data = {
    'participants': ground_truth,
    'slopes': slopes_gt,
    'group_means': group_means,
    'group_mean_slope': group_mean_slope
}

with open('/tmp/tol_ground_truth.json', 'w') as f:
    json.dump(gt_data, f)

PYEOF

chown ga:ga /home/ga/pebl/data/tower_of_london_data.csv
chmod 644 /home/ga/pebl/data/tower_of_london_data.csv
chmod 644 /tmp/tol_ground_truth.json

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open gedit with the data file
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/data/tower_of_london_data.csv > /tmp/gedit_tol.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "tower_of_london_data" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== tol_planning_efficiency_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/tower_of_london_data.csv"
echo "Expected output: /home/ga/pebl/analysis/tol_report.json"