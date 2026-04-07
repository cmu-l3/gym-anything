#!/bin/bash
# Setup script for Freight Transport Project task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Freight Transport Project task ==="

# Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/transport_project_comparison.csv 2>/dev/null || true

# Prepare directories
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

IMPORTS_DIR="/home/ga/LCA_Imports"
mkdir -p "$IMPORTS_DIR"
chown ga:ga "$IMPORTS_DIR"

# Ensure Data is available
USLCI_ZIP="$IMPORTS_DIR/uslci_database.zip"
LCIA_ZIP="$IMPORTS_DIR/lcia_methods.zip"

if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
    echo "Copied USLCI database to imports folder."
fi

if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
    echo "Copied LCIA methods to imports folder."
fi

# Record start time for file timestamp verification
date +%s > /tmp/task_start_timestamp

# Launch OpenLCA
# We launch it empty (no DB loaded) as per task description
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "OpenLCA window maximized"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="