#!/bin/bash
# Setup script for openvsp_high_wing_conversion task
# Prepares the baseline eCRM-001 model and specification document

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_high_wing_conversion ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the specification document
cat > /home/ga/Desktop/highwing_spec.txt << 'SPEC_EOF'
HIGH-WING CONFIGURATION TRADE STUDY
====================================
Baseline: eCRM-001 Low-Wing Transport
Target:   eCRM-001 High-Wing Variant

Modification Instructions:
--------------------------
1. WING VERTICAL POSITION
   Move the Wing component Z-Location upward so the wing root
   sits at the top of the fuselage crown.
   Target Z-Location: +2.0 m to +3.5 m above fuselage centerline
   (Fuselage max radius is approximately 2.0 m)

2. WING DIHEDRAL ADJUSTMENT
   High-wing aircraft benefit from pendulum stability and require
   less geometric dihedral than low-wing designs.
   Target outboard section dihedral: -3.0 to +2.0 degrees
   (Baseline has ~5 degrees dihedral which is excessive for high-wing)

3. SAVE AS
   Save the modified model as:
   /home/ga/Documents/OpenVSP/eCRM001_highwing.vsp3

Do NOT modify span, chord, sweep, or airfoil parameters.
Only reposition vertically (Design/XForm tab) and adjust dihedral (Plan/Section tab).
SPEC_EOF

chown ga:ga /home/ga/Desktop/highwing_spec.txt
chmod 644 /home/ga/Desktop/highwing_spec.txt

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any previous target file
rm -f "$MODELS_DIR/eCRM001_highwing.vsp3"
rm -f /tmp/high_wing_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
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