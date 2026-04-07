#!/bin/bash
# Setup script for openvsp_uuv_hydrodynamic_model task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_uuv_hydrodynamic_model ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the UUV specification document
cat > /home/ga/Desktop/uuv_spec.txt << 'SPEC_EOF'
============================================================
  DEEPMAPPER UUV - GEOMETRY SPECIFICATION
  Document: MAR-2026-UUV-01
  Units: Metric (meters)
============================================================

HULL (Main Body)
----------------
Type                   : Axisymmetric body (Fuselage, Pod, or Stack)
Total Length           : 3.50 m
Max Diameter           : 0.35 m
Nose Shape             : Rounded/Elliptical
Tail Shape             : Tapered (Boat-tail)

TAIL FINS (Control Surfaces)
----------------------------
Type                   : Cruciform (4 fins, arranged radially)
                         Hint: Use a Wing component with radial symmetry or 2 crossed wings
Exposed Span           : 0.15 m (per fin)
Root Chord             : 0.20 m
Tip Chord              : 0.10 m
Position               : Mounted on the tapered aft section of the hull

PROPULSOR
---------
Type                   : Propeller
Blades                 : 3
Diameter               : 0.25 m
Position (X-Origin)    : ~3.50 m (extreme aft of the vehicle)

ANALYSIS REQUIREMENT
--------------------
Run OpenVSP's CompGeom tool (Analysis > CompGeom) to calculate the displacement.
Record the 'Theoretical Volume' and 'Wetted Area' in your final report.

DELIVERABLES
------------
1. Model File: ~/Documents/OpenVSP/uuv_model.vsp3
2. Report File: ~/Desktop/uuv_hydro_report.txt (Must contain Volume and Wetted Area)
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/uuv_spec.txt
chmod 644 /home/ga/Desktop/uuv_spec.txt

# Remove any previous outputs
rm -f "$MODELS_DIR/uuv_model.vsp3"
rm -f /home/ga/Desktop/uuv_hydro_report.txt
rm -f /tmp/openvsp_uuv_hydro_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (for anti-gaming)
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