#!/bin/bash
# Setup script for openvsp_concept_wing task
# Creates wing spec document on Desktop, clears old outputs, launches blank OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_concept_wing ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the wing specification document
cat > /home/ga/Desktop/wing_spec.txt << 'SPEC_EOF'
============================================================
  REGIONAL TURBOPROP CONCEPT - WING GEOMETRY SPECIFICATION
  Document: WD-2400-WING-001  Rev A
  Issued by: Chief Designer
  Units: Metric (meters and degrees)
============================================================

Wing Planform Parameters
------------------------
Total Wing Span        :  12.40 m  (full span, tip to tip)
Root Chord             :   2.30 m
Tip Chord              :   1.20 m
Taper Ratio            :   0.52  (tip/root chord ratio)
Reference Wing Area    :  21.7 m^2 (approximate)

Wing Section Parameters (per half-span section)
-------------------------------------------------
Dihedral               :   5.0 degrees
Leading-Edge Sweep     :   3.0 degrees
Tip Washout (Twist)    :  -2.0 degrees  (negative = leading edge down at tip)

Airfoil Profile
---------------
Root section           :  NACA 23015
Tip section            :  NACA 23012

Component Requirements
----------------------
1. Wing component (WingGeom) — use parameters above
2. Fuselage component (Pod or FuselageGeom) — cylindrical fuselage,
   length ~9.0 m, max diameter ~1.6 m, positioned along X-axis

Notes
-----
- TotalSpan above is the FULL span (both sides). In OpenVSP, set Total Span
  to 12.40 m in the Plan tab (or half-span 6.20 m per side if using half-span mode).
- The dihedral and sweep apply to all wing sections.
- Save the completed model as:
  /home/ga/Documents/OpenVSP/concept_wing.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/wing_spec.txt
chmod 644 /home/ga/Desktop/wing_spec.txt

# Remove any previous concept model
rm -f "$MODELS_DIR/concept_wing.vsp3"
rm -f /tmp/openvsp_concept_wing_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp
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
    echo "WARNING: OpenVSP did not appear — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="
