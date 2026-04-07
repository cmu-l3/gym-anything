#!/bin/bash
echo "=== Setting up configure_beb_charging task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Clean up any pre-existing output files
rm -f "$OUTPUT_DIR"/battery.xml 2>/dev/null || true
rm -f "$OUTPUT_DIR"/charging_summary.txt 2>/dev/null || true
rm -f "$SCENARIO_DIR"/pasubio_charging.add.xml 2>/dev/null || true

# Extract a valid bus stop from the existing configuration to use as the target
cat << 'EOF' > /tmp/extract_bus_stop.py
import xml.etree.ElementTree as ET
import json

try:
    tree = ET.parse('/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_bus_stops.add.xml')
    root = tree.getroot()
    # Find the first bus stop to use as our target
    bus_stop = root.find('busStop')
    
    if bus_stop is not None:
        data = {
            'id': bus_stop.get('id', ''),
            'lane': bus_stop.get('lane', ''),
            'startPos': bus_stop.get('startPos', ''),
            'endPos': bus_stop.get('endPos', '')
        }
        
        # Save exact geometry for verifier
        with open('/tmp/target_bus_stop.json', 'w') as f:
            json.dump(data, f)
            
        # Create briefing file for agent
        with open('/home/ga/SUMO_Scenarios/bologna_pasubio/beb_briefing.txt', 'w') as f:
            f.write("=== BEB Electrification Briefing ===\n\n")
            f.write(f"Target Bus Stop ID: {data['id']}\n")
            f.write("New Charger ID: charger_1\n")
            f.write("Charger Power: 300000\n")
            f.write("Charger Efficiency: 0.95\n\n")
            f.write("Bus vType Parameters:\n")
            f.write("- has.battery.device: true\n")
            f.write("- maximumBatteryCapacity: 150000\n")
            f.write("- actualBatteryCapacity: 50000\n")
            
except Exception as e:
    print(f"Error extracting bus stop: {e}")
EOF

python3 /tmp/extract_bus_stop.py
chown ga:ga "$SCENARIO_DIR/beb_briefing.txt"

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$SCENARIO_DIR &"
sleep 2

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="