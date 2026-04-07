#!/bin/bash
# Setup script for Create Manual Grades task

echo "=== Setting up Create Manual Grades Task ==="

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

# 1. Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found!"
    exit 1
fi
echo "BIO101 Course ID: $COURSE_ID"

# 2. Ensure students are enrolled in BIO101
echo "Ensuring students are enrolled..."
STUDENTS=("jsmith" "mjones" "awilson" "bbrown")
ROLE_ID=$(moodle_query "SELECT id FROM mdl_role WHERE shortname='student'" | tr -d '[:space:]')
CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')
ENROL_ID=$(moodle_query "SELECT id FROM mdl_enrol WHERE courseid=$COURSE_ID AND enrol='manual'" | tr -d '[:space:]')

# Create manual enrolment instance if not exists
if [ -z "$ENROL_ID" ]; then
    # This is complex via raw SQL, assuming manual enrolment exists from install
    # Fallback to just grabbing the first enrolment method
    ENROL_ID=$(moodle_query "SELECT id FROM mdl_enrol WHERE courseid=$COURSE_ID LIMIT 1" | tr -d '[:space:]')
fi

for USERNAME in "${STUDENTS[@]}"; do
    USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='$USERNAME'" | tr -d '[:space:]')
    if [ -n "$USER_ID" ]; then
        # Check enrolment
        IS_ENROLLED=$(moodle_query "SELECT COUNT(*) FROM mdl_user_enrolments WHERE userid=$USER_ID AND enrolid=$ENROL_ID" | tr -d '[:space:]')
        if [ "$IS_ENROLLED" -eq "0" ]; then
            echo "Enrolling $USERNAME (ID: $USER_ID)..."
            # Add to user_enrolments
            moodle_query "INSERT INTO mdl_user_enrolments (status, enrolid, userid, timestart, timeend, modifierid, timecreated, timemodified) VALUES (0, $ENROL_ID, $USER_ID, $(date +%s), 0, 2, $(date +%s), $(date +%s))"
            # Add role assignment
            moodle_query "INSERT INTO mdl_role_assignments (roleid, contextid, userid, timemodified, modifierid) VALUES ($ROLE_ID, $CONTEXT_ID, $USER_ID, $(date +%s), 2)"
        else
            echo "$USERNAME already enrolled."
        fi
    else
        echo "WARNING: User $USERNAME not found!"
    fi
done

# 3. Record baseline grade item count for this course
INITIAL_ITEM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemtype='manual'" | tr -d '[:space:]')
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count
echo "Initial manual grade items in BIO101: $INITIAL_ITEM_COUNT"

# 4. Record task start timestamp
date +%s > /tmp/task_start_timestamp

# 5. Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 6. Wait for and focus Firefox
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