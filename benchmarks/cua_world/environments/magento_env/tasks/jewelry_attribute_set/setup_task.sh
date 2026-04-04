#!/bin/bash
# Setup script for Jewelry Attribute Set task

echo "=== Setting up Jewelry Attribute Set Task ==="

source /workspace/scripts/task_utils.sh

# Record initial counts to detect new creations
echo "Recording initial EAV counts..."
INITIAL_ATTR_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_SET_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute_set WHERE entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "${INITIAL_ATTR_COUNT:-0}" > /tmp/initial_attr_count
echo "${INITIAL_SET_COUNT:-0}" > /tmp/initial_set_count
echo "Initial: attributes=$INITIAL_ATTR_COUNT sets=$INITIAL_SET_COUNT"

# Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/admin' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Auto-login if on login screen
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Navigate to: Stores > Attributes > Product"
echo "             Stores > Attributes > Attribute Set"
echo "Magento Admin: http://localhost/admin  |  admin / Admin1234!"