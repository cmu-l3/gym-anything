#!/bin/bash
echo "=== Setting up internal_cg_repositioning task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/cg_optimization.ork"
GT_ORK="/tmp/cg_optimization_gt.ork"
SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Try to use workspace data, fallback to downloaded rockets
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="/home/ga/Documents/rockets/dual_parachute_deployment.ork"
fi

if [ ! -f "$SOURCE_ORK" ]; then
    echo "FATAL: Could not find dual_parachute_deployment.ork"
    exit 1
fi

# Copy source .ork to task working file and ground truth file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
cp "$SOURCE_ORK" "$GT_ORK" || { echo "FATAL: Could not copy to gt .ork"; exit 1; }
chown ga:ga "$TASK_ORK"
chmod 644 "$GT_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/cg_optimized.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/cg_optimization_report.txt" 2>/dev/null || true

# Reset all simulations to outdated
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/cg_optimization.ork'
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

# Record ground truth start time
echo "task_start_ts=$(date +%s)" > /tmp/cg_task_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== internal_cg_repositioning task setup complete ==="