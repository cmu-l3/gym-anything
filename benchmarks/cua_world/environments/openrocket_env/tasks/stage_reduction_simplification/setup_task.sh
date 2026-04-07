#!/bin/bash
# Setup script for stage_reduction_simplification task

echo "=== Setting up stage_reduction_simplification task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/three_stage_low_power_rocket.ork"
# Fallback to the downloaded directory if workspace data is unavailable
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="$ROCKETS_DIR/three_stage_low_power_rocket.ork"
fi

WORKING_ORK="$ROCKETS_DIR/three_stage_source.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$WORKING_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$WORKING_ORK"

# Clean up previous task artifacts if any
rm -f "$ROCKETS_DIR/two_stage_simplified.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/stage_reduction_report.txt" 2>/dev/null || true

# Reset all simulations to outdated to ensure agent has to run them
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/three_stage_source.ork'
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

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the working rocket
launch_openrocket "$WORKING_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== task setup complete ==="