#!/bin/bash
# Setup script for Shadow Carbon Pricing Method task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi
if ! type ensure_uslci_database &>/dev/null; then
    ensure_uslci_database() { echo "/home/ga/openLCA-data-1.4/databases/USLCI"; }
fi

echo "=== Setting up Shadow Carbon Pricing task ==="

# Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/truck_carbon_liability.csv 2>/dev/null || true

# Prepare results directory
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure USLCI database is available to import
IMPORT_FILE="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$IMPORT_FILE" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$IMPORT_FILE"
    chown ga:ga "$IMPORT_FILE"
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

# Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="