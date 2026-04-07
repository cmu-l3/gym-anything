#!/bin/bash
echo "=== Setting up linux_pam_execution_audit task ==="

source /workspace/scripts/task_utils.sh

# Record initial timestamp
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record baseline objects to ensure the agent doesn't just pass by luck
echo "Recording baseline dashboards and alerts..."

splunk_list_dashboards > /tmp/baseline_dashboards.json 2>/dev/null
splunk_list_saved_searches > /tmp/baseline_searches.json 2>/dev/null

# Ensure Firefox is running with Splunk visible (CRITICAL for visual agent)
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="