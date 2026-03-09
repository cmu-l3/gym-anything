#!/bin/bash
# Setup script for Cookie Consent Compliance task

echo "=== Setting up Cookie Consent Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial state to detect changes
echo "Recording initial configuration state..."
INITIAL_RESTRICTION=$(magento_query "SELECT value FROM core_config_data WHERE path='web/cookie/cookie_restriction'" 2>/dev/null | tail -1)
INITIAL_FOOTER=$(magento_query "SELECT value FROM core_config_data WHERE path='design/footer/copyright'" 2>/dev/null | tail -1)
INITIAL_PAGE_EXISTS=$(magento_query "SELECT COUNT(*) FROM cms_page WHERE identifier='privacy-policy-2026'" 2>/dev/null | tail -1)

# Save initial state to temp file
cat > /tmp/initial_state.json << EOF
{
    "restriction": "${INITIAL_RESTRICTION:-0}",
    "footer": "${INITIAL_FOOTER:-}",
    "page_exists": ${INITIAL_PAGE_EXISTS:-0},
    "start_time": $(date +%s)
}
EOF

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

# Check login state
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