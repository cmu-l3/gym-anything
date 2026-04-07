#!/bin/bash
# Setup script for Agricultural Unit Group task

source /workspace/scripts/task_utils.sh

# Fallback utility definitions
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" & sleep 20; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Agricultural Unit Group task ==="

# Clean previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/db_export.txt 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_timestamp

# Ensure directory structure exists (in case agent creates a new DB)
mkdir -p /home/ga/openLCA-data-1.4/databases
chown -R ga:ga /home/ga/openLCA-data-1.4

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Wait for window and maximize
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "OpenLCA window maximized"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="