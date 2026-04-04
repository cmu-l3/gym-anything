#!/bin/bash
# Setup script for Homepage Widget task

echo "=== Setting up Homepage Widget Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial widget count
echo "Recording initial widget count..."
INITIAL_COUNT=$(magento_query "SELECT COUNT(*) FROM widget_instance" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_widget_count.txt
echo "Initial widget count: $INITIAL_COUNT"

# Get Electronics category ID for reference (to ensure it exists)
echo "Verifying Electronics category..."
ELEC_CAT_ID=$(magento_query "SELECT e.entity_id FROM catalog_category_entity e
    JOIN catalog_category_entity_varchar v ON e.entity_id = v.entity_id
    WHERE v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3)
    AND LOWER(TRIM(v.value)) = 'electronics' LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')

if [ -z "$ELEC_CAT_ID" ]; then
    echo "WARNING: Electronics category not found. Creating fallback..."
    # Fallback creation if needed (though environment should have it)
    # This is complex via SQL, assuming environment is healthy based on description
    echo "Environment might be missing data, but proceeding."
else
    echo "Electronics Category ID: $ELEC_CAT_ID"
    echo "$ELEC_CAT_ID" > /tmp/electronics_category_id.txt
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

# Check if we're on the login page
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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Homepage Widget Task Setup Complete ==="
echo ""
echo "Navigate to: Content > Elements > Widgets"
echo "Magento Admin: http://localhost/admin  |  admin / Admin1234!"