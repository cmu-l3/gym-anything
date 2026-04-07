#!/bin/bash
# Setup script for Configure Course Requests task

echo "=== Setting up Configure Course Requests Task ==="

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

# 1. Resolve IDs for verification later
# We need the ID of the 'Science' category and 'teacher1' user to verify the final state accurately.
echo "Resolving reference IDs..."

SCIENCE_CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science'" | tr -d '[:space:]')
if [ -z "$SCIENCE_CAT_ID" ]; then
    echo "ERROR: 'Science' category not found. Creating it..."
    # Fallback creation if setup_moodle.sh didn't create it
    moodle_query "INSERT INTO mdl_course_categories (name, idnumber, description, parent, sortorder, visible, timemodified, depth, path) VALUES ('Science', 'SCI', 'Science Department', 0, 10000, 1, UNIX_TIMESTAMP(), 1, '/')"
    SCIENCE_CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science'" | tr -d '[:space:]')
fi
echo "$SCIENCE_CAT_ID" > /tmp/ref_science_cat_id
echo "Reference Science Category ID: $SCIENCE_CAT_ID"

TEACHER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='teacher1'" | tr -d '[:space:]')
if [ -z "$TEACHER_ID" ]; then
    echo "ERROR: User 'teacher1' not found!"
    exit 1
fi
echo "$TEACHER_ID" > /tmp/ref_teacher_id
echo "Reference Teacher ID: $TEACHER_ID"

# 2. Record initial state (Baseline)
# Check if requests are currently enabled (should be 0 or empty)
INITIAL_ENABLED=$(moodle_query "SELECT value FROM mdl_config WHERE name='enablecourserequests'" | tr -d '[:space:]')
echo "${INITIAL_ENABLED:-0}" > /tmp/initial_enabled_state

# Count existing requests
INITIAL_REQUEST_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_request" | tr -d '[:space:]')
echo "${INITIAL_REQUEST_COUNT:-0}" > /tmp/initial_request_count

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 3. Ensure browser environment
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
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

# 4. Capture initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="