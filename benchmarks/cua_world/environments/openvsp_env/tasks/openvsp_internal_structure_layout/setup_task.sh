#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_internal_structure_layout ==="

# Create necessary directories
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the engineering specification file
cat > /home/ga/Desktop/structural_spec.txt << 'SPEC_EOF'
============================================================
  STRUCTURAL LAYOUT SPECIFICATION
  Project: eCRM-001 Transport
  Subsystem: Main Wing Box
============================================================

The aerodynamic shape is frozen. Please define the internal 
structural skeleton for the main Wing component to prepare 
for FEA meshing.

Requirements:
-------------
1. Front Spar Location : 22% chord (0.22 fraction)
2. Rear Spar Location  : 68% chord (0.68 fraction)
3. Spanwise Ribs       : Exactly 34 ribs

Instructions:
-------------
In OpenVSP, select the main Wing component, go to the 
Structure tab/panel, and insert the required spars and ribs. 
Ensure the values map correctly to the GUI parameters.

Save the completed assembly to:
/home/ga/Documents/OpenVSP/exports/eCRM001_structural.vsp3
============================================================
SPEC_EOF
chown ga:ga /home/ga/Desktop/structural_spec.txt
chmod 644 /home/ga/Desktop/structural_spec.txt

# Copy base eCRM-001 model
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Clear any stale outputs
rm -f "$EXPORTS_DIR/eCRM001_structural.vsp3"
rm -f /tmp/task_result.json

# Kill any currently running OpenVSP processes
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time

# Launch OpenVSP with the eCRM model pre-loaded
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
WID=$(wait_for_openvsp 60)

if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched and focused."
else
    take_screenshot /tmp/task_initial.png
    echo "WARNING: OpenVSP window did not appear."
fi

echo "=== Setup complete ==="