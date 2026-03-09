#!/bin/bash
# Setup script for MAP Pricing Config task

echo "=== Setting up MAP Pricing Config Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# 1. Reset Global MAP Settings to Defaults (Disabled)
echo "Resetting global MAP settings..."
magento_query "DELETE FROM core_config_data WHERE path LIKE 'sales/msrp/%'" 2>/dev/null
magento_query "INSERT INTO core_config_data (scope, scope_id, path, value) VALUES ('default', 0, 'sales/msrp/enabled', '0')" 2>/dev/null
# Flush config cache to apply
# We can't easily flush cache via DB, but agent will likely flush or changes will take effect on save

# 2. Reset Product 'LAPTOP-001' MAP settings
echo "Resetting product data..."
PRODUCT_ID=$(get_product_by_sku "LAPTOP-001" 2>/dev/null | cut -f1)

if [ -n "$PRODUCT_ID" ]; then
    echo "Found LAPTOP-001 (ID: $PRODUCT_ID)"
    
    # Get attribute IDs
    MSRP_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='msrp' AND entity_type_id=4" 2>/dev/null)
    DISPLAY_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='msrp_display_actual_price_type' AND entity_type_id=4" 2>/dev/null)
    
    # Remove existing values for these attributes for this product (reset to default/empty)
    if [ -n "$MSRP_ATTR_ID" ]; then
        magento_query "DELETE FROM catalog_product_entity_decimal WHERE entity_id=$PRODUCT_ID AND attribute_id=$MSRP_ATTR_ID" 2>/dev/null
    fi
    if [ -n "$DISPLAY_ATTR_ID" ]; then
        # Check both varchar and int tables as backend type varies by version
        magento_query "DELETE FROM catalog_product_entity_varchar WHERE entity_id=$PRODUCT_ID AND attribute_id=$DISPLAY_ATTR_ID" 2>/dev/null
        magento_query "DELETE FROM catalog_product_entity_int WHERE entity_id=$PRODUCT_ID AND attribute_id=$DISPLAY_ATTR_ID" 2>/dev/null
    fi
else
    echo "WARNING: LAPTOP-001 not found. Task may be impossible."
fi

# 3. Ensure Firefox is running and focused on Magento admin
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

# Check login state
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
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

echo "=== MAP Pricing Config Task Setup Complete ==="
echo ""
echo "Goal: Enable MAP globally and configure it for LAPTOP-001."
echo "Admin URL: http://localhost/admin"
echo "Creds: admin / Admin1234!"