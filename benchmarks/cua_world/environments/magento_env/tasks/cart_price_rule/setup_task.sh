#!/bin/bash
# Setup script for Cart Price Rule task

echo "=== Setting up Cart Price Rule Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial counts
echo "Recording initial rule/coupon counts..."
INITIAL_RULE_COUNT=$(magento_query "SELECT COUNT(*) FROM salesrule" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_COUPON_COUNT=$(magento_query "SELECT COUNT(*) FROM salesrule_coupon" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "${INITIAL_RULE_COUNT:-0}" > /tmp/initial_rule_count
echo "${INITIAL_COUPON_COUNT:-0}" > /tmp/initial_coupon_count
echo "Initial rule count: ${INITIAL_RULE_COUNT:-0}, coupon count: ${INITIAL_COUPON_COUNT:-0}"

# Verify General customer group exists (group_id=1 in standard Magento)
GENERAL_GROUP_ID=$(magento_query "SELECT customer_group_id FROM customer_group WHERE LOWER(TRIM(customer_group_code))='general' LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "1")
echo "${GENERAL_GROUP_ID:-1}" > /tmp/general_group_id
echo "General customer group ID: ${GENERAL_GROUP_ID:-1}"

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

echo "=== Cart Price Rule Task Setup Complete ==="
echo ""
echo "Navigate to: Marketing > Promotions > Cart Price Rules"
echo "Magento Admin: http://localhost/admin  |  admin / Admin1234!"
echo ""
