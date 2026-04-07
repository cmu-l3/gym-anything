#!/bin/bash
# Setup script for System Expansion Credit task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up System Expansion Credit task ==="

# 1. Clean previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/substitution_benefit.csv 2>/dev/null || true

# 2. Ensure Results directory exists
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure Data Sources are available
# (The agent is expected to import them, but we must ensure the zips are there)
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
mkdir -p "/home/ga/LCA_Imports"

if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
fi
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
fi
chown -R ga:ga "/home/ga/LCA_Imports"

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Maximize window
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# 6. Record start time and screenshot
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="