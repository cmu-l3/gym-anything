#!/bin/bash
# Setup script for Update LCIA Factors AR6 task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Update LCIA Factors AR6 task ==="

# Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/ar6_update_log.txt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure LCA_Imports exists and has the necessary files
mkdir -p /home/ga/LCA_Imports
chown ga:ga /home/ga/LCA_Imports

# Check for LCIA methods zip (Source for TRACI 2.1)
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
        chown ga:ga "$LCIA_ZIP"
        echo "Copied LCIA methods zip to user imports"
    else
        echo "WARNING: LCIA methods zip not found"
    fi
fi

# Ensure USLCI database zip is available (as a base DB is needed to hold methods)
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

# Ensure output directory exists
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Configure window
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="