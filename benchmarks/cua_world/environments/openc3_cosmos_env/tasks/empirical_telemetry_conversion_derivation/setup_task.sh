#!/bin/bash
echo "=== Setting up Empirical Telemetry Conversion Derivation task ==="

source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Clean up any stale files
rm -f /home/ga/Desktop/ivv_conversion_report.json 2>/dev/null || true
rm -f /tmp/ivv_export_result.json 2>/dev/null || true

# Record task start timestamp (Anti-Gaming)
date +%s > /tmp/ivv_task_start_ts
echo "Task start recorded: $(cat /tmp/ivv_task_start_ts)"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to COSMOS home
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/ivv_task_start.png

echo "=== Setup Complete ==="
echo "The agent must override TEMP3 to 85.0, perform tests on TEMP1 and TEMP2, and write the report."