#!/bin/bash
# Export script for implement_inventory_tracking task
echo "=== Exporting Inventory Tracking Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. EXPORT CONFIGURATION (Field & View)
# We use Drush to export specific config objects to JSON for the verifier to parse easily
cd "$DRUPAL_DIR"

# Export Field Storage Config
echo "Exporting field storage config..."
FIELD_STORAGE_JSON=$($DRUSH config:get field.storage.commerce_product_variation.field_stock_level --format=json 2>/dev/null || echo "null")

# Export View Config
echo "Exporting view config..."
VIEW_CONFIG_JSON=$($DRUSH config:get views.view.low_stock_report --format=json 2>/dev/null || echo "null")

# 2. EXPORT DATA (Stock Values)
# Query the database for the actual values in the field table
# Table name is typically: commerce_product_variation__field_stock_level
# Columns: entity_id (variation_id), field_stock_level_value
echo "Exporting stock values..."

# Helper to get value for a specific SKU
get_stock_for_sku() {
    local sku="$1"
    # Join variation data to get ID from SKU, then join field table
    local query="SELECT f.field_stock_level_value 
                 FROM commerce_product_variation_field_data v
                 LEFT JOIN commerce_product_variation__field_stock_level f ON v.variation_id = f.entity_id
                 WHERE v.sku = '$sku'"
    drupal_db_query "$query" 2>/dev/null || echo "null"
}

SONY_STOCK=$(get_stock_for_sku "SONY-WH1000XM5")
LOGI_STOCK=$(get_stock_for_sku "LOGI-MXM3S")
BOSE_STOCK=$(get_stock_for_sku "BOSE-QC45")

# Check if table even exists (if agent failed to create field, query might fail)
TABLE_EXISTS=$(drupal_db_query "SHOW TABLES LIKE 'commerce_product_variation__field_stock_level'" | wc -l)

# 3. VERIFY VIEW PAGE ACCESS
# Check if the view path is accessible via curl (HTTP 200)
# We need to use drush uli to get a login link or simulate an auth request, 
# but simply checking if the path is registered in router might be enough.
# Let's check the router table in DB.
VIEW_PATH_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM router WHERE path = '/admin/reports/low-stock'" 2>/dev/null || echo "0")

# Create a temporary file for the JSON content
TEMP_JSON=$(mktemp /tmp/result_data.XXXXXX.json)

# Construct JSON
# Note: We embed the raw drush JSON outputs into our result JSON
cat > "$TEMP_JSON" << EOF
{
    "field_storage_config": $FIELD_STORAGE_JSON,
    "view_config": $VIEW_CONFIG_JSON,
    "stock_values": {
        "SONY-WH1000XM5": "${SONY_STOCK:-null}",
        "LOGI-MXM3S": "${LOGI_STOCK:-null}",
        "BOSE-QC45": "${BOSE_STOCK:-null}"
    },
    "table_exists": $TABLE_EXISTS,
    "view_path_registered": $VIEW_PATH_EXISTS,
    "timestamp": $(date +%s)
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="