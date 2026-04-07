#!/bin/bash
# Setup for "disable_auto_device_addition" task

echo "=== Setting up Disable Auto Device Addition task ==="

# Source shared utilities
# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running and accessible
wait_for_eventlog_analyzer 900

# Ensure Firefox is open and on the Dashboard
# We start at the dashboard so the agent has to find the Settings themselves
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Maximize Firefox for better VLM visibility
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="