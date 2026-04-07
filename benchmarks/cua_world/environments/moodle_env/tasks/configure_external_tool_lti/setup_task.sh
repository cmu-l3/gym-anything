#!/bin/bash
# Setup script for Configure External Tool LTI task

echo "=== Setting up Configure External Tool LTI Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils not loaded correctly
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
fi

# 1. Ensure the CS101 course exists
echo "Checking for CS101 course..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CS101'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    echo "Creating CS101 course..."
    # Create course via PHP to ensure proper context creation
    sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    require_once(\$CFG->dirroot . '/course/lib.php');
    
    \$course = new stdClass();
    \$course->fullname = 'Introduction to Programming';
    \$course->shortname = 'CS101';
    \$course->category = 1; // Miscellaneous or default
    \$course->visible = 1;
    \$course->startdate = time();
    \$course->format = 'topics';
    
    try {
        \$created_course = create_course(\$course);
        echo 'Created course ID: ' . \$created_course->id;
    } catch (Exception \$e) {
        echo 'Error creating course: ' . \$e->getMessage();
        exit(1);
    }
    "
    # Get the ID again
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CS101'" | tr -d '[:space:]')
fi

echo "Target Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/target_course_id

# 2. Record initial state (counts of LTI tools and instances)
INITIAL_LTI_TYPES=$(moodle_query "SELECT COUNT(*) FROM mdl_lti_types" | tr -d '[:space:]')
INITIAL_LTI_INSTANCES=$(moodle_query "SELECT COUNT(*) FROM mdl_lti" | tr -d '[:space:]')

echo "$INITIAL_LTI_TYPES" > /tmp/initial_lti_types_count
echo "$INITIAL_LTI_INSTANCES" > /tmp/initial_lti_instances_count

echo "Initial LTI types: $INITIAL_LTI_TYPES"
echo "Initial LTI instances: $INITIAL_LTI_INSTANCES"

# 3. Record start time
date +%s > /tmp/task_start_timestamp

# 4. Prepare Browser
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/login/index.php' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
else
    # Navigate to login if already open
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/login/index.php'"
fi

# Wait for window
wait_for_window "firefox\|mozilla\|Moodle" 30 || echo "WARNING: Firefox window not detected"

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Capture initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="