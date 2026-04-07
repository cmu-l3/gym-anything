#!/bin/bash
echo "=== Setting up network_asset_lookup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Ensure a clean state: remove any pre-existing files or lookups with the target names
echo "Cleaning up any existing artifacts to ensure clean state..."
curl -sk -u "admin:SplunkAdmin1!" -X DELETE "https://localhost:8089/servicesNS/nobody/search/data/transforms/lookups/network_asset_lookup" > /dev/null 2>&1 || true
curl -sk -u "admin:SplunkAdmin1!" -X DELETE "https://localhost:8089/servicesNS/admin/search/data/transforms/lookups/network_asset_lookup" > /dev/null 2>&1 || true

# For automatic lookups, the exact name could vary, so we'll just delete common patterns
curl -sk -u "admin:SplunkAdmin1!" -X DELETE "https://localhost:8089/servicesNS/nobody/search/data/props/lookups/linux_secure%20:%20LOOKUP-asset_context_for_security" > /dev/null 2>&1 || true
curl -sk -u "admin:SplunkAdmin1!" -X DELETE "https://localhost:8089/servicesNS/admin/search/data/props/lookups/linux_secure%20:%20LOOKUP-asset_context_for_security" > /dev/null 2>&1 || true

# Remove CSV files from common Splunk lookup directories
find /opt/splunk/etc -name "network_assets.csv" -type f -delete 2>/dev/null || true

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

# Wait to ensure UI is fully loaded
sleep 3

# Take initial screenshot AFTER successful verification
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="