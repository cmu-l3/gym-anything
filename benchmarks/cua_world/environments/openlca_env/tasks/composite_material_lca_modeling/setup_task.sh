#!/bin/bash
# Setup script for Composite Material LCA Modeling task
set -e

echo "=== Setting up Composite Material LCA task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous runs
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/biobrick_impact.csv 2>/dev/null || true

# 2. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Ensure Import/Export directories exist
mkdir -p /home/ga/LCA_Imports
mkdir -p /home/ga/LCA_Results
chown -R ga:ga /home/ga/LCA_Imports /home/ga/LCA_Results

# 4. Ensure USLCI and LCIA data is available for import
# (The agent must import them, but the files must be ready)
if [ ! -f "/home/ga/LCA_Imports/uslci_database.zip" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip /home/ga/LCA_Imports/
        chown ga:ga /home/ga/LCA_Imports/uslci_database.zip
        echo "USLCI database staged."
    else
        echo "WARNING: USLCI database source not found!"
    fi
fi

if [ ! -f "/home/ga/LCA_Imports/lcia_methods.zip" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp /opt/openlca_data/lcia_methods.zip /home/ga/LCA_Imports/
        chown ga:ga /home/ga/LCA_Imports/lcia_methods.zip
        echo "LCIA methods staged."
    else
        echo "WARNING: LCIA methods source not found!"
    fi
fi

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize window and focus
sleep 5
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "OpenLCA window maximized."
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="