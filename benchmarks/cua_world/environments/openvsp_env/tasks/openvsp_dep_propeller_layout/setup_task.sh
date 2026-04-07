#!/bin/bash
# Setup script for openvsp_dep_propeller_layout task
# Prepares the baseline wing model, specification document, and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_dep_propeller_layout ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the specification document
cat > /home/ga/Desktop/dep_layout_spec.txt << 'SPEC_EOF'
============================================================
  DISTRIBUTED ELECTRIC PROPULSION (DEP) LAYOUT SPECIFICATION
  Document: DEP-2026-001  Rev A
  Units: Metric (meters)
============================================================

Baseline Model:
  /home/ga/Documents/OpenVSP/baseline_wing.vsp3

Task Instructions:
  Add three (3) electric propellers along the leading edge of 
  the right semi-span, enable XZ symmetry for all to populate 
  the left semi-span, and save the model as dep_wing.vsp3.

Propeller Geometry (Identical for all motors):
----------------------------------------------
  Component Type : Propeller
  Diameter       : 0.8 m
  Num Blades     : 3

Motor Locations (Right Semi-Span):
----------------------------------
  Motor 1:
    X (Chordwise) : -0.4 m  (Ahead of leading edge)
    Y (Spanwise)  :  1.5 m
    Z (Vertical)  :  0.0 m

  Motor 2:
    X (Chordwise) : -0.4 m
    Y (Spanwise)  :  3.0 m
    Z (Vertical)  :  0.0 m

  Motor 3:
    X (Chordwise) : -0.4 m
    Y (Spanwise)  :  4.5 m
    Z (Vertical)  :  0.0 m

Symmetry Requirements:
----------------------
  All propeller components MUST have XZ planar symmetry enabled
  so they reflect onto the left wing (Y = -1.5, -3.0, -4.5).

Final Deliverable:
------------------
  Save the completed model to:
  /home/ga/Documents/OpenVSP/dep_wing.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/dep_layout_spec.txt
chmod 644 /home/ga/Desktop/dep_layout_spec.txt

# Copy baseline model to working location (using eCRM wing as baseline)
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/baseline_wing.vsp3"
chmod 644 "$MODELS_DIR/baseline_wing.vsp3"

# Clean up any stale outputs
rm -f "$MODELS_DIR/dep_wing.vsp3"
rm -f /tmp/openvsp_dep_propeller_layout_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/baseline_wing.vsp3"
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