#!/bin/bash
set -e
echo "=== Setting up openvsp_phantom_dihedral_fixes task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the specification memo
cat > /home/ga/Desktop/stability_fixes.txt << 'EOF'
MEMORANDUM
To: Conceptual Design Group
From: Chief Aerodynamicist
Subject: F-4 Phantom Prototype Stability Fixes

Wind tunnel testing of the flat-winged prototype has revealed severe lateral-directional stability issues. We need to implement the following dihedral/anhedral fixes immediately to the production model:

1. MAIN WING (Component: Main_Wing)
   - Inboard Section (Section 1): Maintain at 0.0° dihedral to avoid redesigning the titanium wing box.
   - Outboard Section (Section 2): Apply +12.0° dihedral.

2. HORIZONTAL TAIL (Component: Horiz_Tail)
   - Apply -23.0° dihedral (anhedral) to keep it out of the wing wake at high angles of attack.

Save the updated configuration as:
/home/ga/Documents/OpenVSP/phantom_production.vsp3
EOF
chown ga:ga /home/ga/Desktop/stability_fixes.txt
chmod 644 /home/ga/Desktop/stability_fixes.txt

# Clear stale files
rm -f "$MODELS_DIR/phantom_prototype.vsp3"
rm -f "$MODELS_DIR/phantom_production.vsp3"
rm -f /tmp/task_result.json

# Use Python to generate a valid prototype by modifying an existing base model
# eCRM-001 has multiple sections on the wing, making it a perfect base
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys
import os

base_model = '/workspace/data/eCRM-001_wing_tail.vsp3'
out_model = '/home/ga/Documents/OpenVSP/phantom_prototype.vsp3'

if not os.path.exists(base_model):
    print(f"Error: Base model {base_model} not found.")
    sys.exit(1)

try:
    tree = ET.parse(base_model)
    root = tree.getroot()
    geoms = root.findall(".//Geom")
    
    # We assume eCRM-001 has at least a Wing and a Tail.
    # Rename them and flatten them (Dihedral = 0).
    if len(geoms) >= 1:
        geoms[0].find("Name").text = "Main_Wing"
        for p in geoms[0].findall(".//Parm[@Name='Dihedral']"):
            p.set("Value", "0.000000000000000000e+00")
            
    if len(geoms) >= 2:
        geoms[1].find("Name").text = "Horiz_Tail"
        for p in geoms[1].findall(".//Parm[@Name='Dihedral']"):
            p.set("Value", "0.000000000000000000e+00")
            
    tree.write(out_model)
    print("Successfully created phantom_prototype.vsp3")
except Exception as e:
    print(f"Failed to create prototype XML: {e}")
    sys.exit(1)
PYEOF

chown ga:ga "$MODELS_DIR/phantom_prototype.vsp3"
chmod 644 "$MODELS_DIR/phantom_prototype.vsp3"

# Kill any running OpenVSP
kill_openvsp

# Launch OpenVSP with the prototype file
launch_openvsp "$MODELS_DIR/phantom_prototype.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it"
    take_screenshot /tmp/task_initial.png
fi

echo "=== Setup complete ==="