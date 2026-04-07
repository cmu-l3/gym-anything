#!/bin/bash
# Setup script for performance_envelope_design task
# Copies simple_model_rocket.ork, injects overpowered motor and undersized parachute

echo "=== Setting up performance_envelope_design task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/performance_envelope_report.txt" 2>/dev/null || true

# Inject faults:
# 1. Overpowered motor (C6, will overshoot 150m target significantly)
# 2. Undersized parachute (0.152m / 6 inches, dangerous descent speed)
# 3. Clear existing simulation results
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/simple_model_rocket.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Inject overpowered motor (C6)
for mm in root.iter('motormount'):
    for motor in mm.findall('motor'):
        desig = motor.find('designation')
        if desig is not None:
            desig.text = 'C6'
        else:
            ET.SubElement(motor, 'designation').text = 'C6'
            
        delay = motor.find('delay')
        if delay is not None:
            delay.text = '5.0'
        else:
            ET.SubElement(motor, 'delay').text = '5.0'

# Inject undersized parachute
for para in root.iter('parachute'):
    diam = para.find('diameter')
    if diam is not None:
        diam.text = '0.152'
    else:
        ET.SubElement(para, 'diameter').text = '0.152'

# Reset simulations to outdated
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)

print("Injected C6 motor, 152mm parachute, and outdated simulations.")

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

# Record ground truth and timestamp for anti-gaming verification
echo "task_start_ts=$(date +%s)" > /tmp/envelope_design_gt.txt

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
take_screenshot /tmp/envelope_design_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== performance_envelope_design task setup complete ==="