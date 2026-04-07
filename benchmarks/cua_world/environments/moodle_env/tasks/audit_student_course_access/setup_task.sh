#!/bin/bash
# Setup script for Audit Student Course Access task

echo "=== Setting up Audit Student Course Access Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# 1. Ensure Moodle DB functions are available
if ! type moodle_query &>/dev/null; then
    echo "Defining fallback Moodle query functions..."
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
fi

# 2. Verify/Create Course BIO101
echo "Checking for BIO101..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    echo "Creating BIO101..."
    # Insert course
    CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories LIMIT 1" | tr -d '[:space:]')
    NOW=$(date +%s)
    moodle_query "INSERT INTO mdl_course (category, fullname, shortname, summary, format, startdate, timecreated, timemodified) VALUES ($CAT_ID, 'Introduction to Biology', 'BIO101', 'Introductory Biology Course', 'topics', $NOW, $NOW, $NOW)"
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
fi
echo "Target Course ID: $COURSE_ID"

# 3. Verify/Create User Jane Smith
echo "Checking for Jane Smith..."
USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='jsmith'" | tr -d '[:space:]')
if [ -z "$USER_ID" ]; then
    echo "Creating user jsmith..."
    moodle_query "INSERT INTO mdl_user (auth, confirmed, policyagreed, deleted, mnethostid, username, password, firstname, lastname, email) VALUES ('manual', 1, 0, 0, 1, 'jsmith', 'password', 'Jane', 'Smith', 'jsmith@example.com')"
    USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='jsmith'" | tr -d '[:space:]')
fi
echo "Target User ID: $USER_ID"

# 4. Ensure Enrollment
ENROL_ID=$(moodle_query "SELECT id FROM mdl_enrol WHERE courseid=$COURSE_ID AND enrol='manual'" | tr -d '[:space:]')
if [ -z "$ENROL_ID" ]; then
    moodle_query "INSERT INTO mdl_enrol (enrol, status, courseid) VALUES ('manual', 0, $COURSE_ID)"
    ENROL_ID=$(moodle_query "SELECT id FROM mdl_enrol WHERE courseid=$COURSE_ID AND enrol='manual'" | tr -d '[:space:]')
fi

IS_ENROLLED=$(moodle_query "SELECT COUNT(*) FROM mdl_user_enrolments WHERE enrolid=$ENROL_ID AND userid=$USER_ID" | tr -d '[:space:]')
if [ "$IS_ENROLLED" -eq "0" ]; then
    echo "Enrolling jsmith in BIO101..."
    NOW=$(date +%s)
    moodle_query "INSERT INTO mdl_user_enrolments (status, enrolid, userid, timestart, timeend, timecreated, timemodified) VALUES (0, $ENROL_ID, $USER_ID, $NOW, 0, $NOW, $NOW)"
fi

# 5. Inject Log Entry for TODAY
# We need to simulate that Jane Smith viewed the course today.
echo "Injecting activity log..."
CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')
if [ -z "$CONTEXT_ID" ]; then
    # Create context if missing (unlikely but safe)
    moodle_query "INSERT INTO mdl_context (contextlevel, instanceid) VALUES (50, $COURSE_ID)"
    CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')
fi

CURRENT_TIME=$(date +%s)
# Insert into standard log
# Event: \core\event\course_viewed
moodle_query "INSERT INTO mdl_logstore_standard_log (eventname, component, action, target, objecttable, objectid, crud, edulevel, contextid, contextlevel, instanceid, userid, courseid, relateduserid, anonymous, other, timecreated, origin, ip, realuserid) VALUES ('\\\\core\\\\event\\\\course_viewed', 'core', 'viewed', 'course', NULL, NULL, 'r', 2, $CONTEXT_ID, 50, $COURSE_ID, $USER_ID, $COURSE_ID, NULL, 0, 'N;', $CURRENT_TIME, 'web', '127.0.0.1', NULL)"

echo "Log injected for User $USER_ID in Course $COURSE_ID at time $CURRENT_TIME"

# 6. Clean up previous artifacts
rm -f /home/ga/Documents/audit_evidence.xlsx
rm -f /home/ga/Documents/verdict.txt
date +%s > /tmp/task_start_timestamp

# 7. Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait and Focus
if [ -n "$(which wmctrl)" ]; then
    # Wait loop
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then break; fi
        sleep 1
    done
    # Focus
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Initial Screenshot
if [ -n "$(which scrot)" ]; then
    DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="