#!/bin/bash
# Setup script for openvsp_twin_fuselage_conversion task
# Prepares the baseline eCRM-001 model and creates the specification document

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_twin_fuselage_conversion ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the conversion specification document to the Desktop
cat > /home/ga/Desktop/launcher_spec.txt << 'SPEC_EOF'
HEAVY LIFT LAUNCHER CONVERSION SPECIFICATION
============================================
Baseline: eCRM-001 Wing-Body-Tail
Derivative: Twin-Fuselage Air Launch Platform

1. FUSELAGE & EMPENNAGE REPOSITIONING
   - Shift the Fuselage outboard: Y = +14.0 m
   - Shift the Vertical Tail outboard: Y = +14.0 m
   - Shift the Horizontal Tail outboard: Y = +14.0 m
   - Enable XZ Planar Symmetry on ALL THREE of these components to generate the port-side twins.
   (Hint: Use the XForm tab for Y Location, and Sym tab to enable XZ Planar Symmetry).

2. LIFTING SURFACE SCALING
   - Horizontal Tail Total Span: 25.0 m
   - Main Wing Total Span: 75.0 m
   - Main Wing Root Chord: 10.0 m

Note: The Main Wing should NOT be moved in Y. It remains centered at Y=0 to bridge the two fuselages.
Save the final geometry exactly to: /home/ga/Documents/OpenVSP/twin_fuselage_launcher.vsp3
SPEC_EOF

chown ga:ga /home/ga/Desktop/launcher_spec.txt
chmod 644 /home/ga/Desktop/launcher_spec.txt

# Copy clean eCRM-001 baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any stale output files
rm -f "$MODELS_DIR/twin_fuselage_launcher.vsp3"
rm -f /tmp/openvsp_twin_fuselage_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete: eCRM-001 loaded and ready for conversion ==="