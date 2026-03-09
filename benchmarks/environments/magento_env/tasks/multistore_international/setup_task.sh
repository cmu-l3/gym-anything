#!/bin/bash
# Setup script for Multi-Store International task

echo "=== Setting up Multi-Store International Task ==="

source /workspace/scripts/task_utils.sh

# Record initial counts for store groups and store views
echo "Recording initial store counts..."
INITIAL_GROUP_COUNT=$(magento_query "SELECT COUNT(*) FROM store_group" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_STORE_COUNT=$(magento_query "SELECT COUNT(*) FROM store" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "${INITIAL_GROUP_COUNT:-0}" > /tmp/initial_group_count
echo "${INITIAL_STORE_COUNT:-0}" > /tmp/initial_store_count
echo "Initial: groups=$INITIAL_GROUP_COUNT stores=$INITIAL_STORE_COUNT"

# Ensure Firefox is running and logged in to Admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
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

# Check for login page and auto-login if needed
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

echo "=== Multi-Store Task Setup Complete ==="
echo ""
echo "Task: Create 'NestWell Europe' store group with 'nestwell_fr' and 'nestwell_de' views."
echo "      Configure locales (fr_FR, de_DE) and add EUR currency."
echo "Navigate to: Stores > Settings > All Stores"
echo "             Stores > Settings > Configuration"
echo ""