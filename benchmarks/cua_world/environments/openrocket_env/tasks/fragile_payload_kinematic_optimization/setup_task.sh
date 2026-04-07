#!/bin/bash
# Setup script for fragile_payload_kinematic_optimization task

echo "=== Setting up fragile_payload_kinematic_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="$ROCKETS_DIR/janus_38mm.ork"
TASK_ORK="$ROCKETS_DIR/janus_payload.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Try to find the source file (could be mounted from workspace or downloaded by install script)
if [ ! -f "$SOURCE_ORK" ]; then
    if [ -f "/workspace/data/rockets/janus_38mm.ork" ]; then
        cp "/workspace/data/rockets/janus_38mm.ork" "$SOURCE_ORK"
    else
        # Download fallback if missing
        wget -q "https://raw.githubusercontent.com/3dp-rocket/rockets/master/janus/OpenRocket-38mm.ork" -O "$SOURCE_ORK" || true
    fi
fi

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$ROCKETS_DIR/payload_ready.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/acceleration_plot.png" 2>/dev/null || true
rm -f "$EXPORTS_DIR/payload_memo.txt" 2>/dev/null || true

# Clear all simulations and motor configs so agent starts from scratch
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/janus_payload.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Remove all simulations
sims_elem = root.find('simulations')
removed_sims = 0
if sims_elem is not None:
    for sim in list(sims_elem.findall('simulation')):
        sims_elem.remove(sim)
        removed_sims += 1

# Remove all motor configurations from motormounts
removed_motors = 0
for mm in root.iter('motormount'):
    for motor in list(mm.findall('motor')):
        mm.remove(motor)
        removed_motors += 1
    for ic in list(mm.findall('ignitionconfiguration')):
        mm.remove(ic)

print(f"Cleared {removed_sims} simulations and {removed_motors} motor configs")

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
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the blank-motor rocket
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

echo "=== fragile_payload_kinematic_optimization task setup complete ==="