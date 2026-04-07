#!/bin/bash
# Setup for ant_network_efficiency_analysis task
# Generates highly realistic ex-Gaussian Attention Network Test (ANT) data
# simulating the Fan et al. (2002) empirical distributions for 20 participants,
# plus 1 contaminated participant (sub-99).

set -e
echo "=== Setting up ANT Network Efficiency task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Use Python to generate rigorous ex-Gaussian empirical data and precompute ground truth
python3 << 'PYEOF'
import csv
import random
import json
import os

random.seed(42) # Ensure reproducible dataset

def ex_gauss(mu, sigma, tau):
    """Generate reaction time from ex-Gaussian distribution (standard for cognitive tasks)"""
    return mu + random.gauss(0, sigma) + random.expovariate(1.0 / tau)

participants = [f"sub-{i:02d}" for i in range(1, 21)]
cues = ['nocue', 'center', 'double', 'spatial']
flankers = ['congruent', 'incongruent', 'neutral']
dirs = ['left', 'right']

data = []

# Generate 20 real participants
for p in participants:
    # Participant-specific baseline speed and skewness
    base_mu = random.uniform(320, 420)
    base_tau = random.uniform(50, 90)
    
    for block in range(1, 4):
        # 96 trials per block (4 cues * 3 flankers * 2 dirs * 4 reps)
        trials = []
        for c in cues:
            for f in flankers:
                for d in dirs:
                    for _ in range(4):
                        trials.append((c, f, d))
        random.shuffle(trials)
        
        for t, (c, f, d) in enumerate(trials, 1):
            # Known empirical effects (Fan et al., 2002)
            cue_eff = {'nocue': 35, 'center': 0, 'double': -12, 'spatial': -38}[c]
            flanker_eff = {'congruent': -25, 'incongruent': 65, 'neutral': -18}[f]
            
            rt = ex_gauss(base_mu + cue_eff + flanker_eff, 25, base_tau)
            
            # Realistic accuracy based on condition difficulty
            err_prob = 0.09 if f == 'incongruent' else 0.02
            acc = 1 if random.random() > err_prob else 0
            
            # Random attentional lapses (very slow RT)
            if random.random() < 0.01:
                rt += random.uniform(400, 900)
                
            data.append({
                'participant_id': p,
                'block': block,
                'trial': t,
                'cue_type': c,
                'flanker_type': f,
                'target_direction': d,
                'accuracy': acc,
                'rt_ms': round(rt, 1)
            })

# Generate 1 contaminated participant (sub-99) - button mashing
for block in range(1, 4):
    for t in range(1, 97):
        data.append({
            'participant_id': 'sub-99',
            'block': block,
            'trial': t,
            'cue_type': random.choice(cues),
            'flanker_type': random.choice(flankers),
            'target_direction': random.choice(dirs),
            'accuracy': random.choice([0, 1]), # Chance accuracy
            'rt_ms': round(random.uniform(40, 65), 1) # Physiologically impossible choice RT
        })

# Write CSV for the agent
os.makedirs('/home/ga/pebl/data', exist_ok=True)
with open('/home/ga/pebl/data/ant_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=data[0].keys())
    writer.writeheader()
    writer.writerows(data)

# Precompute exact ground truth from the generated data (Correct Trials ONLY)
gt = {'participants': {}, 'group_means': {}}
for p in participants:
    p_data = [d for d in data if d['participant_id'] == p and d['accuracy'] == 1]
    
    cue_rts = {c: [] for c in cues}
    flanker_rts = {f: [] for f in flankers}
    
    for d in p_data:
        cue_rts[d['cue_type']].append(d['rt_ms'])
        flanker_rts[d['flanker_type']].append(d['rt_ms'])
        
    mean_cue = {c: sum(v)/len(v) for c, v in cue_rts.items()}
    mean_flanker = {f: sum(v)/len(v) for f, v in flankers.items()}
    
    alerting = mean_cue['nocue'] - mean_cue['double']
    orienting = mean_cue['center'] - mean_cue['spatial']
    executive = mean_flanker['incongruent'] - mean_flanker['congruent']
    
    gt['participants'][p] = {
        'alerting_ms': alerting,
        'orienting_ms': orienting,
        'executive_ms': executive
    }

gt['group_means'] = {
    'alerting_ms': sum(x['alerting_ms'] for x in gt['participants'].values()) / len(participants),
    'orienting_ms': sum(x['orienting_ms'] for x in gt['participants'].values()) / len(participants),
    'executive_ms': sum(x['executive_ms'] for x in gt['participants'].values()) / len(participants),
}

# Save ground truth to hidden location for verifier
os.makedirs('/var/lib/pebl_ground_truth', exist_ok=True)
with open('/var/lib/pebl_ground_truth/ant_ground_truth.json', 'w') as f:
    json.dump(gt, f)

# Secure the ground truth file
os.chmod('/var/lib/pebl_ground_truth/ant_ground_truth.json', 0o600)
PYEOF

chown ga:ga /home/ga/pebl/data/ant_data.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === ANT Network Efficiency Analysis ===; echo; echo Data file: ~/pebl/data/ant_data.csv; echo Output target: ~/pebl/analysis/ant_report.json; echo; bash' > /tmp/ant_terminal.log 2>&1 &"

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

echo "=== ant_network_efficiency_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/ant_data.csv"
echo "Expected output: /home/ga/pebl/analysis/ant_report.json"