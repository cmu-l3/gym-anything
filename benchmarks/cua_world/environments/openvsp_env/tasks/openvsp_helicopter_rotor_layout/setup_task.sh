#!/bin/bash
# Setup script for openvsp_helicopter_rotor_layout task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_helicopter_rotor_layout ==="

# Ensure working directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Create a baseline helicopter fuselage by parsing the existing eCRM-001 model
# and stripping out everything except the Fuselage component.
# This ensures we use real OpenVSP geometry parameters rather than synthetic mocks.
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys

source_path = '/workspace/data/eCRM-001_wing_tail.vsp3'
dest_path = '/home/ga/Documents/OpenVSP/heli_fuselage.vsp3'

try:
    tree = ET.parse(source_path)
    root = tree.getroot()
    vehicle = root.find('Vehicle')
    
    # Remove all components that are not the fuselage
    for geom in vehicle.findall('Geom'):
        name_elem = geom.find('Name')
        if name_elem is not None and 'Fuselage' not in name_elem.text:
            vehicle.remove(geom)
            
    tree.write(dest_path)
    print(f"Successfully created baseline fuselage at {dest_path}")
except Exception as e:
    print(f"Warning: Failed to parse {source_path}: {e}")
    # Create minimal fallback file if parsing fails
    with open(dest_path, 'w') as f:
        f.write('<?xml version="1.0"?>\n<VSP_Geometry>\n<Version>3.41.2</Version>\n<Vehicle>\n<Geom>\n<Name>Fuselage</Name>\n<Type>Fuselage</Type>\n</Geom>\n</Vehicle>\n</VSP_Geometry>\n')
PYEOF

chown ga:ga "$MODELS_DIR/heli_fuselage.vsp3"
chmod 644 "$MODELS_DIR/heli_fuselage.vsp3"

# Write the rotor specification document
cat > /home/ga/Desktop/rotor_spec.txt << 'SPEC_EOF'
============================================================
  ROTOR INTEGRATION SPECIFICATION
  Document: HELI-2026-ROTORS-001
  Units: Metric (meters and degrees)
============================================================

1. MAIN LIFTING ROTOR
------------------------
Component Type : Propeller
Name           : MainRotor
Diameter       : 12.0 m
Blade Count    : 4
Position       : X = 3.0 m, Z = 2.0 m
Thrust Axis    : Vertical (Apply 90-degree Pitch / Y_Rot in XForm)

2. ANTI-TORQUE TAIL ROTOR
------------------------
Component Type : Propeller
Name           : TailRotor
Diameter       : 2.2 m
Blade Count    : 2
Position       : X = 10.5 m, Y = 0.4 m, Z = 1.0 m
Thrust Axis    : Lateral (Apply 90-degree Yaw / Z_Rot in XForm)

Notes
-----
- Ensure XForm rotations are applied so the propeller disks are oriented correctly.
- Save the completed model EXACTLY as:
  /home/ga/Documents/OpenVSP/helicopter_configured.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/rotor_spec.txt
chmod 644 /home/ga/Desktop/rotor_spec.txt

# Remove any previous configured model
rm -f "$MODELS_DIR/helicopter_configured.vsp3"
rm -f /tmp/openvsp_helicopter_result.json

# Kill any running OpenVSP instances
kill_openvsp

# Launch OpenVSP with the baseline fuselage
launch_openvsp "$MODELS_DIR/heli_fuselage.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully with baseline model."
else
    echo "WARNING: OpenVSP window did not appear — agent may need to launch it manually."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="