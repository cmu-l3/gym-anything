#!/bin/bash
# Setup script for Characterize Novel GHG Flow task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Characterize Novel GHG Flow task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/hfc_impact_result.csv 2>/dev/null || true

# 2. Prepare Results Directory
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure Import Data is Available
# USLCI Database
if [ ! -f "/home/ga/LCA_Imports/uslci_database.zip" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "/home/ga/LCA_Imports/uslci_database.zip"
        chown ga:ga "/home/ga/LCA_Imports/uslci_database.zip"
        echo "Restored USLCI database zip"
    else
        echo "WARNING: USLCI database zip not found in /opt/openlca_data"
    fi
fi

# LCIA Methods
if [ ! -f "/home/ga/LCA_Imports/lcia_methods.zip" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp /opt/openlca_data/lcia_methods.zip "/home/ga/LCA_Imports/lcia_methods.zip"
        chown ga:ga "/home/ga/LCA_Imports/lcia_methods.zip"
        echo "Restored LCIA methods zip"
    else
        echo "WARNING: LCIA methods zip not found in /opt/openlca_data"
    fi
fi

# 4. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize Window
sleep 5
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "Window maximized"
fi

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Setup Complete ==="