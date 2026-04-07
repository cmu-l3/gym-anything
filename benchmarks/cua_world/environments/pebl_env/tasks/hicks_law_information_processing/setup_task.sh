#!/bin/bash
set -e
echo "=== Setting up hicks_law_information_processing task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Hick-Hyman Cognitive Model Generator (produces realistic Choice RT data with ground truth)
python3 << 'PYEOF'
import csv, random, json, math

random.seed(42)

rows = []
ground_truth = {
    "participants": {},
    "group_mean_slope": 0,
    "group_mean_intercept": 0
}

valid_slopes = []
valid_intercepts = []

for i in range(1, 21):
    pid = f"sub-{i:02d}"
    slope = random.gauss(150, 20)
    intercept = random.gauss(300, 30)
    
    gt_mean_rt_by_n = {1: [], 2: [], 4: [], 8: []}
    
    trial_num = 1
    for N in [1, 2, 4, 8]:
        H = math.log2(N)
        base_rt = intercept + slope * H
        
        for _ in range(40):
            correct = 1 if random.random() > 0.05 else 0
            # Small chance of outliers
            if random.random() < 0.02:
                rt = random.uniform(50, 5000)
            else:
                rt = random.gauss(base_rt, 30)
            rt = max(10, rt)
            
            rows.append({
                "participant_id": pid,
                "trial_num": trial_num,
                "num_choices": N,
                "stimulus_id": random.randint(1, N),
                "response_id": random.randint(1, N),
                "correct": correct,
                "rt_ms": round(rt, 1)
            })
            trial_num += 1
            
            if correct == 1 and 150 <= rt <= 3000:
                gt_mean_rt_by_n[N].append(rt)
                
    gt_means = {N: sum(gt_mean_rt_by_n[N]) / len(gt_mean_rt_by_n[N]) for N in [1, 2, 4, 8]}
    
    # Simple Linear Regression: Mean_RT = Intercept + Slope * H
    x = [0, 1, 2, 3] # H values (log2(N))
    y = [gt_means[1], gt_means[2], gt_means[4], gt_means[8]]
    n = 4
    sum_x = sum(x)
    sum_y = sum(y)
    sum_xy = sum(x[i]*y[i] for i in range(n))
    sum_xx = sum(x[i]*x[i] for i in range(n))
    
    gt_slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
    gt_intercept = (sum_y - gt_slope * sum_x) / n
    
    valid_slopes.append(gt_slope)
    valid_intercepts.append(gt_intercept)
    
    ground_truth["participants"][pid] = {
        "mean_rt_by_n": {str(k): round(v, 2) for k, v in gt_means.items()},
        "slope": gt_slope,
        "intercept": gt_intercept
    }

ground_truth["group_mean_slope"] = sum(valid_slopes) / len(valid_slopes)
ground_truth["group_mean_intercept"] = sum(valid_intercepts) / len(valid_intercepts)

# Contaminated participant (sub-99) - low accuracy, button mashing
pid = "sub-99"
trial_num = 1
for N in [1, 2, 4, 8]:
    for _ in range(40):
        correct = 1 if random.random() < 0.25 else 0
        rt = random.uniform(100, 1000)
        rows.append({
            "participant_id": pid,
            "trial_num": trial_num,
            "num_choices": N,
            "stimulus_id": random.randint(1, N),
            "response_id": random.randint(1, N),
            "correct": correct,
            "rt_ms": round(rt, 1)
        })
        trial_num += 1

# Shuffle all rows together to emulate realistic experimental trial logs
random.shuffle(rows)

with open('/home/ga/pebl/data/hicks_law_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial_num", "num_choices", "stimulus_id", "response_id", "correct", "rt_ms"])
    writer.writeheader()
    writer.writerows(rows)

with open('/tmp/hicks_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)
    
print("Generated data and ground truth.")
PYEOF

chown ga:ga /home/ga/pebl/data/hicks_law_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Launch terminal pointing agent exactly where to start
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Hick\'s Law Information Processing Analysis ===; echo; echo Data file: ~/pebl/data/hicks_law_data.csv; echo Output target: ~/pebl/analysis/hicks_report.json; echo; bash' > /tmp/hicks_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== hicks_law_information_processing setup complete ==="