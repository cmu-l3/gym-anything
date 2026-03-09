#!/bin/bash
# Setup script for Currency Setup task

echo "=== Setting up Currency Setup Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record initial state
echo "Recording initial currency configuration..."
INITIAL_ALLOWED=$(magento_query "SELECT value FROM core_config_data WHERE path = 'currency/options/allow'" 2>/dev/null || echo "")
INITIAL_RATES_COUNT=$(magento_query "SELECT COUNT(*) FROM directory_currency_rate" 2>/dev/null || echo "0")

echo "$INITIAL_ALLOWED" > /tmp/initial_allowed_currencies
echo "$INITIAL_RATES_COUNT" > /tmp/initial_rates_count
echo "Initial allowed: $INITIAL_ALLOWED"
echo "Initial rates count: $INITIAL_RATES_COUNT"

# Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
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
take_screenshot /tmp/task_start_screenshot.png

echo "=== Currency Setup Task Setup Complete ==="
echo ""
echo "If not already logged in, use: admin / Admin1234!"
echo "Steps:"
echo "1. Go to Stores > Configuration > General > Currency Setup"
echo "2. Add EUR, GBP, CAD to Allowed Currencies (keep USD)"
echo "3. Go to Stores > Currency > Currency Rates"
echo "4. Set rates: EUR=0.92, GBP=0.79, CAD=1.36"
echo ""