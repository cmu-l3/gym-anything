#!/bin/bash
set -e
echo "=== Setting up pursuit_rotor_learning_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Record task start time
date +%s > /tmp/task_start_time.txt

# Generate the dataset and exact ground truth
# This Python script models Fitts's Law / exponential motor learning acquisition
# mimicking the output of the PEBL Pursuit Rotor task.
python3 << 'PYEOF'
import csv, random, json
random.seed(42)

rows = []
gt = {'participants': {}, 'group_summary': {}}
valid_pids = []

# Generate 20 normative trackpad participants
for p in range(1, 21):
    pid = f"sub-{p:02d}"
    valid_pids.append(pid)
    
    # Trackpad novices start low (15-30% TOT) and learn steadily
    base_tot = random.uniform(0.15, 0.30)
    learn_rate = random.uniform(0.05, 0.15)
    
    gt_blocks = {1: [], 2: [], 3: [], 4: []}
    
    for b in range(1, 5):
        # Negatively accelerating learning curve (simplified as linear per block for simplicity)
        # We model block base performance with slight saturation
        block_base = base_tot + (b - 1) * learn_rate * (1 - (b-1)*0.1)
        
        for t in range(1, 6):
            # Trial noise
            trial_tot = block_base + random.uniform(-0.04, 0.04)
            trial_tot = max(0.0, min(1.0, trial_tot))
            
            tot_ms = int(trial_tot * 15000)
            rows.append({
                'participant_id': pid,
                'block': b,
                'trial': t,
                'turntable_rpm': 60,
                'trial_duration_ms': 15000,
                'time_on_target_ms': tot_ms
            })
            
            # Record for exact ground truth calculation
            gt_blocks[b].append((tot_ms / 15000.0) * 100)
            
    # Calculate means
    b_means = {}
    for b in range(1, 5):
        b_means[str(b)] = round(sum(gt_blocks[b]) / 5, 1)
        
    gt['participants'][pid] = {
        'block_means': b_means,
        'mli': round(b_means['4'] - b_means['1'], 1)
    }

# Generate 1 anomalous participant (sub-099) using a gaming mouse
# They will exhibit a nearly flat ~95% ceiling performance
for b in range(1, 5):
    for t in range(1, 6):
        trial_tot = random.uniform(0.94, 0.99)
        rows.append({
            'participant_id': "sub-099",
            'block': b,
            'trial': t,
            'turntable_rpm': 60,
            'trial_duration_ms': 15000,
            'time_on_target_ms': int(trial_tot * 15000)
        })

# Shuffle the rows to make it slightly more realistic
random.shuffle(rows)

# Save the dataset
with open('/home/ga/pebl/data/pursuit_rotor_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'block', 'trial', 'turntable_rpm', 'trial_duration_ms', 'time_on_target_ms'])
    writer.writeheader()
    writer.writerows(rows)

# Calculate group summary for GT
b1_all = [gt['participants'][p]['block_means']['1'] for p in valid_pids]
b2_all = [gt['participants'][p]['block_means']['2'] for p in valid_pids]
b3_all = [gt['participants'][p]['block_means']['3'] for p in valid_pids]
b4_all = [gt['participants'][p]['block_means']['4'] for p in valid_pids]
mli_all = [gt['participants'][p]['mli'] for p in valid_pids]

gt['group_summary'] = {
    'mean_block_1': round(sum(b1_all) / len(valid_pids), 1),
    'mean_block_2': round(sum(b2_all) / len(valid_pids), 1),
    'mean_block_3': round(sum(b3_all) / len(valid_pids), 1),
    'mean_block_4': round(sum(b4_all) / len(valid_pids), 1),
    'mean_mli': round(sum(mli_all) / len(valid_pids), 1)
}

# Save hidden ground truth for verifier
with open('/tmp/pursuit_rotor_gt.json', 'w') as f:
    json.dump(gt, f)
PYEOF

chown ga:ga /home/ga/pebl/data/pursuit_rotor_data.csv
chmod 600 /tmp/pursuit_rotor_gt.json

# Get ga user's DBUS session address for proper UI launching
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Pursuit Rotor Motor Learning Analysis ===; echo; echo Data file: ~/pebl/data/pursuit_rotor_data.csv; echo Output target: ~/pebl/analysis/pursuit_rotor_report.json; echo; bash' > /tmp/terminal.log 2>&1 &"

# Wait for terminal to appear and maximize it
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

echo "=== pursuit_rotor_learning_analysis setup complete ==="