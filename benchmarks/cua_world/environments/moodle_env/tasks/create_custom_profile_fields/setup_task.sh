#!/bin/bash
# Setup script for Create Custom Profile Fields task

echo "=== Setting up Custom Profile Fields Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
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

# 1. Clean up any existing data related to this task
echo "Cleaning up previous task artifacts..."
# Delete fields first to avoid FK constraints (though Moodle DB usually handles this via logic, safe to be explicit)
# Find category ID first
CAT_ID=$(moodle_query "SELECT id FROM mdl_user_info_category WHERE name LIKE '%Employee Information%'" | tr -d '[:space:]')

if [ -n "$CAT_ID" ]; then
    echo "Deleting existing fields in category $CAT_ID..."
    moodle_query "DELETE FROM mdl_user_info_field WHERE categoryid=$CAT_ID"
    echo "Deleting category $CAT_ID..."
    moodle_query "DELETE FROM mdl_user_info_category WHERE id=$CAT_ID"
fi

# Also clean by shortname to be safe
moodle_query "DELETE FROM mdl_user_info_field WHERE shortname IN ('employeeid', 'department', 'joblevel')"

# 2. Record initial counts
INITIAL_CAT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_user_info_category" | tr -d '[:space:]')
INITIAL_FIELD_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_user_info_field" | tr -d '[:space:]')

echo "$INITIAL_CAT_COUNT" > /tmp/initial_cat_count
echo "$INITIAL_FIELD_COUNT" > /tmp/initial_field_count

echo "Initial counts - Categories: $INITIAL_CAT_COUNT, Fields: $INITIAL_FIELD_COUNT"

# 3. Record start time
date +%s > /tmp/task_start_timestamp

# 4. Start Browser
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/moodle"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for and focus Firefox
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="