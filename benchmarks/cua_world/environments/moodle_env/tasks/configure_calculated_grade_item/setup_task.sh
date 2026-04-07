#!/bin/bash
# Setup script for Configure Calculated Grade Item task

echo "=== Setting up Calculated Grade Item Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if utils not sourced correctly
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

# 1. Create Course CHEM101
echo "Creating Chemistry 101 course..."
# Check if exists first
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    # Create course via PHP CLI to ensure proper initialization
    sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    require_once(\$CFG->dirroot . '/course/lib.php');
    
    \$course = new stdClass();
    \$course->fullname = 'Chemistry 101';
    \$course->shortname = 'CHEM101';
    \$course->category = 1; // Miscellaneous
    \$course->startdate = time();
    \$course->visible = 1;
    
    \$created_course = create_course(\$course);
    echo \$created_course->id;
    " > /tmp/new_course_id
    COURSE_ID=$(cat /tmp/new_course_id | tail -n1)
fi

echo "Course ID: $COURSE_ID"

# 2. Create Pre-Lab 1 and Post-Lab 1 Grade Items (Manual, NO ID numbers)
# We use PHP to create grade items properly linked to the course
echo "Creating initial grade items..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->libdir . '/gradelib.php');

\$courseid = $COURSE_ID;

// Create Pre-Lab 1
\$grade_item = new grade_item(array('courseid'=>\$courseid, 'itemtype'=>'manual', 'itemname'=>'Pre-Lab 1'), false);
\$grade_item->insert();
echo 'Created Pre-Lab 1 (id: ' . \$grade_item->id . ')\n';

// Create Post-Lab 1
\$grade_item = new grade_item(array('courseid'=>\$courseid, 'itemtype'=>'manual', 'itemname'=>'Post-Lab 1'), false);
\$grade_item->insert();
echo 'Created Post-Lab 1 (id: ' . \$grade_item->id . ')\n';
"

# 3. Record initial state
date +%s > /tmp/task_start_timestamp

# 4. Start Firefox
echo "Starting Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/grade/edit/tree/index.php?id=$COURSE_ID' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 5. Window management
echo "Focusing window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "moodle"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "moodle" | awk '{print $1}' | head -1)
        DISPLAY=:1 wmctrl -ia "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="