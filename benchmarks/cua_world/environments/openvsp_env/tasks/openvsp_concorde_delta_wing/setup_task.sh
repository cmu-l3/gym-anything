#!/bin/bash
# Setup script for openvsp_concorde_delta_wing task
# Creates spec document, clears old files, and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_concorde_delta_wing ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the Concorde wing specification document
cat > /home/ga/Desktop/concorde_wing_spec.txt << 'SPEC_EOF'
CONCORDE DIGITAL TWIN - BASELINE WING SPECIFICATION
===================================================
Aircraft: Aérospatiale/BAC Concorde
Component: Main Wing (Simplified Delta)

PLANFORM GEOMETRY:
------------------
Span                : 25.6 m
Root Chord          : 34.0 m
Tip Chord           : 2.0 m
Leading Edge Sweep  : 60.0 degrees

AIRFOIL / CROSS-SECTION (XSec Tab):
-----------------------------------
Type                : Biconvex (Supersonic profile)
Thickness (T/C)     : 3.0% (0.03)

Note: Ensure the 'Biconvex' airfoil type and 3% thickness are applied 
to ALL spanwise sections of the wing component (both Root and Tip). 
Name the component "Concorde_Wing" and save the model to:
~/Documents/OpenVSP/concorde_wing.vsp3
SPEC_EOF

chown ga:ga /home/ga/Desktop/concorde_wing_spec.txt
chmod 644 /home/ga/Desktop/concorde_wing_spec.txt

# Remove any previous outputs to ensure a clean state
rm -f "$MODELS_DIR/concorde_wing.vsp3"
rm -f /tmp/openvsp_concorde_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (crucial for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp recorded."

# Launch blank OpenVSP (no file argument)
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