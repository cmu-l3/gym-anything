#!/bin/bash
# Setup for flanker_inhibitory_control_analysis task
# Copies the real flanker RT data (with one contaminated participant)
# to a location the agent must discover and analyze.

set -e
echo "=== Setting up flanker_inhibitory_control_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create required directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Copy real flanker data from assets (mounted at /workspace/assets)
cp /workspace/assets/flanker_rt_data.csv /tmp/flanker_base.csv

# Inject contamination: add participant s99 with impossibly fast RTs
# (mean RT = 0.026s = 26ms, well below minimum human RT of ~100ms)
# This simulates an equipment malfunction (key stuck or auto-responder)
python3 << 'PYEOF'
import csv, random
random.seed(12345)

rows = []
with open('/tmp/flanker_base.csv') as f:
    reader = csv.DictReader(f)
    rows = list(reader)

# Inject 12 trials for fake participant s99 with impossibly fast RTs
conditions = ['congruent', 'incongruent', 'neutral', 'congruent', 'incongruent',
              'neutral', 'congruent', 'neutral', 'incongruent', 'congruent',
              'neutral', 'incongruent']
for i, cond in enumerate(conditions, 1):
    rt = round(0.020 + random.uniform(0, 0.012), 6)  # 20-32ms range
    rows.append({
        'participant': 's99',
        'block': '1',
        'trial': str(i),
        'flankers': cond,
        'rt': str(rt)
    })

with open('/home/ga/pebl/data/flanker_rt_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant','block','trial','flankers','rt'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Written {len(rows)} rows to flanker_rt_data.csv")
PYEOF

chown ga:ga /home/ga/pebl/data/flanker_rt_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Flanker Inhibitory Control Analysis ===; echo; echo Data file: ~/pebl/data/flanker_rt_data.csv; echo Output target: ~/pebl/analysis/flanker_report.json; echo; bash' > /tmp/flanker_terminal.log 2>&1 &"

# Wait for terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== flanker_inhibitory_control_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/flanker_rt_data.csv (27 real + 1 contaminated participant)"
echo "Expected output: /home/ga/pebl/analysis/flanker_report.json"
