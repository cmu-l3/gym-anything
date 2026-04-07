#!/bin/bash
echo "=== Setting up launch_site_environmental_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

ROCKET_FILE="$ROCKETS_DIR/EPFL_BellaLui_2020.ork"

# Create directories and ensure permissions
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Clean any existing artifacts from previous runs
rm -f "$ROCKETS_DIR/environmental_analysis.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/switzerland.csv" "$EXPORTS_DIR/new_mexico.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/environmental_impact_report.txt" 2>/dev/null || true

# Strip existing simulations from the base file so the agent MUST create them from scratch
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/EPFL_BellaLui_2020.ork'
if not os.path.exists(ork_path):
    print("WARNING: Base rocket not found, assuming it will be downloaded/copied later.")
    exit(0)
    
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

sims_elem = root.find('simulations')
removed_count = 0
if sims_elem is not None:
    for sim in list(sims_elem.findall('simulation')):
        sims_elem.remove(sim)
        removed_count += 1

print(f"Removed {removed_count} existing simulations to enforce clean slate.")

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

chown ga:ga "$ROCKET_FILE"

# Record task start time for anti-gaming (to check file timestamps later)
date +%s > /tmp/task_start_time.txt

# Launch OpenRocket with the Bella Lui rocket
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

launch_openrocket "$ROCKET_FILE"
sleep 5

# Wait for UI, maximize, and dismiss potential update dialogs
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take baseline screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== Setup complete ==="