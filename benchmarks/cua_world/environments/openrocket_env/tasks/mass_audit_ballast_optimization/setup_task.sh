#!/bin/bash
# Setup script for mass_audit_ballast_optimization task
# Copies simple_model_rocket.ork, injects a 120g aft electronics payload, resets sims

echo "=== Setting up mass_audit_ballast_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/mass_audit_rocket.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
EXPORTS_DIR="/home/ga/Documents/exports"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
if [ ! -f "$SOURCE_ORK" ]; then
    # Fallback to local downloaded dir if workspace mount is missing
    SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"
fi

cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/mass_budget_report.txt" 2>/dev/null || true

# Inject the 120g Electronics Payload into the aft section of the body tube
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/mass_audit_rocket.ork'
tmp_path = ork_path + '.tmp'

try:
    with zipfile.ZipFile(ork_path, 'r') as zin:
        xml_bytes = zin.read('rocket.ork')
    root = ET.fromstring(xml_bytes.decode('utf-8'))
except Exception as e:
    print(f"Failed to read/parse ORK: {e}")
    exit(1)

# Inject the 120g payload to the first bodytube
for bt in root.iter('bodytube'):
    mc = ET.SubElement(bt, 'masscomponent')
    name_el = ET.SubElement(mc, 'name')
    name_el.text = 'Electronics Payload'
    
    pos_el = ET.SubElement(mc, 'position')
    pos_el.set('type', 'bottom')
    pos_el.text = '-0.02'
    
    ET.SubElement(mc, 'packedlength').text = '0.06'
    ET.SubElement(mc, 'packedradius').text = '0.012'
    ET.SubElement(mc, 'mass').text = '0.120'
    ET.SubElement(mc, 'masscomponenttype').text = 'altimeter'
    
    print("Injected 120g Electronics Payload near the aft end of the body tube.")
    break  # only inject once

# Reset all simulations to outdated to force re-verification
sims_elem = root.find('simulations')
sim_count = 0
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)
        sim_count += 1
print(f"Reset {sim_count} simulations to outdated status.")

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

# Record ground truth and anti-gaming initial hash
echo "task_start_ts=$(date +%s)" > /tmp/mass_audit_gt.txt
md5sum "$TASK_ORK" | awk '{print $1}' > /tmp/initial_ork_hash.txt

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
take_screenshot /tmp/mass_audit_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== mass_audit_ballast_optimization task setup complete ==="