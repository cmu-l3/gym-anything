#!/bin/bash
# Setup script for Configure Default Dashboard task

echo "=== Setting up Configure Default Dashboard Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure User 'jsmith' exists (created by install scripts usually, but verify)
echo "Verifying test user jsmith..."
USER_ID=$(get_user_by_username "jsmith" | cut -f1)

if [ -z "$USER_ID" ]; then
    echo "Creating user jsmith..."
    # Create via PHP CLI if not exists
    sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    \$user = create_user_record('jsmith', 'Student1234!');
    echo \$user->id;
    " > /tmp/new_user_id
    USER_ID=$(cat /tmp/new_user_id)
fi

echo "User ID for jsmith: $USER_ID"
echo "$USER_ID" > /tmp/jsmith_id.txt

# 2. Simulate a "Customized" dashboard for jsmith
# We insert a record into mdl_my_pages. If the agent successfully "Resets dashboard for all users",
# this record should be DELETED by Moodle.
echo "Simulating custom dashboard for jsmith..."
moodle_query "DELETE FROM mdl_my_pages WHERE userid=$USER_ID AND name='dashboard'"
moodle_query "INSERT INTO mdl_my_pages (userid, name, private, sortorder) VALUES ($USER_ID, 'dashboard', 1, 0)"

# Verify the record exists
CUSTOM_DASH_CHECK=$(moodle_query "SELECT id FROM mdl_my_pages WHERE userid=$USER_ID AND name='dashboard'")
if [ -n "$CUSTOM_DASH_CHECK" ]; then
    echo "Custom dashboard record created for verification (ID: $CUSTOM_DASH_CHECK)"
else
    echo "ERROR: Failed to create custom dashboard record"
fi

# 3. Ensure Firefox is running
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/moodle/admin/search.php" # Go to admin search or dashboard

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Record task start time
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="