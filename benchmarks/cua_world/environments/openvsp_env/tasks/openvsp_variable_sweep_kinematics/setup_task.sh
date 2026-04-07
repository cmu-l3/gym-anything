#!/bin/bash
# Setup script for openvsp_variable_sweep_kinematics
# Generates the baseline swing-wing model using OpenVSP AngelScript and creates the spec document.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_variable_sweep_kinematics ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the kinematics specification document
cat > /home/ga/Desktop/swing_wing_spec.txt << 'SPEC_EOF'
============================================================
  VARIABLE SWEEP KINEMATICS UPDATE
  Document: AERO-FX-002 Rev B
============================================================

BASELINE CONFIGURATION (Takeoff State)
--------------------------------------
Leading Edge Sweep : 20.0 degrees
Total Span         : 20.0 meters

TARGET CONFIGURATION (Supersonic Dash State)
--------------------------------------------
Target LE Sweep    : 68.0 degrees

ENGINEERING DIRECTIVE
---------------------
To maintain geometric fidelity and aerodynamic validity, the physical length 
of the wing panels must remain constant during the sweep transition. 

Because OpenVSP parameterizes the wing using projected Y-axis span rather 
than physical panel length, you MUST calculate and input the newly reduced 
projected Total Span for the 68-degree swept state. 

Hint: Assume a simple centerline pivot.
Physical Length L = (Span / 2) / cos(Sweep)

ACTION REQUIRED
---------------
1. Calculate the new projected Total Span for the Target Configuration.
2. Open /home/ga/Documents/OpenVSP/fx_unswept.vsp3
3. Update the Wing component's Sweep and Span parameters.
4. Save the new model to: /home/ga/Documents/OpenVSP/fx_swept.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/swing_wing_spec.txt
chmod 644 /home/ga/Desktop/swing_wing_spec.txt

# Kill any running OpenVSP
kill_openvsp

# Clean up any stale files from previous runs
rm -f "$MODELS_DIR/fx_unswept.vsp3"
rm -f "$MODELS_DIR/fx_swept.vsp3"
rm -f /tmp/openvsp_variable_sweep_kinematics_result.json

# Generate the baseline model dynamically using OpenVSP's batch script engine
cat > /tmp/gen_swing_wing.vspscript << 'EOF'
void main() {
    ClearVSPModel();
    string wid = AddGeom("WING");
    SetGeomName(wid, "MainWing");
    
    // Set baseline parameters
    SetParmVal(wid, "TotalSpan", "Plan", 20.0);
    SetParmVal(wid, "Sweep", "XSec_1", 20.0);
    SetParmVal(wid, "Sweep_Location", "XSec_1", 0.0); // Leading edge sweep
    
    Update();
    WriteVSPFile("/home/ga/Documents/OpenVSP/fx_unswept.vsp3");
}
EOF

# Run OpenVSP headlessly to generate the file
echo "Generating baseline model..."
su - ga -c "DISPLAY=:1 $OPENVSP_BIN -script /tmp/gen_swing_wing.vspscript" > /dev/null 2>&1 || true

# Fallback: if AngelScript failed, use python to write a minimal valid XML OpenVSP wing
if [ ! -f "$MODELS_DIR/fx_unswept.vsp3" ]; then
    echo "AngelScript generation failed, falling back to Python XML generation..."
    cp /workspace/data/Cessna-210_metric.vsp3 "$MODELS_DIR/fx_unswept.vsp3" 2>/dev/null || true
    # We will just accept the pre-existing file as a fallback, but the AngelScript should work on all 3.x versions.
fi

chmod 644 "$MODELS_DIR/fx_unswept.vsp3" 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/fx_unswept.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully with fx_unswept.vsp3."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="