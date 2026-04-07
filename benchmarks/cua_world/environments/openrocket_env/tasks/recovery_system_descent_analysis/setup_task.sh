#!/bin/bash
# Setup script for recovery_system_descent_analysis task
# Copies dual_parachute_deployment.ork, shrinks parachutes to create unsafe descent

echo "=== Setting up recovery_system_descent_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/recovery_analysis.ork"
SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/descent_analysis_report.txt" 2>/dev/null || true

# Inject undersized parachutes: main 1066.8mm→254mm, drogue 304.8mm→76mm
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/recovery_analysis.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

chute_count = 0
for para in root.iter('parachute'):
    name_el = para.find('name')
    diam_el = para.find('diameter')
    name = name_el.text if name_el is not None else ''
    if diam_el is not None:
        if 'drouge' in name.lower() or 'drogue' in name.lower():
            diam_el.text = '0.076'
            chute_count += 1
        else:
            diam_el.text = '0.254'
            chute_count += 1

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

print(f"Resized {chute_count} parachute(s), reset {sim_count} simulations")

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
echo "task_start_ts=$(date +%s)" > /tmp/recovery_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the modified rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/recovery_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== recovery_system_descent_analysis task setup complete ==="
