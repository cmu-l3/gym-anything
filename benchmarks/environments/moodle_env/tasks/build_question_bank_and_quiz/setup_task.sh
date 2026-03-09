#!/bin/bash
# Setup script for Build Question Bank and Quiz task

echo "=== Setting up Build Question Bank and Quiz Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils.sh did not provide them
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

echo "--- Creating MATH201 course and question bank categories via PHP CLI ---"

sudo -u www-data php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot . '/course/lib.php');

// Set up admin user context
global $USER;
$USER = get_admin();

// Get Engineering category (idnumber = 'ENG')
$eng_cat = $DB->get_record('course_categories', ['idnumber' => 'ENG']);
if ($eng_cat) {
    $eng_id = $eng_cat->id;
    echo "Engineering category id=$eng_id\n";
} else {
    // Fallback: try by name
    $eng_cat = $DB->get_record('course_categories', ['name' => 'Engineering']);
    $eng_id = $eng_cat ? $eng_cat->id : 1;
    echo "Engineering category (by name) id=$eng_id\n";
}

// Create MATH201 if it does not already exist
if (!$DB->record_exists('course', ['shortname' => 'MATH201'])) {
    $course = new stdClass();
    $course->fullname = 'Probability and Statistics';
    $course->shortname = 'MATH201';
    $course->category = $eng_id;
    $course->format = 'topics';
    $course->numsections = 10;
    $course->visible = 1;
    $course->startdate = mktime(0, 0, 0, 9, 1, 2025);
    $course->summary = 'Introduction to probability theory and statistical analysis, covering discrete and continuous distributions, hypothesis testing, regression, and Bayesian inference.';
    $course->summaryformat = FORMAT_HTML;
    $newcourse = create_course($course);
    echo "Created MATH201 id=" . $newcourse->id . "\n";
} else {
    echo "MATH201 already exists\n";
}

$course = $DB->get_record('course', ['shortname' => 'MATH201'], '*', MUST_EXIST);
$courseid = $course->id;
echo "MATH201 course id=$courseid\n";

// Get course context (contextlevel 50 = CONTEXT_COURSE)
$context = context_course::instance($courseid);
echo "Course context id=" . $context->id . "\n";

// Find the top-level (parent=0) question category for this context, which Moodle
// creates automatically when a course is created.  New user-visible categories
// should be children of that top-level category.
$topcat = $DB->get_record_sql(
    "SELECT * FROM {question_categories} WHERE contextid = ? AND parent = 0 ORDER BY id ASC LIMIT 1",
    [$context->id]
);
if (!$topcat) {
    // Create a top-level category if one does not exist yet
    $topcat = new stdClass();
    $topcat->name        = 'top';
    $topcat->contextid   = $context->id;
    $topcat->info        = '';
    $topcat->infoformat  = FORMAT_MOODLE;
    $topcat->sortorder   = 0;
    $topcat->stamp       = make_unique_id_code();
    $topcat->parent      = 0;
    $topcat->id          = $DB->insert_record('question_categories', $topcat);
    echo "Created top-level question category id=" . $topcat->id . "\n";
} else {
    echo "Top-level question category id=" . $topcat->id . "\n";
}

// Create the two named question bank categories as children of the top-level category
$cats_to_create = [
    'Probability Basics'    => 'Multiple-choice questions covering probability fundamentals.',
    'Descriptive Statistics' => 'True/False questions on descriptive statistics concepts.',
];

foreach ($cats_to_create as $catname => $catinfo) {
    if (!$DB->record_exists('question_categories', ['name' => $catname, 'contextid' => $context->id])) {
        $cat = new stdClass();
        $cat->name        = $catname;
        $cat->contextid   = $context->id;
        $cat->info        = $catinfo;
        $cat->infoformat  = FORMAT_MOODLE;
        $cat->sortorder   = 999;
        $cat->stamp       = make_unique_id_code();
        $cat->parent      = $topcat->id;
        $cat->id          = $DB->insert_record('question_categories', $cat);
        echo "Created question category: $catname (id=" . $cat->id . ")\n";
    } else {
        echo "Question category already exists: $catname\n";
    }
}

echo "SETUP_COMPLETE courseid=$courseid contextid=" . $context->id . "\n";
PHPEOF

PHP_EXIT=$?
if [ $PHP_EXIT -ne 0 ]; then
    echo "WARNING: PHP setup script exited with code $PHP_EXIT"
fi

# -------------------------------------------------------------------
# Save baseline state for use by the verifier
# -------------------------------------------------------------------
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='MATH201'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: MATH201 course not found after PHP setup!"
    exit 1
fi
echo "MATH201 Course ID: $COURSE_ID"

CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE instanceid=$COURSE_ID AND contextlevel=50" | tr -d '[:space:]')
if [ -z "$CONTEXT_ID" ]; then
    echo "ERROR: Course context not found for MATH201!"
    exit 1
fi
echo "MATH201 Context ID: $CONTEXT_ID"

PROB_CAT_ID=$(moodle_query "SELECT id FROM mdl_question_categories WHERE contextid=$CONTEXT_ID AND LOWER(name) LIKE '%probability basics%' LIMIT 1" | tr -d '[:space:]')
STAT_CAT_ID=$(moodle_query "SELECT id FROM mdl_question_categories WHERE contextid=$CONTEXT_ID AND LOWER(name) LIKE '%descriptive stat%' LIMIT 1" | tr -d '[:space:]')

echo "Probability Basics category ID: ${PROB_CAT_ID:-not found}"
echo "Descriptive Statistics category ID: ${STAT_CAT_ID:-not found}"

# Initial question counts in each category (should be 0 at setup time)
if [ -n "$PROB_CAT_ID" ] && [ -n "$STAT_CAT_ID" ]; then
    INITIAL_QUESTION_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_question WHERE category IN ($PROB_CAT_ID, $STAT_CAT_ID) AND qtype != 'random'" | tr -d '[:space:]')
else
    INITIAL_QUESTION_COUNT=0
fi

# Initial quiz count in MATH201
INITIAL_QUIZ_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz WHERE course=$COURSE_ID" | tr -d '[:space:]')

# Persist baselines
echo "$COURSE_ID"                        > /tmp/math201_course_id
echo "$CONTEXT_ID"                       > /tmp/math201_context_id
echo "${PROB_CAT_ID:-0}"                 > /tmp/math201_prob_cat_id
echo "${STAT_CAT_ID:-0}"                 > /tmp/math201_stat_cat_id
echo "${INITIAL_QUESTION_COUNT:-0}"      > /tmp/math201_initial_question_count
echo "${INITIAL_QUIZ_COUNT:-0}"          > /tmp/math201_initial_quiz_count
date +%s                                 > /tmp/task_start_timestamp

echo "Initial question count across both categories: ${INITIAL_QUESTION_COUNT:-0}"
echo "Initial quiz count in MATH201: ${INITIAL_QUIZ_COUNT:-0}"

# -------------------------------------------------------------------
# Ensure Firefox is running and showing Moodle
# -------------------------------------------------------------------
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window to appear
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected within 30 seconds"
fi

# Focus and maximise Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
