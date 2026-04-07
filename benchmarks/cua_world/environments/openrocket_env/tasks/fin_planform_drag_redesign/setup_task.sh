#!/bin/bash
echo "=== Setting up fin planform redesign task ==="
source /workspace/scripts/task_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/rockets
chown -R ga:ga /home/ga/Documents/exports /home/ga/Documents/rockets

# Source rocket
SRC_FILE="/workspace/data/rockets/simple_model_rocket.ork"
# Fallback if not in workspace
if [ ! -f "$SRC_FILE" ]; then
    SRC_FILE="/home/ga/Documents/rockets/simple_model_rocket.ork"
fi

WORK_FILE="/home/ga/Documents/rockets/simple_model_rocket.ork"

if [ ! -f "$SRC_FILE" ]; then
    echo "ERROR: Source rocket not found at $SRC_FILE"
    # Create a dummy to prevent total failure
    touch "$WORK_FILE"
else
    # Copy to work location
    cp "$SRC_FILE" "$WORK_FILE"
    chown ga:ga "$WORK_FILE"
    
    # Modify the .ork file to inject rectangular fins
    python3 << 'PYEOF'
import zipfile
import os
import xml.etree.ElementTree as ET
import json

ork_path = '/home/ga/Documents/rockets/simple_model_rocket.ork'
tmp_path = ork_path + '.tmp'

try:
    with zipfile.ZipFile(ork_path, 'r') as zin:
        xml_filename = None
        for name in zin.namelist():
            if name.endswith('.ork') or name.endswith('.xml'):
                xml_filename = name
                break
        
        if not xml_filename:
            print("No XML found in ZIP")
            exit(0)
            
        xml_bytes = zin.read(xml_filename)

    root = ET.fromstring(xml_bytes.decode('utf-8'))

    initial_state = {}
    modified = False

    for finset in root.iter():
        if 'finset' in finset.tag.lower():
            rc = finset.find('rootchord')
            tc = finset.find('tipchord')
            sw = finset.find('sweeplength')

            if rc is not None and tc is not None:
                initial_state['original_rootchord'] = rc.text
                initial_state['original_tipchord'] = tc.text
                if sw is not None:
                    initial_state['original_sweeplength'] = sw.text

                # Set rectangular fins
                rc.text = '0.15'
                tc.text = '0.15'
                if sw is not None:
                    sw.text = '0.0'
                else:
                    sweep_elem = ET.SubElement(finset, 'sweeplength')
                    sweep_elem.text = '0.0'
                
                modified = True

    # Mark all simulations as outdated
    for sim in root.iter('simulation'):
        status = sim.get('status')
        if status:
            sim.set('status', 'outdated')
        for s_elem in sim.iter('status'):
            s_elem.text = 'outdated'

    if modified:
        modified_xml = ET.tostring(root, encoding='unicode', xml_declaration=False)
        modified_xml_bytes = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + modified_xml).encode('utf-8')

        with zipfile.ZipFile(ork_path, 'r') as zin:
            with zipfile.ZipFile(tmp_path, 'w', zipfile.ZIP_DEFLATED) as zout:
                for item in zin.infolist():
                    if item.filename == xml_filename:
                        zout.writestr(item, modified_xml_bytes)
                    else:
                        zout.writestr(item, zin.read(item.filename))

        os.replace(tmp_path, ork_path)
        print("Successfully injected rectangular fins")
        
        with open('/tmp/initial_fin_state.json', 'w') as f:
            json.dump(initial_state, f)
            
except Exception as e:
    print(f"Error modifying .ork: {e}")
PYEOF
fi

# Kill any running OpenRocket
pkill -9 -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket
echo "Launching OpenRocket with modified rocket..."
if type launch_openrocket &>/dev/null; then
    launch_openrocket "$WORK_FILE"
else
    su - ga -c "DISPLAY=:1 java -Xms512m -Xmx2048m -jar /opt/openrocket/OpenRocket.jar '$WORK_FILE' > /tmp/openrocket_task.log 2>&1 &"
fi

# Wait for window
sleep 10
if type focus_openrocket_window &>/dev/null; then
    focus_openrocket_window
    sleep 2
    dismiss_dialogs 3
else
    DISPLAY=:1 wmctrl -r "OpenRocket" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "OpenRocket" 2>/dev/null || true
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi
sleep 2

# Take initial screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial_state.png
else
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
fi

echo "=== Fin planform redesign task setup complete ==="