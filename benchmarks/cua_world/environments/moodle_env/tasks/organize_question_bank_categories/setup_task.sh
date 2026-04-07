#!/bin/bash
# Setup script for Organize Question Bank task

echo "=== Setting up Organize Question Bank Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Create Course CHEM101
echo "Creating course CHEM101..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');

// Check if course exists
\$existing = \$DB->get_record('course', ['shortname' => 'CHEM101']);
if (!\$existing) {
    \$course = new stdClass();
    \$course->fullname = 'Introduction to Chemistry';
    \$course->shortname = 'CHEM101';
    \$course->category = 1; // Miscellaneous
    \$course->startdate = time();
    \$course->visible = 1;
    \$created_course = create_course(\$course);
    echo 'Created course ID: ' . \$created_course->id . PHP_EOL;
} else {
    echo 'Course exists ID: ' . \$existing->id . PHP_EOL;
}
"

# Get Course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')
echo "CHEM101 Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/chem101_course_id

# 2. Generate Questions via PHP (Safe for Moodle 4.x)
echo "Generating chaotic questions..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->libdir . '/questionlib.php');

\$courseid = $COURSE_ID;
// Get the default category for this course context
\$context = context_course::instance(\$courseid);
\$defaultcat = \$DB->get_record('question_categories', ['contextid' => \$context->id, 'parent' => 0]);
// Actually usually the default category has parent=0 or is the one with name 'Default for...'
// Let's find/create the specific 'Default for CHEM101'
\$qcat = question_get_default_category(\$context->id);

echo 'Using Category ID: ' . \$qcat->id . PHP_EOL;

\$generator = \core_question\local\bank\question_version_status::get_question_bank(); // Not needed for simple generation
// We use the data generator for clean creation
require_once(\$CFG->dirroot . '/lib/generator/lib.php');
\$generator = new testing_data_generator();
\$question_generator = \$generator->get_plugin_generator('core_question');

// Create Atom questions
for (\$i = 1; \$i <= 5; \$i++) {
    \$qname = sprintf('Atom_%02d', \$i);
    if (!\$DB->record_exists('question', ['name' => \$qname])) {
        \$question_generator->create_question('multichoice', null, [
            'name' => \$qname,
            'category' => \$qcat->id,
            'questiontext' => ['text' => 'Question about Atom number ' . \$i, 'format' => FORMAT_HTML],
        ]);
        echo 'Created ' . \$qname . PHP_EOL;
    }
}

// Create Bond questions
for (\$i = 1; \$i <= 5; \$i++) {
    \$qname = sprintf('Bond_%02d', \$i);
    if (!\$DB->record_exists('question', ['name' => \$qname])) {
        \$question_generator->create_question('truefalse', null, [
            'name' => \$qname,
            'category' => \$qcat->id,
            'questiontext' => ['text' => 'Question about Bonding number ' . \$i, 'format' => FORMAT_HTML],
        ]);
        echo 'Created ' . \$qname . PHP_EOL;
    }
}
"

# Save the default category ID for verification later (to ensure we moved OUT of it)
DEFAULT_CAT_ID=$(moodle_query "SELECT qc.id FROM mdl_question_categories qc JOIN mdl_context ctx ON qc.contextid = ctx.id WHERE ctx.instanceid = $COURSE_ID AND ctx.contextlevel = 50 AND qc.parent = 0" | tr -d '[:space:]')
# Sometimes parent is not 0 for the default category itself, but it's the top one in context.
# Let's try finding the one named "Default for CHEM101"
if [ -z "$DEFAULT_CAT_ID" ]; then
    DEFAULT_CAT_ID=$(moodle_query "SELECT id FROM mdl_question_categories WHERE name LIKE 'Default for CHEM101%' LIMIT 1" | tr -d '[:space:]')
fi
echo "$DEFAULT_CAT_ID" > /tmp/default_cat_id
echo "Default Category ID: $DEFAULT_CAT_ID"

# Record start time
date +%s > /tmp/task_start_time.txt

# Start Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/moodle/course/view.php?id=$COURSE_ID"
su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla" 30

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="