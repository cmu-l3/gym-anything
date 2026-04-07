#!/bin/bash
set -e

echo "=== Setting up Logistics Carbon Budget task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -rf /home/ga/LCA_Results/* 2>/dev/null || true
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# 2. Prepare Data Imports
# Ensure USLCI database zip is available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

# Ensure LCIA methods zip is available
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

echo "Data prepared in /home/ga/LCA_Imports/"

# 3. Record initial state
# Count existing DBs (should be 0 or low)
INITIAL_DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# Record start time
date +%s > /tmp/task_start_time.txt

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Window Management
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="