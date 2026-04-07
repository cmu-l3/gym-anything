#!/bin/bash
echo "=== Setting up asymmetric_payload_balancing task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/asymmetric_rocket.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
# Fallback if workspace data is missing
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
fi

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$ROCKETS_DIR/balanced_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/balance_report.txt" 2>/dev/null || true

# Inject the asymmetric Action Camera and clear previous simulations
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/asymmetric_rocket.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Find the first bodytube and add the payload
bodytube = next(root.iter('bodytube'), None)
if bodytube is not None:
    subcomps = bodytube.find('subcomponents')
    if subcomps is None:
        subcomps = ET.SubElement(bodytube, 'subcomponents')
    
    camera = ET.SubElement(subcomps, 'masscomponent')
    ET.SubElement(camera, 'name').text = 'Action Camera'
    ET.SubElement(camera, 'mass').text = '0.05'
    ET.SubElement(camera, 'radialposition').text = '0.03'
    ET.SubElement(camera, 'radialdirection').text = '0.0'
    ET.SubElement(camera, 'length').text = '0.04'
    ET.SubElement(camera, 'radius').text = '0.015'
    
# Reset all simulations to outdated to ensure agent re-runs them
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
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/balancing_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the modified asymmetric rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== asymmetric_payload_balancing task setup complete ==="