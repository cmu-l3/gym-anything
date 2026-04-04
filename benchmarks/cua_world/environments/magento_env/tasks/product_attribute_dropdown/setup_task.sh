#!/bin/bash
# Setup script for Product Attribute Dropdown task

echo "=== Setting up Product Attribute Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial max attribute ID to detect new attributes later
# We use MAX(attribute_id) instead of count to strictly identify new IDs
INITIAL_MAX_ID=$(magento_query "SELECT MAX(attribute_id) FROM eav_attribute" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
[ -z "$INITIAL_MAX_ID" ] && INITIAL_MAX_ID="0"
echo "$INITIAL_MAX_ID" > /tmp/initial_max_attribute_id
echo "Initial Max Attribute ID: $INITIAL_MAX_ID"

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
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check if we're on the login page
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    # Simple login automation
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

# Check if attribute already exists (cleanup from previous runs if any)
EXISTING_ATTR=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='material_origin'" 2>/dev/null | tail -1)
if [ -n "$EXISTING_ATTR" ]; then
    echo "WARNING: Attribute 'material_origin' already exists (ID: $EXISTING_ATTR). This might affect verification."
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Navigate to: Stores > Attributes > Product"
echo "Then: Stores > Attributes > Attribute Set (to assign)"