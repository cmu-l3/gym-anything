#!/bin/bash
# Setup script for openvsp_shuttle_stack_integration
# Creates the STS spec document, prepares the proxy orbiter model, and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_shuttle_stack_integration ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the STS stack specification document
cat > /home/ga/Desktop/sts_stack_spec.txt << 'SPEC_EOF'
============================================================
  STS ASCENT STACK GEOMETRY SPECIFICATION
  Document: NASA-STS-GEO-002
  Units: Metric (meters and degrees)
============================================================

Overview:
Add the External Tank (ET) and Solid Rocket Boosters (SRBs)
to the existing Orbiter proxy model. Do not delete the Orbiter.

1. EXTERNAL TANK (ET)
------------------------
Shape             : Axisymmetric Body (Fuselage, Stack, etc.)
Overall Length    : 47.0 m
Max Diameter      : 8.4 m
XForm Position    : 
   X_Rel_Location =  8.0 m
   Y_Rel_Location =  0.0 m
   Z_Rel_Location = -6.5 m  (Positioned beneath the orbiter)

2. SOLID ROCKET BOOSTERS (SRB)
--------------------------------
Shape             : Axisymmetric Body (Fuselage, Stack, etc.)
Overall Length    : 45.4 m
Max Diameter      : 3.7 m
XForm Position (Right Booster):
   X_Rel_Location =  8.5 m
   Y_Rel_Location =  6.2 m
   Z_Rel_Location = -6.5 m

Note: The STS launch stack requires TWO SRBs. You must either:
A) Use OpenVSP's Y-Symmetry feature on your single SRB component.
   OR
B) Manually create a second identical SRB component at Y = -6.2 m.

Save your final integrated model as:
/home/ga/Documents/OpenVSP/sts_ascent_stack.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/sts_stack_spec.txt
chmod 644 /home/ga/Desktop/sts_stack_spec.txt

# Copy proxy orbiter model (using eCRM-001 as a complex baseline proxy)
PROXY_PATH="$MODELS_DIR/shuttle_orbiter_proxy.vsp3"
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$PROXY_PATH" 2>/dev/null || true
chmod 644 "$PROXY_PATH"

# Clean up any stale output files
rm -f "$MODELS_DIR/sts_ascent_stack.vsp3"
rm -f /tmp/openvsp_shuttle_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the proxy orbiter model
launch_openvsp "$PROXY_PATH"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully with proxy orbiter."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="