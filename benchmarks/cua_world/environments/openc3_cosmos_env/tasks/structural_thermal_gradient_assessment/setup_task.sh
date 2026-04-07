#!/bin/bash
echo "=== Setting up Structural Thermal Gradient Assessment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if type wait_for_cosmos_api &>/dev/null; then
    if ! wait_for_cosmos_api 60; then
        echo "WARNING: COSMOS API not ready, continuing anyway"
    fi
fi

# Clean stale output files FIRST to prevent false positives in timestamps
rm -f /home/ga/Desktop/thermal_gradient_report.json 2>/dev/null || true
rm -f /tmp/structural_thermal_gradient_assessment_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_ts
echo "Task start recorded: $(cat /tmp/task_start_ts)"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:2900' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window and maximize it
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|openc3\|cosmos" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Firefox window detected, maximizing..."
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Structural Thermal Gradient Assessment Setup Complete ==="
echo ""
echo "Task: Collect 10 telemetry samples, compute spatial gradient, and evaluate limits."
echo "Output must be written to: /home/ga/Desktop/thermal_gradient_report.json"
echo ""