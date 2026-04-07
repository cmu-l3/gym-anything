#!/bin/bash
# Setup for matrix_reasoning_ctt_analysis task
# Generates a realistic psychometric dataset using a 1-parameter logistic (Rasch) IRT model.
# Injects one speeding participant (P099) and one miskeyed item (Item 14).

set -e
echo "=== Setting up matrix_reasoning_ctt_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis

# Python script to generate IRT data and compute exact ground truth.
# We use pure Python to avoid dependency issues and ensure absolute precision.
cat > /tmp/generate_data.py << 'PYEOF'
import csv, random, math, json

random.seed(42)

# Generate true item difficulties (b) for 30 items
item_diffs = [random.gauss(0, 1.2) for _ in range(30)]
options = ['A', 'B', 'C', 'D', 'E', 'F']

participants = [f"P{i:03d}" for i in range(1, 106)]
data = []

for pid in participants:
    if pid == "P099":
        # Speeding participant: random responses, fast uniform RT
        ability = 0
        speeding = True
    else:
        # Normal participant: ability (theta) from N(0, 1)
        ability = random.gauss(0, 1)
        speeding = False
    
    for item_idx in range(30):
        item_id = item_idx + 1
        diff = item_diffs[item_idx]
        correct_ans = options[item_idx % 6]
        
        if speeding:
            rt = random.randint(200, 800)
            is_correct = 1 if random.random() < (1/6) else 0
        else:
            # Log-normal RT distribution around 15 seconds
            rt = int(random.lognormvariate(math.log(15000), 0.4))
            # 1-PL IRT (Rasch) Probability
            prob = 1.0 / (1.0 + math.exp(-(ability - diff)))
            is_correct = 1 if random.random() < prob else 0
            
        # Simulate a scoring key error for Item 14
        if item_id == 14:
            is_correct = 1 - is_correct
            
        # Choose response based on is_correct
        if is_correct == 1:
            resp = correct_ans
        else:
            resp = random.choice([o for o in options if o != correct_ans])
            
        data.append({
            'participant_id': pid,
            'item_id': item_id,
            'response': resp,
            'correct_answer': correct_ans,
            'correct': is_correct,
            'rt_ms': rt
        })

# Write CSV for the agent
with open('/home/ga/pebl/data/matrix_reasoning_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'item_id', 'response', 'correct_answer', 'correct', 'rt_ms'])
    writer.writeheader()
    writer.writerows(data)

# Compute exact ground truth
valid_pids = []
for pid in participants:
    rts = [d['rt_ms'] for d in data if d['participant_id'] == pid]
    if sum(rts)/len(rts) >= 1500:
        valid_pids.append(pid)

scores = {pid: {} for pid in valid_pids}
for d in data:
    if d['participant_id'] in valid_pids:
        scores[d['participant_id']][d['item_id']] = d['correct']

def mean(vals): return sum(vals)/len(vals)
def variance(vals): 
    m = mean(vals)
    return sum((x - m)**2 for x in vals) / (len(vals) - 1)
def pearson(x, y):
    mx = mean(x)
    my = mean(y)
    num = sum((xi - mx) * (yi - my) for xi, yi in zip(x, y))
    den = (sum((xi - mx)**2 for xi in x) * sum((yi - my)**2 for yi in y))**0.5
    return num / den if den != 0 else 0

item_stats = []
total_scores = [sum(scores[pid].values()) for pid in valid_pids]
total_var = variance(total_scores)
item_variances = []

for item_id in range(1, 31):
    item_responses = [scores[pid][item_id] for pid in valid_pids]
    diff = mean(item_responses)
    item_variances.append(variance(item_responses))
    
    other_scores = [sum(scores[pid][j] for j in range(1, 31) if j != item_id) for pid in valid_pids]
    citc = pearson(item_responses, other_scores)
    
    item_stats.append({
        'item_id': item_id,
        'difficulty': round(diff, 3),
        'corrected_item_total_correlation': round(citc, 3)
    })

k = 30
alpha = (k / (k - 1)) * (1 - sum(item_variances) / total_var)
bad_item = next(item for item in item_stats if item['corrected_item_total_correlation'] < 0)

gt = {
    "excluded_participants": [p for p in participants if p not in valid_pids],
    "cronbach_alpha": round(alpha, 3),
    "bad_item": bad_item,
    "items": item_stats
}

# Write Ground Truth (hidden from agent, used by verifier)
with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)

PYEOF

python3 /tmp/generate_data.py
chown -R ga:ga /home/ga/pebl
chmod 644 /tmp/ground_truth.json

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Matrix Reasoning CTT Analysis ===; echo; echo Data file: ~/pebl/data/matrix_reasoning_data.csv; echo Output target: ~/pebl/analysis/item_analysis_report.json; echo; bash' > /tmp/matrix_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== matrix_reasoning_ctt_analysis setup complete ==="