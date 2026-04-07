#!/bin/bash
# Setup script for openvsp_uam_quadrotor_layout task
# Creates quadrotor spec document on Desktop, clears old outputs, launches blank OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_uam_quadrotor_layout ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the quadrotor specification document
cat > /home/ga/Desktop/nasa_uam_quadrotor_spec.txt << 'SPEC_EOF'
============================================================
  NASA UAM QUADROTOR CONCEPT - GEOMETRY SPECIFICATION
  Reference: NASA 6-Passenger Quadrotor (Silva et al., 2018)
  Units: Metric (meters and degrees)
============================================================

Fuselage Parameters
-------------------
Type                   : Pod or FuselageGeom
Total Length           : ~8.0 m
Position               : Centered at Origin (0,0,0)

Rotor Parameters (Must explicitly instantiate 4 separate rotors)
--------------------------------------------------------------
Type                   : PropellerGeom
Diameter               : 6.52 m
Orientation (Pitch)    : 90 deg or -90 deg (Y-Axis Rotation)
                         *Thrust axis must point vertically*

Rotor Hub Locations (Absolute X, Y, Z)
--------------------------------------
Rotor 1 (Front Right)  : X =  3.26 m, Y =  3.26 m, Z = 1.50 m
Rotor 2 (Front Left)   : X =  3.26 m, Y = -3.26 m, Z = 1.50 m
Rotor 3 (Rear Right)   : X = -3.26 m, Y =  3.26 m, Z = 1.50 m
Rotor 4 (Rear Left)    : X = -3.26 m, Y = -3.26 m, Z = 1.50 m

Notes
-----
- Do NOT use XZ/XY symmetry checkboxes to mirror a single rotor. Acoustic analysis requires 4 distinct wake entities.
- Save the completed model as:
  /home/ga/Documents/OpenVSP/nasa_quadrotor.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/nasa_uam_quadrotor_spec.txt
chmod 644 /home/ga/Desktop/nasa_uam_quadrotor_spec.txt

# Remove any previous model outputs
rm -f "$MODELS_DIR/nasa_quadrotor.vsp3"
rm -f /tmp/openvsp_uam_quadrotor_layout_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch blank OpenVSP (no file argument)
launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="