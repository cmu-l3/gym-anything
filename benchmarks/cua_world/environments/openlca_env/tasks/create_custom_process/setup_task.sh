#!/bin/bash
# Setup script for Custom Process Creation task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Custom Process Creation task ==="

# 1. Clean up previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/brewery_lca_results.csv 2>/dev/null || true

# 2. Prepare directories
RESULTS_DIR="/home/ga/LCA_Results"
IMPORTS_DIR="/home/ga/LCA_Imports"
mkdir -p "$RESULTS_DIR" "$IMPORTS_DIR"
chown -R ga:ga "$RESULTS_DIR" "$IMPORTS_DIR"

# 3. Ensure Data Files (USLCI & LCIA) are available
USLCI_ZIP="$IMPORTS_DIR/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
    echo "Copied USLCI database zip."
fi

LCIA_ZIP="$IMPORTS_DIR/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
    echo "Copied LCIA methods zip."
fi

# 4. Record Initial State (Process Count)
# We need to find the active DB if one exists to get a baseline count
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
# Simple heuristic: largest directory is likely the active imported DB
if [ -d "$DB_DIR" ]; then
    ACTIVE_DB=$(du -s "$DB_DIR"/* 2>/dev/null | sort -nr | head -1 | awk '{print $2}')
fi

INITIAL_PROCESS_COUNT=0
if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ]; then
    # Try to count processes using Derby
    # Note: openLCA must be closed for this to work reliably without locking,
    # but we haven't launched it yet, so it's safe.
    echo "Checking initial process count in $ACTIVE_DB..."
    INITIAL_PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")
fi
echo "$INITIAL_PROCESS_COUNT" > /tmp/initial_process_count
echo "Initial process count: $INITIAL_PROCESS_COUNT"

# 5. Record Start Time
date +%s > /tmp/task_start_timestamp

# 6. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 7. Maximize Window
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# 8. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="