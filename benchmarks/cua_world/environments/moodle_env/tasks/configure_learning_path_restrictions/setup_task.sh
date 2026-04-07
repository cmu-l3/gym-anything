#!/bin/bash
# Setup script for Configure Learning Path Restrictions task

echo "=== Setting up Learning Path Task ==="

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
    moodle_query_headers() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
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

# 1. Ensure CHEM101 exists
echo "Checking for CHEM101..."
COURSE_CHECK=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')

if [ -z "$COURSE_CHECK" ]; then
    echo "Creating CHEM101 course..."
    
    # Get Science category ID (created in setup_moodle.sh)
    CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science' LIMIT 1" | tr -d '[:space:]')
    [ -z "$CAT_ID" ] && CAT_ID=1
    
    # Create course via SQL (faster than PHP CLI for simple container setup)
    # Note: Using minimal fields required. Real Moodle caches might need purging, 
    # but for this task checking DB existence is primary.
    # Ideally use PHP to trigger events, but direct SQL is often sufficient for valid layout.
    
    # Using PHP CLI to create course properly to ensure context creation
    sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    require_once(\$CFG->dirroot . '/course/lib.php');
    
    \$data = new stdClass();
    \$data->fullname = 'Introduction to Chemistry';
    \$data->shortname = 'CHEM101';
    \$data->category = $CAT_ID;
    \$data->visible = 1;
    \$data->startdate = time();
    \$data->enablecompletion = 1; // Enable completion tracking at course level
    
    try {
        \$course = create_course(\$data);
        echo 'Created course ID: ' . \$course->id;
    } catch (Exception \$e) {
        echo 'Error: ' . \$e->getMessage();
        exit(1);
    }
    "
    
    # Re-fetch ID
    COURSE_CHECK=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')
fi

echo "CHEM101 Course ID: $COURSE_CHECK"
echo "$COURSE_CHECK" > /tmp/target_course_id

# 2. Record initial state (Module counts)
INITIAL_PAGE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_page WHERE course=$COURSE_CHECK" | tr -d '[:space:]')
echo "$INITIAL_PAGE_COUNT" > /tmp/initial_page_count
echo "Initial page count: $INITIAL_PAGE_COUNT"

# 3. Start Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/moodle/course/view.php?id=$COURSE_CHECK"

if ! pgrep -f firefox > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 4. Wait for window and focus
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 5. Record task start time
date +%s > /tmp/task_start_timestamp

# 6. Take screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="