#!/bin/bash
# Setup script for openvsp_floatplane_conversion task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_floatplane_conversion ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure models directory exists
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the float specification document
cat > /home/ga/Desktop/float_spec.txt << 'SPEC_EOF'
============================================================
  AMPHIBIOUS FLOAT CONVERSION - GEOMETRY SPECIFICATION
  Project: Seaplane Variant Study
  Units: Metric (meters)
============================================================

Float Dimension Parameters
--------------------------
Component Type         :  Fuselage or Pod
Total Length           :  5.80 m
Max Width/Diameter     :  ~0.70 m
Max Height             :  ~0.70 m

Float Position (XForm - relative to global origin)
--------------------------------------------------
X Location             :   0.80 m  (aft of nose)
Y Location             :   1.40 m  (offset from centerline)
Z Location             :  -1.80 m  (below the fuselage)

Symmetry Requirement
--------------------
The aircraft requires TWIN floats.
You must enable Planar Symmetry (XZ plane) on the float
component so that OpenVSP mirrors it to the other side
(Y = -1.40 m), OR manually duplicate it.

Deliverable
-----------
Save the completed assembly to:
/home/ga/Documents/OpenVSP/floatplane_variant.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/float_spec.txt
chmod 644 /home/ga/Desktop/float_spec.txt

# Copy the baseline utility aircraft (Cessna-210) to working location
cp /workspace/data/Cessna-210_metric.vsp3 "$MODELS_DIR/utility_aircraft.vsp3"
chmod 644 "$MODELS_DIR/utility_aircraft.vsp3"

# Remove any previous completion file
rm -f "$MODELS_DIR/floatplane_variant.vsp3"
rm -f /tmp/openvsp_floatplane_result.json

# Kill any running OpenVSP
kill_openvsp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/utility_aircraft.vsp3"
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