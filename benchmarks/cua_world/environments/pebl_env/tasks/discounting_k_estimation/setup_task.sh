#!/bin/bash
# Setup script for discounting_k_estimation task
# Generates realistic delay discounting data and injects a contaminated participant

set -e
echo "=== Setting up discounting_k_estimation task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic delay discounting data and ground truth
python3 << 'PYEOF'
import csv, json, random, math
random.seed(12345)

delays = [7, 14, 30, 60, 90, 180]
imm_amts = [20, 35, 50, 65, 80, 95]
del_amt = 100

true_ks = [0.0012, 0.0025, 0.0051, 0.0084, 0.015, 0.022, 0.035, 0.055, 0.071, 0.095, 0.12, 0.008, 0.045, 0.003, 0.088]
participants = [f"sub-{i:02d}" for i in range(1, 16)]

rows = []
gt = {}

for pid, k_true in zip(participants, true_ks):
    chosen = []
    # Create grid of choices
    for d in delays:
        for i in imm_amts:
            sv = del_amt / (1 + k_true * d)
            # Logistic choice probability to add realistic noise
            prob_imm = 1.0 / (1.0 + math.exp(-0.25 * (i - sv)))
            choice = 0 if random.random() < prob_imm else 1
            rt = random.randint(500, 2500)
            chosen.append({'imm': i, 'del': del_amt, 'd': d, 'choice': choice, 'rt': rt})

    # Ensure bounds exist (at least one immediate, at least one delayed)
    k_indiffs_imm = [(c['del']/c['imm'] - 1)/c['d'] for c in chosen if c['choice'] == 0]
    k_indiffs_del = [(c['del']/c['imm'] - 1)/c['d'] for c in chosen if c['choice'] == 1]

    if not k_indiffs_imm:
        # Flip trial with smallest k_indiff to immediate
        idx = min(range(len(chosen)), key=lambda i: (chosen[i]['del']/chosen[i]['imm']-1)/chosen[i]['d'])
        chosen[idx]['choice'] = 0
        val = (chosen[idx]['del']/chosen[idx]['imm']-1)/chosen[idx]['d']
        k_indiffs_imm.append(val)
        k_indiffs_del.remove(val)
        
    if not k_indiffs_del:
        # Flip trial with largest k_indiff to delayed
        idx = max(range(len(chosen)), key=lambda i: (chosen[i]['del']/chosen[i]['imm']-1)/chosen[i]['d'])
        chosen[idx]['choice'] = 1
        val = (chosen[idx]['del']/chosen[idx]['imm']-1)/chosen[idx]['d']
        k_indiffs_del.append(val)
        k_indiffs_imm.remove(val)

    upper = min(k_indiffs_imm)
    lower = max(k_indiffs_del)
    est_k = math.sqrt(lower * upper)
    
    gt[pid] = {
        'k': est_k,
        'ln_k': math.log(est_k),
        'upper': upper,
        'lower': lower
    }

    for idx, c in enumerate(chosen):
        rows.append({
            'participant_id': pid,
            'trial': idx + 1,
            'immediate_amount': c['imm'],
            'delayed_amount': c['del'],
            'delay_days': c['d'],
            'choice': c['choice'],
            'rt_ms': c['rt']
        })

# Inject corrupted participant
for idx in range(36):
    i = random.choice(imm_amts)
    d = random.choice(delays)
    rows.append({
        'participant_id': 'sub-99999',
        'trial': idx + 1,
        'immediate_amount': i,
        'delayed_amount': 100,
        'delay_days': d,
        'choice': 0,  # 100% immediate
        'rt_ms': random.randint(10, 30)  # Impossible RT
    })

# Write CSV
with open('/home/ga/pebl/data/discounting_choices.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'trial', 'immediate_amount', 'delayed_amount', 'delay_days', 'choice', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)

# Compute group medians for ground truth
valid_ks = [v['k'] for v in gt.values()]
valid_ln_ks = [v['ln_k'] for v in gt.values()]
valid_ks.sort()
valid_ln_ks.sort()

n = len(valid_ks)
gt['group_median_k'] = (valid_ks[n//2 - 1] + valid_ks[n//2]) / 2 if n % 2 == 0 else valid_ks[n//2]
gt['group_median_ln_k'] = (valid_ln_ks[n//2 - 1] + valid_ln_ks[n//2]) / 2 if n % 2 == 0 else valid_ln_ks[n//2]

# Save ground truth (hidden from agent)
with open('/tmp/.discounting_gt.json', 'w') as f:
    json.dump(gt, f)
PYEOF

chown ga:ga /home/ga/pebl/data/discounting_choices.csv
chmod 600 /tmp/.discounting_gt.json

# Record start time
date +%s > /tmp/task_start_time.txt

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=110x30 -- bash -c 'echo === Delay Discounting Hyperbolic K Estimation ===; echo; echo Data file: ~/pebl/data/discounting_choices.csv; echo Expected report: ~/pebl/analysis/discounting_report.json; echo; bash' > /tmp/discounting_terminal.log 2>&1 &"

for i in {1..15}; do
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

echo "=== Setup complete ==="