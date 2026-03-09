#!/bin/bash
# Export script for Add Product Variations task
# Queries database for the new variations and their linkage to the parent product

echo "=== Exporting Add Product Variations Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load context from setup
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
INITIAL_VAR_COUNT=$(cat /tmp/initial_variation_count 2>/dev/null || echo "0")
PRODUCT_ID=$(cat /tmp/target_product_id 2>/dev/null || echo "")

# Fallback if PRODUCT_ID lost (e.g. container restart)
if [ -z "$PRODUCT_ID" ]; then
    PRODUCT_ID=$(get_product_id_by_title "Dell XPS 13 Laptop")
fi

echo "Checking Product ID: $PRODUCT_ID"

# 1. Check parent product existence
PARENT_EXISTS="false"
CURRENT_VAR_COUNT=0

if [ -n "$PRODUCT_ID" ]; then
    PARENT_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data WHERE product_id = $PRODUCT_ID")
    if [ "$PARENT_CHECK" -gt 0 ]; then
        PARENT_EXISTS="true"
        # Get current variation count
        CURRENT_VAR_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__variations WHERE entity_id = $PRODUCT_ID")
    fi
fi

# 2. Check for Variation 1: DELL-XPS13-16-512
SKU1="DELL-XPS13-16-512"
VAR1_FOUND="false"
VAR1_PRICE=""
VAR1_STATUS=""
VAR1_LINKED="false"

# Query by SKU (case insensitive)
VAR1_DATA=$(drupal_db_query "SELECT variation_id, price__number, status FROM commerce_product_variation_field_data WHERE LOWER(sku) = LOWER('$SKU1') LIMIT 1")

if [ -n "$VAR1_DATA" ]; then
    VAR1_FOUND="true"
    VAR1_ID=$(echo "$VAR1_DATA" | cut -f1)
    VAR1_PRICE=$(echo "$VAR1_DATA" | cut -f2)
    VAR1_STATUS=$(echo "$VAR1_DATA" | cut -f3)
    
    # Check linkage to parent product
    if [ -n "$PRODUCT_ID" ]; then
        LINK_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__variations WHERE entity_id = $PRODUCT_ID AND variations_target_id = $VAR1_ID")
        if [ "$LINK_CHECK" -gt 0 ]; then
            VAR1_LINKED="true"
        fi
    fi
fi

# 3. Check for Variation 2: DELL-XPS13-32-1TB
SKU2="DELL-XPS13-32-1TB"
VAR2_FOUND="false"
VAR2_PRICE=""
VAR2_STATUS=""
VAR2_LINKED="false"

VAR2_DATA=$(drupal_db_query "SELECT variation_id, price__number, status FROM commerce_product_variation_field_data WHERE LOWER(sku) = LOWER('$SKU2') LIMIT 1")

if [ -n "$VAR2_DATA" ]; then
    VAR2_FOUND="true"
    VAR2_ID=$(echo "$VAR2_DATA" | cut -f1)
    VAR2_PRICE=$(echo "$VAR2_DATA" | cut -f2)
    VAR2_STATUS=$(echo "$VAR2_DATA" | cut -f3)
    
    if [ -n "$PRODUCT_ID" ]; then
        LINK_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__variations WHERE entity_id = $PRODUCT_ID AND variations_target_id = $VAR2_ID")
        if [ "$LINK_CHECK" -gt 0 ]; then
            VAR2_LINKED="true"
        fi
    fi
fi

# Create Result JSON
create_result_json /tmp/task_result.json \
    "parent_product_id=$PRODUCT_ID" \
    "parent_exists=$PARENT_EXISTS" \
    "initial_variation_count=$INITIAL_VAR_COUNT" \
    "current_variation_count=$CURRENT_VAR_COUNT" \
    "var1_sku=$(json_escape "$SKU1")" \
    "var1_found=$VAR1_FOUND" \
    "var1_price=$VAR1_PRICE" \
    "var1_status=$VAR1_STATUS" \
    "var1_linked=$VAR1_LINKED" \
    "var2_sku=$(json_escape "$SKU2")" \
    "var2_found=$VAR2_FOUND" \
    "var2_price=$VAR2_PRICE" \
    "var2_status=$VAR2_STATUS" \
    "var2_linked=$VAR2_LINKED"

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. JSON content:"
cat /tmp/task_result.json