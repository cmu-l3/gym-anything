#!/bin/bash
# Setup script for openvsp_evtol_lift_boom_integration task
# Prepares the baseline eCRM-001 model and creates the engineering specification

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_evtol_lift_boom_integration ==="

# Ensure working directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the boom specification document
cat > /home/ga/Desktop/boom_spec.txt << 'SPEC_EOF'
eVTOL LIFT BOOM GEOMETRY SPECIFICATION
Target Aircraft: eCRM-001 Baseline Configuration

Constraint 1: Acoustic Standoff
To prevent excessive cabin noise, the lift booms MUST be positioned exactly 8.5 meters outboard from the fuselage centerline.
-> Set Boom Y-Location to 8.5 m.

Constraint 2: Wing Integration
The boom must intersect the main wing. The local wing Z-height at the attachment station is +0.8m.
-> Set Boom Z-Location to 0.8 m.

Constraint 3: Boom Dimensions
-> Length: 14.0 m
-> Maximum Diameter / Width: 1.0 m

Constraint 4: Fore/Aft CG Placement
To balance the VTOL thrust, the boom must extend significantly forward of the wing leading edge.
-> Set Boom X-Location to 12.0 m (origin of the boom relative to global origin).

Constraint 5: Symmetry
Ensure the boom is mirrored on both sides of the aircraft to support left and right lift rotors.
(Enable the appropriate symmetry flag in the component's planar symmetry settings)

Requirement: Save the final integrated model to:
/home/ga/Documents/OpenVSP/ecrm_evtol.vsp3
SPEC_EOF

chown ga:ga /home/ga/Desktop/boom_spec.txt
chmod 644 /home/ga/Desktop/boom_spec.txt

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any previous result or output files to prevent gaming
rm -f "$MODELS_DIR/ecrm_evtol.vsp3"
rm -f /tmp/openvsp_evtol_boom_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (for verification)
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully with baseline model."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="