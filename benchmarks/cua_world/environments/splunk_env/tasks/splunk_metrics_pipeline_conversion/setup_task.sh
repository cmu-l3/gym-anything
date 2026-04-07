#!/bin/bash
echo "=== Setting up splunk_metrics_pipeline_conversion task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Clean up any existing state to prevent gaming
echo "Ensuring clean state (removing auth_metrics and Auth_Metrics_Rollup if they exist)..."
curl -sk -u admin:SplunkAdmin1! -X DELETE "https://localhost:8089/services/data/indexes/auth_metrics" >/dev/null 2>&1 || true
curl -sk -u admin:SplunkAdmin1! -X DELETE "https://localhost:8089/servicesNS/admin/search/saved/searches/Auth_Metrics_Rollup" >/dev/null 2>&1 || true
# Give Splunk a moment to process deletions
sleep 3

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

# Allow UI to settle
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="