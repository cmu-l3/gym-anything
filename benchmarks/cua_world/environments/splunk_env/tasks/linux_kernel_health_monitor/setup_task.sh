#!/bin/bash
echo "=== Setting up linux_kernel_health_monitor task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Clean up any pre-existing task artifacts to ensure a fresh state
echo "Cleaning up any existing artifacts..."
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" -X DELETE "${SPLUNK_API}/services/saved/eventtypes/linux_oom_event" >/dev/null 2>&1 || true
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" -X DELETE "${SPLUNK_API}/services/saved/eventtypes/linux_hardware_fault" >/dev/null 2>&1 || true
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" -X DELETE "${SPLUNK_API}/services/saved/eventtypes/linux_disk_error" >/dev/null 2>&1 || true
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" -X DELETE "${SPLUNK_API}/servicesNS/-/-/data/ui/views/Linux_Kernel_Health" >/dev/null 2>&1 || true

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3

# Take initial screenshot AFTER successful verification
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="