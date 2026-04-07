#!/bin/bash
# Setup script for constrained_stability_optimization task

echo "=== Setting up constrained_stability_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="/home/ga/Documents/rockets/aft_heavy_rocket.ork"
SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"

# Create working directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure source file exists (fallback to workspace data if missing)
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
fi

# Remove previous output files
rm -f "/home/ga/Documents/rockets/stable_swept_rocket.ork" 2>/dev/null || true
rm -f "/home/ga/Documents/exports/sweep_optimization_memo.txt" 2>/dev/null || true

# Python script to inject the GPS Tracker, normalize fins, and reset simulations
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

source_path = '/workspace/data/rockets/simple_model_rocket.ork'
if not os.path.exists(source_path):
    source_path = '/home/ga/Documents/rockets/simple_model_rocket.ork'

ork_path = '/home/ga/Documents/rockets/aft_heavy_rocket.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(source_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# 1. Normalize the trapezoidal fin set to strict baseline values
for fin in root.iter('trapezoidfinset'):
    # Remove existing conflicting tags to ensure clean baseline
    for tag in ['rootchord', 'tipchord', 'height', 'sweeplength']:
        el = fin.find(tag)
        if el is not None:
            fin.remove(el)
    
    # Add strictly defined baseline tags
    ET.SubElement(fin, 'rootchord').text = '0.080'
    ET.SubElement(fin, 'tipchord').text = '0.040'
    ET.SubElement(fin, 'height').text = '0.045'
    ET.SubElement(fin, 'sweeplength').text = '0.020'

# 2. Inject the heavy GPS Tracker into the lowest body tube
body_tubes = list(root.iter('bodytube'))
if body_tubes:
    target_bt = body_tubes[-1] # Usually the aft-most main tube
    subcomponents = target_bt.find('subcomponents')
    if subcomponents is None:
        subcomponents = ET.SubElement(target_bt, 'subcomponents')
    
    mc = ET.SubElement(subcomponents, 'masscomponent')
    ET.SubElement(mc, 'name').text = 'GPS Tracker'
    ET.SubElement(mc, 'position', {'type': 'bottom'}).text = '0.0'
    ET.SubElement(mc, 'mass').text = '0.150'
    ET.SubElement(mc, 'cg').text = '0.0'

# 3. Reset all simulations to outdated
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)

modified_xml = ET.tostring(root, encoding='unicode', xml_declaration=False)
modified_xml_bytes = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + modified_xml).encode('utf-8')

with zipfile.ZipFile(tmp_path, 'w', zipfile.ZIP_DEFLATED) as zout:
    with zipfile.ZipFile(source_path, 'r') as zin:
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

chown ga:ga "$TASK_ORK"

# Record timestamps
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Launch OpenRocket with the unstable rocket
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot showing starting state
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== constrained_stability_optimization task setup complete ==="