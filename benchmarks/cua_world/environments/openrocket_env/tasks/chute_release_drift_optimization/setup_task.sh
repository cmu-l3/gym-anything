#!/bin/bash
# Setup script for chute_release_drift_optimization task

echo "=== Setting up chute_release_drift_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/chute_release_task.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Try to find a suitable base rocket (prefer chute_release.ork, fallback to simple_model_rocket.ork)
if [ -f "$ROCKETS_DIR/chute_release.ork" ]; then
    cp "$ROCKETS_DIR/chute_release.ork" "$TASK_ORK"
elif [ -f "/workspace/data/rockets/chute_release.ork" ]; then
    cp "/workspace/data/rockets/chute_release.ork" "$TASK_ORK"
elif [ -f "$ROCKETS_DIR/simple_model_rocket.ork" ]; then
    cp "$ROCKETS_DIR/simple_model_rocket.ork" "$TASK_ORK"
else
    echo "FATAL: Could not find any base rocket"
    exit 1
fi

chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$ROCKETS_DIR/optimized_chute_release.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/chute_release_report.txt" 2>/dev/null || true

# Inject starting faults: 
# 1. Parachute deployevent = APOGEE
# 2. Parachute diameter = 0.15m (unsafe descent)
# 3. All simulations outdated and wind set to 2.0 m/s
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/chute_release_task.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Modify Parachutes
for para in root.iter('parachute'):
    # Force deploy at apogee
    de = para.find('deployevent')
    if de is not None:
        de.text = 'APOGEE'
    else:
        ET.SubElement(para, 'deployevent').text = 'APOGEE'
    
    # Remove altitude if present
    da = para.find('deployaltitude')
    if da is not None:
        para.remove(da)
        
    # Shrink diameter to 0.15m (undersized)
    diam = para.find('diameter')
    if diam is not None:
        diam.text = '0.15'

# Reset simulations
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        
        # Strip flight data
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)
            
        # Reset wind conditions to default 2.0 m/s so agent has to fix it
        cond = sim.find('conditions')
        if cond is not None:
            wind = cond.find('windaverage')
            if wind is not None:
                wind.text = '2.0'
            else:
                ET.SubElement(cond, 'windaverage').text = '2.0'

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

# Record ground truth start time
echo "task_start_ts=$(date +%s)" > /tmp/chute_release_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the modified starting rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== chute_release_drift_optimization task setup complete ==="