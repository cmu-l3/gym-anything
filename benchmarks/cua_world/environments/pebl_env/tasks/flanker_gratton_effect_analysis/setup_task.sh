#!/bin/bash
set -e
echo "=== Setting up flanker_gratton_effect_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create required directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Inject contamination: add participant s99 with impossibly fast RTs
# (10-30 ms, well below minimum human RT)
# This simulates an equipment malfunction (key stuck or auto-responder)
python3 << 'PYEOF'
import csv, random
random.seed(42)

rows = []
# Load real baseline dataset from assets
with open('/workspace/assets/flanker_rt_data.csv', 'r') as f:
    reader = csv.DictReader(f)
    rows = list(reader)

# Inject 40 trials for fake participant s99
conds = ['congruent', 'incongruent', 'neutral']
for i in range(1, 41):
    rt = round(random.uniform(0.010, 0.030), 6)  # 10-30ms range in seconds
    rows.append({
        'participant': 's99',
        'block': '1',
        'trial': str(i),
        'flankers': random.choice(conds),
        'rt': str(rt)
    })

with open('/home/ga/pebl/data/flanker_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant','block','trial','flankers','rt'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Written {len(rows)} rows to flanker_data.csv")
PYEOF

chown ga:ga /home/ga/pebl/data/flanker_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Flanker Gratton Effect Analysis ===; echo; echo Data file: ~/pebl/data/flanker_data.csv; echo Output target: ~/pebl/analysis/gratton_report.json; echo; bash' > /tmp/flanker_terminal.log 2>&1 &"

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

echo "=== flanker_gratton_effect_analysis setup complete ==="
echo "Data: /home/ga/pebl/data/flanker_data.csv (27 real + 1 contaminated participant)"
echo "Expected output: /home/ga/pebl/analysis/gratton_report.json"