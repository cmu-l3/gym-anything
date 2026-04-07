#!/bin/bash
# Setup script for configure_static_homepage task (pre_task hook)

echo "=== Setting up configure_static_homepage task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Ensure a clean slate by deleting any existing pages with our target names
echo "Cleaning up any existing target pages..."
cd /var/www/html/wordpress
wp post delete $(wp post list --post_type=page --name="portfolio" --format=ids --allow-root) --force --allow-root 2>/dev/null || true
wp post delete $(wp post list --post_type=page --name="journal" --format=ids --allow-root) --force --allow-root 2>/dev/null || true

# Reset Reading settings to default WordPress state
echo "Resetting WordPress Reading settings to default..."
wp option update show_on_front posts --allow-root 2>/dev/null
wp option update page_on_front 0 --allow-root 2>/dev/null
wp option update page_for_posts 0 --allow-root 2>/dev/null

# Get baseline for verification
BASELINE_SHOW_ON_FRONT=$(wp option get show_on_front --allow-root 2>/dev/null)
echo "Baseline show_on_front: $BASELINE_SHOW_ON_FRONT"

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox window and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
else
    echo "WARNING: No Firefox window found!"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="