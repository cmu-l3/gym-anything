#!/bin/bash
# Setup script for URL Rewrite SEO Migration task

echo "=== Setting up URL Rewrite Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial custom rewrite count for anti-gaming verification
echo "Recording initial URL rewrite count..."
INITIAL_COUNT=$(magento_query "SELECT COUNT(*) FROM url_rewrite WHERE entity_type='custom'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "${INITIAL_COUNT:-0}" > /tmp/initial_rewrite_count.txt
echo "Initial custom rewrites: ${INITIAL_COUNT:-0}"

# Ensure Firefox is running and admin is logged in
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

# Start Firefox if not running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize
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
    # Click center
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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Navigate to: Marketing > SEO & Search > URL Rewrites"