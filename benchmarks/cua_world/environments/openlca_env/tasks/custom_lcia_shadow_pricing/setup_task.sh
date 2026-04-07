#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Custom LCIA Shadow Pricing task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/shadow_price_result.csv 2>/dev/null || true

# 2. Prepare directories
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure USLCI database zip is available for import
# (Agent needs to import it to find flows)
IMPORT_DIR="/home/ga/LCA_Imports"
mkdir -p "$IMPORT_DIR"
USLCI_ZIP="$IMPORT_DIR/uslci_database.zip"

if [ ! -f "$USLCI_ZIP" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        echo "Copied USLCI zip to $USLCI_ZIP"
    else
        echo "WARNING: USLCI zip not found in /opt/openlca_data"
    fi
fi
chown -R ga:ga "$IMPORT_DIR"

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "OpenLCA window maximized"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="