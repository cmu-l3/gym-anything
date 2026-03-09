#!/bin/bash
# Setup script for Setup Cohort Enrollment task

echo "=== Setting up Cohort Enrollment Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
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

echo "--- Creating engineering student users and ENG110 course via PHP CLI ---"

sudo -u www-data php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->dirroot . '/course/lib.php');

// Set up admin user context
global $USER;
$USER = get_admin();

// Create 5 engineering students
$new_users = [
    ['username' => 'eng_alice', 'firstname' => 'Alice',  'lastname' => 'Chen',     'email' => 'alice.chen@example.com'],
    ['username' => 'eng_bob',   'firstname' => 'Bob',    'lastname' => 'Martinez', 'email' => 'bob.martinez@example.com'],
    ['username' => 'eng_carol', 'firstname' => 'Carol',  'lastname' => 'Kim',      'email' => 'carol.kim@example.com'],
    ['username' => 'eng_dave',  'firstname' => 'Dave',   'lastname' => 'Patel',    'email' => 'dave.patel@example.com'],
    ['username' => 'eng_emma',  'firstname' => 'Emma',   'lastname' => 'Johnson',  'email' => 'emma.johnson@example.com'],
];

foreach ($new_users as $u) {
    if (!$DB->record_exists('user', ['username' => $u['username']])) {
        $user = new stdClass();
        $user->username   = $u['username'];
        $user->firstname  = $u['firstname'];
        $user->lastname   = $u['lastname'];
        $user->email      = $u['email'];
        $user->password   = 'Student1234!';
        $user->auth       = 'manual';
        $user->confirmed  = 1;
        $user->mnethostid = $CFG->mnet_localhost_id;
        $id = user_create_user($user, true, false);
        echo "Created user: {$u['username']} (id=$id)\n";
    } else {
        $existing = $DB->get_record('user', ['username' => $u['username']], 'id');
        echo "User already exists: {$u['username']} (id={$existing->id})\n";
    }
}

// Get Engineering category (idnumber ENG)
$eng_cat = $DB->get_record('course_categories', ['idnumber' => 'ENG']);
$eng_id  = $eng_cat ? $eng_cat->id : 1;
echo "Engineering category id=$eng_id\n";

// Create ENG110 if it does not already exist
if (!$DB->record_exists('course', ['shortname' => 'ENG110'])) {
    $course = new stdClass();
    $course->fullname      = 'Introduction to Engineering';
    $course->shortname     = 'ENG110';
    $course->category      = $eng_id;
    $course->format        = 'topics';
    $course->numsections   = 12;
    $course->visible       = 1;
    $course->startdate     = mktime(0, 0, 0, 9, 1, 2025);
    $course->summary       = 'Introduction to engineering principles, design methodology, professional practice, and problem-solving techniques across engineering disciplines.';
    $course->summaryformat = FORMAT_HTML;
    $newcourse = create_course($course);
    echo "Created ENG110 id=" . $newcourse->id . "\n";
} else {
    $existing = $DB->get_record('course', ['shortname' => 'ENG110'], 'id');
    echo "ENG110 already exists (id={$existing->id})\n";
}

// Ensure the cohort enrolment plugin is enabled (status=0 means enabled in mdl_enrol_plugins)
// In Moodle 4.x, the cohort plugin is active by default; we verify it is available.
$cohort_plugin = enrol_get_plugin('cohort');
if ($cohort_plugin) {
    echo "Cohort enrollment plugin is available\n";
} else {
    echo "WARNING: Cohort enrollment plugin not available\n";
}

// Verify CS110 exists
if ($DB->record_exists('course', ['shortname' => 'CS110'])) {
    $cs110 = $DB->get_record('course', ['shortname' => 'CS110'], 'id');
    echo "CS110 found (id={$cs110->id})\n";
} else {
    echo "WARNING: CS110 course not found\n";
}

echo "SETUP_COMPLETE\n";
PHPEOF

PHP_EXIT=$?
if [ $PHP_EXIT -ne 0 ]; then
    echo "WARNING: PHP setup exited with code $PHP_EXIT"
fi

# ------------------------------------------------------------------
# Save baseline state for the verifier
# ------------------------------------------------------------------

# Save user IDs for the 5 new engineering students
rm -f /tmp/eng_cohort_users.txt
for UNAME in eng_alice eng_bob eng_carol eng_dave eng_emma; do
    UID=$(moodle_query "SELECT id FROM mdl_user WHERE username='$UNAME'" | tr -d '[:space:]')
    if [ -z "$UID" ]; then
        echo "WARNING: User $UNAME not found after PHP setup"
    else
        echo "$UNAME:$UID" >> /tmp/eng_cohort_users.txt
        echo "Saved $UNAME (id=$UID)"
    fi
done

# Record initial cohort count (no cohorts should exist yet)
INITIAL_COHORT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort" | tr -d '[:space:]')
echo "${INITIAL_COHORT_COUNT:-0}" > /tmp/initial_cohort_count
echo "Initial cohort count: ${INITIAL_COHORT_COUNT:-0}"

# Save course IDs
CS110_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CS110'" | tr -d '[:space:]')
ENG110_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='ENG110'" | tr -d '[:space:]')

if [ -z "$CS110_ID" ]; then
    echo "ERROR: CS110 course not found!"
    exit 1
fi
if [ -z "$ENG110_ID" ]; then
    echo "ERROR: ENG110 course not found after PHP setup!"
    exit 1
fi

echo "$CS110_ID"  > /tmp/cs110_course_id
echo "$ENG110_ID" > /tmp/eng110_course_id
echo "CS110 id=$CS110_ID, ENG110 id=$ENG110_ID"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ------------------------------------------------------------------
# Ensure Firefox is running and focused
# ------------------------------------------------------------------
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

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
