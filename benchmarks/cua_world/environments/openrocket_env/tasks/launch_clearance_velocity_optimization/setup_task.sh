#!/bin/bash
# Setup script for launch_clearance_velocity_optimization task
# Clears motor configurations and simulations to provide a clean slate for the agent.

echo "=== Setting up launch_clearance_velocity_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"
BASE_DIR="/home/ga/Documents/rockets"
TASK_ORK="$BASE_DIR/dual_parachute_deployment.ork"
TARGET_ORK="$BASE_DIR/optimized_rail_clearance.ork"
REPORT_FILE="/home/ga/Documents/exports/clearance_report.txt"

# Create directories
mkdir -p "$BASE_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$BASE_DIR" "$EXPORTS_DIR"

# Clean up previous artifacts
rm -f "$TARGET_ORK" 2>/dev/null || true
rm -f "$REPORT_FILE" 2>/dev/null || true

# Copy source .ork
if [ ! -f "$SOURCE_ORK" ]; then
    # Fallback to standard installation path if workspace is not mounted
    SOURCE_ORK="$ROCKETS_DIR/dual_parachute_deployment.ork"
fi

cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Clear all simulations and motors so agent must configure them
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/dual_parachute_deployment.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Remove all simulations
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in list(sims_elem.findall('simulation')):
        sims_elem.remove(sim)

# Remove all motor configurations from motormount
for mm in root.iter('motormount'):
    for motor in list(mm.findall('motor')):
        mm.remove(motor)
    for ic in list(mm.findall('ignitionconfiguration')):
        mm.remove(ic)

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
    echo "FATAL: Python XML preparation failed"
    exit 1
fi

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the prepared rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== launch_clearance_velocity_optimization task setup complete ==="