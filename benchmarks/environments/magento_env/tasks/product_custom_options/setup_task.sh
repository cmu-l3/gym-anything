#!/bin/bash
# Setup script for Product Custom Options task

echo "=== Setting up Product Custom Options Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
TARGET_SKU="BOTTLE-001"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify target product exists
PRODUCT_ID=$(get_product_by_sku "$TARGET_SKU" 2>/dev/null | cut -f1)
if [ -z "$PRODUCT_ID" ]; then
    echo "ERROR: Target product $TARGET_SKU not found. Task cannot proceed."
    exit 1
fi
echo "Target Product ID: $PRODUCT_ID"

# Record initial option count for this product
INITIAL_OPTION_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_option WHERE product_id=$PRODUCT_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "$INITIAL_OPTION_COUNT" > /tmp/initial_option_count
echo "Initial custom option count for $TARGET_SKU: $INITIAL_OPTION_COUNT"

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

# Check if we're on the login page and login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
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
    echo "Waiting for dashboard to load..."
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Product Custom Options Task Setup Complete ==="
echo ""
echo "Target Product: Insulated Water Bottle ($TARGET_SKU)"
echo "If not already logged in, use: admin / Admin1234!"
echo ""