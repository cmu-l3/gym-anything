#!/bin/bash
# Setup script for Office Chair LCA Recreation task

source /workspace/scripts/task_utils.sh

# Define cleanup and launch functions if not available
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi

echo "=== Setting up Office Chair LCA task ==="

# Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
RESULTS_DIR="/home/ga/LCA_Results"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"
rm -f "$RESULTS_DIR/chair_impact.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/verification_verdict.txt" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure Import files are present
IMPORTS_DIR="/home/ga/LCA_Imports"
mkdir -p "$IMPORTS_DIR"
chown ga:ga "$IMPORTS_DIR"

# Check/Copy USLCI Database
if [ ! -f "$IMPORTS_DIR/uslci_database.zip" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$IMPORTS_DIR/"
        echo "Copied USLCI database zip."
    else
        echo "WARNING: USLCI database zip not found!"
    fi
fi

# Check/Copy LCIA Methods
if [ ! -f "$IMPORTS_DIR/lcia_methods.zip" ]; then
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        cp /opt/openlca_data/lcia_methods.zip "$IMPORTS_DIR/"
        echo "Copied LCIA methods zip."
    else
        echo "WARNING: LCIA methods zip not found!"
    fi
fi
chown -R ga:ga "$IMPORTS_DIR"

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize and focus
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "Window maximized."
fi

# Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="