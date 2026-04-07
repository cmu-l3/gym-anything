#!/bin/bash
echo "=== Setting up high_wind_recovery_overhaul task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
if [ ! -f "$SOURCE_ORK" ]; then
    # Fallback if external data isn't mounted
    SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"
fi

mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

cp "$SOURCE_ORK" "$TASK_ORK" 2>/dev/null || true
chown ga:ga "$TASK_ORK"

# Clean up any potential artifacts from previous runs
rm -f "$EXPORTS_DIR/wind_mitigation_report.txt" 2>/dev/null || true

# Reset simulations to outdated status so the agent is forced to re-run them
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/simple_model_rocket.ork'
if not os.path.exists(ork_path):
    print("WARNING: ork file not found for setup")
    exit(0)
    
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

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

echo "task_start_ts=$(date +%s)" > /tmp/high_wind_gt.txt

pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

take_screenshot /tmp/high_wind_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== high_wind_recovery_overhaul task setup complete ==="