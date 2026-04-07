#!/bin/bash
# Setup script for openvsp_joined_wing_config task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_joined_wing_config ==="

# Ensure working directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Provide a baseline model (using the eCRM model as a stand-in for the "forward wing + fuselage" base)
# If eCRM exists in the workspace data, copy it. Otherwise, use Cessna. 
if [ -f "/workspace/data/eCRM-001_wing_tail.vsp3" ]; then
    cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/box_wing_base.vsp3"
elif [ -f "/workspace/data/Cessna-210_metric.vsp3" ]; then
    cp /workspace/data/Cessna-210_metric.vsp3 "$MODELS_DIR/box_wing_base.vsp3"
else
    # Fallback to copy anything from openvsp_models if missing
    cp /opt/openvsp_models/*.vsp3 "$MODELS_DIR/box_wing_base.vsp3" 2>/dev/null || true
fi

chmod 644 "$MODELS_DIR/box_wing_base.vsp3"

# Write the joining wing specification document
cat > /home/ga/Desktop/joined_wing_spec.txt << 'SPEC_EOF'
==================================================
  BOX WING / PRANDTLPLANE GEOMETRY SPECIFICATION
==================================================

BASELINE GEOMETRY (Already in model)
  Forward Wing Area: 36.0 m^2

AFT WING SPECIFICATION (To be created)
  Component Type:  WingGeom
  Name:            Aft_Wing
  Position (X):    14.0 m (aft on fuselage)
  Position (Z):    2.5 m (top of fuselage)
  Total Span:      18.0 m
  Root Chord:      1.5 m
  Tip Chord:       0.5 m
  Sweep (LE):     -28.0 deg (Forward sweep)
  Dihedral:       -12.0 deg (Anhedral, angling down)

AERODYNAMIC REFERENCE QUANTITIES
  The default OpenVSP Reference Area only accounts for the main wing.
  For a Box Wing, the Reference Area MUST be the sum of both wings.
  
  Action Required: 
  1. Calculate the Aft Wing area: Span * Average Chord
     Area = 18.0 * ((1.5 + 0.5) / 2) = 18.0 m^2
  2. Calculate Total Reference Area: 36.0 + 18.0 = 54.0 m^2
  3. Navigate to Model -> Reference... in the top menu.
  4. Uncheck 'Extract from Wing' (if checked) and manually set the
     Reference Area to 54.0 m^2.
==================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/joined_wing_spec.txt
chmod 644 /home/ga/Desktop/joined_wing_spec.txt

# Remove any previous completion files
rm -f "$MODELS_DIR/box_wing_complete.vsp3"
rm -f /tmp/openvsp_joined_wing_config_result.json

# Kill any running OpenVSP instance to start clean
kill_openvsp

# Record task start timestamp for anti-gaming (ensuring file created during task)
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/box_wing_base.vsp3"

# Wait for UI to initialize and maximize it
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully with baseline model."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="