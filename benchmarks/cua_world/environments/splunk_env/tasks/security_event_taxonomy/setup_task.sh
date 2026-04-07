#!/bin/bash
echo "=== Setting up security_event_taxonomy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Clean up any previous task artifacts (eventtypes, tags, and saved search)
echo "Cleaning up pre-existing task artifacts..."
for et in ssh_brute_force ssh_successful_login system_error; do
    curl -sk -u admin:SplunkAdmin1! -X DELETE \
        "https://localhost:8089/servicesNS/admin/search/saved/eventtypes/${et}" 2>/dev/null || true
    
    # Remove tag associations in conf-tags
    curl -sk -u admin:SplunkAdmin1! -X DELETE \
        "https://localhost:8089/servicesNS/admin/search/configs/conf-tags/eventtype%3D${et}" 2>/dev/null || true
done

curl -sk -u admin:SplunkAdmin1! -X DELETE \
    "https://localhost:8089/servicesNS/admin/search/saved/searches/Tagged_Security_Summary" 2>/dev/null || true

# Record initial baseline counts
INITIAL_EVENTTYPES=$(curl -sk -u admin:SplunkAdmin1! \
    "https://localhost:8089/servicesNS/-/-/saved/eventtypes?output_mode=json&count=0" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('entry',[])))" 2>/dev/null || echo "0")
echo "$INITIAL_EVENTTYPES" > /tmp/initial_eventtype_count.txt

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

# Navigate to the Settings > Event types page as a logical starting point
echo "Navigating to Event Types page..."
navigate_to_splunk_page "http://localhost:8000/en-US/manager/search/saved/eventtypes"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Initial eventtypes count: $INITIAL_EVENTTYPES"