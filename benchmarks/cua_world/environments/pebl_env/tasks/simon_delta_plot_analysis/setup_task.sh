#!/bin/bash
# Setup for simon_delta_plot_analysis task
# Generates realistic Simon Task data with ex-Gaussian RT distributions
# ensuring a theoretically accurate decreasing Delta Plot signature.

set -e
echo "=== Setting up simon_delta_plot_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic data using Python
python3 << 'PYEOF'
import csv
import random

random.seed(42)

rows = []
# Generate 25 valid participants
for i in range(1, 26):
    p = f"s{i}"
    for b in range(1, 5):
        for t in range(1, 51):
            cond = random.choice(['congruent', 'incongruent'])
            side = random.choice(['left', 'right'])
            correct = 1 if random.random() < 0.95 else 0

            # Ex-Gaussian baseline reaction time
            base_rt = random.gauss(350, 40) + random.expovariate(1/80)
            if base_rt < 200: 
                base_rt = 200

            if cond == 'incongruent':
                # Delta plot signature: Simon effect decays for slower responses
                se = max(5, 75 - 0.15 * (base_rt - 250)) + random.gauss(0, 10)
                rt = base_rt + se
            else:
                rt = base_rt

            if correct == 0:
                rt -= random.uniform(30, 70)  # Errors are typically faster

            rows.append({
                'participant': p, 'block': b, 'trial': t,
                'condition': cond, 'stimulus_side': side,
                'correct': correct, 'rt_ms': round(rt, 1)
            })

# Inject contaminated participant s99 (Auto-responder)
for b in range(1, 5):
    for t in range(1, 51):
        cond = random.choice(['congruent', 'incongruent'])
        side = random.choice(['left', 'right'])
        rt = random.uniform(200, 210)  # Impossibly uniform RT
        rows.append({
            'participant': 's99', 'block': b, 'trial': t,
            'condition': cond, 'stimulus_side': side,
            'correct': 1, 'rt_ms': round(rt, 1)
        })

with open('/home/ga/pebl/data/simon_task_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant','block','trial','condition','stimulus_side','correct','rt_ms'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {len(rows)} trials.")
PYEOF

chown ga:ga /home/ga/pebl/data/simon_task_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address for terminal spawn
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Simon Effect Delta Plot Analysis ===; echo; echo Data file: ~/pebl/data/simon_task_data.csv; echo Output target: ~/pebl/analysis/simon_report.json; echo; bash' > /tmp/simon_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== simon_delta_plot_analysis setup complete ==="