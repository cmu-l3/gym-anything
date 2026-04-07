#!/bin/bash
# Setup script for crosswind_launch_compensation task
# Copies a competition rocket, clears all simulations

echo "=== Setting up crosswind_launch_compensation task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/crosswind_compensation.ork"
# Use EPFL BellaLui as the complex competition rocket if available, otherwise simple model
if [ -f "$ROCKETS_DIR/EPFL_BellaLui_2020.ork" ]; then
    SOURCE_ORK="$ROCKETS_DIR/EPFL_BellaLui_2020.ork"
else
    SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
fi

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/launch_compensation_report.txt" 2>/dev/null || true

# Clear all simulations so agent starts from scratch
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/crosswind_compensation.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Remove all simulations
sims_elem = root.find('simulations')
removed = 0
if sims_elem is not None:
    for sim in list(sims_elem.findall('simulation')):
        sims_elem.remove(sim)
        removed += 1

print(f"Cleared {removed} simulations (agent must create from scratch)")

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

# Launch OpenRocket with the blank-simulation rocket
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

echo "=== crosswind_launch_compensation task setup complete ==="