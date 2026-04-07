#!/bin/bash
echo "=== Setting up aggregate_edge_data task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure output directory is clean
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Remove any previous analysis configs to ensure clean state
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/run_analysis.sumocfg
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/meandata_output.add.xml
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg.bak

# Verify scenario files are present
if [ ! -f /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg ]; then
    echo "ERROR: Pasubio scenario not found!"
    exit 1
fi

if [ ! -f /home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_buslanes.net.xml ]; then
    echo "ERROR: Pasubio network file not found!"
    exit 1
fi

# Pre-parse network to store edge IDs for robust verification
python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_buslanes.net.xml')
    edges = [e.get('id') for e in tree.findall('.//edge') if not e.get('id','').startswith(':')]
    with open('/tmp/network_edge_ids.txt', 'w') as f:
        for eid in edges:
            f.write(eid + '\n')
    print(f'Network has {len(edges)} valid edges')
except Exception as e:
    print(f'Warning: Could not pre-parse network: {e}')
" 2>/dev/null || echo "Warning: Network parsing skipped"

# Kill any running SUMO processes
kill_sumo

# Open a terminal for the agent since this is a headless/CLI workflow task
if ! pgrep -f "xterm" > /dev/null; then
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30+10+10 -T 'SUMO CLI' &"
    sleep 3
fi

# Maximize and focus terminal
DISPLAY=:1 wmctrl -r "SUMO CLI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SUMO CLI" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Scenario: /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg"
echo "Output dir: /home/ga/SUMO_Output/"