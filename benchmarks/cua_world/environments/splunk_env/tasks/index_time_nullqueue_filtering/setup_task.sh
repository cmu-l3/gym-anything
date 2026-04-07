#!/bin/bash
echo "=== Setting up index_time_nullqueue_filtering task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "Starting Splunk..."
    /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "WARNING: Could not verify Splunk is visible in Firefox"
fi

# Clean up any existing config that might interfere (system/local should be pristine for these)
sudo rm -f /opt/splunk/etc/system/local/props.conf
sudo rm -f /opt/splunk/etc/system/local/transforms.conf

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="