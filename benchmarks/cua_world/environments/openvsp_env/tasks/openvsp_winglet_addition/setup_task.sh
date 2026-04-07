#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_winglet_addition task ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy base model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Write the winglet specification document
cat > /home/ga/Desktop/winglet_spec.txt << 'EOF'
WINGLET GEOMETRY SPECIFICATION
==============================
Project: eCRM-001 Winglet Retrofit Study
Author:  Aerodynamics Group, Rev B
Date:    2024-11-15

Winglet Type:        Blended (single-element, no fence)
Cant Angle:          72° from horizontal
Height (span):       0.85 m
Taper Ratio:         0.30 (tip chord / root chord of winglet section)
LE Sweep:            35°
Twist (tip washout): -2.0°
Airfoil:             Same as wing tip (do not change)
Transition:          Blended (smooth dihedral increase from last wing section)

NOTES:
- Winglet root chord should match or approximate the existing wing tip chord
- The cant angle (72°) maps to the "Dihedral" parameter in OpenVSP
- The wing is symmetric; changes apply to both tips automatically
- Save as: eCRM001_winglet.vsp3
EOF

chown ga:ga /home/ga/Desktop/winglet_spec.txt
chmod 644 /home/ga/Desktop/winglet_spec.txt

# Clean up any stale outputs
rm -f "$MODELS_DIR/eCRM001_winglet.vsp3"
rm -f /tmp/openvsp_winglet_result.json

# Kill any running instances of OpenVSP
kill_openvsp

# Record task start timestamp for anti-gaming checks
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