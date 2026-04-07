#!/bin/bash
set -e
echo "=== Setting up tmt_executive_cost_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate the synthetic TMT dataset with real normative characteristics + 1 injected artifact
python3 << 'PYEOF'
import csv
import random

random.seed(42) # Fixed seed for reproducibility

rows = []
# 31 real participants with realistic TMT times
for i in range(1, 32):
    pid = f"P{i:02d}"
    for part in ['A', 'B']:
        # 25 nodes per part in standard TMT
        for click in range(1, 26):
            # Part B takes roughly 2x-3x longer than Part A
            mean_rt = 1100 if part == 'A' else 2600
            sd_rt = 300 if part == 'A' else 800
            
            rt = int(random.gauss(mean_rt, sd_rt))
            rt = max(250, rt) # Absolute human physiological floor for visual search + motor click
            
            # ~3% error rate on Part A, ~8% on Part B
            err_prob = 0.03 if part == 'A' else 0.08
            err = 1 if random.random() < err_prob else 0
            
            expected = f"Node{click}"
            clicked = expected if err == 0 else "WrongNode"
            
            rows.append([pid, part, click, expected, clicked, err, rt])

# 1 artifact participant (P99) - Automated UI Macro
# 40ms constant latency, 0 errors. Total time = 1 second per part.
for part in ['A', 'B']:
    for click in range(1, 26):
        rows.append(["P99", part, click, f"Node{click}", f"Node{click}", 0, 40])

# Shuffle rows slightly to simulate unsorted log, but keep participant chunks somewhat together
random.shuffle(rows)

out_path = '/home/ga/pebl/data/tmt_click_log.csv'
with open(out_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['participant_id', 'test_part', 'click_idx', 'expected_node', 'clicked_node', 'error_flag', 'rt_ms'])
    writer.writerows(rows)

print(f"Generated {len(rows)} click events at {out_path}")
PYEOF

chown ga:ga /home/ga/pebl/data/tmt_click_log.csv
chmod 644 /home/ga/pebl/data/tmt_click_log.csv

# Record start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address for proper UI launch
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent and optionally gedit
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=100x35 -- bash -c 'echo === Trail Making Test Analysis ===; echo; echo Data: ~/pebl/data/tmt_click_log.csv; echo Output: ~/pebl/analysis/tmt_report.json; echo; bash' > /tmp/term.log 2>&1 &"

# Try to maximize the terminal
for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== tmt_executive_cost_analysis setup complete ==="