#!/bin/bash
# Export script for resolve_duplicate_products task

echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data from database
# Count total published products
FINAL_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data WHERE status=1")

# Count remaining duplicates (Should be 0)
REMAINING_DUPLICATES=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_variation_field_data WHERE sku LIKE 'IMPORT-%' AND status=1")

# Get Bose Price (Should be 429.00)
BOSE_PRICE=$(drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE sku='BOSE-QCU'")

# Check distinct originals to ensure no over-deletion
# We expect specific original SKUs to still exist
ORIGINALS_EXIST="true"
MISSING_ORIGINALS=""
for sku in "SONY-WH1000XM5" "APPLE-MBP16" "LOGI-MXM3S" "DELL-XPS15" "BOSE-QCU"; do
    COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_variation_field_data WHERE sku='$sku' AND status=1")
    if [ "$COUNT" -eq "0" ]; then
        ORIGINALS_EXIST="false"
        MISSING_ORIGINALS="$MISSING_ORIGINALS $sku"
    fi
done

# 3. Get list of deleted duplicates for detailed scoring
# We compare the current list of IMPORT- skus against the ones we know we created
# (Though REMAINING_DUPLICATES gives the count, a list is helpful for feedback)
REMAINING_IMPORT_SKUS=$(drupal_db_query "SELECT sku FROM commerce_product_variation_field_data WHERE sku LIKE 'IMPORT-%' AND status=1")

# 4. Anti-gaming timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Create JSON Result
create_result_json /tmp/task_result.json \
    "final_product_count=$FINAL_COUNT" \
    "remaining_duplicates_count=$REMAINING_DUPLICATES" \
    "bose_final_price=$BOSE_PRICE" \
    "originals_exist=$ORIGINALS_EXIST" \
    "missing_originals=$(json_escape "$MISSING_ORIGINALS")" \
    "remaining_import_skus=$(json_escape "$REMAINING_IMPORT_SKUS")" \
    "task_start=$TASK_START" \
    "task_end=$TASK_END"

# 6. Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="