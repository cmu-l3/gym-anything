#!/bin/bash
echo "=== Setting up kv_store_blocklist task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Clean up any existing state that matches the artifacts we want the agent to create (prevents gaming retries)
curl -sk -X DELETE -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/nobody/search/storage/collections/config/ip_blocklist" >/dev/null 2>&1 || true
curl -sk -X DELETE -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/admin/search/data/transforms/lookups/ip_blocklist_lookup" >/dev/null 2>&1 || true
curl -sk -X DELETE -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/nobody/search/data/transforms/lookups/ip_blocklist_lookup" >/dev/null 2>&1 || true
curl -sk -X DELETE -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/admin/search/saved/searches/Blocklist_Alert" >/dev/null 2>&1 || true

# Save initial timestamp for anti-gaming checks
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    # Take screenshot of failure
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
# Take initial screenshot showing clean state
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete. ==="