#!/bin/bash
# Setup script for Catalog Price Rule task

echo "=== Setting up Catalog Price Rule Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial counts
echo "Recording initial rule counts..."
INITIAL_RULE_COUNT=$(magento_query "SELECT COUNT(*) FROM catalogrule" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "${INITIAL_RULE_COUNT:-0}" > /tmp/initial_rule_count

# Get Electronics Category ID for reference (used in export/verification)
ELECTRONICS_CAT_DATA=$(get_category_by_name "Electronics" 2>/dev/null)
ELECTRONICS_ID=$(echo "$ELECTRONICS_CAT_DATA" | cut -f1)
echo "${ELECTRONICS_ID:-0}" > /tmp/electronics_category_id
echo "Electronics Category ID: $ELECTRONICS_ID"

# Ensure Firefox is running and admin is logged in
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

# Login if needed
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

# Navigate to Marketing section if possible (optional, agent should find it)
# We just leave them at dashboard

take_screenshot /tmp/task_start_screenshot.png

echo "=== Catalog Price Rule Task Setup Complete ==="