#!/bin/bash
echo "=== Setting up apache_field_extraction task ==="

source /workspace/scripts/task_utils.sh

echo "Recording initial state..."

# Record initial field extractions
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/props/extractions?output_mode=json&count=0" \
    > /tmp/initial_extractions.json 2>/dev/null || echo "{}" > /tmp/initial_extractions.json

# Record initial saved searches
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > /tmp/initial_searches.json 2>/dev/null || echo "{}" > /tmp/initial_searches.json

echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="