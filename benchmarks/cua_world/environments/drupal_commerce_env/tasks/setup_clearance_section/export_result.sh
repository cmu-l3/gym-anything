#!/bin/bash
# Export script for setup_clearance_section

echo "=== Exporting setup_clearance_section Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if the field exists in configuration
# We look for the storage configuration of the field
FIELD_CONFIG_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.commerce_product.field_clearance'" 2>/dev/null || echo "0")
echo "Field config count: $FIELD_CONFIG_EXISTS"

# 3. Check if the data table exists and query it for flagged products
# The table name is typically 'commerce_product__field_clearance' for a field named 'field_clearance'
# We need to find the product IDs for Sony and Logitech first
SONY_ID=$(get_product_id_by_title "Sony WH-1000XM5 Wireless Headphones")
LOGI_ID=$(get_product_id_by_title "Logitech MX Master 3S")
APPLE_ID=$(get_product_id_by_title "Apple AirPods Pro") # Should NOT be flagged

SONY_FLAGGED="false"
LOGI_FLAGGED="false"
APPLE_FLAGGED="false"

# Check table existence first
TABLE_CHECK=$(drupal_db_query "SHOW TABLES LIKE 'commerce_product__field_clearance'" 2>/dev/null)

if [ -n "$TABLE_CHECK" ]; then
    echo "Table commerce_product__field_clearance exists."
    
    if [ -n "$SONY_ID" ]; then
        VAL=$(drupal_db_query "SELECT field_clearance_value FROM commerce_product__field_clearance WHERE entity_id = $SONY_ID" 2>/dev/null)
        if [ "$VAL" == "1" ]; then SONY_FLAGGED="true"; fi
    fi
    
    if [ -n "$LOGI_ID" ]; then
        VAL=$(drupal_db_query "SELECT field_clearance_value FROM commerce_product__field_clearance WHERE entity_id = $LOGI_ID" 2>/dev/null)
        if [ "$VAL" == "1" ]; then LOGI_FLAGGED="true"; fi
    fi

    if [ -n "$APPLE_ID" ]; then
        VAL=$(drupal_db_query "SELECT field_clearance_value FROM commerce_product__field_clearance WHERE entity_id = $APPLE_ID" 2>/dev/null)
        if [ "$VAL" == "1" ]; then APPLE_FLAGGED="true"; fi
    fi
else
    echo "Table commerce_product__field_clearance does NOT exist."
fi

# 4. Check if the Page/View exists via Router table
# Matches paths like '/clearance'
PATH_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM router WHERE path = '/clearance'" 2>/dev/null || echo "0")
echo "Router path check: $PATH_CHECK"

# 5. Check Menu Link
# Look for a menu link with title 'Clearance' in the main menu
MENU_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM menu_link_content_data WHERE title = 'Clearance' AND menu_name = 'main'" 2>/dev/null || echo "0")
# Fallback check in menu_tree for non-content links (views often create links differently)
MENU_TREE_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM menu_tree WHERE title = 'Clearance' AND menu_name = 'main'" 2>/dev/null || echo "0")

# 6. HTTP Content Verification (The ultimate test)
# Curl the new page and check content
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/clearance 2>/dev/null || echo "000")
PAGE_CONTENT=$(curl -s http://localhost/clearance 2>/dev/null || echo "")

CONTENT_HAS_SONY="false"
CONTENT_HAS_LOGI="false"
CONTENT_HAS_APPLE="false"

if echo "$PAGE_CONTENT" | grep -q "Sony WH-1000XM5"; then CONTENT_HAS_SONY="true"; fi
if echo "$PAGE_CONTENT" | grep -q "Logitech MX Master 3S"; then CONTENT_HAS_LOGI="true"; fi
if echo "$PAGE_CONTENT" | grep -q "Apple AirPods Pro"; then CONTENT_HAS_APPLE="true"; fi

# 7. Check timestamp of config changes (Anti-gaming)
# We check if the field config was created AFTER task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# config table doesn't have timestamps by default in Drupal, but we rely on the initial check we did in setup_task.sh

# Compile Result
create_result_json /tmp/task_result.json \
    "field_config_exists=$FIELD_CONFIG_EXISTS" \
    "sony_flagged=$SONY_FLAGGED" \
    "logi_flagged=$LOGI_FLAGGED" \
    "apple_flagged=$APPLE_FLAGGED" \
    "path_exists_in_router=$PATH_CHECK" \
    "menu_link_exists=$MENU_CHECK" \
    "menu_tree_exists=$MENU_TREE_CHECK" \
    "http_status=$HTTP_STATUS" \
    "content_has_sony=$CONTENT_HAS_SONY" \
    "content_has_logi=$CONTENT_HAS_LOGI" \
    "content_exclude_apple=$CONTENT_HAS_APPLE" \
    "task_start_timestamp=$TASK_START"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="