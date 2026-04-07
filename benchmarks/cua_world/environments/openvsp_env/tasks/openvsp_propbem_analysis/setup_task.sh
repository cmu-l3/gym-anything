#!/bin/bash
# Setup script for openvsp_propbem_analysis task
# Uses VSPScript to dynamically generate a physically realistic baseline propeller

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_propbem_analysis ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop

# Clear any stale task files
rm -f "$EXPORTS_DIR/3blade_prop.vsp3"
rm -f "$EXPORTS_DIR"/*PropBEM*.csv
rm -f "$MODELS_DIR"/*PropBEM*.csv
rm -f /home/ga/Desktop/prop_report.txt
rm -f /tmp/openvsp_propbem_result.json

# Generate the baseline 2-blade propeller using OpenVSP's batch script engine
# This ensures we have a valid, physically realistic parametric starting point
cat > /tmp/make_prop.vspscript << 'EOF'
string id = AddGeom("PROP");
// Set realistic baseline parameters for a UAV propeller
SetParmVal(id, "NumBlades", "Design", 2.0);
SetParmVal(id, "Diameter", "Design", 1.5);
SetParmVal(id, "DesignCL", "Design", 0.5);
SetParmVal(id, "CruiseSpeed", "Design", 15.0);
SetParmVal(id, "RPM", "Design", 4000.0);
Update();
WriteVSPFile("/home/ga/Documents/OpenVSP/baseline_prop.vsp3");
EOF

# Run VSPScript in headless batch mode
$OPENVSP_BIN -batch /tmp/make_prop.vspscript > /tmp/vsp_batch.log 2>&1

# Create the engineering request document
cat > /home/ga/Desktop/prop_request.txt << 'EOF'
URGENT: Propeller Modification Request
From: Acoustics & Performance Team

We need to evaluate a 3-blade variant of our 1.5m baseline propeller to reduce tip speeds.

ACTION REQUIRED:
1. Open ~/Documents/OpenVSP/baseline_prop.vsp3
2. Change the Propeller blade count from 2 to 3.
3. Save the new model to ~/Documents/OpenVSP/exports/3blade_prop.vsp3
4. Run a Blade Element Momentum (PropBEM) analysis:
   - Variable: Advance Ratio (J)
   - Range: Start J = 0.1, End J = 1.5
   - Points: 15
5. Review the exported PropBEM CSV file to find the peak Efficiency.
6. Write a summary to ~/Desktop/prop_report.txt stating the maximum efficiency and the J value at which it occurs.
EOF

chown -R ga:ga /home/ga/Desktop
chown -R ga:ga "$MODELS_DIR"

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/baseline_prop.vsp3"

# Wait for application window and maximize
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="