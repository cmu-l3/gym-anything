#!/bin/bash
# Setup script for Create Custom Role Assignment task

echo "=== Setting up Create Custom Role Assignment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure the Engineering category exists (from setup_moodle.sh, but verifying)
CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Engineering'" | tr -d '[:space:]')
if [ -z "$CAT_ID" ]; then
    echo "Creating Engineering category..."
    sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    \$data = new stdClass();
    \$data->name = 'Engineering';
    \$data->idnumber = 'ENG';
    \$data->description = 'Engineering Department courses';
    try { \core_course_category::create(\$data); } catch (Exception \$e) {}
    "
    CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Engineering'" | tr -d '[:space:]')
fi

# 2. Ensure the ENG201 course exists
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='ENG201'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "Creating ENG201 course..."
    # Create via PHP API to ensure contexts are created correctly
    sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    \$course = new stdClass();
    \$course->fullname = 'Engineering Mechanics';
    \$course->shortname = 'ENG201';
    \$course->category = $CAT_ID;
    \$course->startdate = time();
    \$course->visible = 1;
    create_course(\$course);
    "
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='ENG201'" | tr -d '[:space:]')
fi
echo "Target Course ID (ENG201): $COURSE_ID"
echo "$COURSE_ID" > /tmp/target_course_id

# 3. Ensure teacher2 exists
USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='teacher2'" | tr -d '[:space:]')
if [ -z "$USER_ID" ]; then
    echo "Creating teacher2 user..."
    sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    \$user = new stdClass();
    \$user->username = 'teacher2';
    \$user->password = 'Teacher1234!';
    \$user->firstname = 'Dr.';
    \$user->lastname = 'Martinez';
    \$user->email = 'teacher2@example.com';
    user_create_user(\$user);
    "
    USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='teacher2'" | tr -d '[:space:]')
fi
echo "Target User ID (teacher2): $USER_ID"
echo "$USER_ID" > /tmp/target_user_id

# 4. Record initial state for anti-gaming
# Max role ID (to detect new roles)
MAX_ROLE_ID=$(moodle_query "SELECT MAX(id) FROM mdl_role" | tr -d '[:space:]')
echo "${MAX_ROLE_ID:-0}" > /tmp/initial_max_role_id

# Check if role already exists (shouldn't, but good to know)
EXISTING_ROLE=$(moodle_query "SELECT id FROM mdl_role WHERE shortname='courseauditor'" | tr -d '[:space:]')
if [ -n "$EXISTING_ROLE" ]; then
    echo "WARNING: Role 'courseauditor' already exists (ID: $EXISTING_ROLE). Cleaning up..."
    # We won't delete it to avoid breaking things, but we'll note it
    echo "$EXISTING_ROLE" > /tmp/pre_existing_role_id
fi

# 5. Launch Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|Moodle" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="