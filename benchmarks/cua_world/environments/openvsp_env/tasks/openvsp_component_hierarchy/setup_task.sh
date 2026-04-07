#!/bin/bash
# Setup script for openvsp_component_hierarchy task
# Creates the unlinked starting model and instructions

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_component_hierarchy ==="

# Ensure models directory exists
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Generate the unlinked model from the standard eCRM-001
# We strip ParentIDs and zero out XForm translations
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys

input_file = '/workspace/data/eCRM-001_wing_tail.vsp3'
output_file = '/home/ga/Documents/OpenVSP/ecrm_unlinked.vsp3'

try:
    tree = ET.parse(input_file)
    root = tree.getroot()
    
    for geom in root.findall('.//Geom'):
        # Strip ParentID
        pid = geom.find('ParentID')
        if pid is not None:
            pid.text = ''
            
        # Zero out XForm translations to stack everything at origin
        for pc in geom.findall('.//ParmContainer'):
            name = pc.find('Name')
            if name is not None and name.text == 'XForm':
                for loc in ['X_Location', 'Y_Location', 'Z_Location']:
                    node = pc.find(loc)
                    if node is not None:
                        node.set('Value', '0.000000000000000000e+00')
                        
    tree.write(output_file)
    print(f"Successfully generated unlinked model at {output_file}")
except Exception as e:
    print(f"XML Parsing failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

chown ga:ga "$MODELS_DIR/ecrm_unlinked.vsp3"
chmod 644 "$MODELS_DIR/ecrm_unlinked.vsp3"

# Write the assembly instructions document
cat > /home/ga/Desktop/assembly_instructions.txt << 'SPEC_EOF'
============================================================
  AIRCRAFT ASSEMBLY INSTRUCTIONS
  Document: ASSY-001 Rev A
============================================================

The model components have lost their parametric hierarchy and 
are currently stacked at the origin. 

Please re-establish the hierarchy using the OpenVSP XForm tab.
DO NOT rename the components.

1. WING ATTACHMENT
   - Parent Component: Fuselage
   - Relative X Location: 13.5 m

2. VERTICAL TAIL ATTACHMENT
   - Parent Component: Fuselage
   - Relative X Location: 35.0 m

3. HORIZONTAL TAIL ATTACHMENT (T-Tail Configuration)
   - Parent Component: Vertical Tail
   - Relative X Location: 2.0 m
   - Relative Z Location: 5.0 m

Once assembled, save the model as:
/home/ga/Documents/OpenVSP/assembled_jet.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/assembly_instructions.txt
chmod 644 /home/ga/Desktop/assembly_instructions.txt

# Clear any previous assembled files
rm -f "$MODELS_DIR/assembled_jet.vsp3"
rm -f /tmp/openvsp_component_hierarchy_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the unlinked model
launch_openvsp "$MODELS_DIR/ecrm_unlinked.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="