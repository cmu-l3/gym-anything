#!/bin/bash
# Setup for posner_cueing_ior_analysis task
# Generates a highly realistic Posner Cueing dataset using ex-Gaussian parameters
# to simulate human reaction times, facilitation, and Inhibition of Return (IOR).

set -e
echo "=== Setting up posner_cueing_ior_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic Posner Exogenous Cueing data and exact Ground Truth
python3 << 'PYEOF'
import csv
import random
import json

random.seed(101) # Ensure deterministic ground truth
rows = []
participants = [f"sub-{i:02d}" for i in range(1, 25)]

gt = {'participants': {}, 'group_means': {}}
valid_effects_short = []
valid_effects_long = []

for pid in participants:
    # Subject-level random effects
    subj_base_rt = random.uniform(280, 360)
    subj_acc_rate = random.uniform(0.88, 0.98)
    subj_ior_magnitude = random.uniform(10, 45) # Long SOA validity effect (negative)
    subj_fac_magnitude = random.uniform(15, 50) # Short SOA validity effect (positive)
    
    rt_sums_filtered = {'short_valid': [], 'short_invalid': [], 'long_valid': [], 'long_invalid': []}
    rt_sums_unfiltered = {'short_valid': [], 'short_invalid': [], 'long_valid': [], 'long_invalid': []}

    for trial in range(1, 161):
        soa = random.choice([100, 800])
        validity = random.choice(['valid', 'invalid'])
        
        # Determine accuracy
        acc = 1 if random.random() < subj_acc_rate else 0
        
        # Ex-Gaussian parameters: Normal(mu, sigma) + Exponential(tau)
        mu = subj_base_rt
        sigma = 35
        tau = 40
        
        if soa == 100:
            if validity == 'valid': mu -= (subj_fac_magnitude / 2)
            else: mu += (subj_fac_magnitude / 2)
        else: # 800
            if validity == 'valid': mu += (subj_ior_magnitude / 2)
            else: mu -= (subj_ior_magnitude / 2)
            
        # Generate RT
        rt = random.gauss(mu, sigma) + random.expovariate(1.0/tau)
        
        # Error trials are heavily skewed (lapses or impulsive responses)
        if acc == 0:
            if random.random() < 0.5: rt -= 100
            else: rt += 300
            
        rt = max(150, min(rt, 1500)) # Truncate to realistic human bounds
        rt_rounded = round(rt, 1)
        rows.append([pid, trial, soa, validity, acc, rt_rounded])
        
        key = f"{'short' if soa==100 else 'long'}_{validity}"
        rt_sums_unfiltered[key].append(rt_rounded)
        if acc == 1:
            rt_sums_filtered[key].append(rt_rounded)

    # Calculate Ground Truths
    means_filtered = {k: sum(v)/len(v) for k, v in rt_sums_filtered.items()}
    means_unfiltered = {k: sum(v)/len(v) for k, v in rt_sums_unfiltered.items()}
    
    short_effect = means_filtered['short_invalid'] - means_filtered['short_valid']
    long_effect = means_filtered['long_invalid'] - means_filtered['long_valid']
    
    gt['participants'][pid] = {
        'short_soa_validity_effect': short_effect,
        'long_soa_validity_effect': long_effect,
        'filtered_means': means_filtered,
        'unfiltered_means': means_unfiltered
    }
    valid_effects_short.append(short_effect)
    valid_effects_long.append(long_effect)

# Inject corrupted participant sub-99 (Hardware artifact)
for trial in range(1, 161):
    soa = random.choice([100, 800])
    validity = random.choice(['valid', 'invalid'])
    acc = random.choice([0, 1])
    rt = random.uniform(15, 35) # Impossibly fast RT
    rows.append(['sub-99', trial, soa, validity, acc, round(rt, 1)])

# Group means GT
gt['group_means']['short_soa_validity_effect'] = sum(valid_effects_short) / len(valid_effects_short)
gt['group_means']['long_soa_validity_effect'] = sum(valid_effects_long) / len(valid_effects_long)

# Save the dataset
with open('/home/ga/pebl/data/posner_cueing_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['participant_id', 'trial', 'soa_ms', 'cue_validity', 'accuracy', 'rt_ms'])
    writer.writerows(rows)

# Save Ground Truth to hidden location for verifier
with open('/tmp/posner_gt.json', 'w') as f:
    json.dump(gt, f)

print("Realistic Posner dataset generated successfully.")
PYEOF

chown ga:ga /home/ga/pebl/data/posner_cueing_data.csv
chmod 644 /tmp/posner_gt.json

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Posner Cueing and IOR Analysis ===; echo; echo Data file: ~/pebl/data/posner_cueing_data.csv; echo Output target: ~/pebl/analysis/posner_ior_report.json; echo; bash' > /tmp/posner_terminal.log 2>&1 &"

# Maximize terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== posner_cueing_ior_analysis setup complete ==="