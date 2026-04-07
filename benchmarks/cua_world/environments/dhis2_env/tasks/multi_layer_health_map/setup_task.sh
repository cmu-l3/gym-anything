#!/bin/bash
# Setup script for Multi-Layer Health Map task

echo "=== Setting up Multi-Layer Health Map Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... (Attempt $i/12)"
    sleep 5
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Clean Downloads folder to ensure clear verification
mkdir -p /home/ga/Downloads
# Move existing images to a backup folder just in case
mkdir -p /home/ga/Downloads/backup_pre_task
mv /home/ga/Downloads/*.png /home/ga/Downloads/*.jpg /home/ga/Downloads/*.pdf /home/ga/Downloads/backup_pre_task/ 2>/dev/null || true

# Record initial map count
INITIAL_MAP_COUNT=$(dhis2_api "maps?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_MAP_COUNT" > /tmp/initial_map_count
echo "Initial map count: $INITIAL_MAP_COUNT"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to DHIS2 URL using xdotool (avoids "Close Firefox" dialog)
    DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || DISPLAY=:1 wmctrl -a "firefox" 2>/dev/null || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key ctrl+l" 2>/dev/null || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers '$DHIS2_URL'" 2>/dev/null || true
    sleep 0.2
    su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
    sleep 4
fi

# Wait for window and maximize
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
        if [ -n "$WID" ]; then
            DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        fi
        break
    fi
    sleep 2
done

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="