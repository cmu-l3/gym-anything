#!/bin/bash
# Setup script for schedule_content_series task (pre_task hook)

echo "=== Setting up schedule_content_series task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Ensure categories exist
echo "Ensuring required categories exist..."
wp_cli term create category "News" --allow-root 2>/dev/null || true
wp_cli term create category "Technology" --allow-root 2>/dev/null || true

# Ensure tags exist
echo "Ensuring required tags exist..."
wp_cli term create post_tag "featured" --allow-root 2>/dev/null || true
wp_cli term create post_tag "guide" --allow-root 2>/dev/null || true

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."

if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Wait for and focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
else
    echo "WARNING: No Firefox window found!"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should now create three scheduled blog posts with specific dates and taxonomies."