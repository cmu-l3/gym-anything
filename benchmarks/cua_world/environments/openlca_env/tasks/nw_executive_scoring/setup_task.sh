#!/bin/bash
# Setup script for Normalization and Weighting Executive Reporting task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up NW Executive Scoring task ==="

# Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/normalized_weighted_results.csv 2>/dev/null || true

# Ensure import directories exist
mkdir -p /home/ga/LCA_Imports
mkdir -p /home/ga/LCA_Results
chown -R ga:ga /home/ga/LCA_Imports
chown -R ga:ga /home/ga/LCA_Results

# Record task start timestamp (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Ensure USLCI zip is available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
    echo "Copied USLCI zip to imports"
fi

# Ensure LCIA methods zip is available
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
    echo "Copied LCIA methods zip to imports"
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

echo "=== Setup Complete ==="