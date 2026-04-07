#!/bin/bash
set -e
echo "=== Setting up pebl_multisite_data_harmonization task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create directories
mkdir -p /home/ga/pebl/data/multisite_raw/site_a
mkdir -p /home/ga/pebl/data/multisite_raw/site_b
mkdir -p /home/ga/pebl/data/multisite_raw/site_c
mkdir -p /home/ga/pebl/analysis

# Run Python script to generate the synthetic-like dataset but with real structural complexity
python3 << 'PYEOF'
import os
import csv
import random
import json

random.seed(10101)

base_dir = '/home/ga/pebl/data/multisite_raw'
sites = ['site_a', 'site_b', 'site_c']

valid_participants = 30
participants_per_site = 10
rules = ['Color', 'Shape', 'Number']

gt_rt_sum = 0
gt_rt_count = 0

# Generate 10 valid for each site
for site_idx, site in enumerate(sites):
    site_letter = chr(65 + site_idx)
    for p in range(1, participants_per_site + 1):
        pid = f"sub-{site_letter}{p:02d}"
        
        rows = []
        for b in range(1, 5):
            for t in range(1, 17):
                rule = random.choice(rules)
                resp = random.randint(1, 4)
                acc = random.choice([0, 1])
                rt = random.randint(300, 2500)
                
                gt_rt_sum += rt
                gt_rt_count += 1
                
                rows.append({
                    'participant_id': pid,
                    'block': b,
                    'trial': t,
                    'rule': rule,
                    'response': resp,
                    'accuracy': acc,
                    'rt_ms': rt
                })
        
        if site == 'site_a':
            filepath = os.path.join(base_dir, site, f"{pid}_bcst.txt")
            with open(filepath, 'w', newline='') as f:
                writer = csv.writer(f, delimiter='\t')
                writer.writerow(['Subject', 'Block', 'Trial', 'TargetRule', 'Response', 'Correct', 'AbsRT'])
                for r in rows:
                    writer.writerow([r['participant_id'], r['block'], r['trial'], r['rule'], r['response'], r['accuracy'], r['rt_ms']])
        elif site == 'site_b':
            filepath = os.path.join(base_dir, site, f"{pid}_bcst.csv")
            with open(filepath, 'w', newline='') as f:
                writer = csv.writer(f, delimiter=',')
                writer.writerow(['pt_id', 'blk', 'trl', 'rule', 'resp', 'acc', 'rt_ms'])
                for r in rows:
                    writer.writerow([r['participant_id'], r['block'], r['trial'], r['rule'], r['response'], r['accuracy'], r['rt_ms']])
        elif site == 'site_c':
            filepath = os.path.join(base_dir, site, f"{pid}_bcst.csv")
            with open(filepath, 'w', newline='') as f:
                writer = csv.writer(f, delimiter=';')
                writer.writerow(['Block', 'Trial', 'Category', 'Choice', 'Hit', 'Time'])
                for r in rows:
                    writer.writerow([r['block'], r['trial'], r['rule'], r['response'], r['accuracy'], r['rt_ms']])

# Inject incomplete participant to site_a (only 45 trials)
pid_inc = "sub-A11"
filepath = os.path.join(base_dir, 'site_a', f"{pid_inc}_bcst.txt")
with open(filepath, 'w', newline='') as f:
    writer = csv.writer(f, delimiter='\t')
    writer.writerow(['Subject', 'Block', 'Trial', 'TargetRule', 'Response', 'Correct', 'AbsRT'])
    for b in range(1, 4):
        max_t = 16 if b < 3 else 14
        for t in range(1, max_t):
            writer.writerow([pid_inc, b, t, 'Shape', 2, 0, 800])

# Inject corrupted participant to site_b
pid_corr = "sub-B11"
filepath = os.path.join(base_dir, 'site_b', f"{pid_corr}_bcst.csv")
with open(filepath, 'w') as f:
    f.write("<!DOCTYPE html>\n<html><body><h1>502 Bad Gateway</h1><p>nginx/1.18.0</p></body></html>\n")

gt_mean_rt = gt_rt_sum / gt_rt_count

gt_data = {
    "total_valid": valid_participants,
    "total_rows": gt_rt_count,
    "gt_mean_rt": gt_mean_rt,
    "excluded": [pid_inc, pid_corr]
}

with open('/tmp/harmonization_gt.json', 'w') as f:
    json.dump(gt_data, f)
PYEOF

chown -R ga:ga /home/ga/pebl

# Record start time
date +%s > /tmp/task_start_time.txt

# Open a terminal for the agent
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Multi-Site Data Harmonization Task ===; echo; echo Raw Data: ~/pebl/data/multisite_raw/; echo Target CSV: ~/pebl/data/harmonized_dataset.csv; echo Target JSON: ~/pebl/analysis/harmonization_report.json; echo; bash' > /tmp/task_terminal.log 2>&1 &"

# Maximize Terminal
for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="