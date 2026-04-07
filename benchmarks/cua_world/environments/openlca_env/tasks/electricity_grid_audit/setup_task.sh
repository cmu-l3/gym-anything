#!/bin/bash
# Setup script for Electricity Grid Mix Data Audit
# Ensures OpenLCA is ready and data sources are available

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Electricity Grid Audit task ==="

# 1. Clean up previous results
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"
rm -f "$RESULTS_DIR/electricity_audit.csv" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# 3. Ensure USLCI import file is available
IMPORT_DIR="/home/ga/LCA_Imports"
mkdir -p "$IMPORT_DIR"
chown ga:ga "$IMPORT_DIR"

USLCI_ZIP="$IMPORT_DIR/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        chown ga:ga "$USLCI_ZIP"
        echo "Restored USLCI database zip to imports folder."
    else
        echo "WARNING: USLCI database zip not found in /opt/openlca_data!"
    fi
fi

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Configure window
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "OpenLCA window maximized"
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="