#!/bin/bash
# Setup script for Global Parameter Formulas task
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

echo "=== Setting up Global Parameter Formulas task ==="

# Clean up any leftover state from previous tasks
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/global_parameter_formulas_result.json 2>/dev/null || true

# Ensure results directory exists and is writable
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"
rm -f "$RESULTS_DIR/parameter_summary.csv" 2>/dev/null || true

# Record task start timestamp (CRITICAL: record BEFORE any file operations)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Ensure USLCI zip is available (as a base to work in)
USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    mkdir -p "/home/ga/LCA_Imports"
    cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
    chown ga:ga "$USLCI_ZIP"
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
echo "=== Global Parameter Formulas setup complete ==="