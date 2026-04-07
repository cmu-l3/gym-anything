#!/bin/bash
echo "=== Setting up rbac_row_level_security task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Ensure baseline data is present
SEC_EVENTS=$(splunk_count_events "security_logs")
echo "Security logs baseline event count: $SEC_EVENTS"
if [ "$SEC_EVENTS" -lt 10 ]; then
    echo "WARNING: Low security_logs count! Environment may not be fully initialized."
fi

# Record start time for anti-gaming
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    exit 1
fi

# Let the UI settle
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="