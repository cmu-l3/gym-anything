#!/bin/bash
echo "=== Setting up generate_demand_routes task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

export SUMO_HOME="/usr/share/sumo"

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Ensure output directory is clean
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown ga:ga /home/ga/SUMO_Output

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"

# Find the exact network file name
NET_FILE=$(find "$SCENARIO_DIR" -name "*.net.xml" -type f | head -1)
if [ -z "$NET_FILE" ]; then
    echo "ERROR: No .net.xml file found in $SCENARIO_DIR"
    exit 1
fi

# Record initial edge list for verification using Python
python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$NET_FILE')
    root = tree.getroot()
    edges = [e.get('id') for e in root.findall('.//edge') if not e.get('id','').startswith(':')]
    with open('/tmp/valid_edge_ids.txt', 'w') as f:
        for eid in edges:
            f.write(eid + '\n')
except Exception as e:
    print('Error extracting edges:', e)
" 2>/dev/null || true

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 cd $SCENARIO_DIR && gnome-terminal --working-directory=$SCENARIO_DIR --maximize &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 xterm -maximized -e 'cd $SCENARIO_DIR && bash' &" 2>/dev/null || true

# Wait for terminal to appear
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="