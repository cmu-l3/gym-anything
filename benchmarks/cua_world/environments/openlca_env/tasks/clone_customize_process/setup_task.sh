#!/bin/bash
# Setup script for Clone & Customize Process task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Clone & Customize Process task ==="

# 1. Clean up previous results
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"
rm -f "$RESULTS_DIR/process_customization_report.csv" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Ensure USLCI zip is available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
fi

# 3. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Maximize window
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# 6. Record initial DB state (approximate via file count if DB exists)
# This helps detect if a new process file is created on disk (Derby stores data in files)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_FILE_COUNT=$(find "$DB_DIR" -type f 2>/dev/null | wc -l)
echo "$INITIAL_FILE_COUNT" > /tmp/initial_db_file_count

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="