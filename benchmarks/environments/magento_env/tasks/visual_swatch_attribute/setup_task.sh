#!/bin/bash
# Setup script for Visual Swatch Attribute task

echo "=== Setting up Visual Swatch Attribute Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial attribute count for verification
echo "Recording initial attribute count..."
INITIAL_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_attribute_count
echo "Initial product attribute count: $INITIAL_COUNT"

# Cleanup: Check if 'finish_color' already exists and delete it to ensure clean state
# This prevents the task from being trivial if the attribute persists from a previous run
EXISTING_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='finish_color' AND entity_type_id=4" 2>/dev/null | tail -1 | tr -d '[:space:]')

if [ -n "$EXISTING_ATTR_ID" ] && [ "$EXISTING_ATTR_ID" != "attribute_id" ]; then
    echo "Found existing 'finish_color' attribute (ID: $EXISTING_ATTR_ID). Deleting..."
    
    # We use a python script to delete via API or raw SQL if necessary, 
    # but raw SQL on EAV is risky. Ideally we'd use magento CLI, but there is no attribute:delete command.
    # We will use a safe SQL deletion cascade for this specific test attribute.
    
    magento_query "DELETE FROM eav_attribute WHERE attribute_id=$EXISTING_ATTR_ID"
    echo "Attribute deleted."
fi

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

echo "=== Visual Swatch Attribute Task Setup Complete ==="
echo ""
echo "If not already logged in, use: admin / Admin1234!"
echo "Navigate to Stores > Attributes > Product to begin."
echo ""