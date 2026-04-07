#!/bin/bash
echo "=== Setting up action_camera_retrofit task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"
WORKING_ORK="$ROCKETS_DIR/action_camera_base.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to working file
cp "$SOURCE_ORK" "$WORKING_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$WORKING_ORK"

# Remove any previous task outputs
rm -f "$ROCKETS_DIR/camera_retrofitted.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/camera_flight.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/retrofit_report.txt" 2>/dev/null || true

# Python script to clean the ORK:
# 1. Removes any existing mass components to ensure a clean baseline
# 2. Resets all simulations to outdated
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/action_camera_base.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Remove all existing mass components
parent_map = {c: p for p in root.iter() for c in p}
mc_count = 0
for mc in root.findall('.//masscomponent'):
    parent = parent_map.get(mc)
    if parent is not None:
        parent.remove(mc)
        mc_count += 1

# Reset all simulations to outdated
sims_elem = root.find('simulations')
sim_count = 0
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)
        sim_count += 1

print(f"Removed {mc_count} mass components, reset {sim_count} simulations to outdated status")

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
echo "task_start_ts=$(date +%s)" > /tmp/camera_retrofit_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the baseline rocket
launch_openrocket "$WORKING_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/camera_retrofit_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== action_camera_retrofit task setup complete ==="