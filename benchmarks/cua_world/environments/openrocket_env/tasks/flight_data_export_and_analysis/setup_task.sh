#!/bin/bash
# Setup script for flight_data_export_and_analysis task
# Uses clustered_motors.ork, resets simulations to outdated status

echo "=== Setting up flight_data_export_and_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/flight_analysis.ork"
SOURCE_ORK="/workspace/data/rockets/clustered_motors.ork"
FLIGHT_DATA_DIR="$EXPORTS_DIR/flight_data"

# Create directories
mkdir -p "$ROCKETS_DIR" "$FLIGHT_DATA_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/flight_analysis_report.txt" 2>/dev/null || true
rm -f "$FLIGHT_DATA_DIR"/*.csv 2>/dev/null || true

# Reset all simulations to 'outdated' status so agent must re-run them
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/flight_analysis.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

sims_elem = root.find('simulations')
sim_count = 0
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)
        sim_count += 1

print(f"Reset {sim_count} simulations to outdated status")

modified_xml = ET.tostring(root, encoding='unicode', xml_declaration=False)
modified_xml_bytes = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + modified_xml).encode('utf-8')

with zipfile.ZipFile(ork_path, 'r') as zin:
    with zipfile.ZipFile(tmp_path, 'w', zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == 'rocket.ork':
                zout.writestr(item, modified_xml_bytes)
            else:
                zout.writestr(item, zin.read(item.filename))

os.replace(tmp_path, ork_path)
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Record ground truth
echo "expected_sim_count=5" > /tmp/flight_analysis_gt.txt
echo "task_start_ts=$(date +%s)" >> /tmp/flight_analysis_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the flight analysis rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/flight_analysis_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== flight_data_export_and_analysis task setup complete ==="
