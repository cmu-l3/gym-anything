#!/bin/bash
echo "=== Setting up create_security_app task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure clean state: remove the app if it already exists (prevent gaming)
APP_DIR="/opt/splunk/etc/apps/ssh_security_monitor"
if [ -d "$APP_DIR" ]; then
    echo "Found existing app directory, removing for clean state..."
    rm -rf "$APP_DIR"
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, starting..."
    /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
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
echo "=== Task setup complete ==="