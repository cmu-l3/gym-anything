#!/bin/bash
# Setup script for Comparative Packaging LCA task
# Pre-task hook: runs BEFORE the agent starts

source /workspace/scripts/task_utils.sh

# Fallback definitions in case sourcing fails
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() {
        su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" &
        sleep 20
    }
fi

echo "=== Setting up Comparative Packaging LCA task ==="

# Clean up any leftover state from previous tasks
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/comparative_packaging_lca_result.json 2>/dev/null || true

# Ensure results directory exists and is writable
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# Record initial state
INITIAL_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)
echo "$INITIAL_RESULT_COUNT" > /tmp/initial_result_count
echo "Initial result file count: $INITIAL_RESULT_COUNT"

# Record task start timestamp (CRITICAL: record BEFORE any file operations)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Ensure USLCI zip is available
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ -f "$USLCI_ZIP" ]; then
    echo "USLCI database zip available: $USLCI_ZIP ($(du -sh "$USLCI_ZIP" | cut -f1))"
else
    echo "WARNING: USLCI zip not found at $USLCI_ZIP"
    # Try alternative location
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        mkdir -p "/home/ga/LCA_Imports"
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        chown ga:ga "$USLCI_ZIP"
        echo "Copied USLCI zip from /opt/openlca_data/"
    fi
fi

# Ensure LCIA methods zip is available
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ -f "$LCIA_ZIP" ]; then
    echo "LCIA methods zip available: $LCIA_ZIP ($(du -sh "$LCIA_ZIP" | cut -f1))"
else
    echo "WARNING: LCIA methods zip not found at $LCIA_ZIP"
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        mkdir -p "/home/ga/LCA_Imports"
        cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
        chown ga:ga "$LCIA_ZIP"
        echo "Copied LCIA methods zip from /opt/openlca_data/"
    fi
fi

# Verify no databases exist yet (distinct starting state)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count
echo "Initial database count: $INITIAL_DB_COUNT"

# Launch OpenLCA
echo ""
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window for better agent visibility
sleep 2
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "OpenLCA window maximized"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved"

echo ""
echo "=== Comparative Packaging LCA setup complete ==="
echo "Available resources:"
echo "  USLCI database: ~/LCA_Imports/uslci_database.zip"
echo "  LCIA methods:   ~/LCA_Imports/lcia_methods.zip"
echo "  Results dir:    ~/LCA_Results/"
