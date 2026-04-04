#!/bin/bash
# Setup script for Wine Layered Navigation task

echo "=== Setting up Wine Layered Navigation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record initial attribute counts to detect new creations
echo "Recording initial counts..."
INITIAL_ATTR_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_OPTION_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute_option" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_GROUP_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute_group" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "$INITIAL_ATTR_COUNT" > /tmp/initial_attr_count
echo "$INITIAL_OPTION_COUNT" > /tmp/initial_option_count
echo "$INITIAL_GROUP_COUNT" > /tmp/initial_group_count
date +%s > /tmp/task_start_time

echo "Initial: Attrs=$INITIAL_ATTR_COUNT, Options=$INITIAL_OPTION_COUNT, Groups=$INITIAL_GROUP_COUNT"

# Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check if we're on the login page
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
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="