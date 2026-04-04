#!/bin/bash
# Setup script for BMI Program Rule Configuration task

echo "=== Setting up BMI Configuration Task ==="

source /workspace/scripts/task_utils.sh

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "Waiting for DHIS2..."
    sleep 10
    if ! check_dhis2_health; then
        echo "WARNING: DHIS2 might not be ready."
    fi
fi

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for window
wait_for_window "firefox\|mozilla\|DHIS" 30

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Clean up any previous attempts (if re-running in same container)
rm -f /home/ga/Desktop/bmi_verification.png

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="