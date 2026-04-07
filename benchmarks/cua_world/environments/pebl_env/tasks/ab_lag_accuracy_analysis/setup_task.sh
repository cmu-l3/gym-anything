#!/bin/bash
# Setup for ab_lag_accuracy_analysis task
# Generates realistic Attentional Blink normative data for 24 participants
# and 1 contaminated participant (p00) with impossible 100% accuracy.

set -e
echo "=== Setting up ab_lag_accuracy_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic AB data and Ground Truth
python3 << 'PYEOF'
import csv, random, json

# Use a fixed seed to ensure deterministic output for the verifier
random.seed(42)

lags = [1, 2, 3, 4, 5, 7, 8]
trials_per_lag = 12
participants = [f"p{i:02d}" for i in range(1, 25)]

# Empirical baseline T2|T1 probabilities per lag (classic AB curve)
base_t2_t1 = {1: 0.85, 2: 0.45, 3: 0.35, 4: 0.55, 5: 0.70, 7: 0.85, 8: 0.90}

data = []
gt = {"participants": {}, "group_means": {"t2_given_t1": {}, "ab_magnitude": 0}}

for p in participants:
    p_t1_acc = random.uniform(0.85, 0.95)
    noise = random.uniform(-0.1, 0.1)
    
    t1_correct_count = 0
    t2_given_t1_counts = {lag: {'t1_corr': 0, 't2_corr': 0} for lag in lags}
    
    for lag in lags:
        for _ in range(trials_per_lag):
            # T1 correctness
            t1_c = 1 if random.random() < p_t1_acc else 0
            t1_correct_count += t1_c
            
            if t1_c == 1:
                # T2 correctness is conditional on T1
                prob = min(1.0, max(0.0, base_t2_t1[lag] + noise + random.uniform(-0.05, 0.05)))
                t2_c = 1 if random.random() < prob else 0
                t2_given_t1_counts[lag]['t1_corr'] += 1
                t2_given_t1_counts[lag]['t2_corr'] += t2_c
            else:
                # If T1 missed, T2 is roughly guessing
                t2_c = 1 if random.random() < 0.5 else 0
                
            data.append({
                'participant': p,
                'trial': 0, # Will set later
                'lag': lag,
                't1_correct': t1_c,
                't2_correct': t2_c
            })
            
    # Calculate ground truth for verifier
    p_gt = {'t2_given_t1': {}}
    for lag in lags:
        c1 = t2_given_t1_counts[lag]['t1_corr']
        c2 = t2_given_t1_counts[lag]['t2_corr']
        p_gt['t2_given_t1'][str(lag)] = round(c2 / c1 if c1 > 0 else 0.0, 4)
        
    vals = list(p_gt['t2_given_t1'].values())
    p_gt['ab_magnitude'] = round(max(vals) - min(vals), 4) if vals else 0
    gt['participants'][p] = p_gt

# Add contaminated participant p00
for lag in lags:
    for _ in range(trials_per_lag):
        data.append({
            'participant': 'p00',
            'trial': 0,
            'lag': lag,
            't1_correct': 1,
            't2_correct': 1
        })

# Randomize rows slightly to emulate realistic raw trial output, 
# then assign sequential trial numbers per participant
random.shuffle(data)
data.sort(key=lambda x: x['participant'])

trials = {p: 1 for p in ['p00'] + participants}
for row in data:
    row['trial'] = trials[row['participant']]
    trials[row['participant']] += 1

# Write CSV
with open('/home/ga/pebl/data/ab_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant', 'trial', 'lag', 't1_correct', 't2_correct'])
    writer.writeheader()
    writer.writerows(data)

# Compute group means for ground truth
for lag in lags:
    lag_sum = sum(gt['participants'][p]['t2_given_t1'][str(lag)] for p in participants)
    gt['group_means']['t2_given_t1'][str(lag)] = round(lag_sum / len(participants), 4)

mag_sum = sum(gt['participants'][p]['ab_magnitude'] for p in participants)
gt['group_means']['ab_magnitude'] = round(mag_sum / len(participants), 4)

# Write hidden ground truth for verifier
with open('/tmp/ab_ground_truth.json', 'w') as f:
    json.dump(gt, f)

PYEOF

chown ga:ga /home/ga/pebl/data/ab_data.csv
date +%s > /tmp/task_start_timestamp

# Get DBUS session
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Attentional Blink Analysis ===; echo; echo Data file: ~/pebl/data/ab_data.csv; echo Expected output: ~/pebl/analysis/ab_report.json; echo; bash' > /tmp/ab_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Open gedit to show the data file format
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/data/ab_data.csv > /dev/null 2>&1 &"

echo "=== ab_lag_accuracy_analysis setup complete ==="