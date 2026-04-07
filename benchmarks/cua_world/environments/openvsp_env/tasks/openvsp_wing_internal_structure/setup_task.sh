#!/bin/bash
# Setup script for openvsp_wing_internal_structure

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_wing_internal_structure ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Write the structural specification document
cat > /home/ga/Desktop/structural_layout_spec.txt << 'SPEC_EOF'
===============================================
eCRM-001 PRELIMINARY WING BOX SPECIFICATION
===============================================
Target Component: Main Wing ("Wing" or "NormalWing")

1. FRONT SPAR
   - Position: 20% chord (0.20 fractional chord / CFrac)

2. REAR SPAR
   - Position: 70% chord (0.70 fractional chord / CFrac)

3. RIBS
   - Configuration: 1 Rib Set
   - Count: 24 ribs evenly spaced across the semi-span

Note: Do not add structures to the horizontal or vertical tails.
Save the modified model to: /home/ga/Documents/OpenVSP/eCRM-001_structural.vsp3
===============================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/structural_layout_spec.txt
chmod 644 /home/ga/Desktop/structural_layout_spec.txt

# Clear stale outputs
rm -f "$MODELS_DIR/eCRM-001_structural.vsp3"
rm -f /tmp/openvsp_wing_internal_structure_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the model
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