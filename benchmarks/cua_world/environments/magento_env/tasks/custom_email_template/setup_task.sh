#!/bin/bash
# Setup script for Custom Email Template task

echo "=== Setting up Custom Email Template Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record initial state
echo "Recording initial email template state..."
INITIAL_TEMPLATE_COUNT=$(magento_query "SELECT COUNT(*) FROM email_template" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_CONFIG_VALUE=$(magento_query "SELECT value FROM core_config_data WHERE path='sales_email/order/template'" 2>/dev/null | tail -1 || echo "default")

echo "${INITIAL_TEMPLATE_COUNT:-0}" > /tmp/initial_template_count
echo "${INITIAL_CONFIG_VALUE:-default}" > /tmp/initial_config_value

echo "Initial templates: $INITIAL_TEMPLATE_COUNT"
echo "Initial config value: $INITIAL_CONFIG_VALUE"

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

# Check for login page and log in if necessary
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
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

# Clean up any previous attempts (optional, but good for idempotency if retrying)
# We don't want to delete data if this is a fresh run, but in dev it helps.
# For now, we assume a clean environment or that the agent handles errors.

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo ""
echo "Task: Create 'NestWell Order Confirmation' email template and assign it to New Order config."
echo "Magento Admin: http://localhost/admin"
echo ""