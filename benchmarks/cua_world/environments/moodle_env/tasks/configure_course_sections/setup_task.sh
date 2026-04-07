#!/bin/bash
# Setup script for Configure Course Sections task

echo "=== Setting up Configure Course Sections Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure the course PHYS101 exists
echo "Checking for PHYS101 course..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='PHYS101'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    echo "Creating PHYS101 course..."
    # Create category if needed
    CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science' LIMIT 1" | tr -d '[:space:]')
    if [ -z "$CAT_ID" ]; then
         # Create Science category via PHP if missing (simplified SQL fallback)
         moodle_query "INSERT INTO mdl_course_categories (name, idnumber, description, parent, sortorder, visible, visibleold, timemodified, depth, path) VALUES ('Science', 'SCI', '', 0, 10000, 1, 1, UNIX_TIMESTAMP(), 1, '/1')"
         CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science' LIMIT 1" | tr -d '[:space:]')
    fi
    
    # Create course via PHP to ensure proper initialization
    sudo -u www-data php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/moodle/config.php');
        \$course = new stdClass();
        \$course->fullname = 'Introduction to Physics';
        \$course->shortname = 'PHYS101';
        \$course->category = $CAT_ID;
        \$course->numsections = 5;
        \$course->format = 'topics';
        \$course->visible = 1;
        \$course->startdate = time();
        try {
            \$created = create_course(\$course);
            echo 'Created course ID: ' . \$created->id;
        } catch (Exception \$e) {
            echo 'Error: ' . \$e->getMessage();
        }
    "
    # Get ID again
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='PHYS101'" | tr -d '[:space:]')
fi

echo "Target Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/target_course_id

# 2. Reset sections 1-5 to default state (clean slate)
if [ -n "$COURSE_ID" ]; then
    echo "Resetting sections 1-5 for course $COURSE_ID..."
    
    # Ensure numsections is at least 5
    moodle_query "UPDATE mdl_course SET numsections = 5 WHERE id = $COURSE_ID AND numsections < 5"
    
    # Ensure section records exist (Moodle sometimes creates them on demand, but we can force empty ones)
    # Ideally we trust Moodle to have created them if we used create_course, 
    # but we will perform an UPDATE to clean them.
    
    # Reset name, summary, and visibility
    # Note: section 0 is general, we want sections 1-5
    moodle_query "UPDATE mdl_course_sections SET name=NULL, summary='', visible=1, timemodified=UNIX_TIMESTAMP() WHERE course=$COURSE_ID AND section BETWEEN 1 AND 5"
    
    # Verify reset
    RESET_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_course_sections WHERE course=$COURSE_ID AND section BETWEEN 1 AND 5 AND (name IS NOT NULL OR summary != '' OR visible != 1)")
    if [ "$RESET_CHECK" -eq 0 ]; then
        echo "Sections reset successfully."
    else
        echo "WARNING: Section reset might have failed."
    fi
fi

# 3. Start Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/moodle/course/view.php?id=$COURSE_ID"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
else
    # Navigate existing firefox
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' &"
fi

# 4. Wait for window and focus
wait_for_window "firefox\|mozilla\|Moodle" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="