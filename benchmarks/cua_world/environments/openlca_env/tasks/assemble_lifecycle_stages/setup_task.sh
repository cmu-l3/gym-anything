#!/bin/bash
set -e

echo "=== Setting up Assemble Life Cycle Stages task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Environment
# Ensure directories exist
mkdir -p /home/ga/LCA_Results
mkdir -p /home/ga/LCA_Imports
chown -R ga:ga /home/ga/LCA_Results /home/ga/LCA_Imports

# Clear previous results
rm -f /home/ga/LCA_Results/pvc_lifecycle_results.csv
rm -f /tmp/task_result.json

# 2. Ensure Data Availability (Zips)
# Copy USLCI if not present
if [ ! -f "/home/ga/LCA_Imports/uslci_database.zip" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp "/opt/openlca_data/uslci_database.zip" "/home/ga/LCA_Imports/"
        echo "Copied USLCI database zip."
    else
        echo "WARNING: USLCI database source not found."
    fi
fi

# Copy LCIA methods if not present
if [ ! -f "/home/ga/LCA_Imports/lcia_methods.zip" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp "/opt/openlca_data/lcia_methods.zip" "/home/ga/LCA_Imports/"
        echo "Copied LCIA methods zip."
    fi
fi
chown -R ga:ga /home/ga/LCA_Imports

# 3. Record Start State
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_db_count.txt
count_openlca_databases > /tmp/initial_db_count.txt

# 4. Launch Application
echo "Launching OpenLCA..."
launch_openlca 180

# 5. UI Setup
# Maximize window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="