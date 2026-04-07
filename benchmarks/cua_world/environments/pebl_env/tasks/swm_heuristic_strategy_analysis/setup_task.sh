#!/bin/bash
# Setup for swm_heuristic_strategy_analysis task
# Generates a realistic Spatial Working Memory (SWM) log file based on standard paradigm rules.
# Includes 15 normative clinical profiles and 1 corrupted profile (sub-99) with random mashing.

set -e
echo "=== Setting up swm_heuristic_strategy_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic SWM dataset using Python
python3 << 'PYEOF'
import csv
import random

random.seed(101)  # Fixed seed for reproducibility
rows = []

participants = [f"sub-{i:02d}" for i in range(1, 16)] + ["sub-99"]

for pid in participants:
    for trial in range(1, 13):
        if trial <= 4:
            boxes_count = 4
        elif trial <= 8:
            boxes_count = 6
        else:
            boxes_count = 8
            
        boxes = list(range(101, 101 + boxes_count))
        # Hide tokens: exactly one token per box across the searches
        token_locations = list(boxes)
        random.shuffle(token_locations)
        
        boxes_with_tokens = set()
        
        for search_num in range(1, boxes_count + 1):
            target_box = token_locations[search_num - 1]
            boxes_clicked_this_search = set()
            
            click_seq = 1
            search_active = True
            
            # Good heuristic strategy: favor starting with the same box
            if pid != "sub-99":
                start_box_pref = boxes[0] if random.random() < 0.6 else random.choice(boxes)
            else:
                start_box_pref = random.choice(boxes)
                
            while search_active:
                if pid == "sub-99":
                    # Random mashing behavior
                    click = random.choice(boxes)
                else:
                    if click_seq == 1:
                        click = start_box_pref
                    else:
                        # Probabilistic error generation for realistic variance
                        if boxes_with_tokens and random.random() < 0.12:
                            click = random.choice(list(boxes_with_tokens))
                        elif boxes_clicked_this_search and random.random() < 0.03:
                            click = random.choice(list(boxes_clicked_this_search))
                        else:
                            available = [b for b in boxes if b not in boxes_clicked_this_search]
                            click = random.choice(available) if available else random.choice(boxes)
                            
                found = 1 if click == target_box else 0
                
                rows.append({
                    "participant_id": pid,
                    "trial": trial,
                    "boxes_count": boxes_count,
                    "search_number": search_num,
                    "click_sequence": click_seq,
                    "box_clicked": click,
                    "found_token": found
                })
                
                if found == 1:
                    boxes_with_tokens.add(click)
                    search_active = False
                else:
                    boxes_clicked_this_search.add(click)
                    
                click_seq += 1

with open('/home/ga/pebl/data/swm_click_logs.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "boxes_count", "search_number", "click_sequence", "box_clicked", "found_token"])
    writer.writeheader()
    writer.writerows(rows)
PYEOF

chown ga:ga /home/ga/pebl/data/swm_click_logs.csv
chmod 644 /home/ga/pebl/data/swm_click_logs.csv

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with context
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Spatial Working Memory Heuristic Analysis ===; echo; echo Data file: ~/pebl/data/swm_click_logs.csv; echo Output target: ~/pebl/analysis/swm_report.json; echo; bash' > /tmp/swm_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== swm_heuristic_strategy_analysis setup complete ==="