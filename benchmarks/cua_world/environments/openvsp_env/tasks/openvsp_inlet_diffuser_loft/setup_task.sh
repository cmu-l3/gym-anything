#!/bin/bash
# Setup script for openvsp_inlet_diffuser_loft task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_inlet_diffuser_loft ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the geometric specification document
cat > /home/ga/Desktop/inlet_spec.txt << 'SPEC_EOF'
============================================================
  RAMJET INLET DIFFUSER - GEOMETRY SPECIFICATION
  Document: RJ-900-INLET-001  Rev A
  Units: Metric (meters)
============================================================

Overview:
Create a lofted internal flow path that transitions from a 
rectangular supersonic capture area to a circular subsonic 
engine compressor face.

Component Requirements
----------------------
Type                  : Duct (or Fuselage inverted)
Component Name        : Ramjet_Inlet
Overall Length        : 4.50 m

Cross-Section 0 (Front Capture Face)
------------------------------------
Shape                 : Rectangle
Width                 : 0.80 m
Height                : 0.40 m

Cross-Section N (Rear Compressor Face)
--------------------------------------
Shape                 : Circle
Diameter              : 0.70 m (Width=0.70, Height=0.70)

Deliverables:
-------------
1. Save the model to: ~/Documents/OpenVSP/ramjet_inlet.vsp3
2. Calculate the cross-sectional Area Ratio (Rear Area / Front Area).
   (Note: Area of Rectangle = W x H, Area of Circle = pi * r^2)
3. Write a short report to ~/Desktop/diffuser_report.txt containing 
   the front area, rear area, and calculated area ratio.
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/inlet_spec.txt
chmod 644 /home/ga/Desktop/inlet_spec.txt

# Clean up any previous attempts
rm -f "$MODELS_DIR/ramjet_inlet.vsp3"
rm -f /home/ga/Desktop/diffuser_report.txt
rm -f /tmp/openvsp_inlet_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch blank OpenVSP (no file argument)
launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="