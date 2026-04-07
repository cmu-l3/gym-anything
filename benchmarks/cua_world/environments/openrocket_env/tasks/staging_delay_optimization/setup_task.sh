#!/bin/bash
# Setup script for staging_delay_optimization task
# Copies three_stage_low_power_rocket.ork and corrupts the upper stage ignition delays

echo "=== Setting up staging_delay_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/three_stage_low_power_rocket.ork"
SOURCE_ORK="/workspace/data/rockets/three_stage_low_power_rocket.ork"

# Fallback to local copy if running outside full workspace context
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="/home/ga/Documents/rockets/three_stage_low_power_rocket.ork"
fi

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/staging_report.txt" 2>/dev/null || true

# Inject 20.0s (stage 3) and 0.0s (stage 2) delays
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/three_stage_low_power_rocket.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Modify stages (Stage 3 is at index 0 (top), Stage 2 at index 1 (middle))
stages = list(root.iter('stage'))
for i, stage in enumerate(stages):
    for mm in stage.iter('motormount'):
        delay_el = mm.find('ignitiondelay')
        if delay_el is None:
            delay_el = ET.SubElement(mm, 'ignitiondelay')
        
        if i == 0:
            delay_el.text = '20.0' # Top stage
        elif i == 1:
            delay_el.text = '0.0'  # Middle stage

# Reset all simulations to outdated
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

# Record ground truth and start time for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/staging_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the corrupted rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot showing loaded state
take_screenshot /tmp/staging_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== staging_delay_optimization task setup complete ==="