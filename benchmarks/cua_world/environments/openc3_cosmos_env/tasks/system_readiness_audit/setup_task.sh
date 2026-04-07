#!/bin/bash
echo "=== Setting up System Readiness Audit task ==="

source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp) to prevent false positives
rm -f /home/ga/Desktop/system_readiness.json 2>/dev/null || true
rm -f /tmp/system_readiness_audit_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/system_readiness_audit_start_ts
echo "Task start recorded: $(cat /tmp/system_readiness_audit_start_ts)"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
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

# Take initial screenshot
take_screenshot /tmp/system_readiness_audit_start.png

echo "=== System Readiness Audit Setup Complete ==="
echo ""
echo "Task: Perform a pre-contact system readiness audit."
echo "Output must be written to: /home/ga/Desktop/system_readiness.json"
echo ""