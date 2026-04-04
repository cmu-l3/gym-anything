#!/bin/bash
# Setup script for Bulk Attribute Update task

echo "=== Setting up Bulk Attribute Update Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset Data: Ensure Clothing products have distinct/empty values to start
echo "Resetting product attributes..."

# Get Clothing category ID
CLOTHING_CAT_ID=$(magento_query "SELECT entity_id FROM catalog_category_entity_varchar WHERE value = 'Clothing' AND attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'name' AND entity_type_id = 3) LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')

if [ -z "$CLOTHING_CAT_ID" ]; then
    echo "ERROR: Clothing category not found!"
    # Fallback to hardcoded ID 4 (standard in sample data) if query fails
    CLOTHING_CAT_ID=4
fi

echo "Clothing Category ID: $CLOTHING_CAT_ID"

# Get IDs of products in Clothing
CLOTHING_PIDS=$(magento_query "SELECT product_id FROM catalog_category_product WHERE category_id = $CLOTHING_CAT_ID" 2>/dev/null)
PIDS_CSV=$(echo "$CLOTHING_PIDS" | tr '\n' ',' | sed 's/,$//')

echo "Target Product IDs: $PIDS_CSV"

if [ -n "$PIDS_CSV" ]; then
    # Reset Cost to 0.00
    COST_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='cost' AND entity_type_id=4" 2>/dev/null | tail -1)
    if [ -n "$COST_ATTR_ID" ]; then
        magento_query_headers "UPDATE catalog_product_entity_decimal SET value = 0.00 WHERE attribute_id = $COST_ATTR_ID AND entity_id IN ($PIDS_CSV)" 2>/dev/null
        # Also insert if not exists (handling sparse tables)
        # This is a simplification; standard Magento uses repositories, but SQL is faster for setup
    fi

    # Reset Meta Keywords to empty
    META_ATTR_ID=$(magento_query "SELECT attribute_id FROM eav_attribute WHERE attribute_code='meta_keyword' AND entity_type_id=4" 2>/dev/null | tail -1)
    if [ -n "$META_ATTR_ID" ]; then
         magento_query_headers "UPDATE catalog_product_entity_text SET value = '' WHERE attribute_id = $META_ATTR_ID AND entity_id IN ($PIDS_CSV)" 2>/dev/null
    fi
fi

# 2. Record Initial State for Anti-Gaming (Control Group)
# Get a product NOT in Clothing (e.g., Electronics) to ensure it DOESN'T change
ELECTRONICS_CAT_ID=$(magento_query "SELECT entity_id FROM catalog_category_entity_varchar WHERE value = 'Electronics' LIMIT 1" 2>/dev/null | tail -1)
CONTROL_PID=$(magento_query "SELECT product_id FROM catalog_category_product WHERE category_id = $ELECTRONICS_CAT_ID LIMIT 1" 2>/dev/null | tail -1)
echo "$CONTROL_PID" > /tmp/control_pid.txt

# Record initial updated_at timestamps for target products
magento_query "SELECT entity_id, updated_at FROM catalog_product_entity WHERE entity_id IN ($PIDS_CSV)" > /tmp/initial_timestamps.txt

# 3. Launch Firefox
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin/catalog/product/"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Handle Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard" && ! echo "$WINDOW_TITLE" | grep -qi "products"; then
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

echo "=== Setup Complete ==="