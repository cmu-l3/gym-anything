#!/bin/bash
echo "=== Setting up search_security_events task ==="

source /workspace/scripts/task_utils.sh

# Record initial state - count of existing saved searches and job history
echo "Recording initial state..."

# Count how many search jobs exist
INITIAL_JOB_COUNT=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/search/jobs?output_mode=json&count=0" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('entry', [])))
except:
    print('0')
" 2>/dev/null)
echo "$INITIAL_JOB_COUNT" > /tmp/initial_job_count

# Verify security_logs index has data
SEC_EVENT_COUNT=$(splunk_count_events "security_logs")
echo "Security log events: $SEC_EVENT_COUNT"
echo "$SEC_EVENT_COUNT" > /tmp/initial_sec_event_count

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk is not running, attempting restart..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
# Using 120 second timeout as recommended by audit
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    # EXIT WITH ERROR - Do not continue with invalid state
    exit 1
fi

# Additional wait to ensure UI is fully loaded
sleep 3

# Take initial screenshot AFTER successful verification
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="
echo "Initial job count: $INITIAL_JOB_COUNT"
echo "Security event count: $SEC_EVENT_COUNT"
