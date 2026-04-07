#!/bin/bash
# Setup script for Create Aggregated LCI Dataset task
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

echo "=== Setting up Create Aggregated LCI Dataset task ==="

# Clean up any leftover state from previous tasks
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/create_aggregated_lci_result.json 2>/dev/null || true

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
if [ ! -f "$USLCI_ZIP" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        echo "Copied USLCI zip from /opt/openlca_data/"
    else
        echo "WARNING: USLCI zip not found at $USLCI_ZIP or /opt/openlca_data/"
    fi
    chown ga:ga "$USLCI_ZIP"
fi

# Ensure LCIA methods zip is available (optional but good practice)
LCIA_ZIP="/home/ga/LCA_Imports/lcia_methods.zip"
if [ ! -f "$LCIA_ZIP" ] && [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/lcia_methods.zip "$LCIA_ZIP"
    chown ga:ga "$LCIA_ZIP"
fi

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
echo "=== Create Aggregated LCI Dataset setup complete ==="
echo "Available resources:"
echo "  USLCI database: ~/LCA_Imports/uslci_database.zip"
echo "  Results dir:    ~/LCA_Results/"