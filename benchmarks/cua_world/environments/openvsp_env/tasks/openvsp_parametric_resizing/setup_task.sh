#!/bin/bash
# Setup script for openvsp_parametric_resizing
# Copies baseline model and writes specification to Desktop

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_parametric_resizing ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# We use the realistic eCRM-001 model as the baseline, renaming it for the task context
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/conceptual_jet_baseline.vsp3"
chmod 644 "$MODELS_DIR/conceptual_jet_baseline.vsp3"

# Write the sizing specification document
cat > /home/ga/Desktop/sizing_update_spec.txt << 'SPEC_EOF'
URGENT: SIZING UPDATE FOR CONCEPTUAL JET
From: Chief Aerodynamicist
To: Design Group

Due to updated MTOW requirements, we need to resize the lifting surfaces on the conceptual_jet_baseline.vsp3 model.

TARGETS:
- Main Wing New Area: 420.0 m^2
- Horizontal Tail New Area: 105.0 m^2

STRICT CONSTRAINTS:
1. Do NOT change the Aspect Ratio of either surface. It must exactly match the baseline.
2. Do NOT change the Fuselage geometry.
3. Use the 'Plan' tab parametric drivers (Area and AR) to perform the resize. XForm scaling is forbidden.

Save the updated model as:
/home/ga/Documents/OpenVSP/conceptual_jet_resized.vsp3
SPEC_EOF

chown ga:ga /home/ga/Desktop/sizing_update_spec.txt
chmod 644 /home/ga/Desktop/sizing_update_spec.txt

# Remove any stale output file
rm -f "$MODELS_DIR/conceptual_jet_resized.vsp3"
rm -f /tmp/openvsp_parametric_resizing_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/conceptual_jet_baseline.vsp3"

# Wait for UI and capture initial state
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="