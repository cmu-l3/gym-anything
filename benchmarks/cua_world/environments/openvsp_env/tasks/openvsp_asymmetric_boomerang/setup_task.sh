#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_asymmetric_boomerang ==="

mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/rutan_boomerang_spec.txt << 'EOF'
============================================================
  RUTAN MODEL 202 BOOMERANG - GEOMETRY SPECIFICATION
  Units: Metric (meters)
============================================================

Overview:
The Boomerang is a highly asymmetric twin-engine aircraft. The main fuselage houses the cockpit, while a smaller left boom houses the second engine.

1. Main Fuselage (Component Name: "MainFuselage")
-------------------------------------------------
  Type             : Fuselage or Pod
  Length           : 8.80 m
  Position         : Origin (X=0, Y=0, Z=0)
  Symmetry         : XZ Symmetry ON (default) is acceptable since it's on centerline

2. Left Boom (Component Name: "LeftBoom")
-------------------------------------------------
  Type             : Fuselage or Pod
  Length           : 7.50 m
  X-Location       : 1.50 m (shifted aft)
  Y-Location       : -2.80 m (shifted LEFT)
  Symmetry         : **MUST DISABLE XZ SYMMETRY** (do not mirror to right side)

3. Main Wing (Component Name: "MainWing")
-------------------------------------------------
  Type             : Wing
  Symmetry         : **MUST DISABLE XZ SYMMETRY**
  
  Section spans (use the Left/Right section editor in the Section tab):
  - RIGHT SIDE (1 section):
      Span: 4.70 m
      
  - LEFT SIDE (2 sections):
      Inner Section (connecting main fuselage to left boom): 
          Span: 2.80 m
      Outer Section (outboard of left boom): 
          Span: 3.70 m

Notes:
- Save completed model to: /home/ga/Documents/OpenVSP/asymmetric_concept.vsp3
============================================================
EOF

chown ga:ga /home/ga/Desktop/rutan_boomerang_spec.txt
chmod 644 /home/ga/Desktop/rutan_boomerang_spec.txt

rm -f "$MODELS_DIR/asymmetric_concept.vsp3"
rm -f /tmp/openvsp_asymmetric_result.json

kill_openvsp

date +%s > /tmp/task_start_timestamp

launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="