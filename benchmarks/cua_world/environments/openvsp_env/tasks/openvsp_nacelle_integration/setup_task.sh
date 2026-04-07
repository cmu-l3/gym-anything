#!/bin/bash
# Setup script for openvsp_nacelle_integration task
# Creates integration spec, copies base model, clears old outputs, launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_nacelle_integration ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the nacelle integration specification document
cat > /home/ga/Desktop/nacelle_integration_spec.txt << 'SPEC_EOF'
===============================================
ENGINE NACELLE INTEGRATION SPECIFICATION
===============================================
Program:  eCRM-001 Twin-Engine Transport Variant
Document: ENG-LAYOUT-001 Rev A
Author:   J. Martinez, Propulsion Integration
Date:     2024-11-15

-----------------------------------------------
1. NACELLE GEOMETRY
-----------------------------------------------
  Component Type:    Axisymmetric pod
                     (Use OpenVSP "Pod" component)
  Length:            3.0 m
  Maximum Diameter:  1.6 m

-----------------------------------------------
2. INSTALLATION POSITION (starboard engine)
-----------------------------------------------
  X (streamwise from model origin):  7.5 m
  Y (spanwise from centerline):      5.0 m
  Z (vertical, below wing plane):   -1.2 m

  Note: Position the STARBOARD (right) nacelle only.
  The port-side nacelle shall be generated via symmetry.

-----------------------------------------------
3. SYMMETRY
-----------------------------------------------
  Apply XZ planar symmetry on the nacelle component
  to automatically generate the port-side engine.

-----------------------------------------------
4. OUTPUT REQUIREMENTS
-----------------------------------------------
  Filename: eCRM-001_with_nacelles.vsp3
  Location: /home/ga/Documents/OpenVSP/
===============================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/nacelle_integration_spec.txt
chmod 644 /home/ga/Desktop/nacelle_integration_spec.txt

# Copy base eCRM-001 model to working location
if [ -f "/workspace/data/eCRM-001_wing_tail.vsp3" ]; then
    cp "/workspace/data/eCRM-001_wing_tail.vsp3" "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
elif [ -f "/opt/openvsp_models/eCRM-001_wing_tail.vsp3" ]; then
    cp "/opt/openvsp_models/eCRM-001_wing_tail.vsp3" "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
fi
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3" 2>/dev/null || true

# Remove any previous target file and result json
rm -f "$MODELS_DIR/eCRM-001_with_nacelles.vsp3"
rm -f /tmp/openvsp_nacelle_integration_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the base model loaded
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
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