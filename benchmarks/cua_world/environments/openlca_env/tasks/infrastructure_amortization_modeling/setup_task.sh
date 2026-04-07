#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Infrastructure Amortization Modeling task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous results
rm -f /home/ga/LCA_Results/turbine_inventory.csv 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# Ensure USLCI database is available for import
IMPORT_FILE="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$IMPORT_FILE" ]; then
    echo "Copying USLCI database..."
    mkdir -p /home/ga/LCA_Imports
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$IMPORT_FILE"
        chown ga:ga "$IMPORT_FILE"
    fi
fi

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "OpenLCA window maximized"
fi

# Record initial database count
DB_COUNT=$(count_openlca_databases)
echo "$DB_COUNT" > /tmp/initial_db_count

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="