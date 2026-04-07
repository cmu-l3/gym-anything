#!/bin/bash
echo "=== Setting up Configure HTTPS Console task ==="

# Source shared utilities
# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any existing marker file
rm -f /home/ga/https_configured.txt

# Ensure EventLog Analyzer is running on default HTTP port (8095)
# If it's not running or already on HTTPS, we might need to reset, 
# but for a fresh env, it should be on 8095.
wait_for_eventlog_analyzer 900

# Open Firefox to the Settings page to help the agent get started,
# but to the dashboard main page so they have to find the settings.
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    maximize_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="