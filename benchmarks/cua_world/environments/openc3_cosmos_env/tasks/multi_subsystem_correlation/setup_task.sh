#!/bin/bash
echo "=== Setting up Multi-Subsystem Correlation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp) to prevent false positives
rm -f /home/ga/Desktop/correlation_report.json 2>/dev/null || true
rm -f /tmp/multi_subsystem_correlation_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/multi_subsystem_correlation_start_ts
echo "Task start recorded: $(cat /tmp/multi_subsystem_correlation_start_ts)"

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

# Navigate to COSMOS home (agent discovers the relevant tools on their own)
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
take_screenshot /tmp/multi_subsystem_correlation_start.png

echo "=== Multi-Subsystem Correlation Setup Complete ==="
echo ""
echo "Task: Collect >=20 samples of TEMP1-TEMP4 & Q1-Q2, compute correlation matrix."
echo "Output must be written to: /home/ga/Desktop/correlation_report.json"
echo ""