#!/bin/bash
# Setup script for openvsp_conformal_radome task
# Prepares the eCRM-001 model, creates the specification document, and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_conformal_radome task ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the radome specification document
cat > /home/ga/Desktop/radome_spec.txt << 'SPEC_EOF'
SATCOM RADOME SPECIFICATION
===========================
Project: eCRM-001 In-Flight Connectivity Upgrade

Component Name: Satcom_Radome
Geometry Type:  Conformal
Parent Body:    Fuselage
Symmetry:       None (Centerline placement)

Parametric Surface Bounds (Conformal tab):
  U_Min (Start Length): 0.25
  U_Max (End Length):   0.30
  V_Min (Right side):   0.45
  V_Max (Left side):    0.55
  Thickness:            0.35 m

Output Requirements:
1. Save model to: /home/ga/Documents/OpenVSP/eCRM001_satcom.vsp3
2. Run CompGeom analysis (Analysis > CompGeom)
3. Note the Total Wetted Area from the results
4. Write the Total Wetted Area value to /home/ga/Desktop/radome_report.txt
SPEC_EOF

chown ga:ga /home/ga/Desktop/radome_spec.txt
chmod 644 /home/ga/Desktop/radome_spec.txt

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any previous task artifacts
rm -f "$MODELS_DIR/eCRM001_satcom.vsp3"
rm -f /home/ga/Desktop/radome_report.txt
rm -f /tmp/task_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_initial.png
fi

echo "=== Setup complete ==="