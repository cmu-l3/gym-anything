#!/bin/bash
# Setup script for openvsp_landing_gear_layout task
# Prepares the spec document, copies the base model, and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_landing_gear_layout ==="

# Ensure working directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Generate the specification document
cat > /home/ga/Desktop/gear_spec.txt << 'SPEC_EOF'
LANDING GEAR PLACEMENT SPECIFICATION
====================================
Aircraft: eCRM-001 Transport

Geometry Parameters:
- Ground Line (Z_ground) : -3.0 m
- Max Aft CG (X_aft_cg)  : 35.0 m
- Fwd CG (X_fwd_cg)      : 32.5 m
- CG Height (Z_cg)       : 1.0 m

Design Requirements:
1. Tip-back Angle: Exactly 15.0 degrees at Max Aft CG.
   Definition: tan(theta) = (X_main - X_aft_cg) / (Z_cg - Z_ground)
   [Note: Z_cg and Z_ground are given in global coordinates. Use absolute vertical distance.]

2. Nose Gear Static Load: Exactly 10.0% of total weight at Fwd CG.
   Definition: f_nose = (X_main - X_fwd_cg) / (X_main - X_nose)
   (Where f_nose = 0.10)
SPEC_EOF

chown ga:ga /home/ga/Desktop/gear_spec.txt
chmod 644 /home/ga/Desktop/gear_spec.txt

# Copy clean base model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Kill any running OpenVSP
kill_openvsp

# Clean up stale files
rm -f "$MODELS_DIR/eCRM001_geared.vsp3"
rm -f /home/ga/Desktop/gear_report.txt
rm -f /tmp/openvsp_landing_gear_layout_result.json

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the base model
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