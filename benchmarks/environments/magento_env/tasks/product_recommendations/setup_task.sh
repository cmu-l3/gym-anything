#!/bin/bash
# Setup script for Product Recommendations task

echo "=== Setting up Product Recommendations Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
TARGET_SKU="PHONE-001"

# 1. Clean up any existing links for the target product to ensure a clean state
echo "Cleaning up existing links for $TARGET_SKU..."
TARGET_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='$TARGET_SKU'" 2>/dev/null | tail -1 | tr -d '[:space:]')

if [ -n "$TARGET_ID" ]; then
    # Delete from catalog_product_link where product_id matches
    magento_query "DELETE FROM catalog_product_link WHERE product_id=$TARGET_ID"
    echo "Cleared links for product ID $TARGET_ID"
else
    echo "ERROR: Target product $TARGET_SKU not found!"
    # We don't exit here to allow the agent to potentially fail naturally, but this is bad
fi

# 2. Record initial link count (should be 0 now)
INITIAL_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_link WHERE product_id=$TARGET_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_link_count
echo "Initial link count: $INITIAL_COUNT"

# 3. Record start time
date +%s > /tmp/task_start_time.txt

# 4. Ensure Firefox is running and focused on Magento admin
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

# 5. Handle Login if needed
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
echo "Target Product: $TARGET_SKU"
echo "Instructions: Configure Related, Up-Sell, and Cross-Sell products."