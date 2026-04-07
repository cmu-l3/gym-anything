#!/bin/bash
echo "=== Setting up emotion_recognition_confusion_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Generates empirical KDEF-validation-like data as a domain-specific generator
# Synthesizes a realistic dataset of 25 healthy subjects + 2 clinical/bot anomalies
python3 << 'EOF'
import csv
import json
import random

random.seed(42) # Ensure reproducible dataset

emotions = ['Happy', 'Sad', 'Angry', 'Fear', 'Disgust', 'Surprise']
participants = [f'sub-{i:02d}' for i in range(1, 26)] + ['sub-BOT', 'sub-AMY']

# Domain-specific empirical confusion probabilities (approximating healthy adults)
base_conf = {
    'Happy': {'Happy': 95, 'Surprise': 5, 'Sad': 0, 'Angry': 0, 'Fear': 0, 'Disgust': 0},
    'Sad': {'Sad': 80, 'Angry': 10, 'Fear': 10, 'Happy': 0, 'Surprise': 0, 'Disgust': 0},
    'Angry': {'Angry': 85, 'Disgust': 10, 'Sad': 5, 'Happy': 0, 'Surprise': 0, 'Fear': 0},
    'Fear': {'Fear': 65, 'Surprise': 25, 'Sad': 10, 'Happy': 0, 'Angry': 0, 'Disgust': 0},
    'Disgust': {'Disgust': 80, 'Angry': 15, 'Sad': 5, 'Happy': 0, 'Surprise': 0, 'Fear': 0},
    'Surprise': {'Surprise': 85, 'Fear': 10, 'Happy': 5, 'Sad': 0, 'Angry': 0, 'Disgust': 0}
}

data = []
for p in participants:
    for trial in range(1, 61):
        true_em = emotions[(trial-1) % 6]
        
        if p == 'sub-BOT':
            # Force ~15% overall accuracy (random responder)
            if random.random() < 0.15:
                resp_em = true_em
            else:
                resp_em = random.choice([e for e in emotions if e != true_em])
            rt = random.uniform(200, 1500)
            
        elif p == 'sub-AMY':
            # Amygdala damage: Cannot recognize fear at all
            if true_em == 'Fear':
                resp_em = random.choice(['Surprise', 'Sad'])
            else:
                resp_em = true_em if random.random() < 0.9 else random.choice(emotions)
            rt = random.uniform(600, 1200)
            
        else:
            # Healthy participant baseline
            choices = list(base_conf[true_em].keys())
            weights = list(base_conf[true_em].values())
            resp_em = random.choices(choices, weights=weights, k=1)[0]
            rt = random.uniform(500, 1100)
            
        data.append({
            'participant_id': p, 
            'trial_num': trial, 
            'true_emotion': true_em, 
            'response_emotion': resp_em, 
            'rt_ms': round(rt, 1)
        })

# Write CSV dataset
with open('/home/ga/pebl/data/emotion_recognition_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'trial_num', 'true_emotion', 'response_emotion', 'rt_ms'])
    writer.writeheader()
    writer.writerows(data)

# Compute strict Ground Truth for verifier
valid_ppts = [p for p in participants if p not in ['sub-BOT', 'sub-AMY']]
confusion = {te: {re: 0 for re in emotions} for te in emotions}
totals = {te: 0 for te in emotions}
indiv_acc = {}

counts = {p: {'overall': 0, 'emotions': {e: 0 for e in emotions}} for p in participants}
for p in participants:
    indiv_acc[p] = {'overall': 0, 'emotions': {e: 0 for e in emotions}}

for row in data:
    p = row['participant_id']
    te = row['true_emotion']
    re = row['response_emotion']
    
    counts[p]['overall'] += 1
    counts[p]['emotions'][te] += 1
    
    if te == re:
        indiv_acc[p]['overall'] += 1
        indiv_acc[p]['emotions'][te] += 1
        
    if p in valid_ppts:
        confusion[te][re] += 1
        totals[te] += 1

# Normalize GT
for p in participants:
    if counts[p]['overall'] > 0:
        indiv_acc[p]['overall'] = round(indiv_acc[p]['overall'] / counts[p]['overall'], 4)
    for e in emotions:
        if counts[p]['emotions'][e] > 0:
            indiv_acc[p]['emotions'][e] = round(indiv_acc[p]['emotions'][e] / counts[p]['emotions'][e], 4)

for te in emotions:
    for re in emotions:
        if totals[te] > 0:
            confusion[te][re] = round(confusion[te][re] / totals[te], 4)

gt = {
    'individual': indiv_acc,
    'matrix': confusion
}
with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(gt, f)
EOF

chown ga:ga /home/ga/pebl/data/emotion_recognition_data.csv
chmod 444 /tmp/ground_truth.json

# Launch a terminal for the agent to work in
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Emotion Recognition Confusion Analysis ===; echo; echo Data file: ~/pebl/data/emotion_recognition_data.csv; echo Output target: ~/pebl/analysis/emotion_report.json; echo; bash' > /tmp/task_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== Setup complete ==="