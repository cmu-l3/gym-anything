#!/bin/bash
# Setup script for System Branding Config task

echo "=== Setting up System Branding Config Task ==="

source /workspace/scripts/task_utils.sh

# Function to reset a system setting
reset_setting() {
    local key="$1"
    # Delete removes the setting, reverting to system default
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/systemSettings/$key" > /dev/null
}

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "WARNING: DHIS2 is not responding. Waiting..."
    sleep 30
    check_dhis2_health || echo "DHIS2 may not be fully ready"
fi

# Reset settings to ensure clean state (and prevent false positives if re-running)
echo "Resetting system settings to defaults..."
reset_setting "applicationTitle"
reset_setting "applicationIntro"
reset_setting "applicationNotification"
reset_setting "keyAnalyticsMaxLimit"
reset_setting "applicationFooter"
reset_setting "keyInfrastructuralIndicators"

# Record task start time
date +%s > /tmp/task_start_timestamp
echo "Task start time: $(cat /tmp/task_start_timestamp)"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_LOGIN_URL="http://localhost:8080/dhis-web-commons/security/login.action"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_LOGIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # Navigate to login page if already running
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_LOGIN_URL' > /dev/null 2>&1 &"
    sleep 4
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|DHIS" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== System Branding Config Task Setup Complete ==="