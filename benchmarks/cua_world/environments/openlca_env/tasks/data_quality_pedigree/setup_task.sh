#!/bin/bash
# Setup script for Data Quality Pedigree task
# Runs before the agent starts

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Data Quality Pedigree task ==="

# 1. Prepare Results Directory
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# Clean up previous results
rm -f "$RESULTS_DIR/data_quality_report.csv" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Record Task Start Timestamp (for file modification checks)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 3. Ensure Import Files exist
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ]; then
    echo "Restoring USLCI zip from /opt/openlca_data..."
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP" 2>/dev/null || true
    chown ga:ga "$USLCI_ZIP"
fi

# 4. Check for existing databases (record initial state)
# We record this to detect if the agent creates a new database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_DB_COUNT=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize Window
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "OpenLCA window maximized"
fi

# 7. Take Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup Complete ==="