#!/bin/bash
# Setup script for openvsp_biplane_configuration task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_biplane_configuration ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the biplane specification document
cat > /home/ga/Desktop/tiger_moth_spec.txt << 'SPEC_EOF'
============================================================
  VINTAGE AIRCRAFT RESTORATION: de Havilland DH.82 Tiger Moth
  Geometry Specification Sheet
  Units: Metric (meters and degrees)
============================================================

Overview:
The DH.82 is a classic biplane. This requires creating TWO separate 
wing components in OpenVSP, stacked vertically with the specified gap.

1. Fuselage
------------------------
Type                   : FuselageGeom or Stack
Length                 : 7.29 m
Max Diameter           : ~0.90 m

2. Upper Wing
------------------------
Type                   : WingGeom
Total Span             : 8.94 m
Constant Chord         : 1.32 m
Dihedral               : 4.0 degrees

3. Lower Wing
------------------------
Type                   : WingGeom
Total Span             : 8.08 m
Constant Chord         : 1.32 m
Dihedral               : 7.0 degrees

4. Biplane Stacking (XForm Positioning)
---------------------------------------
Inter-plane Gap (Z)    : 1.30 m  (Vertical distance between wings)
Forward Stagger (X)    : 0.61 m  (Upper wing leading edge is 0.61m AHEAD of lower wing)

*Note: In OpenVSP, you must change the Z-Location of at least one of the 
 wings in the XForm tab to create the 1.30m vertical gap.

5. Horizontal Tail
------------------------
Type                   : WingGeom
Total Span             : 2.93 m
Location               : Aft end of fuselage

Deliverable:
Save the completed model as:
/home/ga/Documents/OpenVSP/tiger_moth_biplane.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/tiger_moth_spec.txt
chmod 644 /home/ga/Desktop/tiger_moth_spec.txt

# Remove any previous model outputs
rm -f "$MODELS_DIR/tiger_moth_biplane.vsp3"
rm -f /tmp/openvsp_biplane_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch blank OpenVSP
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