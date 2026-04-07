#!/bin/bash
# Setup script for Dominant Phase Analysis task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Dominant Phase Analysis task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/dominance_report.txt 2>/dev/null || true

# 2. Prepare directories
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure import data is available (USLCI)
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ]; then
    echo "Checking for USLCI database..."
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        mkdir -p "/home/ga/LCA_Imports"
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        chown ga:ga "$USLCI_ZIP"
        echo "USLCI database copied to import directory."
    else
        echo "WARNING: USLCI database not found in /opt/openlca_data!"
    fi
fi

# 4. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Window management
sleep 5
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 7. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="