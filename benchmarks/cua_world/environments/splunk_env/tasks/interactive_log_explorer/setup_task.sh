#!/bin/bash
echo "=== Setting up interactive_log_explorer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Pre-task cleanup: Ensure the target dashboard does NOT already exist
# This guarantees the agent must build it from scratch during the task
echo "Cleaning up any pre-existing target dashboards..."
curl -sk -u "admin:SplunkAdmin1!" -X DELETE \
    "https://localhost:8089/servicesNS/admin/search/data/ui/views/web_error_investigator" \
    > /dev/null 2>&1 || true

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

# Additional wait to ensure UI is fully loaded
sleep 3

# Take initial screenshot AFTER successful verification
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="