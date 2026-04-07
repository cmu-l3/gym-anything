#!/bin/bash
# Setup script for Create Course Site task

echo "=== Setting up Create Course Site task ==="

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

# Verify target site does NOT already exist (clean state)
TARGET_SITE="CHEM201"
EXISTING=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE WHERE SITE_ID='$TARGET_SITE'" | tr -d '[:space:]')
if [ "${EXISTING:-0}" -gt 0 ]; then
    echo "WARNING: Site $TARGET_SITE already exists. Removing for clean start..."
    sakai_query "DELETE FROM SAKAI_SITE_USER WHERE SITE_ID='$TARGET_SITE'" || true
    sakai_query "DELETE FROM SAKAI_SITE_TOOL WHERE SITE_ID='$TARGET_SITE'" || true
    sakai_query "DELETE FROM SAKAI_SITE_PAGE WHERE SITE_ID='$TARGET_SITE'" || true
    sakai_query "DELETE FROM SAKAI_SITE_PROPERTY WHERE SITE_ID='$TARGET_SITE'" || true
    sakai_query "DELETE FROM SAKAI_SITE WHERE SITE_ID='$TARGET_SITE'" || true
fi

# Record baseline site count (excluding special sites)
INITIAL_SITE_COUNT=$(sakai_query "SELECT COUNT(*) FROM SAKAI_SITE WHERE SITE_ID NOT LIKE '~%' AND SITE_ID NOT LIKE '!%'" | tr -d '[:space:]')
echo "$INITIAL_SITE_COUNT" > /tmp/initial_site_count
echo "Initial non-special site count: $INITIAL_SITE_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running and pointed at Sakai
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/portal' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Sakai" 30; then
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

echo "=== Create Course Site Setup Complete ==="
