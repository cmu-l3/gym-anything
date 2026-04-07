#!/bin/bash
echo "=== Setting up scripted_input_pipeline task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Create the bin directory if it doesn't exist to prevent early failure
mkdir -p /opt/splunk/etc/apps/search/bin/
chown -R splunk:splunk /opt/splunk/etc/apps/search/bin/ 2>/dev/null || true

# Baseline the existing files in the bin directory so we can identify the new script
ls -1 /opt/splunk/etc/apps/search/bin/ > /tmp/baseline_bin_files.txt

# Remove any pre-existing saved search with the target name to ensure clean state
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" -X DELETE \
    "${SPLUNK_API}/servicesNS/admin/search/saved/searches/Live_Telemetry_Monitor" 2>/dev/null || true

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Task setup complete ==="