#!/bin/bash
# Setup script for parachute_spill_hole_drift_optimization task

echo "=== Setting up parachute_spill_hole_drift_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/high_drift_rocket.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Check if workspace data is mounted, else copy from default home
if [ -f "$SOURCE_ORK" ]; then
    cp "$SOURCE_ORK" "$TASK_ORK"
elif [ -f "/home/ga/Documents/rockets/simple_model_rocket.ork" ]; then
    cp "/home/ga/Documents/rockets/simple_model_rocket.ork" "$TASK_ORK"
else
    echo "FATAL: Could not find base rocket file"
    exit 1
fi

chown ga:ga "$TASK_ORK"

# Remove any pre-existing output files
rm -f "$ROCKETS_DIR/spill_hole_optimized.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/drift_report.txt" 2>/dev/null || true

# Inject massive parachute and 6.0m/s crosswind
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/high_drift_rocket.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Set parachute diameter to 36 inches (0.9144m) and clear any spill holes
for para in root.iter('parachute'):
    diam = para.find('diameter')
    if diam is not None:
        diam.text = '0.9144'
    else:
        ET.SubElement(para, 'diameter').text = '0.9144'
        
    spill = para.find('spillholediameter')
    if spill is not None:
        para.remove(spill)

# Force wind speed to 6.0 m/s and outdated simulation
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        conds = sim.find('conditions')
        if conds is None:
            conds = ET.SubElement(sim, 'conditions')
            
        ws = conds.find('windspeed')
        if ws is None:
            ws = ET.SubElement(conds, 'windspeed')
        ws.text = '6.0'
        
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)

print("Injected 0.9144m parachute and 6.0 m/s wind speed.")

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

# Record start time for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/spill_hole_gt.txt

# Clean launch
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

# Take initial screenshot for evidence
take_screenshot /tmp/spill_hole_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== task setup complete ==="