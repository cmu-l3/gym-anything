#!/bin/bash
# Setup script for Configure Activity Groupings task

echo "=== Setting up Configure Activity Groupings Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type moodle_query &>/dev/null; then
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

# 1. Get Course ID for BIO101
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found!"
    exit 1
fi
echo "BIO101 Course ID: $COURSE_ID"

# 2. Ensure prerequisite groups exist: "Monday Lab" and "Thursday Lab"
echo "Checking/Creating prerequisite groups..."

for GNAME in "Monday Lab" "Thursday Lab"; do
    EXISTS=$(moodle_query "SELECT id FROM mdl_groups WHERE courseid=$COURSE_ID AND name='$GNAME'" | tr -d '[:space:]')
    if [ -z "$EXISTS" ]; then
        echo "Creating group: $GNAME"
        # Insert group directly
        moodle_query "INSERT INTO mdl_groups (courseid, name, description, descriptionformat, timecreated, timemodified) VALUES ($COURSE_ID, '$GNAME', '', 1, UNIX_TIMESTAMP(), UNIX_TIMESTAMP())"
    else
        echo "Group '$GNAME' already exists (ID: $EXISTS)"
    fi
done

# 3. Record Initial State
INITIAL_GROUPING_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_groupings WHERE courseid=$COURSE_ID" | tr -d '[:space:]')
INITIAL_ASSIGN_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_assign WHERE course=$COURSE_ID" | tr -d '[:space:]')
echo "$INITIAL_GROUPING_COUNT" > /tmp/initial_grouping_count
echo "$INITIAL_ASSIGN_COUNT" > /tmp/initial_assign_count
date +%s > /tmp/task_start_timestamp

echo "Initial state: Groupings=$INITIAL_GROUPING_COUNT, Assignments=$INITIAL_ASSIGN_COUNT"

# 4. Start Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/moodle/course/view.php?id=$COURSE_ID"
if ! pgrep -f firefox > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 5. Wait for and focus window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="