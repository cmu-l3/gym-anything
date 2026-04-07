#!/bin/bash
echo "=== Setting up create_reusable_patterns task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (Unix timestamp) for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Record initial count of reusable blocks (wp_block post type)
INITIAL_BLOCK_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='wp_block'" 2>/dev/null || echo "0")
echo "$INITIAL_BLOCK_COUNT" > /tmp/initial_block_count.txt
chmod 666 /tmp/initial_block_count.txt

# Ensure Firefox is running and focused on the WordPress admin dashboard
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window and maximize it
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused and maximized."
else
    echo "WARNING: Could not find Firefox window."
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="