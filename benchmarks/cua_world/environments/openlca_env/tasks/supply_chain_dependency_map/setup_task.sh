#!/bin/bash
# Setup script for Supply Chain Dependency Mapping task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Supply Chain Dependency Mapping task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/natural_gas_dependency.csv 2>/dev/null || true

# 2. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 3. Ensure Results directory exists
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 4. Ensure USLCI import file is available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ]; then
    echo "Checking for USLCI zip in /opt/openlca_data..."
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        mkdir -p "/home/ga/LCA_Imports"
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        chown ga:ga "$USLCI_ZIP"
        echo "Copied USLCI database zip."
    else
        echo "WARNING: USLCI database zip not found!"
    fi
else
    echo "USLCI database zip already exists at $USLCI_ZIP"
fi

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize window
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="