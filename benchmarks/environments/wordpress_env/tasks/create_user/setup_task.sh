#!/bin/bash
# Setup script for create_user task (pre_task hook)
# Records initial user count

echo "=== Setting up create_user task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record initial user count
INITIAL_USER_COUNT=$(get_user_count)
echo "$INITIAL_USER_COUNT" | sudo tee /tmp/initial_user_count > /dev/null
sudo chmod 666 /tmp/initial_user_count
echo "Initial user count: $INITIAL_USER_COUNT"

# Check if the user already exists (shouldn't)
EXPECTED_USERNAME="marketing_lead"
if user_exists "$EXPECTED_USERNAME"; then
    echo "WARNING: User '$EXPECTED_USERNAME' already exists! Removing for clean task..."
    cd /var/www/html/wordpress
    wp user delete "$EXPECTED_USERNAME" --yes --allow-root 2>/dev/null || true
    INITIAL_USER_COUNT=$(get_user_count)
    echo "$INITIAL_USER_COUNT" | sudo tee /tmp/initial_user_count > /dev/null
    sudo chmod 666 /tmp/initial_user_count
    echo "Updated initial user count: $INITIAL_USER_COUNT"
fi

# List current users
echo "Current users:"
wp_cli user list --fields=ID,user_login,user_email,roles

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."

# Check if Firefox is running
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "WARNING: Firefox is not running! Attempting to restart..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
else
    echo "WARNING: No Firefox window found!"
    DISPLAY=:1 wmctrl -l
fi

# Verify Firefox is visible
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
echo "Current windows: $WINDOW_LIST"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "  1. Navigate to Users > Add New in WordPress admin"
echo "  2. Create user with username: marketing_lead"
echo "  3. Set email: marketing@example.com"
echo "  4. Set first name: Sarah, last name: Johnson"
echo "  5. Set role: Editor"
echo "  6. Add the new user"
