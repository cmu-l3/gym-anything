#!/bin/bash
# Setup for wpt_probabilistic_learning_analysis task
# Generates a mathematically precise Weather Prediction Task (WPT) dataset
# simulating probabilistic classification learning, plus one perseverative responder.

set -e
echo "=== Setting up WPT Probabilistic Learning Analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create required directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate structural probabilistic dataset via Python
# Matches the canonical Knowlton et al. (1994) cue probabilities
python3 << 'PYEOF'
import csv
import random

# Fixed seed for deterministic ground truth
random.seed(42)

# Canonical 14 cue patterns of WPT and their P(Sun)
patterns = [
    ("A,B,C", 0.85), ("A,B,D", 0.80), ("A,C,D", 0.75), ("B,C,D", 0.60),
    ("A,B", 0.85), ("A,C", 0.75), ("A,D", 0.57), ("B,C", 0.57),
    ("B,D", 0.43), ("C,D", 0.43), ("A", 0.75), ("B", 0.60),
    ("C", 0.25), ("D", 0.15)
]

rows = []
# Generate 15 genuine participants with a learning curve
for p in range(1, 16):
    pid = f"sub-{p:02d}"
    
    for t in range(1, 101):
        block = (t - 1) // 20
        # Optimal choice probability grows from ~0.50 (chance) to ~0.80 across blocks
        optimal_prob = 0.50 + (block * 0.075) 
        
        cards, p_sun = random.choice(patterns)
        optimal_choice = "sun" if p_sun > 0.5 else "rain"
        actual_weather = "sun" if random.random() < p_sun else "rain"
        
        # Participant response based on their current learning stage
        if random.random() < optimal_prob:
            response = optimal_choice
        else:
            response = "rain" if optimal_choice == "sun" else "sun"
            
        rt = int(random.gauss(800 - block*50, 150))
        rt = max(300, rt)
        
        rows.append({
            "participant_id": pid,
            "trial": t,
            "cards_presented": cards,
            "prob_sun": p_sun,
            "optimal_choice": optimal_choice,
            "actual_weather": actual_weather,
            "response": response,
            "rt_ms": rt
        })

# Inject 1 contaminated participant (sub-999) - perseverative "sun" response
for t in range(1, 101):
    cards, p_sun = random.choice(patterns)
    optimal_choice = "sun" if p_sun > 0.5 else "rain"
    actual_weather = "sun" if random.random() < p_sun else "rain"
    
    rows.append({
        "participant_id": "sub-999",
        "trial": t,
        "cards_presented": cards,
        "prob_sun": p_sun,
        "optimal_choice": optimal_choice,
        "actual_weather": actual_weather,
        "response": "sun",  # Perseverative error
        "rt_ms": int(random.uniform(200, 400))
    })

with open('/home/ga/pebl/data/wpt_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

print(f"Dataset generated: {len(rows)} trials for 16 participants.")
PYEOF

chown ga:ga /home/ga/pebl/data/wpt_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === WPT Probabilistic Learning Analysis ===; echo; echo Data file: ~/pebl/data/wpt_data.csv; echo Expected Outputs: ; echo 1. ~/pebl/analysis/wpt_report.json; echo 2. ~/pebl/analysis/wpt_learning_curve.png; echo; bash' > /tmp/wpt_terminal.log 2>&1 &"

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

# Take initial state screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="