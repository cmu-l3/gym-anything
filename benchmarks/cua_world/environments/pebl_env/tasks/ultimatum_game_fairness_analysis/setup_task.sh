#!/bin/bash
echo "=== Setting up Ultimatum Game Fairness Analysis Task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis

# Generate realistic Ultimatum Game data with a python script
python3 << 'EOF'
import csv
import random

random.seed(42)  # For reproducibility
filename = '/home/ga/pebl/data/ultimatum_data.csv'

# 29 real participants, 1 contaminated (sub-99)
participants = [f"sub-{i:02d}" for i in range(1, 30)] + ["sub-99"]
trials_per_participant = 45 # 5 trials for each offer amount (1-9)

with open(filename, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['participant_id', 'trial', 'endowment', 'offer_to_responder', 'response', 'rt_ms'])
    
    for p in participants:
        # Create a randomized list of offers (5 of each amount 1-9)
        offers = [offer for offer in range(1, 10) for _ in range(5)]
        random.shuffle(offers)
        
        # Determine participant's intrinsic fairness threshold (MAO usually between 2 and 4)
        if p == "sub-99":
            threshold = 1 # Bot doesn't care about lower bound
        else:
            threshold = random.choices([2, 3, 4, 5], weights=[0.2, 0.4, 0.3, 0.1])[0]
        
        for t, offer in enumerate(offers, 1):
            rt = int(random.gauss(1200, 300))
            rt = max(300, min(rt, 3000))
            
            # Acceptance logic
            if p == "sub-99":
                # Contaminated: Rejects hyper-fair offers (simulating spite/error)
                if offer >= 6:
                    accept_prob = 0.10
                else:
                    accept_prob = 0.90
            else:
                # Normal human
                if offer < threshold:
                    # Below MAO: highly likely to reject
                    accept_prob = 0.05 + (0.10 * offer)
                elif offer == threshold:
                    # At MAO: coin flip or slight bias to accept
                    accept_prob = random.uniform(0.5, 0.7)
                else:
                    # Above MAO: highly likely to accept
                    accept_prob = min(0.95 + random.uniform(0, 0.05), 1.0)
            
            response = "Accept" if random.random() < accept_prob else "Reject"
            
            writer.writerow([p, t, 10, offer, response, rt])
EOF

chown -R ga:ga /home/ga/pebl

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Get DBUS for terminal launch
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open terminal for the agent to start working
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=100x30 -- bash -c 'echo === Ultimatum Game Analysis ===; echo; echo Data file: ~/pebl/data/ultimatum_data.csv; echo Expected output: ~/pebl/analysis/ultimatum_report.json; echo; bash' > /tmp/term.log 2>&1 &"

# Maximize terminal
for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="