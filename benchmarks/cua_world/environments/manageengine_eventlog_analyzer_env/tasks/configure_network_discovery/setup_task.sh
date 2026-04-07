#!/bin/bash
# Setup for configure_network_discovery task

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || { echo "Failed to source task_utils.sh"; exit 1; }

echo "=== Setting up Configure Network Discovery task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/discovery_config_summary.txt
rm -f /tmp/task_initial_state.png
rm -f /tmp/discovery_config_final.png

# Wait for EventLog Analyzer to be ready (it can take a while to start)
wait_for_eventlog_analyzer 900

# Ensure Firefox is open on the EventLog Analyzer Dashboard
# We start at the dashboard so the agent has to navigate to Settings/Discovery
ensure_firefox_on_ela "/event/index.do"

# Wait for page to fully load and stabilize
sleep 5

# Dismiss any potential popup dialogs (like "What's New")
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "EventLog Analyzer is ready."
echo "Firefox is open at the dashboard."
echo "Task: Configure network discovery for 10.0.1.1-10.0.1.254 and 127.0.0.1"