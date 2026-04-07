#!/bin/bash
# Setup script for flight_hardware_retrofit task

echo "=== Setting up flight_hardware_retrofit task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/home/ga/Documents/rockets/dual_parachute_deployment.ork"
TARGET_ORK="/home/ga/Documents/rockets/flight_ready_retrofit.ork"
REPORT_FILE="/home/ga/Documents/exports/hardware_penalty_report.txt"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure the source file exists. If not, copy from workspace fallback
if [ ! -f "$SOURCE_ORK" ]; then
    cp "/workspace/data/rockets/dual_parachute_deployment.ork" "$SOURCE_ORK" 2>/dev/null || true
fi

# Remove previous output files to ensure a clean slate
rm -f "$TARGET_ORK" 2>/dev/null || true
rm -f "$REPORT_FILE" 2>/dev/null || true

# Prepare the source file by resetting all simulations to outdated
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/dual_parachute_deployment.ork'
if not os.path.exists(ork_path):
    print("WARNING: Source ORK not found!")
    exit(0)

tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Reset simulations to outdated
sims_elem = root.find('simulations')
sim_count = 0
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)
        sim_count += 1

print(f"Reset {sim_count} simulations in base file")

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
os.system(f"chown ga:ga {ork_path}")
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/retrofit_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket loaded
launch_openrocket "$SOURCE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/retrofit_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== flight_hardware_retrofit task setup complete ==="