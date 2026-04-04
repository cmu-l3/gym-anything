#!/bin/bash
echo "=== Setting up export_rivers_dxf task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and are writable
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/gvsig_data

# Clean up any previous output
OUTPUT_FILE="/home/ga/gvsig_data/exports/brazil_rivers.dxf"
rm -f "$OUTPUT_FILE"

# Kill any running gvSIG instances
kill_gvsig

# Launch gvSIG with a clean state (no project loaded)
# The agent is expected to load layers manually as part of the task
echo "Launching gvSIG..."
launch_gvsig ""

# Verify the window appeared
if ! wait_for_window "gvSIG" 60; then
    echo "ERROR: gvSIG window not detected"
    # Try one more time
    launch_gvsig ""
fi

# Maximize window
DISPLAY=:1 wmctrl -r "gvSIG" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="