#!/bin/bash
# Setup script for Configure Completion Tracking task

echo "=== Setting up Configure Completion Tracking Task ==="

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

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found!"
    exit 1
fi
echo "BIO101 Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/target_course_id

# Record initial state: Is completion already enabled?
INITIAL_COMPLETION_ENABLED=$(moodle_query "SELECT enablecompletion FROM mdl_course WHERE id=$COURSE_ID" | tr -d '[:space:]')
echo "${INITIAL_COMPLETION_ENABLED:-0}" > /tmp/initial_completion_enabled

# Record initial page count
INITIAL_PAGE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_page WHERE course=$COURSE_ID" | tr -d '[:space:]')
echo "${INITIAL_PAGE_COUNT:-0}" > /tmp/initial_page_count

# Record initial course completion criteria count
INITIAL_CRITERIA_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_completion_criteria WHERE course=$COURSE_ID" | tr -d '[:space:]')
echo "${INITIAL_CRITERIA_COUNT:-0}" > /tmp/initial_criteria_count

echo "Initial State: Enabled=$INITIAL_COMPLETION_ENABLED, Pages=$INITIAL_PAGE_COUNT, Criteria=$INITIAL_CRITERIA_COUNT"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="