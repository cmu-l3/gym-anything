#!/bin/bash
# Setup script for competition_compliance_modification task
# Copies dual_parachute_deployment.ork, injects 4 TRA compliance violations

echo "=== Setting up competition_compliance_modification task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/compliance_check.ork"
SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/compliance_memo.txt" 2>/dev/null || true

# Inject 4 TRA violations
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/compliance_check.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

violations = []

# Violation 1: Change drogue deploy from apogee to altitude
# Violation 2: Set main deploy altitude to 500m (must be <=244m/800ft)
for para in root.iter('parachute'):
    name_el = para.find('name')
    name = name_el.text if name_el is not None else ''
    deploy_event = para.find('deployevent')
    deploy_alt = para.find('deployaltitude')

    if 'drouge' in name.lower() or 'drogue' in name.lower():
        if deploy_event is not None:
            deploy_event.text = 'altitude'
            violations.append('drogue deploy changed to altitude (was apogee)')
    else:
        if deploy_alt is not None:
            deploy_alt.text = '500.0'
            violations.append('main deploy altitude set to 500m (was 152.4m)')

# Violation 3: Shrink fins to 15mm (unstable)
for fin in root.iter('trapezoidfinset'):
    height_el = fin.find('height')
    if height_el is not None:
        height_el.text = '0.015'
        violations.append('fin height shrunk to 15mm')

# Violation 4: Reset all simulations to outdated
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)
    violations.append(f'all simulations reset to outdated')

for v in violations:
    print(f"  Injected: {v}")

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
echo "task_start_ts=$(date +%s)" > /tmp/compliance_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the non-compliant rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/compliance_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== competition_compliance_modification task setup complete ==="
