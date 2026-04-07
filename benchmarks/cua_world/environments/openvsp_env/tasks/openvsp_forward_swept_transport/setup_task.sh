#!/bin/bash
# Setup script for openvsp_forward_swept_transport task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_forward_swept_transport task ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any existing output file
rm -f "$MODELS_DIR/eCRM001_fsw.vsp3"
rm -f /tmp/openvsp_fsw_result.json

# Write the engineering specification document
cat > /home/ga/Desktop/fsw_spec.txt << 'SPEC_EOF'
============================================================
  CONFIGURATION TRADE STUDY: FORWARD-SWEPT WING (FSW)
  Document: ENG-FSW-002
  Baseline: eCRM-001 Transport
============================================================

Instructions:
Open the baseline eCRM-001 model and modify the geometry 
to represent a forward-swept configuration.

Required Parameter Changes:
---------------------------
1. Wing Sweep:
   Change the main Wing sweep angle to -25.0 degrees (forward sweep).

2. Wing Longitudinal Balancing:
   To maintain the aerodynamic center and static margin, the Wing 
   must be moved further aft along the fuselage.
   Increase the Wing's X-Location (in the XForm tab) by exactly +3.0 meters 
   from its current baseline value.

3. Wing Twist (Wash-in):
   Forward-swept wings experience root-stall first. To counteract this, 
   reverse the tip twist. Set the outermost section's Twist parameter 
   to +2.0 degrees (wash-in).

4. Horizontal Tail Sweep:
   Change the Horiz_Tail sweep angle to -15.0 degrees to match the 
   forward-swept configuration aesthetic and aero properties.

Final Output:
-------------
Save the modified model to:
/home/ga/Documents/OpenVSP/eCRM001_fsw.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/fsw_spec.txt
chmod 644 /home/ga/Desktop/fsw_spec.txt

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp recorded."

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Wait for UI and capture initial state
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