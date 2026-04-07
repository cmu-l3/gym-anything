#!/bin/bash
# Setup script for openvsp_mass_cg_balance task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_mass_cg_balance ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Write specification document
cat > /home/ga/Desktop/mass_spec.txt << 'SPEC_EOF'
============================================================
  WEIGHT & BALANCE SPECIFICATION
  Model: eCRM-001 Wing-Body-Tail
  Units: Metric (meters, kg)
============================================================

For a preliminary mass properties analysis, apply the following 
material assumptions to ALL geometry components in the model:

Mass Type: Shell
Material Density: 2780 kg/m^3 (Aluminum 2024-T3)
Shell Thickness: 0.003 m (3 mm)

Instructions:
1. Open the Mass properties tab for each component.
2. Set the type to Shell and input the density and thickness above.
3. Run the Mass Properties analysis.
4. Export the output to:
   /home/ga/Documents/OpenVSP/exports/eCRM001_massprops.txt
5. Write a weight & balance report to:
   /home/ga/Desktop/mass_balance_report.txt
   
The report must include:
 - Total structural mass
 - CG coordinates (X, Y, Z)
 - Principal moments of inertia (Ixx, Iyy, Izz)
 - Symmetry check (Is Y_CG near zero?)
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/mass_spec.txt
chmod 644 /home/ga/Desktop/mass_spec.txt

# Kill any running OpenVSP
kill_openvsp

# Clear stale outputs
rm -f "$EXPORTS_DIR/eCRM001_massprops.txt"
find "$MODELS_DIR" -name "*MassProps*" -o -name "*massprops*" 2>/dev/null | xargs rm -f 2>/dev/null || true
rm -f /home/ga/Desktop/mass_balance_report.txt
rm -f /tmp/openvsp_mass_cg_balance_result.json

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the model
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

echo "=== Setup complete: eCRM-001 ready for mass properties analysis ==="