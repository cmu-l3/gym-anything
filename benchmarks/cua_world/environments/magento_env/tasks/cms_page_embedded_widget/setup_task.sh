#!/bin/bash
# Setup script for CMS Page Embedded Widget task

echo "=== Setting up CMS Page Embedded Widget Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record initial page count to verify new creation
echo "Recording initial CMS page count..."
INITIAL_PAGE_COUNT=$(magento_query "SELECT COUNT(*) FROM cms_page" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "$INITIAL_PAGE_COUNT" > /tmp/initial_page_count
echo "Initial page count: $INITIAL_PAGE_COUNT"

# Check if the target page already exists (cleanup from previous runs if necessary)
EXISTING_ID=$(magento_query "SELECT page_id FROM cms_page WHERE identifier='new-arrivals-showcase'" 2>/dev/null | tail -1 | tr -d '[:space:]')
if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "0" ]; then
    echo "Warning: Target page 'new-arrivals-showcase' already exists (ID: $EXISTING_ID). Deleting..."
    magento_query "DELETE FROM cms_page WHERE page_id=$EXISTING_ID"
    magento_query "DELETE FROM url_rewrite WHERE entity_type='cms-page' AND entity_id=$EXISTING_ID"
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

# Login automation if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo ""
echo "Navigate to: Content > Elements > Pages"
echo "Goal: Create a page 'New Arrivals Showcase' with an embedded 'New Products List' widget (6 products)."
echo ""