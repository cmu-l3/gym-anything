#!/bin/bash
set -e
echo "=== Setting up OpenVSP Geometric Tail Sizing Task ==="

source /workspace/scripts/task_utils.sh

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy the base eCRM-001 model
BASE_MODEL="/workspace/data/eCRM-001_wing_tail.vsp3"
TARGET_MODEL="$MODELS_DIR/aircraft_configuration.vsp3"

if [ -f "$BASE_MODEL" ]; then
    cp "$BASE_MODEL" "$TARGET_MODEL"
else
    # Fallback if standard data is missing, try to find any vsp3
    cp $(find /opt/openvsp_models -name "*.vsp3" | head -1) "$TARGET_MODEL"
fi

chmod 644 "$TARGET_MODEL"
chown ga:ga "$TARGET_MODEL"

# Inject randomized parameters into the XML to ensure a unique answer
# We modify the Wing's Span (changes Area) and the Tail's X-Location
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import random
import os

filepath = '/home/ga/Documents/OpenVSP/aircraft_configuration.vsp3'
if not os.path.exists(filepath):
    print(f"Error: {filepath} not found")
    exit(0)

try:
    tree = ET.parse(filepath)
    root = tree.getroot()
    
    # Scale factors for randomization
    span_scale = random.uniform(0.85, 1.15)
    tail_offset = random.uniform(2.0, 6.0)
    
    for geom in root.findall('.//Geom'):
        name_elem = geom.find('GeomName')
        if name_elem is None:
            continue
            
        geom_name = name_elem.text.lower()
        
        # Randomize Wing Span to change Area and MAC
        if 'wing' in geom_name:
            for parm in geom.findall('.//Parm'):
                if parm.get('Name') == 'TotalSpan' or parm.get('Name') == 'Span':
                    val = float(parm.get('Value'))
                    parm.set('Value', str(val * span_scale))
                    
        # Randomize Tail X-Location to change moment arm
        elif 'tail' in geom_name or 'horiz' in geom_name:
            for parm in geom.findall('.//Parm'):
                if parm.get('Name') == 'X_Rel_Location':
                    val = float(parm.get('Value'))
                    parm.set('Value', str(val + tail_offset))

    tree.write(filepath)
    print(f"Randomized model geometry successfully.")
except Exception as e:
    print(f"Error randomizing model: {e}")
PYEOF

# Clean up any stale files from previous runs
rm -f "$MODELS_DIR/aircraft_configuration_sized.vsp3"
rm -f /home/ga/Desktop/sizing_report.txt
rm -f /tmp/openvsp_tail_sizing_result.json

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Kill any running OpenVSP instance
kill_openvsp

# Launch OpenVSP with the starting model
launch_openvsp "$TARGET_MODEL"

# Wait for UI and capture state
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP window did not appear."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="