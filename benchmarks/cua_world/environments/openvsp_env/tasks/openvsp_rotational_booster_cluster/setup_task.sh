#!/bin/bash
# Setup script for openvsp_rotational_booster_cluster task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_rotational_booster_cluster ==="

# Ensure working directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the engineering specification document
cat > /home/ga/Desktop/upgrade_spec.txt << 'SPEC_EOF'
LAUNCH VEHICLE CLUSTER SPECIFICATION
====================================
Configuration: Heavy-Lift Launch Vehicle
Target File: /home/ga/Documents/OpenVSP/heavy_launch_vehicle.vsp3

Please create a new OpenVSP model with two components:

1. CORE STAGE
   - Component Type: Fuselage or Pod
   - Component Name: Core
   - Length: 25.0 m

2. SOLID ROCKET BOOSTER (SRB)
   - Component Type: Fuselage or Pod
   - Component Name: SRB
   - Length: 15.0 m
   
3. SRB POSITIONING (XForm Tab)
   - Translate X: 10.0 m (shift aft along the core)
   - Translate Y: 2.2 m (offset radially from the centerline)
   - Translate Z: 0.0 m
   
4. SRB SYMMETRY (Sym Tab)
   - Planar Symmetry (Y-Symmetry): OFF / Disabled
   - Rotational Symmetry: ON / Enabled
   - Number of Rotational Instances: 4

Note: Save the final clustered geometry to the Target File path above.
SPEC_EOF

chown ga:ga /home/ga/Desktop/upgrade_spec.txt
chmod 644 /home/ga/Desktop/upgrade_spec.txt

# Remove any previous artifacts
rm -f "$MODELS_DIR/heavy_launch_vehicle.vsp3"
rm -f /tmp/openvsp_rotational_booster_result.json

# Kill any running OpenVSP instances
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch blank OpenVSP session
launch_openvsp
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