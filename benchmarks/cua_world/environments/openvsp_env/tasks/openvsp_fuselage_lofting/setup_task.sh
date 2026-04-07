#!/bin/bash
# Setup script for openvsp_fuselage_lofting task
# Creates the fuselage specification document and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_fuselage_lofting ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the specification document to the Desktop
cat > /home/ga/Desktop/fuselage_spec.txt << 'SPEC_EOF'
MALE UAV Fuselage Cross-Section Specification
==============================================
Reference: MQ-1 Predator class approximate dimensions
All dimensions in meters.

Fuselage Total Length: 8.2 m

Cross-Section Stations:
-----------------------
Station 1 (Nose):        Circular,  Width=0.30 m, Height=0.30 m
Station 2 (Fwd Fuse):    Circular,  Width=0.60 m, Height=0.60 m
Station 3 (Fwd Payload): Ellipse,   Width=0.80 m, Height=0.95 m
Station 4 (Max Section): Ellipse,   Width=0.92 m, Height=1.02 m
Station 5 (Aft Payload): Ellipse,   Width=0.78 m, Height=0.88 m
Station 6 (Tail Cone):   Ellipse,   Width=0.40 m, Height=0.45 m

Wing Parameters:
----------------
Type: Trapezoidal wing
Total Span: 14.8 m
Root Chord: 1.60 m
Tip Chord:  0.90 m

Save model as: ~/Documents/OpenVSP/male_uav.vsp3
SPEC_EOF

chown ga:ga /home/ga/Desktop/fuselage_spec.txt
chmod 644 /home/ga/Desktop/fuselage_spec.txt

# Remove any previous model
rm -f "$MODELS_DIR/male_uav.vsp3"
rm -f /tmp/openvsp_fuselage_lofting_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with a blank workspace
launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="