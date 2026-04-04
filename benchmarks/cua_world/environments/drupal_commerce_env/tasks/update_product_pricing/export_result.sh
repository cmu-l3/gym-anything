#!/bin/bash
# Export script for update_product_pricing
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current state
echo "Querying final database state..."

# Function to get price by SKU
get_price() {
    drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE sku='$1'"
}

# Function to get status by SKU
get_status() {
    drupal_db_query "SELECT p.status FROM commerce_product_field_data p JOIN commerce_product__variations pv ON p.product_id = pv.entity_id JOIN commerce_product_variation_field_data v ON pv.variations_target_id = v.variation_id WHERE v.sku='$1'"
}

# Function to get last changed timestamp for a variation
get_changed_time() {
    drupal_db_query "SELECT changed FROM commerce_product_variation_field_data WHERE sku='$1'"
}

SONY_PRICE=$(get_price "SONY-WH1000XM5")
LOGI_PRICE=$(get_price "LOGI-MXM3S")
BOSE_PRICE=$(get_price "BOSE-QC45")
BOSE_STATUS=$(get_status "BOSE-QC45")
TOTAL_PUBLISHED=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data WHERE status=1")
TOTAL_PRODUCTS=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data")

# Timestamps to verify work was done recently
SONY_CHANGED=$(get_changed_time "SONY-WH1000XM5")
LOGI_CHANGED=$(get_changed_time "LOGI-MXM3S")

# Create result JSON
cat > /tmp/task_result.json <<EOF
{
    "sony_price": "${SONY_PRICE:-0}",
    "logi_price": "${LOGI_PRICE:-0}",
    "bose_price": "${BOSE_PRICE:-0}",
    "bose_status": "${BOSE_STATUS:-0}",
    "total_published": ${TOTAL_PUBLISHED:-0},
    "total_products": ${TOTAL_PRODUCTS:-0},
    "sony_changed_timestamp": ${SONY_CHANGED:-0},
    "logi_changed_timestamp": ${LOGI_CHANGED:-0},
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "initial_state": $(cat /tmp/initial_state.json 2>/dev/null || echo "{}")
}
EOF

echo "Exported JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="