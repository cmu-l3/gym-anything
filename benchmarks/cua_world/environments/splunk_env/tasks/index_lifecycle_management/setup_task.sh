#!/bin/bash
echo "=== Setting up index_lifecycle_management task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Reset state to ensure clean start
echo "Resetting index configurations and cleaning up any previous runs..."
# Remove audit_trail if it exists
/opt/splunk/bin/splunk remove index audit_trail -auth admin:SplunkAdmin1! 2>/dev/null || true
# Reset existing indexes to defaults (roughly 6 years)
/opt/splunk/bin/splunk edit index security_logs -frozenTimePeriodInSecs 188697600 -auth admin:SplunkAdmin1! 2>/dev/null || true
/opt/splunk/bin/splunk edit index web_logs -frozenTimePeriodInSecs 188697600 -auth admin:SplunkAdmin1! 2>/dev/null || true
# Remove the saved search if it exists
curl -sk -u admin:SplunkAdmin1! -X DELETE https://localhost:8089/servicesNS/admin/search/saved/searches/Index_Volume_Monitor 2>/dev/null || true

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