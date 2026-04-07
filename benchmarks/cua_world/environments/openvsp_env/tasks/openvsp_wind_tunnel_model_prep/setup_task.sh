#!/bin/bash
# Setup script for openvsp_wind_tunnel_model_prep
set -e

echo "=== Setting up openvsp_wind_tunnel_model_prep ==="

# Source shared OpenVSP utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop

# Ensure proper permissions
chown -R ga:ga "$MODELS_DIR"
chown -R ga:ga /home/ga/Desktop

# Copy the master eCRM-001 model for the task
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wind_tunnel.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wind_tunnel.vsp3"

# Remove any stale outputs
rm -f "$EXPORTS_DIR/wt_model.vsp3"
rm -f "$EXPORTS_DIR/wt_model.stl"
rm -f /tmp/task_result.json

# Write the engineering specification document
cat > /home/ga/Desktop/wt_prep_spec.txt << 'SPEC_EOF'
WIND TUNNEL MODEL PREPARATION SPECIFICATION
===========================================
Target: 1:100 Scale Model of eCRM-001

1. GLOBAL SCALING
   - Scale the entire existing parametric model by a factor of 0.01.
   - Use the Model -> Scale Model tool, set the scale factor to 0.01, and apply to all components.

2. TEST HARDWARE ADDITION (STING)
   - Add a new "Pod" component to the model to act as the wind tunnel sting mount.
   - Rename the component to "Sting".
   - Set Sting Length to 0.3 m.
   - Set Sting Fineness Ratio to 15.0.

3. STING POSITIONING
   - Position the Sting at the rear of the aircraft using the XForm tab.
   - X Location: ~0.60 m (it should securely intersect the aft fuselage and extend backwards).
   - Y Location: 0.0 m.
   - Z Location: 0.0 m.

4. DELIVERABLES
   - Save the scaled model to: /home/ga/Documents/OpenVSP/exports/wt_model.vsp3
   - Export the combined assembly as a triangulated STL mesh to: /home/ga/Documents/OpenVSP/exports/wt_model.stl
SPEC_EOF

chown ga:ga /home/ga/Desktop/wt_prep_spec.txt
chmod 644 /home/ga/Desktop/wt_prep_spec.txt

# Kill any running OpenVSP instance to ensure a clean start
kill_openvsp

# Launch OpenVSP with the starting model
launch_openvsp "$MODELS_DIR/eCRM-001_wind_tunnel.vsp3"

# Wait for OpenVSP window and maximize it
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    # Take initial state screenshot for evidence
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually."
    take_screenshot /tmp/task_initial.png
fi

echo "=== Setup complete ==="