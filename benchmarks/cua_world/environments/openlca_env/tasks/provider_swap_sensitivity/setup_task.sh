#!/bin/bash
# Setup script for Provider Swap Sensitivity task

source /workspace/scripts/task_utils.sh

# Ensure helper functions exist
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Provider Swap Sensitivity task ==="

# 1. Clean up previous artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/provider_sensitivity.csv 2>/dev/null || true

# 2. Prepare Results Directory
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 4. Ensure Data Imports are Available
# USLCI Database
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

# LCIA Methods
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

echo "USLCI zip: $([ -f "$USLCI_ZIP" ] && echo "available" || echo "NOT FOUND")"
echo "LCIA zip:  $([ -f "$LCIA_ZIP" ] && echo "available" || echo "NOT FOUND")"

# 5. Record Initial DB State
INITIAL_DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# 6. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 7. Maximize Window
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "Window maximized."
fi

# 8. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="