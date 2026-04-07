#!/bin/bash
# Setup script for customize_fse_templates task
# Prepares the site by ensuring Twenty Twenty-Four is active and clearing any existing template overrides.

echo "=== Setting up customize_fse_templates task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s | sudo tee /tmp/task_start_time > /dev/null
sudo chmod 666 /tmp/task_start_time

# Ensure the block theme (Twenty Twenty-Four) is active
echo "Activating Twenty Twenty-Four theme (FSE support)..."
cd /var/www/html/wordpress
wp theme activate twentytwentyfour --allow-root 2>/dev/null || true

# Clear any existing user-modified templates (wp_template and wp_template_part)
# This ensures the agent is working from a clean slate and we can detect NEW modifications
echo "Clearing any pre-existing template overrides..."
wp_db_query "DELETE FROM wp_posts WHERE post_type IN ('wp_template', 'wp_template_part')" 2>/dev/null || true

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused and maximized."
else
    echo "WARNING: No Firefox window found!"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="