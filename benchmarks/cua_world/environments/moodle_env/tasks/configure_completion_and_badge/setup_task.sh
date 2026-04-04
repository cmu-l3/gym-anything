#!/bin/bash
# Setup script for Configure Completion and Badge task
# Creates BIO302 Advanced Cell Biology with 5 activities (no completion configured).

echo "=== Setting up Configure Completion and Badge Task ==="

# ---------------------------------------------------------------------------
# Source shared utilities with fallback inline definitions
# ---------------------------------------------------------------------------
if [ -f /workspace/scripts/task_utils.sh ]; then
    . /workspace/scripts/task_utils.sh
else
    echo "Warning: /workspace/scripts/task_utils.sh not found, using inline definitions"
fi

if ! type moodle_query &>/dev/null 2>&1; then
    echo "Warning: moodle_query not available from task_utils.sh, defining inline"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method
        method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
fi

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
fi

if ! type wait_for_window &>/dev/null 2>&1; then
    wait_for_window() {
        local window_pattern="$1"
        local timeout="${2:-30}"
        local elapsed=0
        while [ "$elapsed" -lt "$timeout" ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then return 0; fi
            sleep 1
            elapsed=$((elapsed + 1))
        done
        return 1
    }
fi

if ! type get_firefox_window_id &>/dev/null 2>&1; then
    get_firefox_window_id() {
        DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
    }
fi

if ! type focus_window &>/dev/null 2>&1; then
    focus_window() {
        DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true
        sleep 0.3
    }
fi

# ---------------------------------------------------------------------------
# Enable completion tracking globally and create BIO302 with 5 activities
# ---------------------------------------------------------------------------
echo "Running PHP setup script to create BIO302 course and activities..."

sudo -u www-data php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot . '/course/lib.php');

// Set up admin user context (required for module creation events)
global $USER;
$USER = get_admin();

// Enable completion tracking globally
set_config('enablecompletion', 1);
echo "Completion tracking enabled globally\n";

// Get Science category
$sci_cat = $DB->get_record('course_categories', ['idnumber' => 'SCI']);
$sci_id = $sci_cat ? $sci_cat->id : 1;
echo "Science category id=$sci_id\n";

// Create BIO302 if not exists; ensure enablecompletion=1 either way
if (!$DB->record_exists('course', ['shortname' => 'BIO302'])) {
    $course = new stdClass();
    $course->fullname         = 'Advanced Cell Biology';
    $course->shortname        = 'BIO302';
    $course->category         = $sci_id;
    $course->format           = 'topics';
    $course->numsections      = 8;
    $course->visible          = 1;
    $course->enablecompletion = 1;
    $course->startdate        = mktime(0, 0, 0, 9, 1, 2025);
    $course->summary          = 'Advanced study of cell biology including membrane dynamics, intracellular transport, cell signaling, and molecular mechanisms of cellular processes.';
    $course->summaryformat    = FORMAT_HTML;
    $newcourse = create_course($course);
    echo "Created BIO302 id=" . $newcourse->id . "\n";
} else {
    // Ensure completion tracking is on for the existing course
    $DB->set_field('course', 'enablecompletion', 1, ['shortname' => 'BIO302']);
    echo "BIO302 already exists; ensured enablecompletion=1\n";
}

$course   = $DB->get_record('course', ['shortname' => 'BIO302'], '*', MUST_EXIST);
$courseid = $course->id;
echo "Working with course id=$courseid\n";

// Get module records
$page_module   = $DB->get_record('modules', ['name' => 'page'],   '*', MUST_EXIST);
$assign_module = $DB->get_record('modules', ['name' => 'assign'], '*', MUST_EXIST);
$quiz_module   = $DB->get_record('modules', ['name' => 'quiz'],   '*', MUST_EXIST);
$forum_module  = $DB->get_record('modules', ['name' => 'forum'],  '*', MUST_EXIST);

// ----------------------------------------------------------------
// Activity 1: Page – "Lab Safety and Ethics Module"
// ----------------------------------------------------------------
if (!$DB->record_exists('page', ['course' => $courseid, 'name' => 'Lab Safety and Ethics Module'])) {
    $page = new stdClass();
    $page->course = $courseid;
    $page->name = 'Lab Safety and Ethics Module';
    $page->intro = 'This module covers essential laboratory safety protocols and research ethics guidelines.';
    $page->introformat = FORMAT_HTML;
    $page->content = '<h2>Laboratory Safety Guidelines</h2><p>Always wear appropriate PPE including lab coat, safety goggles, and gloves when working with biological materials. All research must comply with institutional review board guidelines.</p>';
    $page->contentformat = FORMAT_HTML;
    $page->legacyfiles = 0; $page->display = 0; $page->displayoptions = '';
    $page->revision = 1; $page->timemodified = time();
    try {
        require_once($CFG->dirroot . '/mod/page/lib.php');
        $page->id = page_add_instance($page, null);
        echo "Page created via API (id=" . $page->id . ")\n";
    } catch (Throwable $e) {
        $page->id = $DB->insert_record('page', $page);
        echo "Page created via direct insert (id=" . $page->id . ") fallback: " . $e->getMessage() . "\n";
    }
    $cm = new stdClass();
    $cm->course = $courseid; $cm->module = $page_module->id; $cm->instance = $page->id;
    $cm->visible = 1; $cm->completion = 0; $cm->completionview = 0;
    $cmid = add_course_module($cm);
    course_add_cm_to_section($course, $cmid, 1);
    context_module::instance($cmid);
    echo "Created Page: Lab Safety and Ethics Module (cmid=$cmid)\n";
} else {
    echo "Page 'Lab Safety and Ethics Module' already exists\n";
}

// ----------------------------------------------------------------
// Activity 2: Assignment – "Cell Membrane Transport Lab"
// ----------------------------------------------------------------
if (!$DB->record_exists('assign', ['course' => $courseid, 'name' => 'Cell Membrane Transport Lab'])) {
    $assign = new stdClass();
    $assign->course = $courseid; $assign->name = 'Cell Membrane Transport Lab';
    $assign->intro = 'Conduct the virtual cell membrane transport experiment and submit your lab report.';
    $assign->introformat = FORMAT_HTML; $assign->alwaysshowdescription = 1;
    $assign->submissiondrafts = 0; $assign->sendnotifications = 0;
    $assign->sendlatenotifications = 0; $assign->sendstudentnotifications = 1;
    $assign->duedate = 0; $assign->allowsubmissionsfromdate = 0;
    $assign->cutoffdate = 0; $assign->gradingduedate = 0;
    $assign->grade = 100; $assign->timemodified = time();
    $assign->completionsubmit = 0; $assign->requiresubmissionstatement = 0;
    $assign->teamsubmission = 0; $assign->requireallteammemberssubmit = 0;
    $assign->teamsubmissiongroupingid = 0; $assign->blindmarking = 0;
    $assign->hidegrader = 0; $assign->revealidentities = 0;
    $assign->attemptreopenmethod = 'none'; $assign->maxattempts = -1;
    $assign->markingworkflow = 0; $assign->markingallocation = 0;
    try {
        require_once($CFG->dirroot . '/mod/assign/lib.php');
        $assign->id = assign_add_instance($assign, null);
        echo "Assignment 'Cell Membrane Transport Lab' created via API\n";
    } catch (Throwable $e) {
        $assign->id = $DB->insert_record('assign', $assign);
        echo "Assignment 'Cell Membrane Transport Lab' via direct insert fallback: " . $e->getMessage() . "\n";
    }
    $cm = new stdClass();
    $cm->course = $courseid; $cm->module = $assign_module->id; $cm->instance = $assign->id;
    $cm->visible = 1; $cm->completion = 0;
    $cmid = add_course_module($cm);
    course_add_cm_to_section($course, $cmid, 2);
    context_module::instance($cmid);
    echo "Created Assignment: Cell Membrane Transport Lab (cmid=$cmid)\n";
} else {
    echo "Assignment 'Cell Membrane Transport Lab' already exists\n";
}

// ----------------------------------------------------------------
// Activity 3: Quiz – "Molecular Biology Quiz"
// ----------------------------------------------------------------
if (!$DB->record_exists('quiz', ['course' => $courseid, 'name' => 'Molecular Biology Quiz'])) {
    $quiz = new stdClass();
    $quiz->course = $courseid; $quiz->name = 'Molecular Biology Quiz';
    $quiz->intro = 'Test your knowledge of molecular biology concepts. You have 45 minutes and two attempts.';
    $quiz->introformat = FORMAT_HTML;
    $quiz->timeopen = 0; $quiz->timeclose = 0; $quiz->timelimit = 2700;
    $quiz->overduehandling = 'autosubmit'; $quiz->graceperiod = 0;
    $quiz->attempts = 2; $quiz->grademethod = 1;
    $quiz->decimalpoints = 2; $quiz->questiondecimalpoints = -1;
    $quiz->reviewattempt = 0; $quiz->reviewcorrectness = 0; $quiz->reviewmarks = 0;
    $quiz->reviewspecificfeedback = 0; $quiz->reviewgeneralfeedback = 0;
    $quiz->reviewrightanswer = 0; $quiz->reviewmanualcomment = 0;
    $quiz->reviewoverallfeedback = 0; $quiz->attemptonlast = 0;
    $quiz->questionsperpage = 5; $quiz->navmethod = 'free';
    $quiz->shuffleanswers = 1; $quiz->sumgrades = 0.0; $quiz->grade = 100.0;
    $quiz->timecreated = time(); $quiz->timemodified = time();
    $quiz->password = ''; $quiz->subnet = ''; $quiz->browsersecurity = '-';
    $quiz->delay1 = 0; $quiz->delay2 = 0; $quiz->showuserpicture = 0; $quiz->showblocks = 0;
    $quiz->preferredbehaviour = 'deferredfeedback'; $quiz->canredoquestions = 0;
    $quiz->completionattemptsexhausted = 0; $quiz->completionminattempts = 0;
    // Build a clean quiz record with only known-safe fields for direct insert fallback
    $quiz_clean = new stdClass();
    $quiz_clean->course = $quiz->course; $quiz_clean->name = $quiz->name;
    $quiz_clean->intro = $quiz->intro; $quiz_clean->introformat = $quiz->introformat;
    $quiz_clean->timeopen = $quiz->timeopen; $quiz_clean->timeclose = $quiz->timeclose;
    $quiz_clean->timelimit = $quiz->timelimit; $quiz_clean->overduehandling = $quiz->overduehandling;
    $quiz_clean->graceperiod = $quiz->graceperiod; $quiz_clean->attempts = $quiz->attempts;
    $quiz_clean->grademethod = $quiz->grademethod; $quiz_clean->decimalpoints = $quiz->decimalpoints;
    $quiz_clean->questiondecimalpoints = $quiz->questiondecimalpoints;
    $quiz_clean->reviewattempt = $quiz->reviewattempt; $quiz_clean->reviewcorrectness = $quiz->reviewcorrectness;
    $quiz_clean->reviewmarks = $quiz->reviewmarks; $quiz_clean->reviewspecificfeedback = $quiz->reviewspecificfeedback;
    $quiz_clean->reviewgeneralfeedback = $quiz->reviewgeneralfeedback;
    $quiz_clean->reviewrightanswer = $quiz->reviewrightanswer; $quiz_clean->reviewmanualcomment = $quiz->reviewmanualcomment;
    $quiz_clean->reviewoverallfeedback = $quiz->reviewoverallfeedback;
    $quiz_clean->attemptonlast = $quiz->attemptonlast;
    $quiz_clean->questionsperpage = $quiz->questionsperpage; $quiz_clean->navmethod = $quiz->navmethod;
    $quiz_clean->shuffleanswers = $quiz->shuffleanswers; $quiz_clean->sumgrades = $quiz->sumgrades;
    $quiz_clean->grade = $quiz->grade; $quiz_clean->timecreated = $quiz->timecreated;
    $quiz_clean->timemodified = $quiz->timemodified; $quiz_clean->password = $quiz->password;
    $quiz_clean->subnet = $quiz->subnet; $quiz_clean->browsersecurity = $quiz->browsersecurity;
    $quiz_clean->delay1 = $quiz->delay1; $quiz_clean->delay2 = $quiz->delay2;
    $quiz_clean->showuserpicture = $quiz->showuserpicture; $quiz_clean->showblocks = $quiz->showblocks;
    $quiz_clean->preferredbehaviour = $quiz->preferredbehaviour; $quiz_clean->canredoquestions = $quiz->canredoquestions;
    $quiz_clean->completionattemptsexhausted = $quiz->completionattemptsexhausted;
    $quiz_clean->completionminattempts = $quiz->completionminattempts;
    $quiz->id = 0;
    try {
        require_once($CFG->dirroot . '/mod/quiz/lib.php');
        $quiz->id = quiz_add_instance($quiz, null);
        echo "Quiz created via API\n";
    } catch (Throwable $e) {
        echo "Quiz API failed: " . $e->getMessage() . "\n";
        try {
            $quiz->id = $DB->insert_record('quiz', $quiz_clean);
            echo "Quiz created via direct insert\n";
        } catch (Throwable $e2) {
            echo "Quiz direct insert also failed: " . $e2->getMessage() . "\n";
        }
    }
    if ($quiz->id) {
        $cm = new stdClass();
        $cm->course = $courseid; $cm->module = $quiz_module->id; $cm->instance = $quiz->id;
        $cm->visible = 1; $cm->completion = 0; $cm->completionusegrade = 0; $cm->completionpassgrade = 0;
        $cmid = add_course_module($cm);
        course_add_cm_to_section($course, $cmid, 3);
        context_module::instance($cmid);
        echo "Created Quiz: Molecular Biology Quiz (cmid=$cmid)\n";
    } else {
        echo "WARNING: Quiz creation failed, skipping course module\n";
    }
} else {
    echo "Quiz 'Molecular Biology Quiz' already exists\n";
}

// ----------------------------------------------------------------
// Activity 4: Forum – "Research Discussion Forum"
// ----------------------------------------------------------------
if (!$DB->record_exists('forum', ['course' => $courseid, 'name' => 'Research Discussion Forum'])) {
    $forum = new stdClass();
    $forum->course = $courseid; $forum->type = 'general';
    $forum->name = 'Research Discussion Forum';
    $forum->intro = "Use this forum to share research findings and discuss current developments in cell biology.";
    $forum->introformat = FORMAT_HTML;
    $forum->assessed = 0; $forum->assesstimestart = 0; $forum->assesstimefinish = 0;
    $forum->scale = 100; $forum->maxbytes = 512000; $forum->maxattachments = 9;
    $forum->forcesubscribe = 0; $forum->trackingtype = 1;
    $forum->rsstype = 0; $forum->rssarticles = 0; $forum->timemodified = time();
    $forum->warnafter = 0; $forum->blockafter = 0; $forum->blockperiod = 0;
    $forum->completiondiscussions = 0; $forum->completionreplies = 0; $forum->completionposts = 0;
    $forum->displaywordcount = 0; $forum->lockdiscussionafter = 0;
    $forum->id = 0;
    try {
        require_once($CFG->dirroot . '/mod/forum/lib.php');
        $forum->id = forum_add_instance($forum, null);
        echo "Forum created via API\n";
    } catch (Throwable $e) {
        echo "Forum API failed: " . $e->getMessage() . "\n";
        try {
            $forum->id = $DB->insert_record('forum', $forum);
            echo "Forum created via direct insert\n";
        } catch (Throwable $e2) {
            echo "Forum direct insert also failed: " . $e2->getMessage() . "\n";
        }
    }
    if ($forum->id) {
        $cm = new stdClass();
        $cm->course = $courseid; $cm->module = $forum_module->id; $cm->instance = $forum->id;
        $cm->visible = 1; $cm->completion = 0;
        $cmid = add_course_module($cm);
        course_add_cm_to_section($course, $cmid, 4);
        context_module::instance($cmid);
        echo "Created Forum: Research Discussion Forum (cmid=$cmid)\n";
    } else {
        echo "WARNING: Forum creation failed, skipping course module\n";
    }
} else {
    echo "Forum 'Research Discussion Forum' already exists\n";
}

// ----------------------------------------------------------------
// Activity 5: Assignment – "Final Research Report"
// ----------------------------------------------------------------
if (!$DB->record_exists('assign', ['course' => $courseid, 'name' => 'Final Research Report'])) {
    $assign2 = new stdClass();
    $assign2->course = $courseid; $assign2->name = 'Final Research Report';
    $assign2->intro = 'Submit your final research report on an advanced cell biology topic.';
    $assign2->introformat = FORMAT_HTML; $assign2->alwaysshowdescription = 1;
    $assign2->submissiondrafts = 0; $assign2->sendnotifications = 0;
    $assign2->sendlatenotifications = 0; $assign2->sendstudentnotifications = 1;
    $assign2->duedate = 0; $assign2->allowsubmissionsfromdate = 0;
    $assign2->cutoffdate = 0; $assign2->gradingduedate = 0;
    $assign2->grade = 100; $assign2->timemodified = time();
    $assign2->completionsubmit = 0; $assign2->requiresubmissionstatement = 0;
    $assign2->teamsubmission = 0; $assign2->requireallteammemberssubmit = 0;
    $assign2->teamsubmissiongroupingid = 0; $assign2->blindmarking = 0;
    $assign2->hidegrader = 0; $assign2->revealidentities = 0;
    $assign2->attemptreopenmethod = 'none'; $assign2->maxattempts = -1;
    $assign2->markingworkflow = 0; $assign2->markingallocation = 0;
    $assign2->id = 0;
    try {
        $assign2->id = assign_add_instance($assign2, null);
        echo "Assignment 'Final Research Report' created via API\n";
    } catch (Throwable $e) {
        echo "Assignment 'Final Research Report' API failed: " . $e->getMessage() . "\n";
        try {
            $assign2->id = $DB->insert_record('assign', $assign2);
            echo "Assignment 'Final Research Report' via direct insert\n";
        } catch (Throwable $e2) {
            echo "Assignment 'Final Research Report' direct insert also failed: " . $e2->getMessage() . "\n";
        }
    }
    if ($assign2->id) {
        $cm2 = new stdClass();
        $cm2->course = $courseid; $cm2->module = $assign_module->id; $cm2->instance = $assign2->id;
        $cm2->visible = 1; $cm2->completion = 0;
        $cmid2 = add_course_module($cm2);
        course_add_cm_to_section($course, $cmid2, 5);
        context_module::instance($cmid2);
        echo "Created Assignment: Final Research Report (cmid=$cmid2)\n";
    } else {
        echo "WARNING: Final Research Report creation failed, skipping course module\n";
    }
} else {
    echo "Assignment 'Final Research Report' already exists\n";
}

rebuild_course_cache($courseid, true);
echo "SETUP_COMPLETE courseid=$courseid\n";
PHPEOF

echo "PHP setup complete."

# ---------------------------------------------------------------------------
# Save baseline state for use by export_result.sh
# ---------------------------------------------------------------------------
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO302'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO302 course not found in database after PHP setup!"
    exit 1
fi
echo "BIO302 course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/bio302_course_id

INITIAL_BADGE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_badge WHERE courseid=$COURSE_ID" 2>/dev/null | tr -d '[:space:]')
echo "${INITIAL_BADGE_COUNT:-0}" > /tmp/bio302_initial_badge_count
echo "Initial badge count for BIO302: ${INITIAL_BADGE_COUNT:-0}"

date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded."

# ---------------------------------------------------------------------------
# Ensure Firefox is running and take initial screenshot
# ---------------------------------------------------------------------------
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected within 30 seconds"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Configure Completion and Badge Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  Login: admin / Admin1234!"
echo ""
echo "  Course: BIO302 Advanced Cell Biology (ID=$COURSE_ID)"
echo ""
echo "  STEP 1 – Configure activity completion for each of the 5 activities:"
echo "    - Lab Safety and Ethics Module (Page)    → complete when VIEWED"
echo "    - Cell Membrane Transport Lab (Assignment) → complete when SUBMITTED"
echo "    - Molecular Biology Quiz (Quiz)            → complete when PASS GRADE (>=70%) achieved"
echo "    - Research Discussion Forum (Forum)        → complete when POST made"
echo "    - Final Research Report (Assignment)       → complete when SUBMITTED"
echo ""
echo "  STEP 2 – Configure course completion:"
echo "    Course administration > Course completion"
echo "    Require ALL 5 activities to be complete."
echo ""
echo "  STEP 3 – Create badge:"
echo "    Name: Advanced Cell Biology Scholar"
echo "    Description: Awarded to students who successfully complete all BIO302"
echo "      Advanced Cell Biology course requirements including laboratory work,"
echo "      assessments, and discussions."
echo "    Criteria: course completion"
echo "    Expiry: 3 years after issue date"
