#!/bin/bash
# Setup script for Create Forum with Discussion task

echo "=== Setting up Create Forum Task ==="

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
date +%s > /tmp/task_start_time.txt

# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found!"
    # Attempt to proceed (maybe creating it isn't strictly required if ID 0 is handled, but usually fatal)
    echo "0" > /tmp/target_course_id
else
    echo "BIO101 Course ID: $COURSE_ID"
    echo "$COURSE_ID" > /tmp/target_course_id
fi

# Record initial forum count for this course
INITIAL_FORUM_COUNT="0"
if [ -n "$COURSE_ID" ]; then
    INITIAL_FORUM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_forum WHERE course=$COURSE_ID" | tr -d '[:space:]')
fi
echo "$INITIAL_FORUM_COUNT" > /tmp/initial_forum_count
echo "Initial forum count in BIO101: $INITIAL_FORUM_COUNT"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/moodle/course/view.php?id=$COURSE_ID"
if [ -z "$COURSE_ID" ]; then
    MOODLE_URL="http://localhost/moodle/"
fi

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="