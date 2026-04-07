#!/bin/bash
# Setup script for Create Randomized Quiz task
set -e

echo "=== Setting up Create Randomized Quiz Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ==============================================================================
# 1. Create Course and Questions via PHP (Reliable Moodle API usage)
# ==============================================================================
echo "Creating Pharmacology course and question bank data..."

sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->libdir . '/gradelib.php');
require_once(\$CFG->dirroot . '/course/lib.php');
require_once(\$CFG->dirroot . '/question/editlib.php');
require_once(\$CFG->dirroot . '/question/engine/lib.php');

// 1. Create Course: Pharmacology 101
\$course_data = new stdClass();
\$course_data->fullname = 'Pharmacology 101';
\$course_data->shortname = 'PHARM101';
\$course_data->category = 1; // Miscellaneous
\$course_data->startdate = time();
\$course_data->visible = 1;

// Check if exists first
\$existing = \$DB->get_record('course', ['shortname' => 'PHARM101']);
if (\$existing) {
    \$course = \$existing;
    echo \"Course PHARM101 already exists (ID: \$course->id)\n\";
} else {
    \$course = create_course(\$course_data);
    echo \"Created course PHARM101 (ID: \$course->id)\n\";
}

// 2. Create Question Category 'Drug Interactions' in Course Context
\$context = context_course::instance(\$course->id);
\$cat_data = new stdClass();
\$cat_data->name = 'Drug Interactions';
\$cat_data->contextid = \$context->id;
\$cat_data->info = 'Questions about drug interactions';
\$cat_data->infoformat = FORMAT_HTML;
\$cat_data->stamp = make_unique_id_code();
\$cat_data->parent = 0; // Top level
\$cat_data->sortorder = 999;

// Check if category exists
\$existing_cat = \$DB->get_record('question_categories', ['contextid' => \$context->id, 'name' => 'Drug Interactions']);
if (\$existing_cat) {
    \$category = \$existing_cat;
    echo \"Category 'Drug Interactions' already exists (ID: \$category->id)\n\";
} else {
    \$category_id = \$DB->insert_record('question_categories', \$cat_data);
    \$category = \$DB->get_record('question_categories', ['id' => \$category_id]);
    echo \"Created category 'Drug Interactions' (ID: \$category->id)\n\";
}

// Save Category ID for bash script to pick up
file_put_contents('/tmp/target_category_id', \$category->id);

// 3. Create 12 True/False Questions
\$qtype_tf = 'truefalse';
\$questions = [
    ['name' => 'Grapefruit Statin', 'txt' => 'Grapefruit juice inhibits CYP3A4, increasing toxicity of statins.', 'ans' => true],
    ['name' => 'Warfarin Vitamin K', 'txt' => 'High intake of leafy green vegetables (Vitamin K) increases the effect of Warfarin.', 'ans' => false],
    ['name' => 'MAOI Tyramine', 'txt' => 'Patients on MAOIs must avoid tyramine-rich foods like aged cheese to prevent hypertensive crisis.', 'ans' => true],
    ['name' => 'Tetracycline Calcium', 'txt' => 'Calcium supplements enhance the absorption of Tetracycline antibiotics.', 'ans' => false],
    ['name' => 'Alcohol Acetaminophen', 'txt' => 'Chronic alcohol use depletes glutathione, increasing acetaminophen hepatotoxicity.', 'ans' => true],
    ['name' => 'Digoxin Potassium', 'txt' => 'Hyperkalemia increases the risk of Digoxin toxicity.', 'ans' => false],
    ['name' => 'Nitrates Sildenafil', 'txt' => 'Combining nitrates and sildenafil can cause life-threatening hypotension.', 'ans' => true],
    ['name' => 'Iron Antacids', 'txt' => 'Antacids increase the absorption of oral iron supplements.', 'ans' => false],
    ['name' => 'Levodopa Protein', 'txt' => 'High protein meals can compete with Levodopa absorption in the gut.', 'ans' => true],
    ['name' => 'NSAIDs Lithium', 'txt' => 'NSAIDs reduce renal blood flow and can increase Lithium levels to toxic ranges.', 'ans' => true],
    ['name' => 'Ciprofloxacin Caffeine', 'txt' => 'Ciprofloxacin decreases caffeine metabolism, potentially leading to jitteriness.', 'ans' => true],
    ['name' => 'Omeprazole Clopidogrel', 'txt' => 'Omeprazole is a potent inducer of CYP2C19, making Clopidogrel more effective.', 'ans' => false]
];

foreach (\$questions as \$q) {
    // Check if question exists
    if (\$DB->record_exists('question', ['name' => \$q['name'], 'category' => \$category->id])) {
        continue;
    }

    // Create Question Object
    \$question = new stdClass();
    \$question->category = \$category->id;
    \$question->qtype = \$qtype_tf;
    \$question->name = \$q['name'];
    \$question->questiontext = \$q['txt'];
    \$question->questiontextformat = FORMAT_HTML;
    \$question->defaultmark = 1;
    \$question->penalty = 1;
    \$question->status = \core_question\local\bank\question_version_status::READY;
    \$question->createdby = 2; // admin
    \$question->modifiedby = 2;
    \$question->timecreated = time();
    \$question->timemodified = time();
    \$question->idnumber = null;

    // Answer specific data
    // True/False uses 'trueanswer' and 'falseanswer' fields in older APIs,
    // but saving via question_save is complex.
    // Simplest way for T/F in script is direct DB insertion for simple types if save() is hard,
    // but let's try to simulate a basic save or just insert raw records which is robust for T/F.
    
    // Core question insert
    \$qid = \$DB->insert_record('question', \$question);
    
    // Versioning (Moodle 4.x requirement)
    \$version = new stdClass();
    \$version->questionbankentryid = \$DB->insert_record('question_bank_entries', ['questioncategoryid' => \$category->id, 'idnumber' => null, 'ownerid' => 2]);
    \$version->version = 1;
    \$version->questionid = \$qid;
    \$version->status = \core_question\local\bank\question_version_status::READY;
    \$DB->insert_record('question_versions', \$version);
    
    // True/False Specifics
    // Answer ID 1 = True, 2 = False (usually, but we insert own)
    
    // True Answer
    \$ans_true = new stdClass();
    \$ans_true->question = \$qid;
    \$ans_true->answer = 'True';
    \$ans_true->fraction = \$q['ans'] ? 1.0 : 0.0;
    \$ans_true->feedback = '';
    \$ans_true->feedbackformat = FORMAT_HTML;
    \$ans_true_id = \$DB->insert_record('question_answers', \$ans_true);
    
    // False Answer
    \$ans_false = new stdClass();
    \$ans_false->question = \$qid;
    \$ans_false->answer = 'False';
    \$ans_false->fraction = \$q['ans'] ? 0.0 : 1.0;
    \$ans_false->feedback = '';
    \$ans_false->feedbackformat = FORMAT_HTML;
    \$ans_false_id = \$DB->insert_record('question_answers', \$ans_false);
    
    // T/F Table
    \$tf = new stdClass();
    \$tf->question = \$qid;
    \$tf->trueanswer = \$ans_true_id;
    \$tf->falseanswer = \$ans_false_id;
    \$DB->insert_record('question_truefalse', \$tf);
    
    echo \"Created question: {\$q['name']}\n\";
}
"

# Get the created IDs for reference
TARGET_CATEGORY_ID=$(cat /tmp/target_category_id 2>/dev/null || echo "0")
echo "Target Category ID: $TARGET_CATEGORY_ID"

# ==============================================================================
# 2. Browser Setup
# ==============================================================================
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/moodle/course/index.php"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for and focus Firefox
wait_for_window "firefox\|mozilla\|Moodle" 30 || echo "WARNING: Firefox window not detected"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Record initial quiz count for later comparison
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='PHARM101'" | tr -d '[:space:]')
if [ -n "$COURSE_ID" ]; then
    INITIAL_QUIZ_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz WHERE course=$COURSE_ID" | tr -d '[:space:]')
    echo "$INITIAL_QUIZ_COUNT" > /tmp/initial_quiz_count
    echo "Initial quiz count: $INITIAL_QUIZ_COUNT"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="