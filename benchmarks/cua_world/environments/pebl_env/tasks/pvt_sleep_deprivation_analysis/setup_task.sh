#!/bin/bash
# Setup for pvt_sleep_deprivation_analysis task
# Generates 12-participant x 3-session PVT data based on Basner & Dinges (2011)
# statistics, with p08's TSD session contaminated by equipment artifact

set -e
echo "=== Setting up pvt_sleep_deprivation_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data/pvt
mkdir -p /home/ga/pebl/analysis
mkdir -p /home/ga/pebl/lab
chown -R ga:ga /home/ga/pebl

# Generate PVT data files using Python
python3 << 'PYEOF'
import csv
import random
import math
import os

random.seed(42)

# Based on Basner & Dinges (2011) SLEEP:
# BL session: mean RT ~253 ms, lapses ~1.2 per 10-min test
# TSD session: mean RT ~314 ms, lapses ~7.4 per 10-min test
# REC session: mean RT ~267 ms, lapses ~2.1 per 10-min test

SESSIONS = ['BL', 'TSD', 'REC']
N_PARTICIPANTS = 12
N_TRIALS = 144  # 10-min PVT at 1 trial per ~4.2s average

# Session parameters: (mean_rt_ms, lapse_prob, sd_rt_ms)
# Using lognormal distribution for RT (typical for reaction time data)
SESSION_PARAMS = {
    'BL':  {'mean_rt': 253, 'sd_rt': 28, 'lapse_prob': 0.0083},   # ~1.2 lapses / 144 trials
    'TSD': {'mean_rt': 314, 'sd_rt': 52, 'lapse_prob': 0.0514},   # ~7.4 lapses / 144 trials
    'REC': {'mean_rt': 267, 'sd_rt': 33, 'lapse_prob': 0.0146},   # ~2.1 lapses / 144 trials
}

def generate_rt(mean_rt, sd_rt, lapse_prob):
    """Generate a single RT sample from a mixture: normal RTs + occasional lapses."""
    if random.random() < lapse_prob:
        # Lapse: RT > 500ms (drawn from exponential tail starting at 500ms)
        return round(500 + random.expovariate(0.008), 1)
    else:
        # Normal RT: lognormal distribution
        mu = math.log(mean_rt) - 0.5 * (sd_rt/mean_rt)**2
        sigma = sd_rt / mean_rt
        rt = round(random.lognormvariate(mu, sigma), 1)
        # Clamp to 100-499ms for valid non-lapse trials
        return max(100.0, min(rt, 499.0))

data_dir = '/home/ga/pebl/data/pvt'

# Generate per-participant inter-individual variability
participant_multipliers = {f'p{i:02d}': random.gauss(1.0, 0.12) for i in range(1, N_PARTICIPANTS + 1)}

ground_truth = {}

for pid_num in range(1, N_PARTICIPANTS + 1):
    pid = f'p{pid_num:02d}'
    mult = participant_multipliers[pid]
    ground_truth[pid] = {}

    for session in SESSIONS:
        params = SESSION_PARAMS[session]
        mean_rt = params['mean_rt'] * mult
        sd_rt = params['sd_rt'] * mult
        lapse_prob = params['lapse_prob']

        # p08 TSD session: contaminate with sub-100ms RTs (equipment artifact)
        # These RTs are physiologically impossible (< 100ms)
        is_contaminated = (pid == 'p08' and session == 'TSD')

        filepath = os.path.join(data_dir, f'{pid}_session_{session}.csv')
        trials = []
        t = 2000  # First stimulus at 2000ms

        for trial in range(1, N_TRIALS + 1):
            if is_contaminated:
                # Equipment artifact: all RTs impossibly fast (40-85ms)
                rt = round(random.uniform(40, 85), 1)
            else:
                rt = generate_rt(mean_rt, sd_rt, lapse_prob)

            lapse = 1 if rt > 500 else 0
            trials.append({
                'trial': trial,
                'stimulus_onset_ms': t,
                'response_time_ms': rt,
                'lapse': lapse
            })
            # ISI: 2000-10000ms uniform jitter (PVT standard)
            isi = random.uniform(2000, 10000)
            t = round(t + isi + rt)

        with open(filepath, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['trial', 'stimulus_onset_ms', 'response_time_ms', 'lapse'])
            writer.writeheader()
            writer.writerows(trials)

        if not is_contaminated:
            valid_rts = [r['response_time_ms'] for r in trials]
            lapse_count = sum(r['lapse'] for r in trials)
            mean_rt_actual = sum(valid_rts) / len(valid_rts)
            rrt = sum(1000.0 / r for r in valid_rts) / len(valid_rts)
            n_slow = max(1, round(len(valid_rts) * 0.10))
            slowest10 = sorted(valid_rts)[-n_slow:]
            mean_slowest10 = sum(slowest10) / len(slowest10)
            ground_truth[pid][session] = {
                'mean_rt_ms': round(mean_rt_actual, 2),
                'lapse_count': lapse_count,
                'mean_rrt': round(rrt, 4),
                'mean_slowest10pct_rt_ms': round(mean_slowest10, 2)
            }
        else:
            ground_truth[pid][session] = 'contaminated'

# Save ground truth for verifier
import json
with open('/tmp/pvt_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Generated PVT data for {N_PARTICIPANTS} participants x {len(SESSIONS)} sessions")
print(f"Contaminated: p08 TSD session (sub-100ms RTs from equipment artifact)")
print(f"Ground truth saved to /tmp/pvt_ground_truth.json")
PYEOF

# Write incident log (the key artifact the agent must read to identify contaminated data)
cat > /home/ga/pebl/lab/pvt_incidents.log << 'LOGEOF'
PVT Study Incident Log
======================
Study: Total Sleep Deprivation (TSD) Protocol v2.1
PI: Dr. Sarah Chen, Sleep & Cognition Laboratory
IRB: SL-2023-0847

--- SESSION INCIDENTS ---

2023-09-12 [p03, BL]: Participant reported mild headache before session. RT data
  appears normal. No exclusion recommended.

2023-09-14 [p07, BL]: Participant was 8 minutes late. Session started at 14:12
  instead of 14:00. Testing completed normally. No data quality concerns.

2023-09-19 [p08, TSD]: EQUIPMENT MALFUNCTION - The response button box (Cedrus
  RB-840) exhibited a hardware fault approximately 3 hours after start of TSD
  vigil. Specifically, the button contact debris caused continuous shorting of
  the response circuit, generating spurious response signals that were logged
  as participant responses with sub-100ms latencies throughout the PVT session.
  Technician observed RTs consistently in the 40-85ms range, which are
  physiologically impossible for a genuine PVT response.
  STATUS: p08 TSD session data is INVALID and must be EXCLUDED from all
  analyses. p08 BL and REC sessions are unaffected.
  Corrective action: Button box replaced with spare unit (S/N CE-2847-B).

2023-09-22 [p11, TSD]: Participant fell asleep for approximately 90 seconds
  during the TSD session (epoch 4). Data from that epoch contains extended
  RT gaps. This is expected in a TSD protocol; lapse counts naturally increase.
  Data is valid; no exclusion required.

2023-09-25 [p02, REC]: Participant reported consuming 2 cups of coffee before
  REC session. RT data slightly better than expected for recovery, but within
  normal variability. Data retained with note.

--- END OF LOG ---
LOGEOF

chown -R ga:ga /home/ga/pebl
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x38 -- bash -c '
echo \"=== PVT Sleep Deprivation Analysis ===\"
echo \"\"
echo \"PVT data:     ~/pebl/data/pvt/  (p01-p12 x BL/TSD/REC sessions)\"
echo \"Incident log: ~/pebl/lab/pvt_incidents.log\"
echo \"Output:       ~/pebl/analysis/pvt_report.json\"
echo \"\"
echo \"Steps: 1) Read incident log to identify excluded data\"
echo \"       2) Compute per-participant stats (mean RT, lapses, RRT, slowest 10%)\"
echo \"       3) Compute group-level session means (excluding bad data)\"
echo \"       4) Write JSON report\"
echo \"\"
bash' > /tmp/pvt_terminal.log 2>&1 &"

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

echo "=== pvt_sleep_deprivation_analysis setup complete ==="
echo "Files: /home/ga/pebl/data/pvt/ (12 participants x 3 sessions = 36 CSV files)"
echo "Contamination: p08 TSD session (sub-100ms RTs)"
echo "Incident log: /home/ga/pebl/lab/pvt_incidents.log"
