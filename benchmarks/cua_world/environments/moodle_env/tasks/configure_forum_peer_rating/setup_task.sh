#!/bin/bash
# Setup script for Configure Forum Peer Rating task

echo "=== Setting up Configure Forum Peer Rating Task ==="

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
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
fi

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure BIO101 course exists
echo "Checking for BIO101..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    echo "BIO101 not found. Creating it..."
    # Create the course via PHP CLI to ensure all tables are populated correctly
    sudo -u www-data php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/moodle/config.php');
        \$course = new stdClass();
        \$course->fullname = 'Introduction to Biology';
        \$course->shortname = 'BIO101';
        \$course->category = 1; 
        \$course->visible = 1;
        \$course->startdate = time();
        try {
            \$created = create_course(\$course);
            echo 'Created course ID: ' . \$created->id;
        } catch (Exception \$e) {
            echo 'Error: ' . \$e->getMessage();
            exit(1);
        }
    "
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
fi
echo "Target Course ID: $COURSE_ID"

# Clean up any previous attempts (delete forum if exists)
echo "Cleaning up previous attempts..."
FORUM_EXISTS=$(moodle_query "SELECT id FROM mdl_forum WHERE course=$COURSE_ID AND name='Nature vs Nurture Debate'" | tr -d '[:space:]')
if [ -n "$FORUM_EXISTS" ]; then
    # We can't easily delete via SQL safely because of contexts/modules
    # But we can rename it to avoid name collision detection issues
    moodle_query "UPDATE mdl_forum SET name=CONCAT('Archived ', name, ' ', UUID()) WHERE id=$FORUM_EXISTS"
    echo "Renamed old forum to avoid conflicts."
fi

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="