#!/bin/bash
# Export script for implement_product_documentation_field task
echo "=== Exporting implement_product_documentation_field Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# 1. Verify Field Storage Configuration
# Checks if the field storage config object exists
FIELD_STORAGE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.commerce_product.field_user_manual'")

# 2. Verify Field Instance Configuration
# Checks if the field is attached to the 'default' bundle
FIELD_INSTANCE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.field.commerce_product.default.field_user_manual'")

# 3. Verify Display Configuration
# Checks if the field is enabled in the default view display
# We look for the field name in the serialized content. If it's in the 'hidden' section, it's bad.
# If it's in 'content', it's good.
DISPLAY_CONFIG=$(drupal_db_query "SELECT CAST(data AS CHAR) FROM config WHERE name = 'core.entity_view_display.commerce_product.default.default'")

FIELD_IN_DISPLAY="false"
FIELD_HIDDEN="false"
LABEL_INLINE="false"

if [[ "$DISPLAY_CONFIG" == *"field_user_manual"* ]]; then
    # Simple grep check on the serialized string
    # In Drupal config export:
    # content:
    #   field_user_manual:
    #     type: link
    # ...
    # hidden:
    #   ...
    
    # We'll use a python one-liner for robust parsing of the serialized/yaml-like structure if needed,
    # but for now, checking if it appears before "hidden" block is a decent heuristic, or using python to parse.
    
    # Let's use Python to check specific structure if possible, but serialized PHP is hard to parse in bash/python without 'phpserialize'.
    # Instead, we will look for the string sequence.
    
    # Check if 'field_user_manual' exists in the 'content' array
    if echo "$DISPLAY_CONFIG" | grep -q "s:17:\"field_user_manual\";a:"; then
        FIELD_IN_DISPLAY="true"
        
        # Check for inline label: s:5:"label";s:6:"inline"
        if echo "$DISPLAY_CONFIG" | grep -q "s:5:\"label\";s:6:\"inline\""; then
            LABEL_INLINE="true"
        fi
    fi
    
    # Check if it's in hidden array (less likely if we found it in content, but good to check)
    # This is harder to definitively distinguish without parsing, so we rely on FIELD_IN_DISPLAY=true
fi

# 4. Verify Data Content
# The field data is stored in 'commerce_product__field_user_manual'
TABLE_EXISTS=$(drupal_db_query "SHOW TABLES LIKE 'commerce_product__field_user_manual'")

DATA_FOUND="false"
ACTUAL_URI=""
ACTUAL_TITLE=""

if [ -n "$TABLE_EXISTS" ]; then
    # Find the product ID for the Sony headphones
    PRODUCT_ID=$(drupal_db_query "SELECT product_id FROM commerce_product_field_data WHERE title LIKE '%Sony WH-1000XM5%' LIMIT 1")
    
    if [ -n "$PRODUCT_ID" ]; then
        # Fetch the field data
        ROW_DATA=$(drupal_db_query "SELECT field_user_manual_uri, field_user_manual_title FROM commerce_product__field_user_manual WHERE entity_id = '$PRODUCT_ID' LIMIT 1")
        
        if [ -n "$ROW_DATA" ]; then
            DATA_FOUND="true"
            ACTUAL_URI=$(echo "$ROW_DATA" | cut -f1)
            ACTUAL_TITLE=$(echo "$ROW_DATA" | cut -f2)
        fi
    fi
fi

# Export to JSON
cat > /tmp/task_result.json << EOF
{
    "field_storage_exists": $([ "$FIELD_STORAGE_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "field_instance_exists": $([ "$FIELD_INSTANCE_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "field_in_display": $FIELD_IN_DISPLAY,
    "label_inline": $LABEL_INLINE,
    "data_table_exists": $([ -n "$TABLE_EXISTS" ] && echo "true" || echo "false"),
    "data_found": $DATA_FOUND,
    "actual_uri": "$(json_escape "$ACTUAL_URI")",
    "actual_title": "$(json_escape "$ACTUAL_TITLE")"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="