#!/bin/bash
# Setup script for body_tube_altitude_tuning task

echo "=== Setting up body_tube_altitude_tuning task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/altitude_tuning_rocket.ork"
SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"

# Fallback to workspace data if not in Documents
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
fi

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/altitude_tuning_report.txt" 2>/dev/null || true

# Inject a C6-5 motor configuration and baseline state
python3 << 'PYEOF'
import zipfile, os, json
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/altitude_tuning_rocket.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Force motor to C6-5
for mm in root.iter('motormount'):
    # Clear existing motors
    for motor in list(mm.findall('motor')):
        mm.remove(motor)
    
    # Add C6 motor
    motor = ET.SubElement(mm, 'motor')
    motor.set('configid', 'c1')
    desig = ET.SubElement(motor, 'designation')
    desig.text = 'C6'
    delay = ET.SubElement(motor, 'delay')
    delay.text = '5.0'

# Calculate initial body tube length
initial_length = 0.0
for bt in root.iter('bodytube'):
    l_el = bt.find('length')
    if l_el is not None:
        try:
            initial_length += float(l_el.text)
        except ValueError:
            pass

# Reset simulations to outdated to force the agent to re-run
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        # Ensure it uses the C1 config
        conds = sim.find('conditions')
        if conds is not None:
            configid = conds.find('configid')
            if configid is not None:
                configid.text = 'c1'
            else:
                configid = ET.SubElement(conds, 'configid')
                configid.text = 'c1'
        
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)

# Save the initial length to a JSON file for the verifier
with open('/tmp/initial_state.json', 'w') as f:
    json.dump({'initial_body_tube_length_m': initial_length}, f)

# Write modified XML back to ZIP
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
print(f"Injected C6-5 motor. Initial body tube length: {initial_length}m")
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Record start time for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the target file
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 60
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== body_tube_altitude_tuning task setup complete ==="