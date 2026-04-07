#!/bin/bash
# Setup script for LCI Inventory Export task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up LCI Inventory Export task ==="

# 1. Clean up previous artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/electricity_lci_inventory.csv 2>/dev/null || true
rm -f /home/ga/LCA_Results/lci_summary_report.txt 2>/dev/null || true

# 2. Ensure Results directory exists
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure USLCI database zip is available
# (The environment usually has it in /opt, we make sure it's accessible to user)
IMPORT_DIR="/home/ga/LCA_Imports"
mkdir -p "$IMPORT_DIR"
USLCI_ZIP="$IMPORT_DIR/uslci_database.zip"

if [ ! -f "$USLCI_ZIP" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        echo "Copied USLCI database to $USLCI_ZIP"
    else
        echo "WARNING: USLCI database not found in /opt/openlca_data/"
    fi
fi
chown -R ga:ga "$IMPORT_DIR"

# 4. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 5. Record initial DB state (to verify import happens during task)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_DB_COUNT=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

# 6. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 7. Maximize window and take initial screenshot
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png
echo "Setup complete."