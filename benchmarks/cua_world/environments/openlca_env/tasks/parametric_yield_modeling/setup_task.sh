#!/bin/bash
# Setup script for Parametric Yield Modeling task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Parametric Yield Modeling task ==="

# Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/yield_result_20.csv 2>/dev/null || true
rm -f /home/ga/LCA_Results/yield_result_10.csv 2>/dev/null || true

# Ensure Results directory exists
mkdir -p "/home/ga/LCA_Results"
chown ga:ga "/home/ga/LCA_Results"

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure USLCI zip is available for import
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        echo "Copied USLCI zip from /opt/openlca_data/"
    else
        echo "WARNING: USLCI database zip not found!"
    fi
    chown ga:ga "$USLCI_ZIP"
fi

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="