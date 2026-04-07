#!/bin/bash
# Setup script for implement_acf_employee_directory task

echo "=== Setting up ACF Employee Directory Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

cd /var/www/html/wordpress

# 1. Clean up any existing ACF installation to ensure the agent has to install it
echo "Ensuring ACF is not installed..."
wp plugin deactivate advanced-custom-fields --allow-root 2>/dev/null || true
wp plugin delete advanced-custom-fields --allow-root 2>/dev/null || true

# 2. Ensure the "Team" category exists
echo "Setting up 'Team' category..."
if ! category_exists "Team"; then
    wp term create category "Team" --description="Employee Directory Profiles" --allow-root 2>/dev/null || true
fi

# 3. Clean up any previous attempts at these posts
echo "Cleaning up any existing target posts..."
wp post delete $(wp post list --post_type=post --title="Emily Chen" --format=ids --allow-root) --force --allow-root 2>/dev/null || true
wp post delete $(wp post list --post_type=post --title="Marcus Johnson" --format=ids --allow-root) --force --allow-root 2>/dev/null || true

# 4. Ensure Firefox is running and focused on WP Admin Plugins page
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/plugin-install.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
else
    # Navigate existing Firefox to plugin install page
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/plugin-install.php' &"
    sleep 3
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="