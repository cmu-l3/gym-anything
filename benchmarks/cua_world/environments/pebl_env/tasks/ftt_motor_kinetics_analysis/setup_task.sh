#!/bin/bash
# Setup for ftt_motor_kinetics_analysis task
# Generates realistic normative FTT physiological data based on clinical distributions,
# and injects one participant (P99) with a simulated hardware key-repeat artifact.

set -e
echo "=== Setting up ftt_motor_kinetics_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic clinical FTT data
python3 << 'PYEOF'
import csv, random, math
random.seed(42)

rows = []
# Generate 10 valid clinical participants
for pid in range(1, 11):
    p_id = f"P{pid:02d}"
    
    # Realistic tapping parameters
    base_rate = random.uniform(4.5, 6.0) # 4.5 to 6.0 taps per second
    fatigue_rate = random.uniform(0.1, 0.4) # drop in taps/sec per trial
    asym = random.uniform(0.05, 0.15) # 5-15% slower in nondominant hand
    
    for hand in ['dominant', 'nondominant']:
        hand_mult = 1.0 if hand == 'dominant' else (1.0 - asym)
        for trial in [1, 2, 3]:
            # Rate of tapping for this specific 10-second trial
            rate = (base_rate - (trial-1)*fatigue_rate) * hand_mult
            num_taps = int(rate * 10)
            mean_iti = 1000.0 / rate
            
            # Use lognormal distribution for realistic physiological ITI variation (SD ~ 15ms)
            mu = math.log(mean_iti**2 / math.sqrt(15**2 + mean_iti**2))
            sigma = math.sqrt(math.log(1 + (15**2 / mean_iti**2)))
            
            for tap in range(1, num_taps + 1):
                iti = random.lognormvariate(mu, sigma)
                rows.append({
                    'participant_id': p_id,
                    'hand': hand,
                    'trial': trial,
                    'tap_number': tap,
                    'iti_ms': round(iti, 1)
                })

# Inject P99 (Corrupted Participant - Hardware Polling Artifact)
for hand in ['dominant', 'nondominant']:
    for trial in [1, 2, 3]:
        # ~300 taps per 10s trial due to ~33ms polling rate
        for tap in range(1, 298):
            rows.append({
                'participant_id': 'P99',
                'hand': hand,
                'trial': trial,
                'tap_number': tap,
                'iti_ms': round(33.3 + random.uniform(-0.1, 0.1), 1)
            })

with open('/home/ga/pebl/data/ftt_tap_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'hand', 'trial', 'tap_number', 'iti_ms'])
    writer.writeheader()
    writer.writerows(rows)

print(f"Generated {len(rows)} event rows for ftt_tap_data.csv")
PYEOF

chown ga:ga /home/ga/pebl/data/ftt_tap_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === FTT Motor Kinetics Analysis ===; echo; echo Data file: ~/pebl/data/ftt_tap_data.csv; echo Output target: ~/pebl/analysis/ftt_report.json; echo; bash' > /tmp/ftt_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== ftt_motor_kinetics_analysis setup complete ==="