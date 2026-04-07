#!/bin/bash
# Setup script for openvsp_propeller_blade_design task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_propeller_blade_design ==="

# Record task start time
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded: $(cat /tmp/task_start_timestamp)"

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the propeller specification document (Real data: Hartzell HC-B4TN-5FL)
cat > /home/ga/Desktop/propeller_spec.txt << 'SPEC_EOF'
HARTZELL PROPELLER SPECIFICATION
================================
Model: HC-B4TN-5FL
Application: King Air 350-class turboprop

Geometry Parameters:
  Number of Blades  : 4
  Diameter          : 2.36 m  (92.9 in)
  Precone Angle     : 2.5 deg
  
Design Conditions:
  Design RPM        : 1700
  Activity Factor   : 105 per blade

Modeling Notes:
  - Name the propeller component "HC-B4TN" in OpenVSP
  - Save model as: /home/ga/Documents/OpenVSP/kingair_propeller.vsp3
  - Ensure at least 3 blade radial cross-sections are defined
SPEC_EOF

chown ga:ga /home/ga/Desktop/propeller_spec.txt
chmod 644 /home/ga/Desktop/propeller_spec.txt

# Clean up any old files
rm -f "$MODELS_DIR/kingair_propeller.vsp3"
rm -f /tmp/openvsp_propeller_result.json

# Kill any running OpenVSP
kill_openvsp

# Launch blank OpenVSP (no file argument)
launch_openvsp
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