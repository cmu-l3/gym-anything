#!/bin/bash
# Setup script for Configure Tiered Assessment Pathway task
# Creates NUR401 course, enrolls users, pre-seeds question bank with 5 MCQs

echo "=== Setting up Tiered Assessment Pathway Task ==="

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
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
fi

# ---------------------------------------------------------------------------
# Delete stale outputs BEFORE recording timestamp
# ---------------------------------------------------------------------------
rm -f /tmp/tiered_assessment_result.json 2>/dev/null || true
rm -f /tmp/task_start_screenshot.png 2>/dev/null || true
rm -f /tmp/task_end_screenshot.png 2>/dev/null || true

# ---------------------------------------------------------------------------
# Enable completion tracking at site level
# ---------------------------------------------------------------------------
echo "Enabling completion tracking and weighted mean aggregation at site level..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
set_config('enablecompletion', 1);
set_config('grade_aggregations_visible', '0,10,11,13');
echo 'Completion tracking and grade aggregation methods enabled at site level.';
"

# ---------------------------------------------------------------------------
# Create NUR401 course, enroll users, and pre-seed question bank via PHP
# ---------------------------------------------------------------------------
echo "--- Creating NUR401 course and seeding question bank via PHP CLI ---"

sudo -u www-data php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/lib/enrollib.php');
require_once($CFG->dirroot . '/lib/questionlib.php');
require_once($CFG->dirroot . '/question/engine/bank.php');

global $USER, $DB;
$USER = get_admin();

// =========================================================================
// 1. Create course NUR401
// =========================================================================
$sci_cat = $DB->get_record('course_categories', ['idnumber' => 'SCI']);
if (!$sci_cat) {
    $sci_cat = $DB->get_record('course_categories', ['name' => 'Science']);
}
$cat_id = $sci_cat ? $sci_cat->id : 1;

if (!$DB->record_exists('course', ['shortname' => 'NUR401'])) {
    $course_data = new stdClass();
    $course_data->fullname    = 'Clinical Pharmacology';
    $course_data->shortname   = 'NUR401';
    $course_data->category    = $cat_id;
    $course_data->format      = 'topics';
    $course_data->numsections = 8;
    $course_data->visible     = 1;
    $course_data->startdate   = mktime(0, 0, 0, 9, 1, 2025);
    $course_data->enablecompletion = 1;
    $course_data->summary     = 'Clinical Pharmacology covers drug classification, pharmacokinetics, medication safety, and clinical drug interactions for nursing professionals.';
    $course_data->summaryformat = FORMAT_HTML;
    $newcourse = create_course($course_data);
    echo "Created NUR401 id=" . $newcourse->id . "\n";
} else {
    echo "NUR401 already exists\n";
    // Ensure completion is enabled on existing course
    $existing = $DB->get_record('course', ['shortname' => 'NUR401']);
    if ($existing && !$existing->enablecompletion) {
        $DB->set_field('course', 'enablecompletion', 1, ['id' => $existing->id]);
        echo "Enabled completion on existing NUR401\n";
    }
}

$course = $DB->get_record('course', ['shortname' => 'NUR401'], '*', MUST_EXIST);
$courseid = $course->id;
echo "NUR401 course id=$courseid\n";

// =========================================================================
// 2. Enroll teacher1 and 4 students
// =========================================================================
$enrol_plugin = enrol_get_plugin('manual');
$enrol_instances = enrol_get_instances($courseid, true);
$manual_instance = null;
foreach ($enrol_instances as $inst) {
    if ($inst->enrol === 'manual') {
        $manual_instance = $inst;
        break;
    }
}
if (!$manual_instance) {
    $enrolid = $enrol_plugin->add_instance($course);
    $manual_instance = $DB->get_record('enrol', ['id' => $enrolid]);
    echo "Created manual enrol instance\n";
}

// Teacher role (editingteacher = role id 3)
$teacher = $DB->get_record('user', ['username' => 'teacher1']);
if ($teacher) {
    $enrol_plugin->enrol_user($manual_instance, $teacher->id, 3);
    echo "Enrolled teacher1\n";
}

// Student role (student = role id 5)
$students = ['jsmith', 'mjones', 'awilson', 'bbrown'];
foreach ($students as $uname) {
    $u = $DB->get_record('user', ['username' => $uname]);
    if ($u) {
        $enrol_plugin->enrol_user($manual_instance, $u->id, 5);
        echo "Enrolled $uname\n";
    } else {
        echo "WARNING: user $uname not found\n";
    }
}

// =========================================================================
// 3. Create question bank category "Pharmacology Fundamentals"
// =========================================================================
$context = context_course::instance($courseid);
echo "Course context id=" . $context->id . "\n";

// Find or create top-level question category
$topcat = $DB->get_record_sql(
    "SELECT * FROM {question_categories} WHERE contextid = ? AND parent = 0 ORDER BY id ASC LIMIT 1",
    [$context->id]
);
if (!$topcat) {
    $topcat = new stdClass();
    $topcat->name       = 'top';
    $topcat->contextid  = $context->id;
    $topcat->info       = '';
    $topcat->infoformat = FORMAT_MOODLE;
    $topcat->sortorder  = 0;
    $topcat->stamp      = make_unique_id_code();
    $topcat->parent     = 0;
    $topcat->id         = $DB->insert_record('question_categories', $topcat);
    echo "Created top-level question category id=" . $topcat->id . "\n";
}

$pharm_cat_name = 'Pharmacology Fundamentals';
$pharm_cat = $DB->get_record('question_categories', [
    'name' => $pharm_cat_name,
    'contextid' => $context->id
]);
if (!$pharm_cat) {
    $pharm_cat = new stdClass();
    $pharm_cat->name       = $pharm_cat_name;
    $pharm_cat->contextid  = $context->id;
    $pharm_cat->info       = 'Core pharmacology questions for NUR401 assessments.';
    $pharm_cat->infoformat = FORMAT_MOODLE;
    $pharm_cat->sortorder  = 999;
    $pharm_cat->stamp      = make_unique_id_code();
    $pharm_cat->parent     = $topcat->id;
    $pharm_cat->id         = $DB->insert_record('question_categories', $pharm_cat);
    echo "Created question category: $pharm_cat_name (id=" . $pharm_cat->id . ")\n";
} else {
    echo "Question category already exists: $pharm_cat_name\n";
}

// =========================================================================
// 4. Create 5 MCQ questions in the category
// =========================================================================
$questions = [
    [
        'name' => 'Cell Wall Synthesis Inhibitors',
        'text' => 'Which drug class inhibits bacterial cell wall synthesis?',
        'answers' => [
            ['text' => 'Penicillins', 'fraction' => 1.0],
            ['text' => 'SSRIs', 'fraction' => 0.0],
            ['text' => 'Statins', 'fraction' => 0.0],
            ['text' => 'ACE inhibitors', 'fraction' => 0.0],
        ],
    ],
    [
        'name' => 'ACE Inhibitor Mechanism',
        'text' => 'What is the primary mechanism of action of ACE inhibitors?',
        'answers' => [
            ['text' => 'Block angiotensin-converting enzyme', 'fraction' => 1.0],
            ['text' => 'Block calcium channels', 'fraction' => 0.0],
            ['text' => 'Inhibit COX-2', 'fraction' => 0.0],
            ['text' => 'Block beta-adrenergic receptors', 'fraction' => 0.0],
        ],
    ],
    [
        'name' => 'Fastest Absorption Route',
        'text' => 'Which route of administration provides the fastest drug absorption?',
        'answers' => [
            ['text' => 'Intravenous', 'fraction' => 1.0],
            ['text' => 'Oral', 'fraction' => 0.0],
            ['text' => 'Sublingual', 'fraction' => 0.0],
            ['text' => 'Transdermal', 'fraction' => 0.0],
        ],
    ],
    [
        'name' => 'Clinical Trial Phases',
        'text' => 'What phase of clinical trials involves testing in healthy volunteers?',
        'answers' => [
            ['text' => 'Phase I', 'fraction' => 1.0],
            ['text' => 'Phase II', 'fraction' => 0.0],
            ['text' => 'Phase III', 'fraction' => 0.0],
            ['text' => 'Phase IV', 'fraction' => 0.0],
        ],
    ],
    [
        'name' => 'Primary Metabolic Organ',
        'text' => 'Which organ is primarily responsible for drug metabolism?',
        'answers' => [
            ['text' => 'Liver', 'fraction' => 1.0],
            ['text' => 'Kidney', 'fraction' => 0.0],
            ['text' => 'Lungs', 'fraction' => 0.0],
            ['text' => 'Spleen', 'fraction' => 0.0],
        ],
    ],
];

// Moodle 4.x: questions link to categories via question_bank_entries, not a category column
$existing_q_count = $DB->count_records('question_bank_entries', ['questioncategoryid' => $pharm_cat->id]);
if ($existing_q_count >= 5) {
    echo "Questions already seeded ($existing_q_count found), skipping.\n";
} else {
    // Clear any partial state via the versioning chain
    if ($existing_q_count > 0) {
        $entries = $DB->get_records('question_bank_entries', ['questioncategoryid' => $pharm_cat->id]);
        foreach ($entries as $entry) {
            $versions = $DB->get_records('question_versions', ['questionbankentryid' => $entry->id]);
            foreach ($versions as $v) {
                $DB->delete_records('question_answers', ['question' => $v->questionid]);
                $DB->delete_records('qtype_multichoice_options', ['questionid' => $v->questionid]);
                $DB->delete_records('question', ['id' => $v->questionid]);
            }
            $DB->delete_records('question_versions', ['questionbankentryid' => $entry->id]);
        }
        $DB->delete_records('question_bank_entries', ['questioncategoryid' => $pharm_cat->id]);
        echo "Cleared $existing_q_count partial entries.\n";
    }

    foreach ($questions as $qdata) {
        // Create question record (no category column in Moodle 4.x)
        $q = new stdClass();
        $q->parent       = 0;
        $q->name         = $qdata['name'];
        $q->questiontext = '<p>' . $qdata['text'] . '</p>';
        $q->questiontextformat = FORMAT_HTML;
        $q->generalfeedback = '';
        $q->generalfeedbackformat = FORMAT_HTML;
        $q->defaultmark  = 1.0000000;
        $q->penalty      = 0.3333333;
        $q->qtype        = 'multichoice';
        $q->length       = 1;
        $q->stamp        = make_unique_id_code();
        $q->timecreated  = time();
        $q->timemodified = time();
        $q->createdby    = $USER->id;
        $q->modifiedby   = $USER->id;
        $q->id           = $DB->insert_record('question', $q);

        // Create question_bank_entries (links question to category)
        $qbe = new stdClass();
        $qbe->questioncategoryid = $pharm_cat->id;
        $qbe->idnumber  = null;
        $qbe->ownerid   = $USER->id;
        $qbe->id        = $DB->insert_record('question_bank_entries', $qbe);

        // Create question_versions
        $qv = new stdClass();
        $qv->questionbankentryid = $qbe->id;
        $qv->version    = 1;
        $qv->questionid = $q->id;
        $qv->status     = 'ready';
        $DB->insert_record('question_versions', $qv);

        // Create multichoice options
        $mc = new stdClass();
        $mc->questionid     = $q->id;
        $mc->layout         = 0;
        $mc->single         = 1;
        $mc->shuffleanswers = 1;
        $mc->correctfeedback = '';
        $mc->correctfeedbackformat = FORMAT_HTML;
        $mc->partiallycorrectfeedback = '';
        $mc->partiallycorrectfeedbackformat = FORMAT_HTML;
        $mc->incorrectfeedback = '';
        $mc->incorrectfeedbackformat = FORMAT_HTML;
        $mc->answernumbering = 'abc';
        $mc->shownumcorrect  = 0;
        $mc->showstandardinstruction = 0;
        $DB->insert_record('qtype_multichoice_options', $mc);

        // Create answer records
        foreach ($qdata['answers'] as $adata) {
            $ans = new stdClass();
            $ans->question       = $q->id;
            $ans->answer         = $adata['text'];
            $ans->answerformat   = FORMAT_PLAIN;
            $ans->fraction       = $adata['fraction'];
            $ans->feedback       = '';
            $ans->feedbackformat = FORMAT_HTML;
            $DB->insert_record('question_answers', $ans);
        }

        echo "Created question: " . $qdata['name'] . " (id=" . $q->id . ")\n";
    }
    echo "All 5 questions seeded.\n";
}

echo "SETUP_COMPLETE courseid=$courseid contextid=" . $context->id . "\n";
PHPEOF

PHP_EXIT=$?
if [ $PHP_EXIT -ne 0 ]; then
    echo "WARNING: PHP setup script exited with code $PHP_EXIT"
fi

# ---------------------------------------------------------------------------
# Save baseline state for verifier
# ---------------------------------------------------------------------------
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='NUR401'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: NUR401 course not found after PHP setup!"
    exit 1
fi
echo "NUR401 Course ID: $COURSE_ID"

CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE instanceid=$COURSE_ID AND contextlevel=50" | tr -d '[:space:]')
echo "NUR401 Context ID: ${CONTEXT_ID:-not found}"

INITIAL_QUIZ_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz WHERE course=$COURSE_ID" | tr -d '[:space:]')
INITIAL_BADGE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_badge WHERE courseid=$COURSE_ID" | tr -d '[:space:]')

echo "$COURSE_ID"                       > /tmp/nur401_course_id
echo "${CONTEXT_ID:-0}"                 > /tmp/nur401_context_id
echo "${INITIAL_QUIZ_COUNT:-0}"         > /tmp/nur401_initial_quiz_count
echo "${INITIAL_BADGE_COUNT:-0}"        > /tmp/nur401_initial_badge_count

# Record timestamp AFTER setup, AFTER deleting stale outputs
date +%s > /tmp/task_start_timestamp

# ---------------------------------------------------------------------------
# Ensure Firefox is running and showing the course
# ---------------------------------------------------------------------------
MOODLE_URL="http://localhost/course/view.php?id=$COURSE_ID"

if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window and focus
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
