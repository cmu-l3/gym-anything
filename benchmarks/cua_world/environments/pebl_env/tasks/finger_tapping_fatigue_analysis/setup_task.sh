#!/bin/bash
set -e
echo "=== Setting up finger_tapping_fatigue_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Generate realistic high-frequency FTT data
python3 << 'EOF'
import csv
import random
import math

random.seed(42)

def generate_participant(pid, is_pd, is_fake=False):
    rows = []
    base_dom_hz = random.uniform(3.5, 5.5) if is_pd else random.uniform(4.5, 6.5)
    base_nondom_hz = base_dom_hz * random.uniform(0.85, 0.95)
    base_fi = random.uniform(0.75, 0.90) if is_pd else random.uniform(0.90, 1.05)
    base_cv = random.uniform(0.15, 0.25) if is_pd else random.uniform(0.08, 0.15)
    
    for hand in ['Dominant', 'NonDominant']:
        hz = base_dom_hz if hand == 'Dominant' else base_nondom_hz
        
        for trial in range(1, 6):
            if is_fake:
                t = 0
                tap_num = 1
                while t <= 10000:
                    iti = 20.0 if tap_num > 1 else 0.0
                    rows.append({
                        'participant_id': pid,
                        'diagnosis': 'Control',
                        'hand': hand,
                        'trial': trial,
                        'tap_number': tap_num,
                        'tap_time_ms': round(t, 2),
                        'iti_ms': round(iti, 2) if tap_num > 1 else 'NA'
                    })
                    t += 20.0
                    tap_num += 1
                continue
                
            t = 0
            tap_num = 1
            expected_total_taps = hz * 10.0
            expected_first_half = expected_total_taps / (1 + base_fi)
            expected_second_half = expected_total_taps - expected_first_half
            
            hz_first = expected_first_half / 5.0
            hz_second = expected_second_half / 5.0
            
            mean_iti_first = 1000.0 / hz_first
            mean_iti_second = 1000.0 / hz_second
            
            while t <= 10000:
                current_mean_iti = mean_iti_first if t <= 5000 else mean_iti_second
                sigma = math.sqrt(math.log(1 + base_cv**2))
                mu = math.log(current_mean_iti) - (sigma**2) / 2
                
                iti = random.lognormvariate(mu, sigma)
                if tap_num == 1:
                    iti_val = 'NA'
                else:
                    iti_val = round(iti, 2)
                    
                rows.append({
                    'participant_id': pid,
                    'diagnosis': 'PD' if is_pd else 'Control',
                    'hand': hand,
                    'trial': trial,
                    'tap_number': tap_num,
                    'tap_time_ms': round(t, 2),
                    'iti_ms': iti_val
                })
                
                t += iti if tap_num > 1 else 0
                tap_num += 1

    return rows

all_rows = []
for i in range(1, 22):
    pid = f"P{i:03d}"
    is_pd = i > 10
    all_rows.extend(generate_participant(pid, is_pd, False))

all_rows.extend(generate_participant("P099", False, True))

with open('/home/ga/pebl/data/ftt_tapping_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'diagnosis', 'hand', 'trial', 'tap_number', 'tap_time_ms', 'iti_ms'])
    writer.writeheader()
    writer.writerows(all_rows)

print(f"Generated {len(all_rows)} tap events across 22 participants.")
EOF

chown ga:ga /home/ga/pebl/data/ftt_tapping_data.csv

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Finger Tapping Fatigue Analysis ===; echo; echo Data file: ~/pebl/data/ftt_tapping_data.csv; echo Output target: ~/pebl/analysis/ftt_fatigue_report.json; echo; bash' > /tmp/ftt_terminal.log 2>&1 &"

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

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== finger_tapping_fatigue_analysis setup complete ==="