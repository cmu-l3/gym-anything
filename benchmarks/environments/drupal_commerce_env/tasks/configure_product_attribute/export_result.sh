#!/bin/bash
# Export script for configure_product_attribute task
echo "=== Exporting configure_product_attribute Result ==="

source /workspace/scripts/task_utils.sh

# Define database query function if not present
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# 1. Check if the Attribute Entity exists (Config entity)
# Drupal Commerce attributes are config entities. 
# We look for a config entry with name 'commerce_product.commerce_product_attribute.[machine_name]'
# We expect machine name 'color' based on label 'Color', but agent might use something else.
# We'll search for any attribute with label 'Color'.

# First, try to find the machine name from the config data where label is Color
# Config data is serialized PHP. We use a simple grep approach or Python parser.
ATTR_MACHINE_NAME=$(drupal_db_query "SELECT name FROM config WHERE name LIKE 'commerce_product.commerce_product_attribute.%' AND data LIKE '%s:5:\"label\";s:5:\"Color\";%'" | sed 's/commerce_product.commerce_product_attribute.//' | head -1)

# If not found by exact label length serialization, try broad search
if [ -z "$ATTR_MACHINE_NAME" ]; then
    # Fallback: check if 'color' exists directly
    EXISTS_COLOR=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'commerce_product.commerce_product_attribute.color'")
    if [ "$EXISTS_COLOR" -gt 0 ]; then
        ATTR_MACHINE_NAME="color"
    fi
fi

echo "Detected Attribute Machine Name: $ATTR_MACHINE_NAME"

# 2. Get Attribute Values
# Values are stored in commerce_product_attribute_value_field_data
# Columns: attribute, name
FOUND_VALUES_JSON="[]"
if [ -n "$ATTR_MACHINE_NAME" ]; then
    # Get all values for this attribute
    # We output them as a JSON array string
    VALS=$(drupal_db_query "SELECT name FROM commerce_product_attribute_value_field_data WHERE attribute = '$ATTR_MACHINE_NAME'")
    
    # Convert newline separated values to JSON array
    # Python is safer for JSON formatting
    FOUND_VALUES_JSON=$(echo "$VALS" | python3 -c "import sys, json; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))")
fi

# 3. Check Association with Default Variation Type
# When an attribute is added to a variation type, a field instance is created.
# Config name format: field.field.commerce_product_variation.[variation_type].attribute_[attribute_machine_name]
VARIATION_ASSOCIATED="false"
if [ -n "$ATTR_MACHINE_NAME" ]; then
    FIELD_CONFIG_NAME="field.field.commerce_product_variation.default.attribute_$ATTR_MACHINE_NAME"
    ASSOC_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = '$FIELD_CONFIG_NAME'")
    if [ "$ASSOC_CHECK" -gt 0 ]; then
        VARIATION_ASSOCIATED="true"
    fi
fi

# 4. Get Counts
INITIAL_ATTR_COUNT=$(cat /tmp/initial_attr_count 2>/dev/null || echo "0")
CURRENT_ATTR_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'commerce_product.commerce_product_attribute.%'")
INITIAL_VAL_COUNT=$(cat /tmp/initial_val_count 2>/dev/null || echo "0")
CURRENT_VAL_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_attribute_value_field_data")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "attribute_found": $([ -n "$ATTR_MACHINE_NAME" ] && echo "true" || echo "false"),
    "attribute_machine_name": "${ATTR_MACHINE_NAME:-null}",
    "found_values": $FOUND_VALUES_JSON,
    "variation_associated": $VARIATION_ASSOCIATED,
    "initial_attr_count": ${INITIAL_ATTR_COUNT:-0},
    "current_attr_count": ${CURRENT_ATTR_COUNT:-0},
    "initial_val_count": ${INITIAL_VAL_COUNT:-0},
    "current_val_count": ${CURRENT_VAL_COUNT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json