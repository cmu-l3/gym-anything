#!/bin/bash
# Setup script for Repair Gradebook Structure task
# Creates CHEM201 course with a flat, broken gradebook (all items at top level,
# wrong aggregation) that the agent must discover and fix.

echo "=== Setting up Repair Gradebook Structure Task ==="

# Source shared utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    . /workspace/scripts/task_utils.sh
else
    echo "Warning: /workspace/scripts/task_utils.sh not found, using inline definitions"
fi

# Fallback definitions in case task_utils.sh did not export them
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
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
        echo "Warning: Could not take screenshot"
        [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
    }
fi

if ! type wait_for_window &>/dev/null; then
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
fi

if ! type get_firefox_window_id &>/dev/null; then
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
fi

if ! type focus_window &>/dev/null; then
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
fi

# ---------------------------------------------------------------------------
# Step 1: Create CHEM201 course and set up broken gradebook via PHP CLI
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 1: Creating CHEM201 course and broken gradebook via PHP CLI ---"

sudo -u www-data php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/grade/lib.php');

// Set up admin user context (needed for grade item events)
global $USER;
$USER = get_admin();

// Get Science category (idnumber=SCI); fall back to category id=1
$sci_cat = $DB->get_record('course_categories', ['idnumber' => 'SCI']);
$sci_id = $sci_cat ? $sci_cat->id : 1;
echo "Science category id=$sci_id\n";

// Create CHEM201 course if it does not exist
if (!$DB->record_exists('course', ['shortname' => 'CHEM201'])) {
    $course = new stdClass();
    $course->fullname  = 'Organic Chemistry I';
    $course->shortname = 'CHEM201';
    $course->category  = $sci_id;
    $course->format    = 'topics';
    $course->numsections = 10;
    $course->visible   = 1;
    $course->startdate = mktime(0, 0, 0, 9, 1, 2025);
    $course->summary   = 'Organic Chemistry I covers fundamental concepts including molecular structure, bonding, nomenclature, stereochemistry, and reaction mechanisms.';
    $course->summaryformat = FORMAT_HTML;
    $newcourse = create_course($course);
    echo "Created CHEM201 course id=" . $newcourse->id . "\n";
} else {
    echo "CHEM201 already exists\n";
}

$course   = $DB->get_record('course', ['shortname' => 'CHEM201'], '*', MUST_EXIST);
$courseid = $course->id;
echo "CHEM201 courseid=$courseid\n";

// Get (or re-fetch) the top-level grade category for this course
$topcategory = grade_category::fetch_course_category($courseid);
if (!$topcategory) {
    die("ERROR: could not get top grade category for course $courseid\n");
}
echo "Top grade category id=" . $topcategory->id . "\n";

// ------------------------------------------------------------------
// Set aggregation to MEAN (broken state) — correct is Weighted mean
// GRADE_AGGREGATE_MEAN = 0
// ------------------------------------------------------------------
$topcategory->aggregation  = GRADE_AGGREGATE_MEAN; // 0 = Mean of grades
$topcategory->keephigh     = 0;
$topcategory->droplow      = 0;
$topcategory->aggregateonlygraded = 1;
$topcategory->aggregatesubcats    = 0;
$topcategory->update('setup_task');
echo "Set top aggregation to Mean of grades (broken state, code=0)\n";

// ------------------------------------------------------------------
// Remove any existing non-root grade categories so we start clean
// ------------------------------------------------------------------
$existing_subcats = $DB->get_records_select(
    'grade_categories',
    'courseid = ? AND depth > 1',
    [$courseid]
);
foreach ($existing_subcats as $subcat) {
    $DB->delete_records('grade_categories', ['id' => $subcat->id]);
    // Also remove the corresponding grade_item row for this category
    $DB->delete_records('grade_items', [
        'courseid' => $courseid,
        'itemtype' => 'category',
        'iteminstance' => $subcat->id,
    ]);
}
if (count($existing_subcats) > 0) {
    echo "Removed " . count($existing_subcats) . " existing sub-categories\n";
}

// Remove any existing manual grade items for clean state
$deleted = $DB->delete_records_select(
    'grade_items',
    "courseid = ? AND itemtype = 'manual'",
    [$courseid]
);
echo "Cleared existing manual grade items\n";

// ------------------------------------------------------------------
// Create 6 manual grade items ALL at the top-level (flat broken state)
// ------------------------------------------------------------------
$items_to_create = [
    'Problem Set 1',
    'Problem Set 2',
    'Lab Report 1',
    'Lab Report 2',
    'Midterm Exam',
    'Final Exam',
];

foreach ($items_to_create as $itemname) {
    $gi = new grade_item();
    $gi->courseid        = $courseid;
    $gi->categoryid      = $topcategory->id;
    $gi->itemtype        = 'manual';
    $gi->itemname        = $itemname;
    $gi->grademax        = 100.0;
    $gi->grademin        = 0.0;
    $gi->gradetype       = GRADE_TYPE_VALUE;
    $gi->aggregationcoef  = 1.0;   // equal weight (but meaningless under Mean)
    $gi->aggregationcoef2 = 0.0;
    $gi->insert('setup_task');
    echo "Created grade item: $itemname (categoryid=" . $topcategory->id . ")\n";
}

// Re-sort and regrade
grade_regrade_final_grades($courseid);

echo "SETUP_COMPLETE courseid=$courseid\n";
PHPEOF

PHP_EXIT=$?
if [ $PHP_EXIT -ne 0 ]; then
    echo "ERROR: PHP setup script failed with exit code $PHP_EXIT"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Record initial state to files for the verifier
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 2: Recording initial state ---"

COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM201'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: CHEM201 course not found in DB after setup!"
    exit 1
fi
echo "CHEM201 course ID: $COURSE_ID"

INITIAL_CAT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_grade_categories WHERE courseid=$COURSE_ID AND depth > 1" | tr -d '[:space:]')
INITIAL_CAT_COUNT=${INITIAL_CAT_COUNT:-0}
echo "$INITIAL_CAT_COUNT" > /tmp/chem201_initial_cat_count
echo "Initial sub-category count: $INITIAL_CAT_COUNT (expected 0)"

INITIAL_AGG=$(moodle_query "SELECT aggregation FROM mdl_grade_categories WHERE courseid=$COURSE_ID AND depth=1 LIMIT 1" | tr -d '[:space:]')
INITIAL_AGG=${INITIAL_AGG:-0}
echo "$INITIAL_AGG" > /tmp/chem201_initial_agg
echo "Initial top-level aggregation: $INITIAL_AGG (0=Mean, expected broken state)"

echo "$COURSE_ID" > /tmp/chem201_course_id

INITIAL_ITEM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemtype='manual'" | tr -d '[:space:]')
echo "Initial manual grade item count: ${INITIAL_ITEM_COUNT:-0} (expected 6)"

# ---------------------------------------------------------------------------
# Step 3: Record task start timestamp
# ---------------------------------------------------------------------------
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded: $(cat /tmp/task_start_timestamp)"

# ---------------------------------------------------------------------------
# Step 4: Ensure Firefox is running and navigate to Moodle
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 4: Ensuring Firefox is running ---"

if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &" 2>/dev/null || \
    DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &
    sleep 5
else
    echo "Firefox is already running"
fi

if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected within 30s"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused and maximized: $WID"
else
    echo "WARNING: Could not find Firefox window ID"
fi

# ---------------------------------------------------------------------------
# Step 5: Take initial screenshot
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 5: Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Summary ==="
echo "Course: CHEM201 (id=$COURSE_ID)"
echo "Initial aggregation: $INITIAL_AGG (0=Mean, broken — should be 10=Weighted mean)"
echo "Initial sub-categories: $INITIAL_CAT_COUNT (0, all items flat)"
echo "Initial manual items: ${INITIAL_ITEM_COUNT:-0} (6 items all at top level)"
echo "State files: /tmp/chem201_course_id, /tmp/chem201_initial_cat_count, /tmp/chem201_initial_agg"
echo "=== Setup Complete ==="
