#!/bin/bash
# Setup script for Grid Mix Source Analysis task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Grid Mix Source Analysis task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/grid_source_breakdown.csv 2>/dev/null || true

# 2. Prepare directories
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure Import Data is available
IMPORT_DIR="/home/ga/LCA_Imports"
mkdir -p "$IMPORT_DIR"

# USLCI Database
if [ ! -f "$IMPORT_DIR/uslci_database.zip" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$IMPORT_DIR/"
        echo "Copied USLCI database to imports"
    else
        echo "WARNING: USLCI database source not found!"
    fi
fi

# LCIA Methods
if [ ! -f "$IMPORT_DIR/lcia_methods.zip" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp /opt/openlca_data/lcia_methods.zip "$IMPORT_DIR/"
        echo "Copied LCIA methods to imports"
    else
        echo "WARNING: LCIA methods source not found!"
    fi
fi

chown -R ga:ga "$IMPORT_DIR"

# 4. Record initial state
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Count existing databases
INITIAL_DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="