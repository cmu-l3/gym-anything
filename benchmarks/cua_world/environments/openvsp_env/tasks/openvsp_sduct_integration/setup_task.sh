#!/bin/bash
# Setup script for openvsp_sduct_integration task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_sduct_integration ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy a generic transport model to act as the baseline bizjet
# We use eCRM-001 as the starting point since it provides a valid fuselage and wing
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/bizjet_baseline.vsp3"
chmod 644 "$MODELS_DIR/bizjet_baseline.vsp3"

# Write the S-Duct specification document to the Desktop
cat > /home/ga/Desktop/s_duct_spec.txt << 'SPEC_EOF'
============================================================
  TRI-JET VARIANT - CENTER S-DUCT GEOMETRY SPECIFICATION
  Document: BZJ-300-DUCT-001 Rev A
  Units: Metric (meters)
============================================================

General Requirements
--------------------
Component Type       : Duct
Component Name       : Center_S_Duct

Global Positioning (Location Tab)
---------------------------------
X Location           : 16.0 m  (Aft fuselage mount)
Z Location           : 1.0 m   (Above centerline)
Total Length         : 4.5 m

Cross-Section S-Curve Routing (XSec Tab)
----------------------------------------
To route the air from the high dorsal inlet down to the engine face,
apply the following local Z_Offsets to the duct's cross sections:

- Inlet (First Section) Z_Offset :  1.2 m
- Exit  (Last Section)  Z_Offset : -0.2 m

(Intermediate sections can be interpolated or adjusted as needed to
maintain a smooth curve, but the Inlet and Exit heights are strictly
controlled).

Save Deliverable
----------------
Save the integrated model as:
/home/ga/Documents/OpenVSP/bizjet_trijet.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/s_duct_spec.txt
chmod 644 /home/ga/Desktop/s_duct_spec.txt

# Remove any previous outputs
rm -f "$MODELS_DIR/bizjet_trijet.vsp3"
rm -f /tmp/openvsp_sduct_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp (Anti-Gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp recorded."

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/bizjet_baseline.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time — agent may need to launch it"
    take_screenshot /tmp/task_initial.png
fi

echo "=== Setup complete ==="