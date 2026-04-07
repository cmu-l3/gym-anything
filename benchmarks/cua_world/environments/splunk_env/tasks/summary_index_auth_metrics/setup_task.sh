#!/bin/bash
echo "=== Setting up summary_index_auth_metrics task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Clean up any previous task artifacts to ensure a pristine state
echo "Cleaning up previous task artifacts if they exist..."
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/servicesNS/-/-/saved/searches/Auth_Metrics_Collector" \
    > /dev/null 2>&1 || true

# Note: Deleting an index via REST marks it disabled. We'll try to clean it, 
# but if it exists, the agent using the same name is fine.
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X DELETE "${SPLUNK_API}/services/data/indexes/auth_summary" \
    > /dev/null 2>&1 || true
sleep 2

# Reload indexer to apply deletion if possible
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    -X POST "${SPLUNK_API}/services/data/indexes/_reload" \
    > /dev/null 2>&1 || true

# Record task start time
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="