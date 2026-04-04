#!/bin/bash
# Setup script for Search Relevance Configuration task

echo "=== Setting up Search Relevance Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Record Initial State (Search Weights)
echo "Recording initial search weights..."
# We query the catalog_eav_attribute table joined with eav_attribute
# entity_type_id = 4 is for Catalog Products
QUERY="SELECT ea.attribute_code, cea.search_weight 
       FROM eav_attribute ea 
       JOIN catalog_eav_attribute cea ON ea.attribute_id = cea.attribute_id 
       WHERE ea.entity_type_id = 4 
       AND ea.attribute_code IN ('sku', 'name', 'description');"

INITIAL_STATE=$(magento_query "$QUERY" 2>/dev/null)
echo "$INITIAL_STATE" > /tmp/initial_search_weights.txt
echo "Initial weights:"
echo "$INITIAL_STATE"

# 2. Ensure Firefox is running and focused on Magento admin
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

# 3. Handle Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2

    # Click to focus
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5

    # Type credentials
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.1
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return

    echo "Waiting for dashboard..."
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Search Relevance Task Setup Complete ==="
echo "Navigate to: Stores > Attributes > Product"