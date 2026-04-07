#!/bin/bash
# Setup script for Custom LCIA Method task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Custom LCIA Method task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/single_score_results.csv 2>/dev/null || true

# 2. Prepare results directory
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure USLCI database is available/imported
# The task assumes a database exists to link flows.
# We will check if one exists; if not, we prepare the zip for import.
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        chown ga:ga "$USLCI_ZIP"
        echo "Copied USLCI database zip to imports"
    fi
fi

# 4. Check if a database is already imported in OpenLCA
# If not, the agent will need to do it (part of the environment anyway).
DB_COUNT=$(count_openlca_databases)
echo "Current database count: $DB_COUNT"

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize and focus
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# 7. Record start time and screenshot
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="