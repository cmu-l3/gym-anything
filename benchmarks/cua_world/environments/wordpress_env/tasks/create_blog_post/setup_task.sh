#!/bin/bash
# Setup script for create_blog_post task (pre_task hook)
# Records initial post count and ensures WordPress admin is ready

echo "=== Setting up create_blog_post task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record initial post count with permission handling
INITIAL_POST_COUNT=$(get_post_count "post" "publish")
echo "$INITIAL_POST_COUNT" | sudo tee /tmp/initial_post_count > /dev/null
sudo chmod 666 /tmp/initial_post_count
echo "Initial published post count: $INITIAL_POST_COUNT"

# Get total post count (all statuses)
TOTAL_POST_COUNT=$(wp_cli post list --post_type=post --format=count)
echo "$TOTAL_POST_COUNT" | sudo tee /tmp/initial_total_post_count > /dev/null
sudo chmod 666 /tmp/initial_total_post_count
echo "Initial total post count: $TOTAL_POST_COUNT"

# Ensure the Technology category exists
if category_exists "Technology"; then
    echo "Technology category exists"
else
    echo "WARNING: Technology category not found - agent may need to create it"
fi

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

# Navigate to Posts > Add New
echo "Note: Agent should navigate to Posts > Add New in WordPress admin"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should now create a blog post titled: 'The Future of Artificial Intelligence in Healthcare'"
