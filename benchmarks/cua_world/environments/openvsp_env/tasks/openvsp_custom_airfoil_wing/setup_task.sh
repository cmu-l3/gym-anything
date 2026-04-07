#!/bin/bash
# Setup script for openvsp_custom_airfoil_wing task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_custom_airfoil_wing ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# 1. Create the blade specification document
cat > /home/ga/Desktop/blade_spec.txt << 'SPEC_EOF'
WIND TURBINE BLADE SPECIFICATION
--------------------------------
Component: Main Blade (Wing)
Units: Meters and Degrees

Planform:
- Total Span    : 5.00 m
- Root Chord    : 0.80 m
- Tip Chord     : 0.30 m
- Sweep         : 0.0 deg
- Dihedral      : 0.0 deg

Cross-Sections:
- Root Airfoil  : S809  (Load from s809.dat)
- Tip Airfoil   : S805A (Load from s805a.dat)

Instructions:
Add a Wing component. In the XSec tab, change the airfoil type from 
the default (e.g. NACA 4-series) to "AF File" or "Airfoil File", 
then browse to the provided .dat files on the Desktop.
Save the final model as: ~/Documents/OpenVSP/turbine_blade.vsp3
SPEC_EOF

# 2. Create the S809 airfoil .dat file (Selig format, subset of real points)
cat > /home/ga/Desktop/s809.dat << 'S809_EOF'
S809 (21% thick NREL wind turbine airfoil)
 1.000000  0.000000
 0.954500  0.013500
 0.852100  0.039600
 0.704200  0.071600
 0.505200  0.098800
 0.395200  0.101300
 0.298200  0.094200
 0.150400  0.065800
 0.053600  0.031500
 0.008400  0.008400
 0.000000  0.000000
 0.012500 -0.012700
 0.063200 -0.033400
 0.158500 -0.061900
 0.306000 -0.091500
 0.404800 -0.106500
 0.503400 -0.108500
 0.702400 -0.081100
 0.850900 -0.046100
 0.954000 -0.015800
 1.000000  0.000000
S809_EOF

# 3. Create the S805A airfoil .dat file (Selig format, subset of real points)
cat > /home/ga/Desktop/s805a.dat << 'S805A_EOF'
S805A (13% thick NREL wind turbine airfoil)
 1.000000  0.000000
 0.950200  0.006800
 0.803700  0.024500
 0.605300  0.046300
 0.404700  0.063300
 0.252000  0.064500
 0.106600  0.046400
 0.027900  0.018900
 0.000000  0.000000
 0.017500 -0.017100
 0.096300 -0.038500
 0.245800 -0.055800
 0.400500 -0.060100
 0.602600 -0.046800
 0.802800 -0.021500
 0.950000 -0.005500
 1.000000  0.000000
S805A_EOF

# Set proper ownership and permissions
chown ga:ga /home/ga/Desktop/blade_spec.txt /home/ga/Desktop/s809.dat /home/ga/Desktop/s805a.dat
chmod 644 /home/ga/Desktop/blade_spec.txt /home/ga/Desktop/s809.dat /home/ga/Desktop/s805a.dat

# Remove any previous model
rm -f "$MODELS_DIR/turbine_blade.vsp3"
rm -f /tmp/openvsp_custom_airfoil_wing_result.json

# Kill any running OpenVSP
kill_openvsp

# Launch OpenVSP (blank session)
launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_initial_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time"
    take_screenshot /tmp/task_initial_screenshot.png
fi

echo "=== Setup complete ==="