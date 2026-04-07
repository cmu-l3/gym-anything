#!/bin/bash
set -e
echo "=== Setting up semantic_fluency_depletion_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic verbal fluency data using exponential decay modeling 
# to represent the temporal depletion effect in human semantic memory
python3 << 'PYEOF'
import csv
import random

random.seed(42)
animals = ["cat", "dog", "horse", "cow", "pig", "sheep", "lion", "tiger", 
           "bear", "elephant", "monkey", "giraffe", "zebra", "snake", 
           "lizard", "frog", "toad", "bird", "eagle", "hawk", "fish", 
           "shark", "whale", "dolphin", "penguin", "seal", "walrus", 
           "mouse", "rat", "squirrel", "rabbit", "deer", "elk", "moose",
           "ant", "bee", "beetle", "butterfly", "moth", "spider", "crab"]

rows = []

for i in range(1, 26):
    pid = f"sub-{i:02d}"
    rt = 0
    words_produced = []
    
    # Depletion modeling: intervals get progressively longer
    base_interval = random.uniform(1000, 2000)
    
    while True:
        interval = random.expovariate(1.0 / base_interval) + 500
        rt += interval
        if rt > 60000:
            break
            
        word = random.choice(animals)
        
        # Test 1: Randomize case and whitespace for cleaning validation
        if random.random() < 0.3:
            word = word.upper()
        if random.random() < 0.3:
            word = f" {word} "
            
        # Test 2: Insert realistic duplicates (which should be filtered out)
        if len(words_produced) > 0 and random.random() < 0.15:
            dup = random.choice(words_produced)
            if random.random() < 0.5:
                dup = dup.upper()
            rows.append({"participant": pid, "category": "animals", "word_typed": dup, "rt_ms": int(rt)})
            continue
            
        # Test 3: Insert accidental blank submissions
        if random.random() < 0.05:
            rows.append({"participant": pid, "category": "animals", "word_typed": "   ", "rt_ms": int(rt)})
            continue
            
        rows.append({"participant": pid, "category": "animals", "word_typed": word, "rt_ms": int(rt)})
        words_produced.append(word.strip().lower())
        
        base_interval *= 1.15 # Slow down over time (simulating semantic depletion)

# Inject contamination: sub-99 (Bot auto-responder)
# Physiologically impossible because it has exactly 0ms variance in intervals
rt = 3000
for i in range(20):
    rows.append({"participant": "sub-99", "category": "animals", "word_typed": animals[i], "rt_ms": int(rt)})
    rt += 3000

with open('/home/ga/pebl/data/semantic_fluency_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant", "category", "word_typed", "rt_ms"])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga /home/ga/pebl/data/semantic_fluency_data.csv
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Semantic Fluency Temporal Depletion Analysis ===; echo; echo Data file: ~/pebl/data/semantic_fluency_data.csv; echo Output target: ~/pebl/analysis/fluency_report.json; echo; bash' > /tmp/fluency_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== Setup complete ==="