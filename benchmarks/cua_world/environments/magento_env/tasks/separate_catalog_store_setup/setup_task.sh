#!/bin/bash
# Setup script for Separate Catalog Store Setup task

echo "=== Setting up Separate Catalog Store Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record initial counts to detect new creations
echo "Recording initial counts..."
INITIAL_CAT_COUNT=$(get_category_count 2>/dev/null || echo "0")
INITIAL_GROUP_COUNT=$(magento_query "SELECT COUNT(*) FROM store_group" 2>/dev/null | tail -1)
INITIAL_VIEW_COUNT=$(magento_query "SELECT COUNT(*) FROM store" 2>/dev/null | tail -1)

echo "$INITIAL_CAT_COUNT" > /tmp/initial_cat_count
echo "$INITIAL_GROUP_COUNT" > /tmp/initial_group_count
echo "$INITIAL_VIEW_COUNT" > /tmp/initial_view_count

echo "Initial: Categories=$INITIAL_CAT_COUNT, Groups=$INITIAL_GROUP_COUNT, Views=$INITIAL_VIEW_COUNT"

# Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check for login page and login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="