#!/bin/bash
# Setup script for Transport Modal Split Optimization

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Transport Optimization Task ==="

# 1. clean up previous runs
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/optimization_report.txt 2>/dev/null || true

# 2. Prepare directories
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure Import Data is ready
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
mkdir -p "/home/ga/LCA_Imports"

# Copy from /opt if not present in user home
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

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

# 7. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="