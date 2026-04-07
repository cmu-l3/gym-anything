#!/bin/bash
# Setup script for post_flight_aerodynamic_calibration task

echo "=== Setting up post_flight_aerodynamic_calibration task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/calibration_task.ork"
SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove any pre-existing output files from previous attempts
rm -f "$ROCKETS_DIR/calibrated_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/calibration_flight.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/prediction_flight.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/calibration_report.txt" 2>/dev/null || true

# Reset simulations to outdated status so the agent must re-run them
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/calibration_task.ork'
tmp_path = ork_path + '.tmp'

try:
    with zipfile.ZipFile(ork_path, 'r') as zin:
        xml_bytes = zin.read('rocket.ork')

    root = ET.fromstring(xml_bytes.decode('utf-8'))

    # Clear simulation flight data
    sims_elem = root.find('simulations')
    if sims_elem is not None:
        for sim in sims_elem.findall('simulation'):
            sim.set('status', 'outdated')
            fd = sim.find('flightdata')
            if fd is not None:
                sim.remove(fd)

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
except Exception as e:
    print(f"Failed to reset simulations: {e}")
PYEOF

# Record task start time for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/calibration_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the task rocket
launch_openrocket "$TASK_ORK"
sleep 3

# Wait for UI to initialize
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot documenting starting state
take_screenshot /tmp/calibration_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== post_flight_aerodynamic_calibration task setup complete ==="