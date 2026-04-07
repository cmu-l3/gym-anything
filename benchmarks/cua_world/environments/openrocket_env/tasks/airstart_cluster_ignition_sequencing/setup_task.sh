#!/bin/bash
echo "=== Setting up airstart_cluster_ignition_sequencing task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

ROCKETS_DIR="/home/ga/Documents/rockets"
EXPORTS_DIR="/home/ga/Documents/exports"
TASK_ORK="$ROCKETS_DIR/clustered_motors.ork"
SOURCE_ORK="/workspace/data/rockets/clustered_motors.ork"

mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
if [ -f "$SOURCE_ORK" ]; then
    cp "$SOURCE_ORK" "$TASK_ORK"
else
    # Fallback to wget if not in workspace
    wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/Clustered%20motors.ork" -O "$TASK_ORK"
fi

chown ga:ga "$TASK_ORK"

# Remove any target files from previous runs to prevent gaming
rm -f "$ROCKETS_DIR/airstart_cluster.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/airstart_flight_data.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/airstart_report.txt" 2>/dev/null || true

# Strip existing simulations to ensure the agent creates and runs new ones
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/clustered_motors.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Remove simulations
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in list(sims_elem.findall('simulation')):
        sims_elem.remove(sim)

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

echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the source file loaded
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

echo "=== Setup complete ==="