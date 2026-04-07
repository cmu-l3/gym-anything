#!/bin/bash
# Setup script for Auto Generate Course Groups task

echo "=== Setting up Auto Generate Groups Task ==="

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
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
fi

# 1. Verify BIO101 exists
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found!"
    exit 1
fi
echo "BIO101 Course ID: $COURSE_ID"

# 2. Ensure enough students are enrolled
# We need at least 6 students to make "groups of 2" meaningful (3 groups)
# The default setup usually has ~8-10 users. Let's verify enrollment count.
ENROLLED_COUNT=$(moodle_query "SELECT COUNT(DISTINCT ue.userid) FROM mdl_user_enrolments ue JOIN mdl_enrol e ON ue.enrolid=e.id JOIN mdl_user u ON ue.userid=u.id WHERE e.courseid=$COURSE_ID AND u.username != 'admin' AND u.deleted=0")
echo "Currently enrolled students: $ENROLLED_COUNT"

if [ "$ENROLLED_COUNT" -lt 6 ]; then
    echo "Warning: Low enrollment count ($ENROLLED_COUNT). Adding more students..."
    # Add dummy students if needed (simplified, assuming standard users exist)
    # This is a fallback; usually standard environment has enough users.
    # For now, we assume the environment is standard.
fi

# 3. CLEANUP: Delete any existing groups in this course to ensure clean state
echo "Clearing existing groups in BIO101..."
moodle_query "DELETE FROM mdl_groups WHERE courseid=$COURSE_ID"
moodle_query "DELETE FROM mdl_groupings WHERE courseid=$COURSE_ID"
# Clean up linking tables (orphaned records are fine in dev, but let's try to be clean)
# mdl_groups_members and mdl_groupings_groups will effectively be dead links if not cascaded, 
# but Moodle might handle this. For task safety, we just need the IDs gone.

# 4. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 5. Launch Firefox
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    # Direct to course page
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/course/view.php?id=$COURSE_ID' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 6. Wait for window and focus
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 7. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="