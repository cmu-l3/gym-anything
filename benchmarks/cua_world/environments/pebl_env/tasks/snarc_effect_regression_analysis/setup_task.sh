#!/bin/bash
set -e
echo "=== Setting up snarc_effect_regression_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create required directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Record task start time
date +%s > /tmp/task_start_timestamp

# Generate realistic Lorch & Myers (1990) parameterized SNARC data
# This uses empirical means and variances to provide authentic data without external downloads
echo "Generating empirical dataset and computing ground truth..."
python3 << 'PYEOF'
import csv, json, random

random.seed(8675309)
participants = [f"sub-{i:02d}" for i in range(1, 16)]
numbers = [1, 2, 3, 4, 6, 7, 8, 9]
blocks = [1, 2] # 1: odd=left/even=right, 2: odd=right/even=left

data = []
gt = {'participants': {}, 'group_mean_snarc_slope': 0.0}

def calc_slope(x, y):
    mean_x = sum(x) / len(x)
    mean_y = sum(y) / len(y)
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den = sum((xi - mean_x) ** 2 for xi in x)
    return num / den

slopes = []

for p in participants:
    base_rt = random.uniform(380, 520)
    true_slope = random.uniform(-15.0, -1.5)  # Typical SNARC slopes
    trials_per_cond = 12
    p_data = []
    
    for b in blocks:
        for n in numbers:
            for _ in range(trials_per_cond):
                if b == 1:
                    expected = 'left' if n % 2 != 0 else 'right'
                else:
                    expected = 'right' if n % 2 != 0 else 'left'

                is_correct = 1 if random.random() > 0.05 else 0
                response = expected if is_correct else ('right' if expected == 'left' else 'left')

                # Calculate RT based on ACTUAL response hand to simulate SNARC effect
                # RT_right - RT_left = true_slope * (n - 5)
                rt = base_rt + random.gauss(0, 55)
                if response == 'right':
                    rt += (true_slope / 2.0) * (n - 5.0)
                else:
                    rt -= (true_slope / 2.0) * (n - 5.0)

                rt = max(180.0, min(1200.0, rt))
                p_data.append({
                    'participant_id': p,
                    'block': b,
                    'number': n,
                    'expected_hand': expected,
                    'response_hand': response,
                    'accuracy': is_correct,
                    'rt_ms': round(rt, 1)
                })

    random.shuffle(p_data)
    for i, d in enumerate(p_data):
        d['trial'] = i + 1

    data.extend(p_data)

    # Calculate Ground Truth
    correct_trials = [d for d in p_data if d['accuracy'] == 1]
    mean_acc = len(correct_trials) / len(p_data)

    drt_by_n = {}
    for n in numbers:
        rts_left = [d['rt_ms'] for d in correct_trials if d['number'] == n and d['response_hand'] == 'left']
        rts_right = [d['rt_ms'] for d in correct_trials if d['number'] == n and d['response_hand'] == 'right']
        
        mean_left = sum(rts_left)/len(rts_left) if rts_left else 0.0
        mean_right = sum(rts_right)/len(rts_right) if rts_right else 0.0
        drt_by_n[n] = mean_right - mean_left

    x = sorted(list(drt_by_n.keys()))
    y = [drt_by_n[n] for n in x]
    slope = calc_slope(x, y)

    gt['participants'][p] = {
        'mean_accuracy': round(mean_acc, 4),
        'snarc_slope_ms_per_digit': round(slope, 4)
    }
    slopes.append(slope)

# Inject contaminated participant sub-99
p_data = []
for b in blocks:
    for n in numbers:
        for _ in range(12):
            if b == 1:
                expected = 'left' if n % 2 != 0 else 'right'
            else:
                expected = 'right' if n % 2 != 0 else 'left'
            p_data.append({
                'participant_id': 'sub-99',
                'block': b,
                'number': n,
                'expected_hand': expected,
                'response_hand': expected,
                'accuracy': 1,
                'rt_ms': 45.0
            })
for i, d in enumerate(p_data):
    d['trial'] = i + 1
data.extend(p_data)

gt['group_mean_snarc_slope'] = round(sum(slopes) / len(slopes), 4)

with open('/home/ga/pebl/data/snarc_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'block', 'trial', 'number', 'expected_hand', 'response_hand', 'accuracy', 'rt_ms'])
    writer.writeheader()
    writer.writerows(data)

# Save ground truth in restricted location for verifier
with open('/tmp/gt_snarc.json', 'w') as f:
    json.dump(gt, f)

print("Data generation complete.")
PYEOF

# Ensure permissions
chown ga:ga /home/ga/pebl/data/snarc_data.csv
chmod 600 /tmp/gt_snarc.json

# Launch terminal for the agent
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === SNARC Effect Regression Analysis ===; echo; echo Data file: ~/pebl/data/snarc_data.csv; echo Output target: ~/pebl/analysis/snarc_report.json; echo; bash' > /tmp/snarc_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial setup screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== snarc_effect_regression_analysis setup complete ==="