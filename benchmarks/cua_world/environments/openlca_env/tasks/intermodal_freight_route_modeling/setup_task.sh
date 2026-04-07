#!/bin/bash
# Setup script for Intermodal Freight Route Modeling task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Intermodal Freight Route Modeling task ==="

# Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/route_gwp.csv 2>/dev/null || true

# Ensure results directory exists
mkdir -p "/home/ga/LCA_Results"
chown ga:ga "/home/ga/LCA_Results"

# Record task start timestamp (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure Import files are available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
mkdir -p "/home/ga/LCA_Imports"

if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="