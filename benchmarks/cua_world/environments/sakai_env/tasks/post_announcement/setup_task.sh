#!/bin/bash
# Setup script for Post Announcement task

echo "=== Setting up Post Announcement task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type sakai_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    sakai_query() {
        docker exec sakai-db mysql -u sakai -psakaipass sakai -N -B -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    wait_for_window() {
        local window_pattern="$1"
        local timeout=${2:-30}
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then return 0; fi
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
fi

# Verify HIST201 course site exists
TARGET_SITE="HIST201"
SITE_EXISTS=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE WHERE SITE_ID='$TARGET_SITE'" | tr -d '[:space:]')
if [ "${SITE_EXISTS:-0}" -eq 0 ]; then
    echo "WARNING: HIST201 site not found!"
fi
echo "HIST201 site exists: $SITE_EXISTS"

# Verify Announcements tool is present
ANNOUNCE_TOOL=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE_TOOL WHERE SITE_ID='$TARGET_SITE' AND REGISTRATION='sakai.announcements'" | tr -d '[:space:]')
echo "Announcements tool in HIST201: $ANNOUNCE_TOOL"

# Record baseline announcement count
# Sakai stores announcements in ANNOUNCEMENT_MESSAGE with channel reference
INITIAL_ANNOUNCEMENT_COUNT=$(sakai_query "SELECT COUNT(*) FROM ANNOUNCEMENT_MESSAGE WHERE CHANNEL_ID LIKE '%/channel/$TARGET_SITE/main%'" 2>/dev/null | tr -d '[:space:]')
INITIAL_ANNOUNCEMENT_COUNT=${INITIAL_ANNOUNCEMENT_COUNT:-0}
echo "$INITIAL_ANNOUNCEMENT_COUNT" > /tmp/initial_announcement_count
echo "Initial announcement count in HIST201: $INITIAL_ANNOUNCEMENT_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running and pointed at HIST201
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/portal/site/$TARGET_SITE' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
else
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/portal/site/$TARGET_SITE'" 2>/dev/null || true
    sleep 3
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Sakai\|HIST" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Post Announcement Setup Complete ==="
