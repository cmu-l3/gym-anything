#!/bin/bash
echo "=== Setting up add_provider task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure a clean state by removing any existing target records
echo "Cleaning up any existing target records..."
freemed_query "DELETE FROM physician WHERE phyfname='Maria' AND phylname='Rodriguez'" 2>/dev/null || true

# Record initial physician count and max ID
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM physician" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_physician_count

INITIAL_MAX_ID=$(freemed_query "SELECT COALESCE(MAX(id),0) FROM physician" 2>/dev/null || echo "0")
echo "$INITIAL_MAX_ID" > /tmp/initial_max_physician_id

echo "Initial physician count: $INITIAL_COUNT"
echo "Initial max physician ID: $INITIAL_MAX_ID"

# Make sure FreeMED is accessible
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/freemed/ 2>/dev/null)
echo "FreeMED HTTP status: $HTTP_CODE"

# Start Firefox and navigate to FreeMED dashboard
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_provider_start.png

echo ""
echo "=== add_provider task setup complete ==="
echo "Task: Add Provider Maria Elena Rodriguez"
echo "FreeMED URL: http://localhost/freemed/"
echo "Login: admin / admin"
echo ""