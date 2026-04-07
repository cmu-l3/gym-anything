#!/bin/bash
# Setup script for Soybean Crushing Allocation task

source /workspace/scripts/task_utils.sh

# Fallback for local testing if task_utils not present
if ! type launch_openlca &>/dev/null; then
    launch_openlca() { echo "Mock launch"; sleep 2; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { echo "Mock screenshot"; }
fi

echo "=== Setting up Soybean Crushing Allocation task ==="

# 1. Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/derby_dump.txt 2>/dev/null || true

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# 3. Ensure OpenLCA is running
# We need the app open so the agent can interact immediately
echo "Launching OpenLCA..."
launch_openlca 180

# 4. Maximize window
sleep 5
WID=$(get_openlca_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
    echo "OpenLCA window maximized"
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="