#!/bin/bash
# Setup script for Category Merchandising task

echo "=== Setting up Category Merchandising Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record task start time
date +%s > /tmp/task_start_time.txt

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

# Reset positions if they happen to be already set (to ensure task is valid)
echo "Resetting product positions to default..."
# Get IDs
CAT_DATA=$(get_category_by_name "Electronics")
CAT_ID=$(echo "$CAT_DATA" | cut -f1)

if [ -n "$CAT_ID" ]; then
    # Reset positions to 0 for all products in this category
    magento_query "UPDATE catalog_category_product SET position = 0 WHERE category_id = $CAT_ID"
    # Reset sort order to default (usually 'name' or null/use config)
    # We delete the specific override so it falls back to config
    magento_query "DELETE FROM catalog_category_entity_varchar WHERE entity_id = $CAT_ID AND attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='default_sort_by' AND entity_type_id=3)"
    
    # Reindex to ensure changes stick
    # docker exec magento-web php bin/magento indexer:reindex catalog_category_product >/dev/null 2>&1 || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Category Merchandising Task Setup Complete ==="
echo ""
echo "Navigate to Catalog > Categories"
echo "Select 'Electronics' and configure sort order and product positions."
echo ""