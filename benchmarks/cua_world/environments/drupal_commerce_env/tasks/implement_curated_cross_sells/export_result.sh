#!/bin/bash
# Export script for implement_curated_cross_sells
echo "=== Exporting implement_curated_cross_sells Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
DRUPAL_ROOT="/var/www/html/drupal"
DRUSH="$DRUPAL_ROOT/vendor/bin/drush"
RESULT_FILE="/tmp/task_result.json"

# 1. Verify Field Storage Configuration
# Check if field.storage.commerce_product.field_related_accessories exists
echo "Checking field storage..."
FIELD_STORAGE_JSON=$(cd "$DRUPAL_ROOT" && $DRUSH config:get field.storage.commerce_product.field_related_accessories --format=json 2>/dev/null || echo "{}")
FIELD_EXISTS=$(echo "$FIELD_STORAGE_JSON" | jq -r '.id // empty')

if [ -n "$FIELD_EXISTS" ] && [ "$FIELD_EXISTS" != "null" ]; then
    HAS_FIELD="true"
    FIELD_TYPE=$(echo "$FIELD_STORAGE_JSON" | jq -r '.type')
    CARDINALITY=$(echo "$FIELD_STORAGE_JSON" | jq -r '.cardinality')
else
    HAS_FIELD="false"
    FIELD_TYPE=""
    CARDINALITY=""
fi

# 2. Verify Field Instance & Display Configuration
# Check core.entity_view_display.commerce_product.default.default
echo "Checking display configuration..."
DISPLAY_JSON=$(cd "$DRUPAL_ROOT" && $DRUSH config:get core.entity_view_display.commerce_product.default.default --format=json 2>/dev/null || echo "{}")

# Check if the field is enabled in the content section of the display
DISPLAY_CONFIGURED=$(echo "$DISPLAY_JSON" | jq -r '.content.field_related_accessories // empty')

if [ -n "$DISPLAY_CONFIGURED" ] && [ "$DISPLAY_CONFIGURED" != "null" ]; then
    IS_VISIBLE="true"
    DISPLAY_TYPE=$(echo "$DISPLAY_JSON" | jq -r '.content.field_related_accessories.type')
    VIEW_MODE=$(echo "$DISPLAY_JSON" | jq -r '.content.field_related_accessories.settings.view_mode // "default"')
else
    IS_VISIBLE="false"
    DISPLAY_TYPE=""
    VIEW_MODE=""
fi

# 3. Verify Content (Data Curation)
echo "Checking product associations..."
# Find Product IDs
MAIN_PRODUCT_ID=$(get_product_id_by_title "Apple MacBook Pro 16\"")
ACC1_ID=$(get_product_id_by_title "Logitech MX Master 3S")
ACC2_ID=$(get_product_id_by_title "Sony WH-1000XM5")

ASSOCIATIONS_FOUND="false"
LINKED_IDS="[]"

if [ -n "$MAIN_PRODUCT_ID" ] && [ "$HAS_FIELD" = "true" ]; then
    # Query the specific field table
    # Table name is usually commerce_product__field_related_accessories
    # Columns: entity_id, field_related_accessories_target_id
    QUERY="SELECT field_related_accessories_target_id FROM commerce_product__field_related_accessories WHERE entity_id = $MAIN_PRODUCT_ID"
    LINKED_IDS_RAW=$(drupal_db_query "$QUERY" 2>/dev/null)
    
    # Convert newline separated IDs to JSON array
    LINKED_IDS=$(echo "$LINKED_IDS_RAW" | jq -R -s -c 'split("\n") | map(select(length > 0) | tonumber)')
    
    # Check if both accessories are linked
    if [ -n "$ACC1_ID" ] && [ -n "$ACC2_ID" ]; then
        HAS_ACC1=$(echo "$LINKED_IDS_RAW" | grep -q "$ACC1_ID" && echo "true" || echo "false")
        HAS_ACC2=$(echo "$LINKED_IDS_RAW" | grep -q "$ACC2_ID" && echo "true" || echo "false")
        
        if [ "$HAS_ACC1" = "true" ] && [ "$HAS_ACC2" = "true" ]; then
            ASSOCIATIONS_FOUND="true"
        fi
    fi
fi

# Compile result
cat <<EOF > "$RESULT_FILE"
{
  "has_field": $HAS_FIELD,
  "field_type": "$FIELD_TYPE",
  "cardinality": "$CARDINALITY",
  "display_visible": $IS_VISIBLE,
  "display_type": "$DISPLAY_TYPE",
  "view_mode": "$VIEW_MODE",
  "main_product_id": "${MAIN_PRODUCT_ID:-null}",
  "accessory_ids": {
    "logitech": "${ACC1_ID:-null}",
    "sony": "${ACC2_ID:-null}"
  },
  "linked_ids": $LINKED_IDS,
  "associations_correct": $ASSOCIATIONS_FOUND
}
EOF

# Fix permissions
chmod 666 "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="