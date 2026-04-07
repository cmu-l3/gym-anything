#!/bin/bash
# Setup script for Supply Chain Logistics Modeling task
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Supply Chain Logistics task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 2. Ensure USLCI zip is available (Agent must import it)
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ]; then
    echo "Restoring USLCI database zip..."
    mkdir -p "$(dirname "$USLCI_ZIP")"
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    else
        echo "WARNING: USLCI source not found!"
    fi
    chown -R ga:ga "$(dirname "$USLCI_ZIP")"
fi

# 3. Ensure LCIA methods are available
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

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
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="