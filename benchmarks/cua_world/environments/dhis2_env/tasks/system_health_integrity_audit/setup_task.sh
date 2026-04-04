#!/bin/bash
# Setup script for System Health Integrity Audit task

echo "=== Setting up System Health Integrity Audit Task ==="

source /workspace/scripts/task_utils.sh

# Define local helper for API calls if not present
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Verify DHIS2 is running and ready
echo "Checking DHIS2 health..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... ($i/30)"
    sleep 2
done

# 2. Record Task Start Time
# High precision timestamp for strictly filtering API events
date +%s > /tmp/task_start_timestamp
# ISO format for API comparison if needed
date -u +"%Y-%m-%dT%H:%M:%S.000Z" > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# 3. Clean up previous artifacts
rm -f /home/ga/Desktop/system_health_report.txt
echo "Cleaned up previous report file."

# 4. Prepare UI (Firefox)
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 8
else
    # If already running, ensure we are at home/login
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 4
fi

# Wait for window
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="