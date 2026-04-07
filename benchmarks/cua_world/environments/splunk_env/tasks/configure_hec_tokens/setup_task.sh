#!/bin/bash
echo "=== Setting up configure_hec_tokens task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if ! splunk_is_running; then
    echo "Starting Splunk..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Ensure HEC is globally DISABLED so the agent has to enable it
echo "Disabling HTTP Event Collector (HEC) globally..."
curl -sk -u "admin:SplunkAdmin1!" -X POST "https://localhost:8089/services/data/inputs/http/http" -d "disabled=1" 2>/dev/null

# Clean up any existing tokens or index that might conflict (for pure state)
curl -sk -u "admin:SplunkAdmin1!" -X DELETE "https://localhost:8089/services/data/inputs/http/webapp_frontend" 2>/dev/null
curl -sk -u "admin:SplunkAdmin1!" -X DELETE "https://localhost:8089/services/data/inputs/http/webapp_backend" 2>/dev/null

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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="