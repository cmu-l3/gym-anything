#!/bin/bash
# Setup script for Comparative Project Analysis task
# Pre-task hook: runs BEFORE the agent starts

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() {
        su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" &
        sleep 20
    }
fi

echo "=== Setting up Comparative Project Analysis task ==="

# Clean up any leftover state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/project_analysis_debug.log 2>/dev/null || true

# Ensure results directory exists
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# Record initial state of results directory
INITIAL_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)
echo "$INITIAL_RESULT_COUNT" > /tmp/initial_result_count

# Record task start timestamp (for file modification checks)
date +%s > /tmp/task_start_timestamp

# Ensure Data is available for import
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

echo "USLCI zip: $([ -f "$USLCI_ZIP" ] && echo "available" || echo "missing")"
echo "LCIA zip:  $([ -f "$LCIA_ZIP" ] && echo "available" || echo "missing")"

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "Window maximized"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="