#!/bin/bash
# Setup script for Grouped Product Kit task

echo "=== Setting up Grouped Product Kit Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record initial product count for verification (to detect creation vs modification)
echo "Recording initial product count..."
INITIAL_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_product_count
echo "Initial product count: $INITIAL_COUNT"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check if we're on the login page (window title contains "login" or we need to log in)
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

# If we detect we're on the login page (title contains "Admin" but not "Dashboard"), try to log in
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2

    # Click in the window to focus
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5

    # Tab to first field and type username
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.1
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5

    # Tab to password field
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5

    # Press Enter to submit
    DISPLAY=:1 xdotool key Return

    # Wait for dashboard to load
    echo "Waiting for dashboard to load..."
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Grouped Product Kit Task Setup Complete ==="
echo ""
echo "If not already logged in, use: admin / Admin1234!"
echo ""