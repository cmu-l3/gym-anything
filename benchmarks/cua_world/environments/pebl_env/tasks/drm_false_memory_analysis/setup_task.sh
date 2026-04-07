#!/bin/bash
# Setup for drm_false_memory_analysis task

set -e
echo "=== Setting up drm_false_memory_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic normative DRM data based on Roediger & McDermott (1995)
# This acts as a domain-specific statistical generator for cognitive data, 
# ensuring realistic variance, individual differences, and log-normal RT distributions.
python3 << 'PYEOF'
import csv, random, math

random.seed(42)

lists = ['sleep', 'chair', 'mountain', 'needle', 'sweet', 'music', 'doctor', 'slow', 'river', 'cold']
participants = [f"sub-{i:02d}" for i in range(1, 26)]

rows = []

for p in participants:
    p_hit_rate = random.gauss(0.75, 0.10)
    p_lure_rate = random.gauss(0.65, 0.15)
    p_fa_rate = random.gauss(0.15, 0.05)
    
    p_hit_rate = max(0.4, min(0.95, p_hit_rate))
    p_lure_rate = max(0.3, min(0.95, p_lure_rate))
    p_fa_rate = max(0.01, min(0.4, p_fa_rate))
    
    p_rt_mean = random.gauss(800, 150)
    
    for l in lists:
        for w in range(12):
            resp = 1 if random.random() < p_hit_rate else 0
            rt = int(random.lognormvariate(math.log(p_rt_mean), 0.3))
            rows.append({'participant_id': p, 'list_id': l, 'word': f"{l}_study_{w}", 'condition': 'studied', 'response': resp, 'rt_ms': rt})
        
        resp = 1 if random.random() < p_lure_rate else 0
        rt = int(random.lognormvariate(math.log(p_rt_mean + 150), 0.3))
        rows.append({'participant_id': p, 'list_id': l, 'word': l, 'condition': 'critical_lure', 'response': resp, 'rt_ms': rt})
        
        for w in range(3):
            resp = 1 if random.random() < p_fa_rate else 0
            rt = int(random.lognormvariate(math.log(p_rt_mean - 50), 0.3))
            rows.append({'participant_id': p, 'list_id': l, 'word': f"unrel_{l}_{w}", 'condition': 'unrelated', 'response': resp, 'rt_ms': rt})

# Inject corrupted participant sub-99 (Automated button mashing artifact)
for l in lists:
    for w in range(12):
        rows.append({'participant_id': 'sub-99', 'list_id': l, 'word': f"{l}_study_{w}", 'condition': 'studied', 'response': 1, 'rt_ms': random.randint(20, 80)})
    rows.append({'participant_id': 'sub-99', 'list_id': l, 'word': l, 'condition': 'critical_lure', 'response': 1, 'rt_ms': random.randint(20, 80)})
    for w in range(3):
        rows.append({'participant_id': 'sub-99', 'list_id': l, 'word': f"unrel_{l}_{w}", 'condition': 'unrelated', 'response': 1, 'rt_ms': random.randint(20, 80)})

with open('/home/ga/pebl/data/drm_recognition_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'list_id', 'word', 'condition', 'response', 'rt_ms'])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga /home/ga/pebl/data/drm_recognition_data.csv

# Keep a hidden ground truth copy for the verifier to calculate exact parameters
cp /home/ga/pebl/data/drm_recognition_data.csv /tmp/.drm_ground_truth.csv
chmod 600 /tmp/.drm_ground_truth.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === DRM False Memory Analysis ===; echo; echo Data file: ~/pebl/data/drm_recognition_data.csv; echo Output target: ~/pebl/analysis/drm_report.json; echo; bash' > /tmp/drm_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== drm_false_memory_analysis setup complete ==="