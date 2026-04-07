#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Agricultural Water Balance task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LCA_Imports directory exists and has the database zip
mkdir -p /home/ga/LCA_Imports
chown ga:ga /home/ga/LCA_Imports

if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip /home/ga/LCA_Imports/uslci_database.zip
    chown ga:ga /home/ga/LCA_Imports/uslci_database.zip
    echo "USLCI database zip prepared."
else
    echo "WARNING: USLCI database zip not found in /opt/openlca_data/"
fi

# Ensure Results directory exists
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# Clean up any previous results
rm -f /home/ga/LCA_Results/wheat_water_balance.csv

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="