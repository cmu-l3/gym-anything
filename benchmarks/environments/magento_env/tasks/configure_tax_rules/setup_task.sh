#!/bin/bash
# Setup script for Configure Tax Rules task

echo "=== Setting up Configure Tax Rules Task ==="

source /workspace/scripts/task_utils.sh

# Record initial counts for tax entities
echo "Recording initial tax entity counts..."
INITIAL_CLASS_COUNT=$(magento_query "SELECT COUNT(*) FROM tax_class" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_RATE_COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation_rate" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_RULE_COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation_rule" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "${INITIAL_CLASS_COUNT:-0}" > /tmp/initial_class_count
echo "${INITIAL_RATE_COUNT:-0}" > /tmp/initial_rate_count
echo "${INITIAL_RULE_COUNT:-0}" > /tmp/initial_rule_count

# Ensure Firefox is running and logged in
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

# Auto-login if needed
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

echo "=== Tax Rules Task Setup Complete ==="
echo ""
echo "Navigate to: Stores > Taxes > Tax Rules"
echo "Magento Admin: http://localhost/admin  |  admin / Admin1234!"
echo ""