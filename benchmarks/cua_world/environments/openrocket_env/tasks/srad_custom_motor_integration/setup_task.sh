#!/bin/bash
# Setup script for srad_custom_motor_integration task

echo "=== Setting up srad_custom_motor_integration task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

MOTORS_DIR="/home/ga/Documents/motors"
ROCKETS_DIR="/home/ga/Documents/rockets"
EXPORTS_DIR="/home/ga/Documents/exports"
START_ORK="$ROCKETS_DIR/srad_start.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"

# Fallback if workspace data isn't mounted
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"
fi

# Create directories
mkdir -p "$MOTORS_DIR" "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$MOTORS_DIR" "$ROCKETS_DIR" "$EXPORTS_DIR"

# 1. Generate the custom SRAD RASP (.eng) motor file
cat > "$MOTORS_DIR/SRAD_C40.eng" << 'EOF'
; SRAD Custom Motor C40
; Generated for OpenRocket task
SRAD_C40 18 70 5 0.012 0.035 SRAD_Team
  0.000  0.000
  0.020 20.000
  0.050 45.000
  0.300 40.000
  0.350 20.000
  0.370  0.000
EOF
chown ga:ga "$MOTORS_DIR/SRAD_C40.eng"

# 2. Copy source .ork to task working file and clear existing motors/simulations
cp "$SOURCE_ORK" "$START_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$START_ORK"

# Clear all simulations and motor configs so agent starts clean
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/srad_start.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Remove all simulations
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in list(sims_elem.findall('simulation')):
        sims_elem.remove(sim)

# Remove all motor configurations from motormount
for mm in root.iter('motormount'):
    for motor in list(mm.findall('motor')):
        mm.remove(motor)
    for ic in list(mm.findall('ignitionconfiguration')):
        mm.remove(ic)

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
    echo "FATAL: Python setup failed to strip .ork"
    exit 1
fi

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure OpenRocket is closed to start fresh
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the stripped start rocket
launch_openrocket "$START_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== srad_custom_motor_integration task setup complete ==="