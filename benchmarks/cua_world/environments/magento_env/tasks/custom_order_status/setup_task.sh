#!/bin/bash
# Setup script for Custom Order Status task

echo "=== Setting up Custom Order Status Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial counts for anti-gaming verification
echo "Recording initial table counts..."
INITIAL_STATUS_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_order_status" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_STATE_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_order_status_state" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "${INITIAL_STATUS_COUNT:-0}" > /tmp/initial_status_count
echo "${INITIAL_STATE_COUNT:-0}" > /tmp/initial_state_count
echo "Initial: statuses=$INITIAL_STATUS_COUNT mappings=$INITIAL_STATE_COUNT"

# Ensure Firefox is running and logged in to Admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus window and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Handle Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    # Click center to focus
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    # Login flow
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
    # Wait for dashboard
    sleep 10
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Custom Order Status Task Setup Complete ==="
echo ""
echo "Navigate to: Stores > Settings > Order Status"
echo "Admin Credentials: admin / Admin1234!"
echo ""