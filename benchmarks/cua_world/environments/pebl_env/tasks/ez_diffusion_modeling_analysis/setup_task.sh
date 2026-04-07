#!/bin/bash
set -e
echo "=== Setting up ez_diffusion_modeling_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic LDT data and compute exact ground truth locally
python3 << 'PYEOF'
import csv
import random
import json
import math

random.seed(42)

participants = [f"sub-{i:02d}" for i in range(1, 25)]
conditions = {
    "Word_HighFreq": {"n": 40, "mean_rt": 0.600, "sd_rt": 0.150, "acc": 0.95},
    "Word_LowFreq": {"n": 40, "mean_rt": 0.750, "sd_rt": 0.200, "acc": 0.85},
    "NonWord": {"n": 80, "mean_rt": 0.850, "sd_rt": 0.250, "acc": 0.90}
}

rows = []

# Generate data
for p in participants:
    for cond, props in conditions.items():
        n = props["n"]
        for _ in range(n):
            # Inject 100% accuracy condition for edge case testing
            if p == "sub-01" and cond == "Word_HighFreq":
                acc_val = 1
            else:
                acc_val = 1 if random.random() < props["acc"] else 0
            
            # Using lognormal distribution for realistic RTs
            mu = math.log(props["mean_rt"])
            sigma = 0.2
            rt = random.lognormvariate(mu, sigma)
            rt_ms = max(200, int(rt * 1000))
            
            rows.append({
                "participant_id": p,
                "trial": len(rows) + 1,
                "condition": cond,
                "accuracy": acc_val,
                "rt_ms": rt_ms
            })

# Inject corrupted participant (impossible variance)
for cond, props in conditions.items():
    for _ in range(props["n"]):
        rows.append({
            "participant_id": "sub-999",
            "trial": len(rows) + 1,
            "condition": cond,
            "accuracy": 1,
            "rt_ms": 400
        })

with open('/home/ga/pebl/data/ldt_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "condition", "accuracy", "rt_ms"])
    writer.writeheader()
    writer.writerows(rows)

# Helper math functions
def mean(lst):
    return sum(lst)/len(lst) if lst else 0

def variance(lst):
    if len(lst) < 2: return 0
    m = mean(lst)
    return sum((x - m)**2 for x in lst)/(len(lst)-1)

def compute_ez(pc, mrt, vrt):
    s = 0.1
    if pc == 1.0 or pc == 0.0 or pc == 0.5:
        return None
    
    L = math.log(pc / (1 - pc))
    x = L * (pc**2 * L - pc * L + pc - 0.5) / vrt
    if x <= 0:
        return None
    v = s * (x**0.25)
    a = (s**2 * L) / v
    y = (-v * a) / (s**2)
    
    try:
        if y > 100:
            exp_y = float('inf')
        else:
            exp_y = math.exp(y)
            
        if exp_y == float('inf'):
            md = (a / (2*v)) * (-1)
        else:
            md = (a / (2*v)) * ((1 - exp_y) / (1 + exp_y))
    except OverflowError:
        md = (a / (2*v)) * (-1)
        
    ter = mrt - md
    return v, a, ter

# Pre-compute exact ground truth
gt = {"participants": {}, "group_means": {}}
cond_sums = {"Word_HighFreq": {"v":0, "a":0, "Ter":0, "n":0},
             "Word_LowFreq": {"v":0, "a":0, "Ter":0, "n":0}}

for p in participants:
    gt["participants"][p] = {}
    for cond in ["Word_HighFreq", "Word_LowFreq"]:
        c_rows = [r for r in rows if r["participant_id"] == p and r["condition"] == cond]
        N = len(c_rows)
        correct_rts = [r["rt_ms"]/1000.0 for r in c_rows if r["accuracy"] == 1]
        pc = len(correct_rts) / N if N > 0 else 0
        
        # Explicit Edge Correction logic
        if pc == 1.0:
            pc = 1 - 1/(2*N)
        elif pc == 0.0:
            pc = 1/(2*N)
            
        mrt = mean(correct_rts)
        vrt = variance(correct_rts)
        
        res = compute_ez(pc, mrt, vrt)
        if res:
            v, a, ter = res
            gt["participants"][p][cond] = {"v": v, "a": a, "Ter": ter}
            cond_sums[cond]["v"] += v
            cond_sums[cond]["a"] += a
            cond_sums[cond]["Ter"] += ter
            cond_sums[cond]["n"] += 1

for cond in cond_sums:
    n = cond_sums[cond]["n"]
    if n > 0:
        gt["group_means"][cond] = {
            "mean_v": cond_sums[cond]["v"]/n,
            "mean_a": cond_sums[cond]["a"]/n,
            "mean_Ter": cond_sums[cond]["Ter"]/n
        }

with open('/tmp/ez_gt.json', 'w') as f:
    json.dump(gt, f)
PYEOF

chown ga:ga /home/ga/pebl/data/ldt_data.csv
chmod 600 /tmp/ez_gt.json  # Hide GT from agent

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === EZ-Diffusion Modeling Analysis ===; echo; echo Data file: ~/pebl/data/ldt_data.csv; echo Output target: ~/pebl/analysis/ez_diffusion_report.json; echo; bash' > /tmp/ez_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== ez_diffusion_modeling_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/ldt_data.csv"
echo "Expected output: /home/ga/pebl/analysis/ez_diffusion_report.json"