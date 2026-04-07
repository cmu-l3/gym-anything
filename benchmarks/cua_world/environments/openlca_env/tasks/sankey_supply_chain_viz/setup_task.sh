#!/bin/bash
# Setup script for Sankey Supply Chain Viz task

source /workspace/scripts/task_utils.sh

# Fallback function definitions if sourcing fails
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Sankey Supply Chain Viz task ==="

# 1. Prepare timestamp and clean state
date +%s > /tmp/task_start_timestamp
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/sankey_hdpe.png 2>/dev/null || true
rm -f /home/ga/LCA_Results/hdpe_supply_chain_report.txt 2>/dev/null || true

# 2. Ensure Results directory exists
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure Import files are available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
mkdir -p "/home/ga/LCA_Imports"

# Copy USLCI if missing
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
    echo "Restored USLCI zip"
fi

# Copy LCIA methods if missing
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
    echo "Restored LCIA zip"
fi

# 4. Check initial database count (to detect creation later)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
mkdir -p "$DB_DIR"
INITIAL_DB_COUNT=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l)
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count

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

# 7. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Start time: $(cat /tmp/task_start_timestamp)"