#!/bin/bash
echo "=== Setting up convert_allway_stop task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"

# Ensure the directory exists and has base files
if [ ! -d "$SCENARIO_DIR" ]; then
    echo "Error: Scenario directory not found!"
    exit 1
fi

# Clean up any potential artifacts from previous runs
rm -f "$SCENARIO_DIR/patch.nod.xml"
rm -f "$SCENARIO_DIR/pasubio_allway.net.xml"
rm -f "$SCENARIO_DIR/run_allway.sumocfg"
rm -f "$SCENARIO_DIR/tripinfos_allway.xml"

# Find a suitable priority junction dynamically and create the briefing file
python3 - <<EOF
import xml.etree.ElementTree as ET
import os

net_path = os.path.join("$SCENARIO_DIR", "pasubio_buslanes.net.xml")
briefing_path = os.path.join("$SCENARIO_DIR", "junction_briefing.txt")

try:
    tree = ET.parse(net_path)
    root = tree.getroot()
    
    candidates = []
    for j in root.findall('junction'):
        if j.get('type') == 'priority':
            inc_lanes = j.get('incLanes', '').split()
            # Find a real intersection with at least 3 incoming lanes
            if len(inc_lanes) >= 3:
                candidates.append(j.get('id'))
                
    if candidates:
        target = candidates[len(candidates)//2] # Pick one deterministically from the middle
    else:
        target = "cluster_1811520023_29012411_3325603830" # Fallback to a known complex junction
        
    with open(briefing_path, 'w') as f:
        f.write(f"TARGET_JUNCTION_ID={target}\n")
        f.write("Task: Convert this junction to an allway_stop using an XML patch file.\n")
        
except Exception as e:
    print(f"Error parsing network: {e}")
    # Write a fallback just in case
    with open(briefing_path, 'w') as f:
        f.write("TARGET_JUNCTION_ID=cluster_1811520023_29012411_3325603830\n")
EOF

chown ga:ga "$SCENARIO_DIR/junction_briefing.txt"

# Open a terminal for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$SCENARIO_DIR &"
    sleep 3
fi

# Maximize the terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take an initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="