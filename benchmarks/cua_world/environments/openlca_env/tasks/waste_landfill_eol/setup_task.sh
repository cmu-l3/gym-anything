#!/bin/bash
# Setup script for Waste Landfill EOL task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Waste Landfill EOL task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/landfill_eol_results.csv 2>/dev/null || true

# 2. Ensure Results directory exists
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# 3. Ensure Import files are available
mkdir -p /home/ga/LCA_Imports
# Copy USLCI if missing
if [ ! -f "/home/ga/LCA_Imports/uslci_database.zip" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip /home/ga/LCA_Imports/
    chown ga:ga /home/ga/LCA_Imports/uslci_database.zip
fi
# Copy LCIA methods if missing
if [ ! -f "/home/ga/LCA_Imports/lcia_methods.zip" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip /home/ga/LCA_Imports/
    chown ga:ga /home/ga/LCA_Imports/lcia_methods.zip
fi

# 4. Record baseline state (DB counts)
# We want to know if the agent created new flows/processes
# Note: exact flow count depends on if DB is already loaded.
# We'll just record timestamp for file changes.
date +%s > /tmp/task_start_timestamp

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="