#!/bin/bash
# Setup script for Circular Economy Closed-Loop task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Circular Economy Closed-Loop task ==="

# 1. Clean previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/circular_pet_result.json 2>/dev/null || true

# 2. Prepare directories
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure Data Availability (USLCI and LCIA methods)
# This uses the standard environment locations
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"

if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

# 4. Record Initial State
# Count databases to detect if user creates one
INITIAL_DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# Record timestamp for file modification checks
date +%s > /tmp/task_start_timestamp

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize Window
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="