#!/bin/bash
# Setup script for Support Tools Config task

echo "=== Setting up Support Tools Config Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial configuration states to detect changes
echo "Recording initial config values..."

# Helper to get config value
get_config() {
    magento_query "SELECT value FROM core_config_data WHERE path='$1'" 2>/dev/null | tail -1
}

INIT_LAC_ENABLED=$(get_config "login_as_customer/general/enabled")
INIT_LAC_TITLE=$(get_config "login_as_customer/general/ui_title")
INIT_INTERVAL=$(get_config "customer/online/interval")
INIT_EMAIL=$(get_config "contact/contact/recipient_email")

# Save to temp file
cat > /tmp/initial_config_state.json << EOF
{
    "lac_enabled": "${INIT_LAC_ENABLED:-0}",
    "lac_title": "${INIT_LAC_TITLE:-}",
    "interval": "${INIT_INTERVAL:-}",
    "email": "${INIT_EMAIL:-}"
}
EOF

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

echo "=== Setup Complete ==="